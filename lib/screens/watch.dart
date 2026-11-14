import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../date.dart';
import '../db.dart';
import '../pickers.dart';
import '../theme.dart';
import '../ui.dart';
import '../watch_api.dart';
import 'settings.dart';

const _kindLabel = {'anime': 'Anime', 'movie': 'Movie', 'series': 'Series'};
const _kindIcon = {'anime': Icons.auto_awesome, 'movie': Icons.movie_outlined, 'series': Icons.tv};

final _ratingPart = RegExp(r'^(IMDb|TMDB|AniList) ');

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with Live {
  /// 'mine', or the kind being browsed.
  String _tab = 'mine';
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
      'movie' => 120,
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

  Future<void> _remove(Rec item) async {
    final row = {...item}..remove('live_event_id');
    await appDb.transaction((txn) async {
      if (item['live_event_id'] != null) {
        await txn.execute('DELETE FROM events WHERE id = ?', [item['live_event_id']]);
      }
      await txn.execute('DELETE FROM watch_items WHERE id = ?', [item['id']]);
    });
    showUndo('Removed ${item['title']}', () => appDb.restore('watch_items', row));
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
    await appDb.insert(
      'INSERT OR IGNORE INTO watch_items (kind, title, release_date, detail, ext_id, poster) VALUES (?, ?, ?, ?, ?, ?)',
      [
        f.kind,
        f.title,
        date,
        [note, f.rating].where((s) => s.isNotEmpty).join(' · '),
        f.extId,
        f.poster,
      ],
    );
  }

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
          await appDb.insert('INSERT INTO watch_items (kind, title, release_date, detail) VALUES (?, ?, ?, ?)', [
            kind,
            title,
            date.isEmpty ? null : date,
            '',
          ]);
          if (sheet.mounted) Navigator.pop(sheet);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tmdbKey = appDb.setting('tmdb_key', '');
    final omdbKey = appDb.setting('omdb_key', '');
    final mine = _tab == 'mine';
    final today = todayKey();
    final upcoming = _items.where((i) => ((i['release_date'] as String?) ?? '').compareTo(today) >= 0).toList();
    final rest = _items.where((i) => !upcoming.contains(i)).toList();

    return Screen(
      title: 'Watchlist',
      subtitle: _items.isEmpty ? 'Movies, series and anime' : '${_items.length} saved · ${upcoming.length} coming up',
      actions: [HeaderIcon(Icons.key_outlined, label: 'Movie and series keys', onPressed: _openKeys)],
      fabLabel: mine ? 'Add title' : null,
      onFab: _openAdd,
      children: [
        Segmented<String>(
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
          options: const {'mine': 'My list', 'movie': 'Movies', 'series': 'Series', 'anime': 'Anime'},
        ),
        if (mine) ...[
          if (ready && _items.isEmpty)
            const Empty(
              icon: Icons.bookmark_add_outlined,
              title: 'Your list is empty',
              hint: 'Open Movies, Series or Anime to see what is hot and save what you want to watch.',
            ),
          if (upcoming.isNotEmpty)
            Section(title: 'Coming up', children: [for (final item in upcoming) _itemCard(item)]),
          if (rest.isNotEmpty)
            Section(
              title: upcoming.isEmpty ? 'Saved' : 'Out now or undated',
              children: [for (final item in rest) _itemCard(item)],
            ),
        ] else if (_tab != 'anime' && tmdbKey.isEmpty)
          Empty(
            icon: Icons.key_outlined,
            title: 'Two free keys needed',
            hint:
                'Hot movies and series come from TMDB, and their IMDb ratings from OMDb. Both are free, '
                'and you paste each key in once.',
            action: AppButton('Add my keys', onPressed: _openKeys),
          )
        else ...[
          if (_tab != 'anime' && omdbKey.isEmpty)
            AppCard(
              children: [
                const T('Showing TMDB scores. Add a free OMDb key to see IMDb ratings instead.', dim: true),
                AppButton('Add OMDb key', kind: ButtonKind.soft, small: true, onPressed: _openKeys),
              ],
            ),
          _Browser(
            key: ValueKey(_tab),
            kind: _tab,
            tmdbKey: tmdbKey,
            omdbKey: omdbKey,
            savedIds: {for (final i in _items) i['ext_id'] as String?},
            onSave: _saveFound,
            onFixKeys: _openKeys,
          ),
        ],
      ],
    );
  }

  Widget _itemCard(Rec item) {
    final c = context.colors;
    final release = item['release_date'] as String?;
    final detail = item['detail'] as String;
    final kind = item['kind'] as String;
    final days = release == null ? null : daysBetween(todayKey(), release);
    final upcoming = days != null && days >= 0;
    final when = release == null
        ? 'No date'
        : !upcoming
        ? 'Out now'
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
            if (item['live_event_id'] != null)
              AppChip('On calendar', icon: Icons.check, selected: true, color: c.success)
            else
              AppButton(
                upcoming ? 'Add to calendar' : 'Plan a watch night',
                icon: Icons.event_available_outlined,
                kind: ButtonKind.soft,
                small: true,
                onPressed: () => _addToCalendar(item),
              ),
            const Spacer(),
            AppButton('Remove', kind: ButtonKind.plain, small: true, onPressed: () => _remove(item)),
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
    required this.savedIds,
    required this.onSave,
    required this.onFixKeys,
  });

  final String kind;
  final String tmdbKey;
  final String omdbKey;
  final Set<String?> savedIds;
  final Future<void> Function(Found) onSave;
  final VoidCallback onFixKeys;

  @override
  State<_Browser> createState() => _BrowserState();
}

class _BrowserState extends State<_Browser> {
  final _text = TextEditingController();
  String _search = '';
  String _mode = 'hot';

  // Each request gets a number; an answer to anything but the latest is dropped.
  int _request = 0;
  bool _loading = true;
  String _error = '';
  bool _badKey = false;
  List<Found> _results = [];

  /// Titles being saved right now, so the button cannot be pressed twice.
  final _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(_Browser old) {
    super.didUpdateWidget(old);
    if (old.tmdbKey != widget.tmdbKey || old.omdbKey != widget.omdbKey) _fetch();
  }

  @override
  void dispose() {
    _request = -1;
    _text.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = '';
      _results = [];
    });
    try {
      final found = widget.kind == 'anime'
          ? await fetchAnime(_search)
          : await fetchTitles(widget.kind, _mode, _search, tmdbKey: widget.tmdbKey, omdbKey: widget.omdbKey);
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _results = found;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _badKey = e is KeyError;
        _error = e is KeyError ? e.message : 'Check your internet connection and try again.';
      });
    }
  }

  void _setSearch(String value) {
    FocusManager.instance.primaryFocus?.unfocus();
    _search = value;
    _fetch();
  }

  void _setMode(String mode) {
    if (_mode == mode) return;
    _mode = mode;
    _fetch();
  }

  Future<void> _save(Found f) async {
    setState(() => _saving.add(f.extId));
    try {
      await widget.onSave(f);
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
    final thisYear = todayKey().substring(0, 4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.lg,
      children: [
        Field(
          controller: _text,
          icon: Icons.search,
          hint: 'Search $plural',
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          onSubmitted: (v) => _setSearch(v.trim()),
        ),
        if ((kind != 'anime' && _search.isEmpty) || _search.isNotEmpty || typed.isNotEmpty)
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              if (kind != 'anime' && _search.isEmpty) ...[
                AppChip('Hot this week', selected: _mode == 'hot', onPressed: () => _setMode('hot')),
                AppChip('Coming soon', selected: _mode == 'upcoming', onPressed: () => _setMode('upcoming')),
              ],
              if (_search.isNotEmpty)
                AppChip(
                  'Clear search',
                  icon: Icons.close,
                  onPressed: () {
                    _text.clear();
                    _setSearch('');
                  },
                )
              else if (typed.isNotEmpty)
                AppChip('Search', icon: Icons.search, selected: true, onPressed: () => _setSearch(typed)),
            ],
          ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator(color: c.accent)),
          ),
        if (_error.isNotEmpty)
          Empty(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load titles',
            hint: _error,
            action: _badKey
                ? AppButton('Check my keys', kind: ButtonKind.soft, onPressed: widget.onFixKeys)
                : AppButton('Try again', kind: ButtonKind.soft, onPressed: _fetch),
          ),
        if (!_loading && _error.isEmpty && _results.isEmpty)
          const Empty(icon: Icons.search_off, title: 'Nothing found', hint: 'Try a different title.'),
        for (final f in _results)
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
                  if (widget.savedIds.contains(f.extId))
                    AppChip('Saved', icon: Icons.check, selected: true, color: c.success)
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

class _ManualForm extends StatefulWidget {
  const _ManualForm({required this.onSave});

  final void Function(String kind, String title, String date) onSave;

  @override
  State<_ManualForm> createState() => _ManualFormState();
}

class _ManualFormState extends State<_ManualForm> {
  final _title = TextEditingController();
  String _kind = 'movie';
  String _date = '';
  String _error = '';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return setState(() => _error = 'Enter the title.');
    widget.onSave(_kind, title, _date);
  }

  @override
  Widget build(BuildContext context) {
    return FormColumn(
      children: [
        Segmented<String>(
          value: _kind,
          onChanged: (v) => setState(() => _kind = v),
          options: const {'movie': 'Movie', 'series': 'Series', 'anime': 'Anime'},
        ),
        Field(label: 'Title', controller: _title, hint: 'Title', autofocus: true),
        DateField(label: 'Release date', value: _date, onChanged: (d) => setState(() => _date = d), optional: true),
        if (_error.isNotEmpty) T(_error, color: context.colors.danger),
        AppButton('Add to my list', onPressed: _save),
      ],
    );
  }
}
