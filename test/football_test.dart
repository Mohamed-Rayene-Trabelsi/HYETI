import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/date.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/football.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/watch_api.dart' show httpClient;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show field, openTab, settle, tapText, tapTip;

const tunisia = Team(6719, 'Tunisia');
const africain = Team(102102, 'Club Africain', league: 'Ligue I');

/// A kick-off [days] from now at 18:00 local time, as FotMob writes it (UTC).
String kickOff(int days, {int hour = 18}) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days, hour).toUtc().toIso8601String();
}

Map<String, Object?> fixture(
  int id,
  Team home,
  Team away,
  int days, {
  bool finished = false,
  bool dateTbd = false,
  int hour = 18,
}) => {
  'id': id,
  'home': {'id': home.id, 'name': home.name},
  'away': {'id': away.id, 'name': away.name},
  'tournament': {'name': 'Ligue I'},
  'status': {
    'utcTime': kickOff(days, hour: hour),
    'finished': finished,
    'started': finished,
    'cancelled': false,
    'matchDateTbd': dateTbd,
  },
};

const esperance = Team(8153, 'Espérance');
const libya = Team(6328, 'Libya');
const arsenal = Team(9825, 'Arsenal');
const chelsea = Team(8455, 'Chelsea');

/// Fake FotMob. Records every address asked for. [hour] moves Club Africain's derby, to test a change of time.
List<Uri> fakeFotmob({int derbyHour = 18}) {
  final asked = <Uri>[];
  httpClient = MockClient((request) async {
    asked.add(request.url);
    final q = request.url.queryParameters;
    final Object body = switch (request.url.path) {
      '/api/data/search/suggest' => [
        {
          'suggestions': [
            if ('tunisia'.contains(q['term']!.toLowerCase())) ...[
              {'type': 'team', 'id': '6719', 'name': 'Tunisia', 'leagueId': 0},
              {'type': 'league', 'id': '544', 'name': 'Ligue I'},
            ],
            if ('club africain'.contains(q['term']!.toLowerCase()))
              {'type': 'team', 'id': '102102', 'name': 'Club Africain', 'leagueId': 544, 'leagueName': 'Ligue I'},
          ],
        },
      ],
      '/api/data/teams' => {
        'fixtures': {
          'allFixtures': {
            'fixtures': switch (q['id']) {
              '6719' => [
                fixture(1, libya, tunisia, -3, finished: true),
                fixture(2, tunisia, libya, 3),
                // Too far ahead for the two weeks.
                fixture(3, tunisia, libya, 40),
              ],
              '102102' => [
                fixture(10, africain, esperance, 1, hour: derbyHour),
                fixture(11, esperance, africain, 9, dateTbd: true),
              ],
              _ => [],
            },
          },
        },
      },
      '/api/data/leagues' => {
        'details': {'name': 'Premier League'},
        'fixtures': {
          'allMatches': [
            {...fixture(20, arsenal, chelsea, 2), 'id': '20'},
          ],
        },
      },
      _ => throw StateError('Unexpected ${request.url}'),
    };
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
  return asked;
}

void main() {
  setUp(() async {
    sqfliteFfiInit();
    appDb = await AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    // Past the Watch tab's first-time questions, showing everything; the setup has tests of its own.
    await appDb.setSetting('watch_prefs', {'setUp': true});
  });

  tearDown(() => appDb.raw.close());

  test('search tells national teams from clubs', () async {
    fakeFotmob();
    expect(await searchTeams('tunisia', nations: true), [tunisia]);
    expect(await searchTeams('tunisia', nations: false), isEmpty);
    final clubs = await searchTeams('africain', nations: false);
    expect(clubs.single.name, 'Club Africain');
    expect(clubs.single.league, 'Ligue I');
  });

  test('only what is followed is downloaded, and only two weeks of it is kept', () async {
    final asked = fakeFotmob();
    final matches = await followedMatches(
      FootballPrefs(setUp: true, nation: tunisia, clubs: [africain], leagues: [47]),
    );
    // One request per team and league followed; never a whole day of every match.
    expect(asked.map((u) => '${u.path}?${u.query}').toSet(), {
      '/api/data/teams?id=6719',
      '/api/data/teams?id=102102',
      '/api/data/leagues?id=47',
    });
    expect(matches.map((m) => m.title), [
      'Club Africain vs Espérance',
      'Arsenal vs Chelsea',
      'Tunisia vs Libya',
      'Espérance vs Club Africain',
    ]);
    expect(matches[1].detail, 'Premier League · 18:00');
    expect(matches.last.dateTbd, isTrue);
  });

  test('the national team and clubs go on the calendar once, and move when their match moves', () async {
    fakeFotmob();
    await appDb.setSetting(
      'football',
      FootballPrefs(setUp: true, nation: tunisia, clubs: [africain], leagues: [47]).toJson(),
    );
    await syncFootballCalendar();
    var events = await appDb.query('SELECT * FROM events ORDER BY date');
    // League matches are not added, nor a match whose date is still a guess.
    expect(events.map((e) => e['title']), ['Club Africain vs Espérance', 'Tunisia vs Libya']);
    expect(events.first['start_min'], 18 * 60);
    expect(events.first['category'], 'watch');
    final saved = await appDb.query('SELECT * FROM watch_items ORDER BY release_date');
    expect(saved.map((w) => w['ext_id']), ['fotmob:10', 'fotmob:2']);

    // The derby moves to 20:00: its block follows.
    fakeFotmob(derbyHour: 20);
    await syncFootballCalendar(force: true);
    events = await appDb.query('SELECT * FROM events ORDER BY date');
    expect(events.first['start_min'], 20 * 60);
    expect(events, hasLength(2));

    // Taken off the list: it stays off.
    await appDb.run("DELETE FROM watch_items WHERE ext_id = 'fotmob:2'");
    await appDb.run("DELETE FROM events WHERE title = 'Tunisia vs Libya'");
    await syncFootballCalendar(force: true);
    events = await appDb.query('SELECT * FROM events');
    expect(events.map((e) => e['title']), ['Club Africain vs Espérance']);
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LifeApp());
    await settle(tester);
    await openTab(tester, 'Watch');
  }

  testWidgets('the first visit asks for a country, clubs and leagues, then shows two weeks of them', (tester) async {
    final asked = fakeFotmob();
    await start(tester);
    await tapText(tester, 'Football');
    expect(find.text('Make Football yours'), findsOneWidget);
    // Nothing is downloaded until something is chosen.
    expect(asked, isEmpty);

    await tapText(tester, 'Get started');
    expect(find.text('Step 1 of 3 · Your country'), findsOneWidget);
    await tester.enterText(field(0), 'tun');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tapText(tester, 'Tunisia');
    await tapText(tester, 'Next');

    expect(find.text('Step 2 of 3 · Favourite clubs'), findsOneWidget);
    await tester.enterText(field(0), 'africain');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tapText(tester, 'Club Africain');
    await tapText(tester, 'Next');

    expect(find.text('Step 3 of 3 · The big leagues'), findsOneWidget);
    await tapText(tester, 'Premier League');
    await tapText(tester, 'Done');
    await settle(tester);

    final prefs = footballPrefs();
    expect(prefs.nation, tunisia);
    expect(prefs.clubs, [africain]);
    expect(prefs.leagues, [47]);

    expect(find.text('Club Africain vs Espérance'), findsOneWidget);
    expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
    // Grouped under a heading per day.
    expect(find.text('TOMORROW'), findsOneWidget);
    expect(find.text('Tunisia vs Libya', skipOffstage: false), findsOneWidget);
    // No filters on the tab: what is followed is changed in Settings.
    expect(find.text('All'), findsNothing);
    expect(find.text('Follow a country'), findsNothing);

    // The calendar got the national team's and the club's matches, not the league's.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    final events = (await tester.runAsync(() => appDb.query('SELECT title FROM events ORDER BY date')))!;
    expect(events.map((e) => e['title']), ['Club Africain vs Espérance', 'Tunisia vs Libya']);
  });

  testWidgets('any team can be looked up without following it', (tester) async {
    final asked = fakeFotmob();
    await tester.runAsync(() => appDb.setSetting('football', const FootballPrefs(setUp: true, leagues: [47]).toJson()));
    await start(tester);
    await tapText(tester, 'Football');
    expect(find.text('Arsenal vs Chelsea'), findsOneWidget);

    await tester.enterText(field(0), 'club africain');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tapText(tester, 'Club Africain');
    await settle(tester);
    expect(find.text('Club Africain · next two weeks'), findsOneWidget);
    expect(find.text('Club Africain vs Espérance'), findsOneWidget);
    expect(find.text('Arsenal vs Chelsea'), findsNothing);
    expect(asked.where((u) => u.path == '/api/data/teams').map((u) => u.queryParameters['id']), ['102102']);
    // Looking a team up does not follow it.
    expect(footballPrefs().clubs, isEmpty);

    await tapTip(tester, 'Clear search');
    expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
  });

  testWidgets('someone who does not follow football never sees the tab, until Settings brings it back', (tester) async {
    fakeFotmob();
    await start(tester);
    await tapText(tester, 'Football');
    await tapText(tester, "I don't follow football");
    expect(find.text('Football'), findsNothing);
    expect(footballPrefs().off, isTrue);

    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    await tapText(tester, 'Watch');
    expect(find.text('Football'), findsOneWidget, reason: 'offered, but not ticked');
    await tapText(tester, 'Football');
    expect(footballPrefs().off, isFalse);
    expect(find.text('National team'), findsOneWidget);
  });

  test('a kick-off is shown in local time', () {
    final m = FootballMatch(
      id: '1',
      home: 'A',
      away: 'B',
      homeId: 1,
      awayId: 2,
      kickOff: DateTime(2026, 11, 22, 17, 30),
      competition: 'Ligue I',
    );
    expect(m.date, '2026-11-22');
    expect(m.detail, 'Ligue I · 17:30');
    expect(m.toFound().extId, 'fotmob:1');
    expect(toKey(m.kickOff), '2026-11-22');
  });
}
