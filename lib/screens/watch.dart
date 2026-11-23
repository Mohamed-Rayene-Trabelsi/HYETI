import 'dart:convert';
import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../date.dart';
import '../db.dart';
import '../football.dart';
import '../football_pickers.dart';
import '../genre_picker.dart';
import '../genres.dart';
import '../theme.dart';
import '../ui.dart';
import '../watch_api.dart';
import '../watch_prefs.dart';
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

  /// The genre each list is filtered by: 'mine', 'movie', 'series' or 'anime' → genre; absent for all.
  final _genres = <String, String>{};

  void _setGenre(String list, String? genre) =>
      setState(() => genre == null ? _genres.remove(list) : _genres[list] = genre);

  @override
  void initState() {
    super.initState();
    _refreshStale();
    _fillGenres();
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

  /// Titles saved before genres were kept get theirs looked up, a few a day, so the genre filter and the
  /// suggestions know about them too.
  Future<void> _fillGenres() async {
    final today = todayKey();
    if (appDb.setting('genres_filled', '') == today) return;
    final tmdbKey = appDb.setting('tmdb_key', '');
    var changed = false, reached = false;
    final rows = await appDb.query(
      "SELECT id, ext_id FROM watch_items WHERE genres IS NULL AND ext_id IS NOT NULL AND ext_id NOT LIKE 'fotmob:%' "
      'LIMIT 25',
    );
    for (final row in rows) {
      try {
        final genres = await fetchGenres(row['ext_id'] as String, tmdbKey);
        if (genres == null) continue;
        reached = true;
        if (genres.isEmpty) continue;
        // Straight to the database, then one redraw at the end.
        await appDb.raw.execute('UPDATE watch_items SET genres = ? WHERE id = ?', [joinGenres(genres), row['id']]);
        changed = true;
      } catch (_) {
        // Offline: try again another day.
      }
    }
    if (reached) await appDb.setSetting('genres_filled', today);
    if (changed) appDb.refresh();
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
    final genres = joinGenres(f.genres);
    // A title typed in by hand earlier becomes this one, rather than sitting beside it as a duplicate.
    final typed = _items.where((i) => i['ext_id'] == null && _sameTitle(i, f.kind, f.title)).firstOrNull;
    if (typed != null) {
      await appDb.run(
        'UPDATE OR IGNORE watch_items SET title = ?, release_date = ?, detail = ?, ext_id = ?, poster = ?, genres = ? '
        'WHERE id = ?',
        [f.title, date, detail, f.extId, f.poster, genres, typed['id']],
      );
      return;
    }
    await appDb.insert(
      'INSERT OR IGNORE INTO watch_items (kind, title, release_date, detail, ext_id, poster, genres) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [f.kind, f.title, date, detail, f.extId, f.poster, genres],
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

  @override
  Widget build(BuildContext context) {
    final tmdbKey = appDb.setting('tmdb_key', '');
    final omdbKey = appDb.setting('omdb_key', '');
    final football = footballPrefs();
    final prefs = watchPrefs();
    // Only what the person said they watch has a tab; Settings → Watch changes it.
    final showKinds = [
      for (final k in const ['movie', 'series'])
        if (prefs.shows(k)) k,
    ];
    final tabs = {
      'mine': 'My list',
      if (showKinds.isNotEmpty)
        'shows': showKinds.length == 2 ? 'Shows' : (showKinds.single == 'movie' ? 'Movies' : 'Series'),
      if (prefs.shows('anime')) 'anime': 'Anime',
      if (prefs.shows('match')) 'match': 'Football',
    };
    final tab = tabs.containsKey(_tab) ? _tab : 'mine';
    final mine = tab == 'mine';
    final showKind = showKinds.contains(_showKind) || showKinds.isEmpty ? _showKind : showKinds.first;
    final kind = tab == 'shows' ? showKind : tab;
    final today = todayKey();
    // One card per title. A title with any entry still ahead goes under "Coming up", led by that entry;
    // otherwise it goes under "Out now or undated". It is never in both.
    final byTitle = <String, List<Rec>>{};
    for (final item in _items) {
      (byTitle[_listKey(item)] ??= []).add(item);
    }
    final allTitles = [
      for (final copies in byTitle.values)
        [...copies.where((i) => _isUpcoming(i, today)), ...copies.where((i) => !_isUpcoming(i, today))],
    ];
    // The genre filter on My list offers only genres something saved has.
    final myGenres = {for (final item in _items) ...parseGenres(item['genres'])}.toList()..sort();
    final myGenre = myGenres.contains(_genres['mine']) ? _genres['mine'] : null;
    final titles = myGenre == null
        ? allTitles
        : allTitles.where((t) => t.any((i) => parseGenres(i['genres']).contains(myGenre))).toList();
    final upcoming = titles.where((t) => _isUpcoming(t.first, today)).toList();
    final rest = titles.where((t) => !_isUpcoming(t.first, today)).toList();

    return Screen(
      title: 'Watchlist',
      // The tabs below already say what is here; the subtitle only counts what you saved.
      subtitle: !prefs.setUp || allTitles.isEmpty ? null : '${allTitles.length} saved · ${upcoming.length} coming up',
      // Once a key is saved nothing here asks for one again; both stay editable in Settings.
      actions: [
        if (prefs.setUp && showKinds.isNotEmpty && tmdbKey.isEmpty && omdbKey.isEmpty)
          HeaderIcon(Icons.key_outlined, label: 'Movie and series keys', onPressed: _openKeys),
      ],
      children: [
        if (!prefs.setUp)
          const WatchSetup()
        else ...[
          if (tabs.length > 1) Segmented<String>(value: tab, onChanged: (v) => setState(() => _tab = v), options: tabs),
          if (mine) ...[
            if (myGenres.isNotEmpty)
              Wrap(
                children: [GenreChip(options: myGenres, value: myGenre, onChanged: (g) => _setGenre('mine', g))],
              ),
            if (ready && _items.isEmpty)
              Empty(
                icon: Icons.bookmark_add_outlined,
                title: 'Your list is empty',
                hint: tabs.length > 1
                    ? 'Open ${tabs.values.skip(1).join(', ')} to see what is on and save what you want to watch.'
                    : 'Turn on what you watch in Settings, under Watch.',
              ),
            if (_items.isNotEmpty && titles.isEmpty)
              Empty(
                icon: Icons.filter_alt_off_outlined,
                title: 'Nothing saved in $myGenre',
                action: AppButton('Show all genres', kind: ButtonKind.soft, onPressed: () => _setGenre('mine', null)),
              ),
            if (upcoming.isNotEmpty)
              Section(title: 'Coming up', children: [for (final copies in upcoming) _itemCard(copies)]),
            if (rest.isNotEmpty)
              Section(
                title: upcoming.isEmpty ? 'Saved' : 'Out now or undated',
                children: [for (final copies in rest) _itemCard(copies)],
              ),
          ] else if (tab == 'match')
            _FootballView(
              prefs: football,
              isSaved: (f) => _savedAs(f) != null,
              onSave: _saveFound,
              onUnsave: _unsaveFound,
            )
          else if (tab == 'shows' && tmdbKey.isEmpty)
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
            if (tab == 'shows' && showKinds.length == 2)
              Segmented<String>(
                value: showKind,
                onChanged: (v) => setState(() => _showKind = v),
                options: const {'movie': 'Movies', 'series': 'Series'},
              ),
            _Browser(
              key: ValueKey(kind),
              kind: kind,
              tmdbKey: tmdbKey,
              omdbKey: omdbKey,
              genre: _genres[kind],
              onGenre: (g) => _setGenre(kind, g),
              isSaved: (f) => _savedAs(f) != null,
              onSave: _saveFound,
              onUnsave: _unsaveFound,
              onFixKeys: _openKeys,
            ),
          ],
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
            WatchPoster(url: item['poster'] as String?, kind: kind),
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
class WatchPoster extends StatelessWidget {
  const WatchPoster({super.key, required this.url, required this.kind});

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
    required this.genre,
    required this.onGenre,
    required this.isSaved,
    required this.onSave,
    required this.onUnsave,
    required this.onFixKeys,
  });

  final String kind;
  final String tmdbKey;
  final String omdbKey;

  /// The genre to keep to; null for all.
  final String? genre;
  final ValueChanged<String?> onGenre;

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

  /// 'hot' (trending), 'upcoming' (movies and series only) or 'foryou' (suggestions from what was saved).
  String _mode = 'hot';

  /// In "For you", true when nothing saved says what the person likes yet.
  bool _noTaste = false;

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

  /// Saved while this list was on screen: stays in it, marked saved, rather than vanishing under the finger.
  final _keep = <String>{};

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
    if (old.tmdbKey != widget.tmdbKey || old.omdbKey != widget.omdbKey || old.genre != widget.genre) _fetch();
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
      _noTaste = false;
      if (!next) _results = [];
    });
    try {
      final taste = _mode == 'foryou' && _search.isEmpty ? await loadTaste() : null;
      if (taste != null && taste.isEmpty) {
        if (!mounted || request != _request) return;
        return setState(() {
          _loading = false;
          _noTaste = true;
          _more = false;
        });
      }
      final found = switch (widget.kind) {
        'anime' => await fetchAnime(_search, page: page, genre: widget.genre, taste: taste),
        _ => await fetchTitles(
          widget.kind,
          _mode,
          _search,
          tmdbKey: widget.tmdbKey,
          omdbKey: widget.omdbKey,
          page: page,
          genre: widget.genre,
          taste: taste,
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
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 400), () => _setSearch(value.trim()));
  }

  void _setSearch(String value) {
    _typing?.cancel();
    if (!mounted || value == _search) return;
    _search = value;
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
    setState(() {
      _saving.add(f.extId);
      _keep.add(f.extId);
    });
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
      _ => 'anime',
    };
    final typed = _text.text.trim();
    // What is on My list stays there and leaves the other lists, except when searching for it by name.
    final results = typed.isEmpty
        ? _results.where((f) => !widget.isSaved(f) || _keep.contains(f.extId)).toList()
        : _results;
    final allSaved = results.isEmpty && _results.isNotEmpty;
    final chips = [
      if (typed.isEmpty) ...[
        AppChip(
          kind == 'anime' ? 'Trending' : 'Hot this week',
          selected: _mode == 'hot',
          onPressed: () => _setMode('hot'),
        ),
        if (kind != 'anime')
          AppChip('Coming soon', selected: _mode == 'upcoming', onPressed: () => _setMode('upcoming')),
        AppChip(
          'For you',
          icon: Icons.auto_awesome_outlined,
          selected: _mode == 'foryou',
          onPressed: () => _setMode('foryou'),
        ),
      ],
      GenreChip(options: genresFor(kind), value: widget.genre, onChanged: widget.onGenre),
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
            _setSearch(v.trim());
          },
        ),
        if (chips.isNotEmpty) Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: chips),
        if (_noTaste)
          Empty(
            icon: Icons.auto_awesome_outlined,
            title: 'Save a few you like',
            hint:
                'Suggestions come from what is on your list. Save some $plural you enjoyed and '
                'they show up here.',
            action: AppButton('See what is hot', kind: ButtonKind.soft, onPressed: () => _setMode('hot')),
          )
        else if (allSaved && !_loading)
          Empty(
            icon: Icons.bookmark_added_outlined,
            title: 'All on your list',
            hint: 'Everything here is already saved. It is under My list.',
            action: _more ? AppButton('Show more', kind: ButtonKind.soft, onPressed: () => _fetch(next: true)) : null,
          )
        else if (!_loading && _error.isEmpty && results.isEmpty)
          Empty(
            icon: Icons.search_off,
            title: 'Nothing found',
            hint: widget.genre != null && typed.isEmpty
                ? 'Nothing in ${widget.genre} here. Try another genre.'
                : 'Check the spelling, or try the original title.',
          ),
        for (final f in results)
          _FoundCard(
            found: f,
            saved: widget.isSaved(f),
            busy: _saving.contains(f.extId),
            onSave: () => _save(f),
            onUnsave: () => _save(f, off: true),
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
            title: _results.isNotEmpty ? 'Could not load more' : 'Could not load titles',
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

/// One title or match found online, with its Save button.
class _FoundCard extends StatelessWidget {
  const _FoundCard({
    required this.found,
    required this.saved,
    required this.busy,
    required this.onSave,
    required this.onUnsave,
    this.showDay = true,
  });

  final Found found;
  final bool saved;

  /// Being saved right now, so the button cannot be pressed twice.
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onUnsave;

  /// False under a day heading that already says the day.
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = found;
    final thisYear = todayKey().substring(0, 4);
    return AppCard(
      children: [
        Row(
          spacing: Spacing.md,
          children: [
            WatchPoster(url: f.poster, kind: f.kind),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  T(f.title, variant: TextVariant.heading, maxLines: 2),
                  T(
                    [
                      if (showDay && f.releaseDate != null)
                        formatDay(f.releaseDate!) +
                            (f.releaseDate!.startsWith(thisYear) ? '' : ' ${f.releaseDate!.substring(0, 4)}'),
                      if (f.note.isNotEmpty) f.note,
                    ].join(' · '),
                    variant: TextVariant.small,
                    dim: true,
                    maxLines: 2,
                  ),
                  if (f.rating.isNotEmpty) T('★ ${f.rating}', variant: TextVariant.label, color: c.warn),
                  if (f.reason.isNotEmpty) T(f.reason, variant: TextVariant.small, color: c.accent, maxLines: 2),
                ],
              ),
            ),
            if (saved)
              Semantics(
                label: 'Remove ${f.title} from my list',
                child: AppChip('Saved', icon: Icons.check, selected: true, color: c.success, onPressed: onUnsave),
              )
            else
              AppButton(
                'Save',
                icon: Icons.bookmark_add_outlined,
                kind: ButtonKind.soft,
                small: true,
                onPressed: busy ? null : onSave,
              ),
          ],
        ),
      ],
    );
  }
}

/// Football made to measure: a first-time setup, then the next two weeks of what is followed.
/// What is followed is changed in Settings only, so nothing here filters; the search looks up any one team.
class _FootballView extends StatefulWidget {
  const _FootballView({required this.prefs, required this.isSaved, required this.onSave, required this.onUnsave});

  final FootballPrefs prefs;
  final bool Function(Found) isSaved;
  final Future<void> Function(Found) onSave;
  final Future<void> Function(Found) onUnsave;

  @override
  State<_FootballView> createState() => _FootballViewState();
}

class _FootballViewState extends State<_FootballView> {
  /// The last list loaded, kept for half an hour so moving between tabs does not download it again.
  static ({String key, DateTime at, List<FootballMatch> matches})? _cache;

  final _text = TextEditingController();
  Timer? _typing;
  int _request = 0;
  bool _loading = false;
  String _error = '';
  List<FootballMatch> _matches = [];

  /// Teams found by the search, and the one picked from them with its matches.
  List<Team> _found = [];
  Team? _picked;
  List<FootballMatch> _pickedMatches = [];

  final _saving = <String>{};

  String get _key => '${jsonEncode(widget.prefs.toJson())}|${todayKey()}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_FootballView old) {
    super.didUpdateWidget(old);
    if (jsonEncode(old.prefs.toJson()) != jsonEncode(widget.prefs.toJson())) _load();
  }

  @override
  void dispose() {
    _request = -1;
    _typing?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load({bool fresh = false}) async {
    final prefs = widget.prefs;
    if (!prefs.setUp || prefs.followsNothing) return setState(() => _matches = []);
    final cache = _cache;
    if (!fresh && cache != null && cache.key == _key && DateTime.now().difference(cache.at).inMinutes < 30) {
      return setState(() => _matches = cache.matches);
    }
    final request = ++_request;
    final key = _key;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final matches = await followedMatches(prefs);
      _cache = (key: key, at: DateTime.now(), matches: matches);
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _matches = matches;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = footballError(e);
      });
    }
  }

  void _onTyped(String value) {
    _typing?.cancel();
    final term = value.trim();
    setState(() {
      _picked = null;
      if (term.length < 2) _found = [];
    });
    if (term.length < 2) return;
    _typing = Timer(const Duration(milliseconds: 400), () => _search(term));
  }

  Future<void> _search(String term) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final found = await searchTeams(term);
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _found = found;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Could not search. Is the phone online?';
      });
    }
  }

  Future<void> _pick(Team team) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final request = ++_request;
    setState(() {
      _picked = team;
      _pickedMatches = [];
      _loading = true;
      _error = '';
    });
    try {
      final matches = await searchedTeamMatches(team.id);
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _pickedMatches = matches;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = footballError(e);
      });
    }
  }

  void _clearSearch() {
    _text.clear();
    _request++;
    setState(() {
      _found = [];
      _picked = null;
      _loading = false;
      _error = '';
    });
    _load();
  }

  Future<void> _save(Found f, {bool off = false}) async {
    if (_saving.contains(f.extId)) return;
    setState(() => _saving.add(f.extId));
    try {
      await (off ? widget.onUnsave(f) : widget.onSave(f));
    } finally {
      if (mounted) setState(() => _saving.remove(f.extId));
    }
  }

  Future<void> _notAFan() async {
    final before = widget.prefs;
    await saveFootballPrefs(before.copyWith(setUp: true, off: true));
    showUndo('Football is hidden. Settings can bring it back.', () => saveFootballPrefs(before));
  }

  void _openSettings() =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  /// Matches under a heading per day.
  List<Widget> _days(List<FootballMatch> matches) {
    final byDay = <String, List<FootballMatch>>{};
    for (final m in matches) {
      (byDay[m.date] ??= []).add(m);
    }
    return [
      for (final MapEntry(key: day, value: list) in byDay.entries)
        Section(
          title: relativeDay(day),
          children: [
            for (final m in list)
              () {
                final f = m.toFound();
                return _FoundCard(
                  found: f,
                  showDay: false,
                  saved: widget.isSaved(f),
                  busy: _saving.contains(f.extId),
                  onSave: () => _save(f),
                  onUnsave: () => _save(f, off: true),
                );
              }(),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final prefs = widget.prefs;
    if (!prefs.setUp) {
      return Empty(
        icon: Icons.sports_soccer,
        title: 'Make Football yours',
        hint:
            'Pick your country, your clubs and the big leagues you care about, and see their next two weeks of '
            'matches. Matches of your country and clubs also go on your calendar.',
        action: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Spacing.sm,
          children: [
            AppButton('Get started', onPressed: () => openFootballSetup(context)),
            AppButton("I don't follow football", kind: ButtonKind.plain, onPressed: _notAFan),
          ],
        ),
      );
    }

    final typed = _text.text.trim().length >= 2;
    final spinner = Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
      child: Center(child: CircularProgressIndicator(color: c.accent)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.lg,
      children: [
        Field(
          controller: _text,
          icon: Icons.search,
          hint: 'Look up any team',
          textInputAction: TextInputAction.search,
          onChanged: _onTyped,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        if (typed || _picked != null)
          Wrap(
            children: [AppChip('Clear search', icon: Icons.close, onPressed: _clearSearch)],
          ),
        if (_picked != null) ...[
          T('${_picked!.name} · next two weeks', variant: TextVariant.label, dim: true),
          if (_loading) spinner,
          if (!_loading && _error.isEmpty && _pickedMatches.isEmpty)
            Empty(
              icon: Icons.event_busy,
              title: 'No match in the next two weeks',
              hint: '${_picked!.name} has nothing scheduled before ${formatDay(addDays(todayKey(), footballDays))}.',
            ),
          ..._days(_pickedMatches),
        ] else if (typed) ...[
          if (_loading) spinner,
          if (!_loading && _error.isEmpty && _found.isEmpty)
            const Empty(icon: Icons.search_off, title: 'No team by that name', hint: 'Check the spelling.'),
          if (_found.isNotEmpty)
            AppCard(
              padding: listCardPadding,
              children: [
                for (final (i, team) in _found.indexed)
                  ListRow(
                    divider: i > 0,
                    onTap: () => _pick(team),
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            T(team.name, maxLines: 1),
                            T(
                              team.league.isEmpty ? 'National team' : team.league,
                              variant: TextVariant.small,
                              dim: true,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: c.textDim),
                    ],
                  ),
              ],
            ),
        ] else if (prefs.followsNothing)
          Empty(
            icon: Icons.sports_soccer,
            title: 'You follow nothing yet',
            hint: 'Choose your country, clubs and leagues in Settings, under Football.',
            action: AppButton('Open Settings', kind: ButtonKind.soft, onPressed: _openSettings),
          )
        else ...[
          if (_loading) spinner,
          if (!_loading && _error.isEmpty && _matches.isEmpty)
            const Empty(
              icon: Icons.event_busy,
              title: 'No matches in the next two weeks',
              hint: 'Nothing you follow plays before then.',
            ),
          // Saved matches stay here: followed teams' matches are saved by themselves, and this is their schedule.
          ..._days(_matches),
        ],
        if (_error.isNotEmpty)
          Empty(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load matches',
            hint: _error,
            action: AppButton(
              'Try again',
              kind: ButtonKind.soft,
              onPressed: () => _picked != null
                  ? _pick(_picked!)
                  : typed
                  ? _search(_text.text.trim())
                  : _load(fresh: true),
            ),
          ),
        const T(
          'Fixtures from FotMob. Change what you follow in Settings.',
          variant: TextVariant.small,
          dim: true,
          align: TextAlign.center,
        ),
      ],
    );
  }
}

/// What to say when football could not be loaded: offline, or FotMob (unofficial, and free to change without notice)
/// answering in a way this version does not understand.
String footballError(Object e) => e is SocketException || e is TimeoutException || e is http.ClientException
    ? 'Check your internet connection and try again.'
    : 'FotMob did not answer as expected. It is an unofficial source and may have changed, so this can last until '
          'HYETI is updated. Matches already on your calendar stay there.';
