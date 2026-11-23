import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'date.dart';
import 'db.dart';
import 'watch_api.dart' show Found, httpClient;

/*
 * Football from FotMob's public data, which needs no key. It is unofficial, like ESPN's was, so a change
 * on their side can break it. Only what the person follows or searches for is ever asked for: one request
 * per team or league, never a whole day of every match in the world.
 */

const _timeout = Duration(seconds: 15);

/// How far ahead the Football tab and the calendar look.
const footballDays = 14;

/// The five big leagues offered in the setup, by FotMob's id.
const topLeagues = {47: 'Premier League', 87: 'LaLiga', 55: 'Serie A', 54: 'Bundesliga', 53: 'Ligue 1'};

/// A club or national team.
class Team {
  const Team(this.id, this.name, {this.league = ''});

  factory Team.fromJson(Map<String, dynamic> j) =>
      Team((j['id'] as num).toInt(), j['name'] as String, league: j['league'] as String? ?? '');

  final int id;
  final String name;

  /// The league a club plays in, for telling clubs with similar names apart; '' for a national team.
  final String league;

  Map<String, Object> toJson() => {'id': id, 'name': name, if (league.isNotEmpty) 'league': league};

  @override
  bool operator ==(Object other) => other is Team && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// What the person follows, kept as one JSON value in settings under 'football'.
class FootballPrefs {
  const FootballPrefs({
    this.setUp = false,
    this.off = false,
    this.nation,
    this.clubs = const [],
    this.leagues = const [],
  });

  factory FootballPrefs.fromJson(Map<String, dynamic> j) => FootballPrefs(
    setUp: j['setUp'] == true,
    off: j['off'] == true,
    nation: j['nation'] == null ? null : Team.fromJson((j['nation'] as Map).cast<String, dynamic>()),
    clubs: [for (final c in (j['clubs'] as List? ?? const [])) Team.fromJson((c as Map).cast<String, dynamic>())],
    leagues: [for (final l in (j['leagues'] as List? ?? const [])) (l as num).toInt()],
  );

  /// Whether the setup was finished or skipped; until then the Football tab asks.
  final bool setUp;

  /// True for someone who does not follow football: the Football tab is not shown.
  final bool off;

  /// The person's national team.
  final Team? nation;
  final List<Team> clubs;

  /// Ids from [topLeagues].
  final List<int> leagues;

  /// The national team and clubs, whose matches also go on the calendar.
  List<Team> get teams => [?nation, ...clubs];

  bool get followsNothing => teams.isEmpty && leagues.isEmpty;

  FootballPrefs copyWith({bool? setUp, bool? off, Team? Function()? nation, List<Team>? clubs, List<int>? leagues}) =>
      FootballPrefs(
        setUp: setUp ?? this.setUp,
        off: off ?? this.off,
        nation: nation == null ? this.nation : nation(),
        clubs: clubs ?? this.clubs,
        leagues: leagues ?? this.leagues,
      );

  Map<String, Object?> toJson() => {
    'setUp': setUp,
    'off': off,
    'nation': nation?.toJson(),
    'clubs': [for (final c in clubs) c.toJson()],
    'leagues': leagues,
  };
}

FootballPrefs footballPrefs() {
  final saved = appDb.setting<Map>('football', const {});
  return FootballPrefs.fromJson(saved.cast<String, dynamic>());
}

/// Saves what is followed and brings the calendar in line with it.
Future<void> saveFootballPrefs(FootballPrefs prefs) async {
  await appDb.setSetting('football', prefs.toJson());
  // Offline: the calendar catches up on the next start.
  unawaited(syncFootballCalendar(force: true).catchError((_) {}));
}

Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
  final res = await httpClient
      .get(Uri.https('www.fotmob.com', '/api/data/$path', query), headers: const {'Accept': 'application/json'})
      .timeout(_timeout);
  if (res.statusCode != 200) throw Exception('FotMob answered ${res.statusCode}');
  final body = jsonDecode(utf8.decode(res.bodyBytes));
  return body is Map<String, dynamic> ? body : {'items': body};
}

/// Teams whose name matches [term]: only national teams when [nations] is true, only clubs when false, both when null.
Future<List<Team>> searchTeams(String term, {bool? nations}) async {
  final body = await _get('search/suggest', {'term': term});
  final teams = <Team>[];
  for (final group in (body['items'] as List? ?? const []).cast<Map<String, dynamic>>()) {
    for (final s in (group['suggestions'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      if (s['type'] != 'team') continue;
      final id = int.tryParse('${s['id']}');
      final name = s['name'] as String?;
      if (id == null || name == null) continue;
      // FotMob files national teams under no league.
      final isNation = (s['leagueId'] as num? ?? 0) == 0;
      if (nations != null && isNation != nations) continue;
      final team = Team(id, name, league: isNation ? '' : s['leagueName'] as String? ?? '');
      if (!teams.contains(team)) teams.add(team);
    }
  }
  return teams;
}

/// One match not yet played.
class FootballMatch {
  const FootballMatch({
    required this.id,
    required this.home,
    required this.away,
    required this.homeId,
    required this.awayId,
    required this.kickOff,
    required this.competition,
    this.dateTbd = false,
    this.timeTbd = false,
  });

  final String id;
  final String home, away;
  final int homeId, awayId;

  /// Local time.
  final DateTime kickOff;
  final String competition;

  /// FotMob's guess while the real date or time is not set yet.
  final bool dateTbd, timeTbd;

  String get extId => 'fotmob:$id';
  String get title => '$home vs $away';
  String get date => toKey(kickOff);
  int get startMin => kickOff.hour * 60 + kickOff.minute;

  /// What is written under the title: the competition and the kick-off time.
  String get detail =>
      '$competition · ${switch ((dateTbd, timeTbd)) {
        (true, _) => 'Date to be confirmed',
        (_, true) => 'Time to be confirmed',
        _ => formatTime(startMin),
      }}';

  bool involves(Team t) => homeId == t.id || awayId == t.id;

  Found toFound() => Found(
    extId: extId,
    kind: 'match',
    title: title,
    releaseDate: date,
    startMin: timeTbd ? null : startMin,
    note: detail,
    rating: '',
    poster: 'https://images.fotmob.com/image_resources/logo/teamlogo/${homeId}_small.png',
  );
}

FootballMatch? _match(Map<String, dynamic> m, String competition) {
  final status = (m['status'] as Map?)?.cast<String, dynamic>() ?? const {};
  if (status['finished'] == true || status['cancelled'] == true || status['started'] == true) return null;
  final kickOff = DateTime.tryParse(status['utcTime'] as String? ?? '')?.toLocal();
  final home = (m['home'] as Map?)?.cast<String, dynamic>(), away = (m['away'] as Map?)?.cast<String, dynamic>();
  if (kickOff == null || home == null || away == null) return null;
  return FootballMatch(
    id: '${m['id']}',
    home: home['name'] as String? ?? 'Home',
    away: away['name'] as String? ?? 'Away',
    homeId: int.tryParse('${home['id']}') ?? 0,
    awayId: int.tryParse('${away['id']}') ?? 0,
    kickOff: kickOff,
    competition: competition,
    dateTbd: status['matchDateTbd'] == true,
    timeTbd: status['matchTimeTbd'] == true,
  );
}

/// A team's coming matches, in every competition it plays.
Future<List<FootballMatch>> teamMatches(int id) async {
  final body = await _get('teams', {'id': '$id'});
  final all = ((body['fixtures'] as Map?)?['allFixtures'] as Map?)?['fixtures'] as List? ?? const [];
  return [
    for (final m in all.cast<Map<String, dynamic>>())
      ?_match(m, ((m['tournament'] as Map?)?['name'] as String?) ?? 'Football'),
  ];
}

/// A league's coming matches.
Future<List<FootballMatch>> leagueMatches(int id) async {
  final body = await _get('leagues', {'id': '$id'});
  final name = ((body['details'] as Map?)?['name'] as String?) ?? topLeagues[id] ?? 'Football';
  final all = (body['fixtures'] as Map?)?['allMatches'] as List? ?? const [];
  return [for (final m in all.cast<Map<String, dynamic>>()) ?_match(m, name)];
}

/// Within the next [footballDays] days of [now], soonest first, each match once.
List<FootballMatch> _soon(Iterable<FootballMatch> matches, DateTime now) {
  final end = DateTime(now.year, now.month, now.day + footballDays + 1);
  final seen = <String>{};
  return [
    for (final m in matches)
      if (!m.kickOff.isBefore(now.subtract(const Duration(hours: 2))) && m.kickOff.isBefore(end) && seen.add(m.id)) m,
  ]..sort((a, b) => a.kickOff.compareTo(b.kickOff));
}

/// The next two weeks of everything followed. One source failing leaves the others; all failing throws.
Future<List<FootballMatch>> followedMatches(FootballPrefs prefs, {DateTime? now}) async {
  final asks = [
    for (final t in prefs.teams) () => teamMatches(t.id),
    for (final l in prefs.leagues) () => leagueMatches(l),
  ];
  var failed = 0;
  Object? lastError;
  final lists = await Future.wait([
    for (final ask in asks)
      ask().catchError((Object e) {
        failed++;
        lastError = e;
        return <FootballMatch>[];
      }),
  ]);
  // Thrown as it came, so the screen can tell being offline from FotMob answering in a way it no longer understands.
  if (asks.isNotEmpty && failed == asks.length) throw lastError ?? Exception('No fixtures could be loaded');
  return _soon(lists.expand((l) => l), now ?? DateTime.now());
}

/// The next two weeks of one team, for a team that was searched for.
Future<List<FootballMatch>> searchedTeamMatches(int id, {DateTime? now}) async =>
    _soon(await teamMatches(id), now ?? DateTime.now());

/// Puts the coming matches of the national team and the favourite clubs on the calendar, once a day.
/// Each match is added once: deleting its block or its watchlist entry keeps it off. A match that moves
/// keeps its block, which moves with it.
Future<void> syncFootballCalendar({DateTime? now, bool force = false}) async {
  final today = toKey(now ?? DateTime.now());
  final prefs = footballPrefs();
  if (prefs.off || prefs.teams.isEmpty) return;
  if (!force && appDb.setting('football_synced', '') == today) return;
  final lists = await Future.wait([for (final t in prefs.teams) teamMatches(t.id)]);
  final matches = _soon(lists.expand((l) => l), now ?? DateTime.now()).where((m) => !m.dateTbd);
  final added = appDb.setting<List>('football_added', const []).cast<String>().toList();
  for (final m in matches) {
    final saved = await appDb.query(
      'SELECT w.id, w.event_id, e.id AS live FROM watch_items w LEFT JOIN events e ON e.id = w.event_id '
      'WHERE w.ext_id = ?',
      [m.extId],
    );
    final start = math.min(m.timeTbd ? 20 * 60 : m.startMin, 1380);
    final end = math.min(start + 120, 1439);
    if (saved.isEmpty) {
      if (added.contains(m.id)) continue;
      await appDb.transaction((txn) async {
        final eventId = await txn.rawInsert(
          'INSERT INTO events (date, title, category, start_min, end_min, flex_min) VALUES (?, ?, ?, ?, ?, 0)',
          [m.date, m.title, 'watch', start, end],
        );
        await txn.rawInsert(
          'INSERT OR IGNORE INTO watch_items (kind, title, release_date, detail, ext_id, poster, event_id) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          ['match', m.title, m.date, m.detail, m.extId, m.toFound().poster, eventId],
        );
      });
      added.add(m.id);
    } else if (saved.single['live'] != null) {
      await appDb.transaction((txn) async {
        await txn.execute('UPDATE events SET date = ?, start_min = ?, end_min = ? WHERE id = ?', [
          m.date,
          start,
          end,
          saved.single['live'],
        ]);
        await txn.execute('UPDATE watch_items SET release_date = ?, detail = ? WHERE id = ?', [
          m.date,
          m.detail,
          saved.single['id'],
        ]);
      });
    }
  }
  // Remembered so a match taken off stays off; the oldest are forgotten, long after they were played.
  await appDb.setSetting('football_added', added.length > 300 ? added.sublist(added.length - 300) : added);
  await appDb.setSetting('football_synced', today);
}
