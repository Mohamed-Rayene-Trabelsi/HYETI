import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../date.dart';
import '../db.dart';
import '../pickers.dart';
import '../theme.dart';
import '../ui.dart';
import '../watch_api.dart';
import 'settings.dart';

const _kindLabel = {'anime': 'Anime', 'movie': 'Movie', 'series': 'Series', 'match': 'Football'};
const _kindIcon = {
  'anime': Icons.auto_awesome,
  'movie': Icons.movie_outlined,
  'series': Icons.tv,
  'match': Icons.sports_soccer,
};

final _ratingPart = RegExp(r'^(IMDb|TMDB|AniList) ');

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with Live {
  /// 'mine', 'shows' (movies and series), 'anime' or 'match'.
  String _tab = 'mine';

  /// Which half of Shows is open: 'movie' or 'series'.
  String _showKind = 'movie';
  List<Rec> _items = [];

  @override
  void initState() {
    super.initState();
    _refreshStale();
  }

  @override
  Future<void> load() async {
    // Joined so a block deleted from the calendar stops counting as "on calendar".
    _items = await appDb.query('''
      SELECT w.*, e.id AS live_event_id
      FROM watch_items w LEFT JOIN events e ON e.id = w.event_id
      ORDER BY w.release_date IS NULL, w.release_date, w.id''');
  }

  /// Once a day, look up the next episode of saved shows whose date has passed,
  /// so the list keeps pointing at what is coming rather than what already aired.
  Future<void> _refreshStale() async {
    final today = todayKey();
    if (appDb.setting('watch_refreshed', '') == today) return;
    final stale = await appDb.query(
      "SELECT * FROM watch_items WHERE ext_id IS NOT NULL AND kind IN ('series', 'anime') "
      'AND (release_date IS NULL OR release_date < ?)',
      [today],
    );
    if (stale.isEmpty) return;
    final tmdbKey = appDb.setting('tmdb_key', '');
    var reached = false;
    for (final item in stale) {
      final extId = item['ext_id'] as String;
      try {
        final ({String date, String note})? next;
        if (item['kind'] == 'anime') {
          next = await nextAnimeEpisode(extId);
        } else if (tmdbKey.isNotEmpty && extId.startsWith('tmdb:')) {
          next = await nextEpisode(extId, tmdbKey);
        } else {
          continue;
        }
        reached = true;
        if (next == null) continue;
        final rating = (item['detail'] as String).split(' · ').where(_ratingPart.hasMatch);
        await appDb.raw.execute('UPDATE watch_items SET release_date = ?, detail = ? WHERE id = ?', [
          next.date,
          [next.note, ...rating].join(' · '),
          item['id'],
        ]);
      } catch (_) {
        // Offline or the service is down: keep what is saved and try again next time.
      }
    }
    if (reached) await appDb.setSetting('watch_refreshed', today);
  }

  /// Put a title on the calendar: on its release day if that is ahead, otherwise tonight.
  Future<void> _addToCalendar(Rec item) async {
    final today = todayKey();
    final release = item['release_date'] as String?;
    final upcoming = release != null && release.compareTo(today) >= 0;
    final date = upcoming ? release : (nowMinutes() > 21 * 60 ? addDays(today, 1) : today);
    final airTime = RegExp(r'(\d\d):(\d\d)').firstMatch(item['detail'] as String);
    final start = math.min(airTime == null ? 20 * 60 : int.parse(airTime[1]!) * 60 + int.parse(airTime[2]!), 1380);
    final length = switch (item['kind']) {
      'movie' || 'match' => 120,
      'series' => 60,
      _ => 30,
    };
    await appDb.transaction((txn) async {
      final eventId = await txn.rawInsert(
        'INSERT INTO events (date, title, category, start_min, end_min, flex_min) VALUES (?, ?, ?, ?, ?, 0)',
        [date, item['title'], 'watch', start, math.min(start + length, 1439)],
      );
      await txn.execute('UPDATE watch_items SET event_id = ? WHERE id = ?', [eventId, item['id']]);
    });
    showUndo('Added to ${relativeDay(date).toLowerCase()} at ${formatTime(start)}', () async {
      await appDb.run('DELETE FROM events WHERE id = (SELECT event_id FROM watch_items WHERE id = ?)', [item['id']]);
    });
  }

  /// Removes a title: every saved entry behind its card, with their calendar blocks.
  Future<void> _remove(List<Rec> copies) async {
    await appDb.transaction((txn) async {
      for (final item in copies) {
        if (item['live_event_id'] != null) {
          await txn.execute('DELETE FROM events WHERE id = ?', [item['live_event_id']]);
        }
        await txn.execute('DELETE FROM watch_items WHERE id = ?', [item['id']]);
      }
    });
    showUndo('Removed ${copies.first['title']}', () async {
      for (final item in copies) {
        await appDb.restore('watch_items', {...item}..remove('live_event_id'));
      }
    });
  }

  Future<void> _saveFound(Found f) async {
    var date = f.releaseDate;
    var note = f.note;
    final tmdbKey = appDb.setting('tmdb_key', '');
    // A series that already started: track its next episode rather than the old premiere.
    if (f.kind == 'series' && tmdbKey.isNotEmpty && date != null && date.compareTo(todayKey()) <= 0) {
      ({String date, String note})? next;
      try {
        next = await nextEpisode(f.extId, tmdbKey);
      } catch (_) {
        next = null;
      }
      date = next?.date;
      note = next?.note ?? 'No new episode announced';
    }
    final detail = [note, f.rating].where((s) => s.isNotEmpty).join(' · ');
    // A title typed in by hand earlier becomes this one, rather than sitting beside it as a duplicate.
    final typed = _items.where((i) => i['ext_id'] == null && _sameTitle(i, f.kind, f.title)).firstOrNull;
    if (typed != null) {
      await appDb.run(
        'UPDATE OR IGNORE watch_items SET title = ?, release_date = ?, detail = ?, ext_id = ?, poster = ? WHERE id = ?',
        [f.title, date, detail, f.extId, f.poster, typed['id']],
      );
      return;
    }
    await appDb.insert(
      'INSERT OR IGNORE INTO watch_items (kind, title, release_date, detail, ext_id, poster) VALUES (?, ?, ?, ?, ?, ?)',
      [f.kind, f.title, date, detail, f.extId, f.poster],
    );
  }

  bool _sameTitle(Rec item, String kind, String title) =>
      watchTitleKey(item['kind'] as String, item['title'] as String) == watchTitleKey(kind, title);

  /// The list entry saved from this exact online entry, if there is one.
  Rec? _savedAs(Found f) => _items.where((i) => i['ext_id'] == f.extId).firstOrNull;

  /// Tapping "Saved" takes the title back off the list.
  Future<void> _unsaveFound(Found f) async {
    final item = _savedAs(f);
    if (item != null) await _remove([item]);
  }

  /// What a saved entry is called on "My list". Entries that share it are drawn as one card, so a show
  /// saved from both Series and Anime sits in one section instead of two. Nothing is merged in storage.
  static String _listKey(Rec item) => watchTitleKey(switch (item['kind']) {
    'movie' => 'movie',
    'match' => 'match',
    _ => 'show',
  }, item['title'] as String);

  static bool _isUpcoming(Rec item, String today) => ((item['release_date'] as String?) ?? '').compareTo(today) >= 0;

  void _openKeys() {
    showSheet(
      context,
      title: 'Movie and series keys',
      builder: (sheet) => KeysForm(onSaved: () => Navigator.pop(sheet)),
    );
  }

  void _openAdd() {
    showSheet(
      context,
      title: 'Add a title',
      builder: (sheet) => _ManualForm(
        onSave: (kind, title, date) async {
          if (_items.any((i) => _sameTitle(i, kind, title))) return 'That is already on your list.';
          await appDb.insert('INSERT INTO watch_items (kind, title, release_date, detail) VALUES (?, ?, ?, ?)', [
            kind,
            title,
            date.isEmpty ? null : date,
            '',
          ]);
          if (sheet.mounted) Navigator.pop(sheet);
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tmdbKey = appDb.setting('tmdb_key', '');
    final omdbKey = appDb.setting('omdb_key', '');
    final mine = _tab == 'mine';
    final kind = _tab == 'shows' ? _showKind : _tab;
    final today = todayKey();
    // One card per title. A title with any entry still ahead goes under "Coming up", led by that entry;
    // otherwise it goes under "Out now or undated". It is never in both.
    final byTitle = <String, List<Rec>>{};
    for (final item in _items) {
      (byTitle[_listKey(item)] ??= []).add(item);
    }
    final titles = [
      for (final copies in byTitle.values)
        [...copies.where((i) => _isUpcoming(i, today)), ...copies.where((i) => !_isUpcoming(i, today))],
    ];
    final upcoming = titles.where((t) => _isUpcoming(t.first, today)).toList();
    final rest = titles.where((t) => !_isUpcoming(t.first, today)).toList();

    return Screen(
      title: 'Watchlist',
      subtitle: titles.isEmpty ? 'Shows, anime and football' : '${titles.length} saved · ${upcoming.length} coming up',
      // Once a key is saved nothing here asks for one again; both stay editable in Settings.
      actions: [
        if (tmdbKey.isEmpty && omdbKey.isEmpty)
          HeaderIcon(Icons.key_outlined, label: 'Movie and series keys', onPressed: _openKeys),
      ],
      fabLabel: mine ? 'Add title' : null,
      onFab: _openAdd,
      children: [
        Segmented<String>(
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
          options: const {'mine': 'My list', 'shows': 'Shows', 'anime': 'Anime', 'match': 'Football'},
        ),
        if (mine) ...[
          if (ready && _items.isEmpty)
            const Empty(
              icon: Icons.bookmark_add_outlined,
              title: 'Your list is empty',
              hint: 'Open Shows, Anime or Football to see what is on and save what you want to watch.',
            ),
          if (upcoming.isNotEmpty)
            Section(title: 'Coming up', children: [for (final copies in upcoming) _itemCard(copies)]),
          if (rest.isNotEmpty)
            Section(
              title: upcoming.isEmpty ? 'Saved' : 'Out now or undated',
              children: [for (final copies in rest) _itemCard(copies)],
            ),
        ] else if (_tab == 'shows' && tmdbKey.isEmpty)
          Empty(
            icon: Icons.key_outlined,
            title: omdbKey.isEmpty ? 'A free key is needed' : 'A TMDB key is needed',
            hint: omdbKey.isEmpty
                ? 'Hot movies and series come from TMDB. The key is free and you paste it in once. '
                      'An OMDb key is optional and adds IMDb ratings.'
                : 'Your OMDb key is saved, but the lists themselves come from TMDB. Its key is free too.',
            action: AppButton(omdbKey.isEmpty ? 'Add a key' : 'Add TMDB key', onPressed: _openKeys),
          )
        else ...[
          if (_tab == 'shows')
            Segmented<String>(
              value: _showKind,
              onChanged: (v) => setState(() => _showKind = v),
              options: const {'movie': 'Movies', 'series': 'Series'},
            ),
          _Browser(
            key: ValueKey(kind),
            kind: kind,
            tmdbKey: tmdbKey,
            omdbKey: omdbKey,
            isSaved: (f) => _savedAs(f) != null,
            onSave: _saveFound,
            onUnsave: _unsaveFound,
            onFixKeys: _openKeys,
          ),
        ],
      ],
    );
  }

  /// One title on the list. [copies] are the saved entries behind it, the one to show first.
  Widget _itemCard(List<Rec> copies) {
    final item = copies.first;
    final c = context.colors;
    final release = item['release_date'] as String?;
    final detail = item['detail'] as String;
    final kind = item['kind'] as String;
    final days = release == null ? null : daysBetween(todayKey(), release);
    final upcoming = days != null && days >= 0;
    final when = release == null
        ? 'No date'
        : !upcoming
        ? (kind == 'match' ? 'Played' : 'Out now')
        : days <= 1
        ? relativeDay(release)
        : days < 7
        ? 'In $days days'
        : formatDay(release);
    return AppCard(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Spacing.md,
          children: [
            _Poster(url: item['poster'] as String?, kind: kind),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  T(item['title'] as String, variant: TextVariant.heading, maxLines: 2),
                  T(
                    '${_kindLabel[kind]}${detail.isNotEmpty ? ' · $detail' : ''}',
                    variant: TextVariant.small,
                    dim: true,
                    maxLines: 2,
                  ),
                  T(when, variant: TextVariant.label, color: upcoming && days <= 1 ? c.accent : c.textDim),
                ],
              ),
            ),
          ],
        ),
        Row(
          spacing: Spacing.sm,
          children: [
            if (copies.any((i) => i['live_event_id'] != null))
              AppChip('On calendar', icon: Icons.check, selected: true, color: c.success)
            else
              // Flexible, so with a large font size the label shortens instead of pushing Remove off the card.
              Flexible(
                child: AppButton(
                  upcoming ? 'Add to calendar' : 'Plan a watch night',
                  icon: Icons.event_available_outlined,
                  kind: ButtonKind.soft,
                  small: true,
                  onPressed: () => _addToCalendar(item),
                ),
              ),
            const Spacer(),
            AppButton('Remove', kind: ButtonKind.plain, small: true, onPressed: () => _remove(copies)),
          ],
        ),
      ],
    );
  }
}

/// A small poster, or a tinted placeholder when there is none or it cannot be loaded.
class _Poster extends StatelessWidget {
  const _Poster({required this.url, required this.kind});

  final String? url;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placeholder = Container(
      color: c.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(_kindIcon[kind] ?? Icons.movie_outlined, color: c.textDim, size: 22),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: SizedBox(
        width: 54,
        height: 80,
        child: url == null || url!.isEmpty
            ? placeholder
            : kind == 'match'
            // A club crest is shown whole on the card's tint, where a poster fills the frame.
            ? Container(
                color: c.surfaceAlt,
                padding: const EdgeInsets.all(Spacing.sm),
                child: Image.network(
                  url!,
                  fit: BoxFit.contain,
                  cacheWidth: 162,
                  errorBuilder: (_, _, _) => placeholder,
                ),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                cacheWidth: 162,
                errorBuilder: (_, _, _) => placeholder,
                frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : placeholder,
              ),
      ),
    );
  }
}

/// Hot / upcoming / searched titles of one kind, loaded online.
class _Browser extends StatefulWidget {
  const _Browser({
    super.key,
    required this.kind,
    required this.tmdbKey,
    required this.omdbKey,
    required this.isSaved,
    required this.onSave,
    required this.onUnsave,
    required this.onFixKeys,
  });

  final String kind;
  final String tmdbKey;
  final String omdbKey;

  /// Whether a found title is on the list already.
  final bool Function(Found) isSaved;
  final Future<void> Function(Found) onSave;
  final Future<void> Function(Found) onUnsave;
  final VoidCallback onFixKeys;

  @override
  State<_Browser> createState() => _BrowserState();
}

class _BrowserState extends State<_Browser> {
  final _text = TextEditingController();
  String _search = '';
  String _mode = 'hot';

  /// The football competition being shown; '' for all of them.
  String _league = '';

  /// Runs the search a moment after the last keystroke, so typing a word asks once rather than per letter.
  Timer? _typing;

  // Each request gets a number; an answer to anything but the latest is dropped.
  int _request = 0;
  bool _loading = true;
  String _error = '';
  bool _badKey = false;
  List<Found> _results = [];

  /// The last page loaded, and whether the source has another after it.
  int _page = 0;
  bool _more = false;

  /// Titles being saved right now, so the button cannot be pressed twice.
  final _saving = <String>{};

  /// The scroll position of the screen this list sits in: nearing its end loads the next page.
  ScrollPosition? _scroll;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll == _scroll) return;
    _scroll?.removeListener(_onScroll);
    _scroll = scroll?..addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_Browser old) {
    super.didUpdateWidget(old);
    if (old.tmdbKey != widget.tmdbKey || old.omdbKey != widget.omdbKey) _fetch();
  }

  @override
  void dispose() {
    _request = -1;
    _typing?.cancel();
    _scroll?.removeListener(_onScroll);
    _text.dispose();
    super.dispose();
  }

  void _onScroll() {
    final scroll = _scroll;
    if (!mounted || scroll == null || !scroll.hasContentDimensions) return;
    if (_loading || !_more || _error.isNotEmpty) return;
    // About two screens of cards before the end, so the next page is usually there on arrival.
    if (scroll.extentAfter < 1200) _fetch(next: true);
  }

  /// Loads the first page, or with [next] the page after the last one and adds it to the list.
  Future<void> _fetch({bool next = false}) async {
    final request = ++_request;
    final page = next ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = '';
      if (!next) _results = [];
    });
    try {
      final found = switch (widget.kind) {
        'anime' => await fetchAnime(_search, page: page),
        'match' => await fetchMatches(_league),
        _ => await fetchTitles(
          widget.kind,
          _mode,
          _search,
          tmdbKey: widget.tmdbKey,
          omdbKey: widget.omdbKey,
          page: page,
        ),
      };
      if (!mounted || request != _request) return;
      // Rankings shift between requests, so a later page can repeat a title already shown.
      final shown = {for (final f in _results) f.extId};
      setState(() {
        _loading = false;
        _page = page;
        _more = found.more;
        _results = [..._results, ...found.items.where((f) => shown.add(f.extId))];
      });
      // A page of nothing but repeats leaves the list where it was; keep going.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _badKey = e is KeyError;
        _error = e is KeyError ? e.message : 'Check your internet connection and try again.';
      });
    }
  }

  /// Called on every keystroke: the search follows the typing, with no button to press.
  void _onTyped(String value) {
    setState(() {});
    // Matches are few and all loaded already, so typing only narrows what is shown.
    if (widget.kind == 'match') return;
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 400), () => _setSearch(value.trim()));
  }

  void _setSearch(String value) {
    _typing?.cancel();
    if (!mounted || value == _search) return;
    _search = value;
    _fetch();
  }

  void _setLeague(String league) {
    if (_league == league) return;
    _league = league;
    _fetch();
  }

  void _setMode(String mode) {
    if (_mode == mode) return;
    _mode = mode;
    _fetch();
  }

  /// Saves a title, or with [off] takes a saved one back off the list.
  Future<void> _save(Found f, {bool off = false}) async {
    if (_saving.contains(f.extId)) return;
    setState(() => _saving.add(f.extId));
    try {
      await (off ? widget.onUnsave(f) : widget.onSave(f));
    } finally {
      if (mounted) setState(() => _saving.remove(f.extId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kind = widget.kind;
    final plural = switch (kind) {
      'movie' => 'movies',
      'series' => 'series',
      'match' => 'teams',
      _ => 'anime',
    };
    final typed = _text.text.trim();
    final thisYear = todayKey().substring(0, 4);
    final results = kind == 'match' && typed.isNotEmpty
        ? _results.where((f) => f.title.toLowerCase().contains(typed.toLowerCase())).toList()
        : _results;
    final chips = [
      if (kind == 'match') ...[
        AppChip('All', selected: _league.isEmpty, onPressed: () => _setLeague('')),
        for (final league in footballLeagues.entries)
          AppChip(league.value, selected: _league == league.key, onPressed: () => _setLeague(league.key)),
      ] else if (kind != 'anime' && typed.isEmpty) ...[
        AppChip('Hot this week', selected: _mode == 'hot', onPressed: () => _setMode('hot')),
        AppChip('Coming soon', selected: _mode == 'upcoming', onPressed: () => _setMode('upcoming')),
      ],
      if (typed.isNotEmpty)
        AppChip(
          'Clear search',
          icon: Icons.close,
          onPressed: () {
            _text.clear();
            setState(() {});
            _setSearch('');
          },
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.lg,
      children: [
        Field(
          controller: _text,
          icon: Icons.search,
          hint: 'Search $plural',
          textInputAction: TextInputAction.search,
          onChanged: _onTyped,
          // The keyboard's search key only puts the keyboard away; the results are already there or on their way.
          onSubmitted: (v) {
            FocusManager.instance.primaryFocus?.unfocus();
            if (kind != 'match') _setSearch(v.trim());
          },
        ),
        if (chips.isNotEmpty) Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: chips),
        if (!_loading && _error.isEmpty && results.isEmpty)
          if (kind == 'match' && typed.isEmpty)
            const Empty(
              icon: Icons.sports_soccer,
              title: 'No matches coming up',
              hint: 'The next round shows here once its fixtures are set.',
            )
          else
            Empty(
              icon: Icons.search_off,
              title: 'Nothing found',
              hint: kind == 'match'
                  ? 'No upcoming match has a team by that name.'
                  : 'Check the spelling, or try the original title.',
            ),
        for (final f in results)
          AppCard(
            children: [
              Row(
                spacing: Spacing.md,
                children: [
                  _Poster(url: f.poster, kind: kind),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        T(f.title, variant: TextVariant.heading, maxLines: 2),
                        T(
                          [
                            if (f.releaseDate != null)
                              formatDay(f.releaseDate!) +
                                  (f.releaseDate!.startsWith(thisYear) ? '' : ' ${f.releaseDate!.substring(0, 4)}'),
                            if (f.note.isNotEmpty) f.note,
                          ].join(' · '),
                          variant: TextVariant.small,
                          dim: true,
                          maxLines: 2,
                        ),
                        if (f.rating.isNotEmpty) T('★ ${f.rating}', variant: TextVariant.label, color: c.warn),
                      ],
                    ),
                  ),
                  if (widget.isSaved(f))
                    Semantics(
                      label: 'Remove ${f.title} from my list',
                      child: AppChip(
                        'Saved',
                        icon: Icons.check,
                        selected: true,
                        color: c.success,
                        onPressed: () => _save(f, off: true),
                      ),
                    )
                  else
                    AppButton(
                      'Save',
                      icon: Icons.bookmark_add_outlined,
                      kind: ButtonKind.soft,
                      small: true,
                      onPressed: _saving.contains(f.extId) ? null : () => _save(f),
                    ),
                ],
              ),
            ],
          ),
        // Below the list, so loading or failing on a later page leaves the titles above in place.
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator(color: c.accent)),
          ),
        if (_error.isNotEmpty)
          Empty(
            icon: Icons.cloud_off_outlined,
            title: _results.isNotEmpty
                ? 'Could not load more'
                : kind == 'match'
                ? 'Could not load matches'
                : 'Could not load titles',
            hint: _error,
            action: _badKey
                ? AppButton('Check my keys', kind: ButtonKind.soft, onPressed: widget.onFixKeys)
                : AppButton(
                    'Try again',
                    kind: ButtonKind.soft,
                    onPressed: () => _fetch(next: _results.isNotEmpty),
                  ),
          ),
        T(
          kind == 'anime'
              ? 'Data from AniList'
              : kind == 'match'
              ? 'Fixtures from ESPN'
              : 'Lists from TMDB, IMDb ratings via OMDb. This app uses the TMDB API but is not endorsed or '
                    'certified by TMDB.',
          variant: TextVariant.small,
          dim: true,
          align: TextAlign.center,
        ),
      ],
    );
  }
}

class _ManualForm extends StatefulWidget {
  const _ManualForm({required this.onSave});

  /// Saves the title; returns a message when it cannot be added.
  final Future<String?> Function(String kind, String title, String date) onSave;

  @override
  State<_ManualForm> createState() => _ManualFormState();
}

class _ManualFormState extends State<_ManualForm> {
  final _title = TextEditingController();
  String _kind = 'movie';
  String _date = '';
  String _error = '';

  /// True while saving, so a second tap cannot add the title twice.
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return setState(() => _error = 'Enter the title.');
    setState(() => _busy = true);
    final problem = await widget.onSave(_kind, title, _date);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = problem ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return FormColumn(
      children: [
        Segmented<String>(
          value: _kind,
          onChanged: (v) => setState(() => _kind = v),
          options: const {'movie': 'Movie', 'series': 'Series', 'anime': 'Anime', 'match': 'Match'},
        ),
        Field(label: 'Title', controller: _title, hint: _kind == 'match' ? 'Home vs Away' : 'Title', autofocus: true),
        DateField(
          label: _kind == 'match' ? 'Match day' : 'Release date',
          value: _date,
          onChanged: (d) => setState(() => _date = d),
          optional: true,
        ),
        if (_error.isNotEmpty) T(_error, color: context.colors.danger),
        AppButton('Add to my list', onPressed: _busy ? null : _save),
      ],
    );
  }
}
