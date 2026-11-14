import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// One row as returned by SQLite.
typedef Rec = Map<String, Object?>;

const _databaseVersion = 5;

const _tables = [
  'events', 'routines', 'day_offs', 'notes', 'watch_items', //
  'food_logs', 'workout_sets', 'transactions', 'ratings', 'settings',
];

/// The single database handle. Set once in `main` (and in tests).
late AppDb appDb;

/// The on-device database. Notifies listeners after every write so screens can re-read.
class AppDb extends ChangeNotifier {
  AppDb._(this.raw, this._settings);

  final Database raw;
  final Map<String, Object?> _settings;

  static Future<AppDb> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final raw = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'life.db'),
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: (db, version) => _migrate(db, 0),
        onUpgrade: (db, from, to) => _migrate(db, from),
      ),
    );
    return AppDb._(raw, await _readSettings(raw));
  }

  static Future<Map<String, Object?>> _readSettings(Database raw) async {
    final rows = await raw.rawQuery('SELECT key, value FROM settings');
    return {for (final r in rows) r['key'] as String: jsonDecode(r['value'] as String)};
  }

  Future<List<Rec>> query(String sql, [List<Object?> args = const []]) => raw.rawQuery(sql, args);

  /// Run one write statement and refresh every screen.
  Future<void> run(String sql, [List<Object?> args = const []]) async {
    await raw.execute(sql, args);
    notifyListeners();
  }

  /// Run one INSERT, refresh every screen, and return the new row id.
  Future<int> insert(String sql, [List<Object?> args = const []]) async {
    final id = await raw.rawInsert(sql, args);
    notifyListeners();
    return id;
  }

  /// Several writes as one unit, with a single refresh at the end.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final result = await raw.transaction(action);
    notifyListeners();
    return result;
  }

  /// A JSON value kept in the settings table, read from memory.
  T setting<T>(String key, T fallback) {
    final v = _settings[key];
    return v is T && v != null ? v : fallback;
  }

  Future<void> setSetting(String key, Object? value) async {
    _settings[key] = value;
    await run('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, jsonEncode(value)]);
  }

  /// Puts a deleted row back exactly as it was (used by Undo).
  Future<void> restore(String table, Rec row) {
    final columns = row.keys.join(', ');
    final marks = List.filled(row.length, '?').join(', ');
    return run('INSERT OR REPLACE INTO $table ($columns) VALUES ($marks)', row.values.toList());
  }

  /// Makes every screen re-read, e.g. when the app comes back to the foreground on a new day.
  void refresh() => notifyListeners();

  Future<void> eraseAll() async {
    await raw.transaction((txn) async {
      for (final table in _tables) {
        await txn.execute('DELETE FROM $table');
      }
    });
    _settings.clear();
    notifyListeners();
  }
}

/// Add a new `if (from < N)` block per schema change.
Future<void> _migrate(Database db, int from) async {
  if (from < 1) {
    const statements = [
      'CREATE TABLE settings (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',

      // Weekly repeating blocks. days is a comma list of weekdays, 0 = Monday.
      '''CREATE TABLE routines (
        id INTEGER PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        days TEXT NOT NULL,
        start_min INTEGER NOT NULL,
        end_min INTEGER NOT NULL,
        flex_min INTEGER NOT NULL DEFAULT 0,
        created_date TEXT NOT NULL
      )''',

      // One block on one day. Routine blocks are copied in the first time a day is opened,
      // so each day can be shifted, ticked off or removed without touching the routine.
      '''CREATE TABLE events (
        id INTEGER PRIMARY KEY NOT NULL,
        routine_id INTEGER,
        date TEXT NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        start_min INTEGER NOT NULL,
        end_min INTEGER NOT NULL,
        flex_min INTEGER NOT NULL DEFAULT 0,
        shift_min INTEGER NOT NULL DEFAULT 0,
        done INTEGER NOT NULL DEFAULT 0,
        hidden INTEGER NOT NULL DEFAULT 0
      )''',
      'CREATE INDEX events_date ON events (date)',
      'CREATE UNIQUE INDEX events_routine_day ON events (routine_id, date) WHERE routine_id IS NOT NULL',

      'CREATE TABLE day_offs (date TEXT PRIMARY KEY NOT NULL)',

      '''CREATE TABLE notes (
        id INTEGER PRIMARY KEY NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        pinned INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )''',

      '''CREATE TABLE watch_items (
        id INTEGER PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        release_date TEXT,
        detail TEXT NOT NULL DEFAULT '',
        ext_id TEXT,
        event_id INTEGER
      )''',
      'CREATE UNIQUE INDEX watch_ext ON watch_items (ext_id) WHERE ext_id IS NOT NULL',

      '''CREATE TABLE food_logs (
        id INTEGER PRIMARY KEY NOT NULL,
        date TEXT NOT NULL,
        name TEXT NOT NULL,
        kcal REAL NOT NULL DEFAULT 0,
        protein REAL NOT NULL DEFAULT 0,
        carbs REAL NOT NULL DEFAULT 0,
        fat REAL NOT NULL DEFAULT 0
      )''',
      'CREATE INDEX food_date ON food_logs (date)',

      '''CREATE TABLE workout_sets (
        id INTEGER PRIMARY KEY NOT NULL,
        date TEXT NOT NULL,
        muscle TEXT NOT NULL,
        exercise TEXT NOT NULL,
        weight REAL NOT NULL DEFAULT 0,
        reps INTEGER NOT NULL DEFAULT 0
      )''',
      'CREATE INDEX sets_date ON workout_sets (date)',

      // kind: income | expense | saving. amount is always positive.
      '''CREATE TABLE transactions (
        id INTEGER PRIMARY KEY NOT NULL,
        date TEXT NOT NULL,
        kind TEXT NOT NULL,
        amount REAL NOT NULL,
        label TEXT NOT NULL DEFAULT ''
      )''',
      'CREATE INDEX tx_date ON transactions (date)',
    ];
    for (final s in statements) {
      await db.execute(s);
    }
  }

  if (from < 2) {
    // IMDb ratings looked up online, kept so each title is only fetched about once a week.
    await db.execute('''CREATE TABLE ratings (
      key TEXT PRIMARY KEY NOT NULL,
      rating TEXT,
      fetched TEXT NOT NULL
    )''');
  }

  if (from < 3) {
    // Poster image address for titles saved from the online lists.
    await db.execute('ALTER TABLE watch_items ADD COLUMN poster TEXT');
  }

  if (from < 4) {
    // The watchlist could hold the same title twice: typed in by hand more than once, or typed in and
    // also saved from an online list. Keep one of each, preferring the one linked to an online source.
    // Two entries that are both linked are different works that share a name, so both stay.
    final rows = await db.rawQuery('SELECT * FROM watch_items ORDER BY ext_id IS NULL, id');
    final kept = <String, Rec>{};
    for (final row in rows) {
      final key = watchTitleKey(row['kind'] as String, row['title'] as String);
      final keeper = kept[key];
      if (keeper == null || row['ext_id'] != null) {
        kept.putIfAbsent(key, () => Map.of(row));
        continue;
      }
      // A calendar block planned for the copy stays linked.
      if (keeper['event_id'] == null && row['event_id'] != null) {
        keeper['event_id'] = row['event_id'];
        await db.execute('UPDATE watch_items SET event_id = ? WHERE id = ?', [row['event_id'], keeper['id']]);
      }
      await db.execute('DELETE FROM watch_items WHERE id = ?', [row['id']]);
    }
  }

  if (from < 5) {
    // A note that is a drawing keeps its strokes here as JSON; null for a written note.
    await db.execute('ALTER TABLE notes ADD COLUMN sketch TEXT');
  }
}

/// Two watchlist titles of the same kind are the same one when this matches.
/// Case, spaces and punctuation are ignored.
String watchTitleKey(String kind, String title) =>
    '$kind:${title.toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '')}';

/// For a screen that shows database rows: implement [load] to read them into fields.
/// It runs once at start and again after every write anywhere in the app.
/// [ready] is false until the first read finishes, so screens can avoid flashing an empty state.
mixin Live<W extends StatefulWidget> on State<W> {
  bool ready = false;
  int _generation = 0;

  Future<void> load();

  Future<void> reload() async {
    final generation = ++_generation;
    try {
      await load();
    } catch (e) {
      debugPrint('load failed in $runtimeType: $e');
    }
    if (!mounted || generation != _generation) return;
    setState(() => ready = true);
  }

  @override
  void initState() {
    super.initState();
    appDb.addListener(reload);
    reload();
  }

  @override
  void dispose() {
    appDb.removeListener(reload);
    super.dispose();
  }
}
