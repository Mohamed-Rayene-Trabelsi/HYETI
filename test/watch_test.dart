import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/watch_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show field, openTab, settle, tapText;

/// One anime as AniList returns it; finished, with no poster so nothing is downloaded.
Map<String, Object?> anime(int id, {String? title}) => {
  'id': id,
  'title': {'romaji': null, 'english': title ?? 'Anime $id'},
  'averageScore': 80,
  'status': 'FINISHED',
  'format': 'TV',
  'episodes': 12,
  'nextAiringEpisode': null,
  'startDate': {'year': 2020, 'month': 1, 'day': 5},
  'coverImage': {'medium': null},
};

http.Response anilistPage(List<Map<String, Object?>> media, {required bool more}) => http.Response(
  jsonEncode({
    'data': {
      'Page': {
        'pageInfo': {'hasNextPage': more},
        'media': media,
      },
    },
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// The variables of every AniList request made, in order.
List<Map<String, dynamic>> fakeAnilist(http.Response Function(Map<String, dynamic> variables) answer) {
  final seen = <Map<String, dynamic>>[];
  httpClient = MockClient((request) async {
    final variables = (jsonDecode(request.body) as Map<String, dynamic>)['variables'] as Map<String, dynamic>;
    seen.add(variables);
    return answer(variables);
  });
  return seen;
}

void main() {
  setUp(() async {
    sqfliteFfiInit();
    appDb = await AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });

  tearDown(() => appDb.raw.close());

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LifeApp());
    await settle(tester);
    await openTab(tester, 'Watch');
  }

  test('an anime search looks through finished shows; browsing sticks to current ones', () async {
    final seen = fakeAnilist((_) => anilistPage([anime(1535, title: 'Death Note')], more: false));

    final searched = await fetchAnime('death note');
    expect(seen.last['search'], 'death note');
    expect(seen.last['sort'], ['SEARCH_MATCH', 'POPULARITY_DESC']);
    expect(seen.last.containsKey('status'), isFalse);
    expect(searched.more, isFalse);
    expect(searched.items.single.title, 'Death Note');
    expect(searched.items.single.note, 'Finished · 12 episodes');
    expect(searched.items.single.releaseDate, '2020-01-05');

    await fetchAnime('', page: 3);
    expect(seen.last['page'], 3);
    expect(seen.last['status'], ['RELEASING', 'NOT_YET_RELEASED']);
    expect(seen.last.containsKey('search'), isFalse);
  });

  testWidgets('scrolling to the end of the anime list loads the next page, without repeats', (tester) async {
    final seen = fakeAnilist(
      (v) => v['page'] == 1
          ? anilistPage([for (var i = 1; i <= 20; i++) anime(i)], more: true)
          // Anime 20 moved down the ranking between the two requests.
          : anilistPage([anime(20), for (var i = 21; i <= 30; i++) anime(i)], more: false),
    );
    await start(tester);
    await tapText(tester, 'Anime');
    expect(find.text('Anime 1'), findsOneWidget);
    expect(find.text('Anime 21'), findsNothing);
    expect(seen, hasLength(1));

    await tester.drag(find.text('Anime 3'), const Offset(0, -6000));
    await settle(tester);

    expect(seen.map((v) => v['page']), [1, 2]);
    expect(find.text('Anime 30', skipOffstage: false), findsOneWidget);
    expect(find.text('Anime 20', skipOffstage: false), findsOneWidget);

    // The source said that was the last page: reaching the end again asks for nothing.
    await tester.drag(find.byType(Scrollable).hitTestable().first, const Offset(0, -6000));
    await settle(tester);
    expect(seen, hasLength(2));
  });

  testWidgets('typing searches by itself, once the typing pauses', (tester) async {
    final seen = fakeAnilist(
      (v) => anilistPage([anime(1, title: v['search'] == null ? 'Trending' : 'Death Note')], more: false),
    );
    await start(tester);
    await tapText(tester, 'Anime');
    expect(seen, hasLength(1));
    expect(find.text('Search'), findsNothing);

    await tester.enterText(field(0), 'dea');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(field(0), 'death');
    await tester.pump(const Duration(milliseconds: 200));
    // Still typing: nothing has been asked yet.
    expect(seen, hasLength(1));

    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(seen, hasLength(2));
    expect(seen.last['search'], 'death');
    expect(find.text('Death Note'), findsOneWidget);

    await tapText(tester, 'Clear search');
    expect(seen.last.containsKey('search'), isFalse);
    expect(find.text('Trending'), findsOneWidget);
  });

  testWidgets('movies and series sit together under Shows', (tester) async {
    final paths = <String>[];
    httpClient = MockClient((request) async {
      paths.add(request.url.path);
      return http.Response(jsonEncode({'results': [], 'total_pages': 1}), 200);
    });
    await tester.runAsync(() => appDb.setSetting('tmdb_key', 'abc'));
    await start(tester);
    expect(find.text('Movies'), findsNothing);

    await tapText(tester, 'Shows');
    expect(paths.last, '/3/trending/movie/week');
    await tapText(tester, 'Series');
    expect(paths.last, '/3/trending/tv/week');
  });

  testWidgets('football lists upcoming matches, narrows them as a team is typed, and saves one', (tester) async {
    Map<String, Object?> match(int id, String home, String away, {String state = 'pre'}) => {
      'id': '$id',
      'date': '2999-03-0${id}T12:00Z',
      'competitions': [
        {
          'status': {
            'type': {'state': state},
          },
          'competitors': [
            {
              'homeAway': 'away',
              'team': {'displayName': away},
            },
            {
              'homeAway': 'home',
              'team': {'displayName': home},
            },
          ],
        },
      ],
    };
    final leagues = <String>[];
    httpClient = MockClient((request) async {
      final league = request.url.pathSegments[5];
      leagues.add(league);
      // One competition being down does not hide the rest.
      if (league == 'ita.1') return http.Response('', 500);
      return http.Response(
        jsonEncode({
          'events': switch (league) {
            'eng.1' => [match(2, 'Arsenal', 'Chelsea'), match(3, 'Leeds', 'Everton', state: 'post')],
            'esp.1' => [match(1, 'Barcelona', 'Real Madrid')],
            _ => [],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await start(tester);
    await tapText(tester, 'Football');

    expect(leagues.toSet(), footballLeagues.keys.toSet());
    // Soonest first, and a match already played is left out.
    expect(
      tester.getTopLeft(find.text('Barcelona vs Real Madrid')).dy,
      lessThan(tester.getTopLeft(find.text('Arsenal vs Chelsea')).dy),
    );
    expect(find.text('Leeds vs Everton'), findsNothing);

    leagues.clear();
    await tester.enterText(field(0), 'chel');
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
    expect(find.text('Barcelona vs Real Madrid'), findsNothing);
    expect(leagues, isEmpty);

    await tapText(tester, 'Save');
    final saved = (await tester.runAsync(() => appDb.query('SELECT * FROM watch_items')))!.single;
    expect(saved['kind'], 'match');
    expect(saved['ext_id'], 'espn:2');
    expect(saved['detail'], startsWith('Premier League · '));

    await tapText(tester, 'Clear search');
    await tapText(tester, 'La Liga');
    expect(leagues, ['esp.1']);
    expect(find.text('Arsenal vs Chelsea'), findsNothing);
    expect(find.text('Barcelona vs Real Madrid'), findsOneWidget);
  });

  testWidgets('a title cannot be typed in twice', (tester) async {
    await start(tester);
    for (final title in ['Dune', 'dune!']) {
      await tapText(tester, 'Add title');
      await tester.enterText(field(0), title);
      await tapText(tester, 'Add to my list');
    }
    expect(find.text('That is already on your list.'), findsOneWidget);
    expect(await tester.runAsync(() => appDb.query('SELECT * FROM watch_items')), hasLength(1));
  });

  testWidgets('saving a found title takes over the copy typed in by hand', (tester) async {
    fakeAnilist((_) => anilistPage([anime(7)], more: false));
    await tester.runAsync(
      () => appDb.insert("INSERT INTO watch_items (kind, title, detail) VALUES ('anime', 'ANIME 7', '')"),
    );
    await start(tester);
    // The first "Anime" is the tab; the saved title's card says "Anime" too.
    await tester.tap(find.text('Anime').hitTestable().first);
    await settle(tester);
    await tapText(tester, 'Save');

    final rows = (await tester.runAsync(() => appDb.query('SELECT * FROM watch_items')))!;
    expect(rows.single['ext_id'], 'anilist:7');
    expect(rows.single['title'], 'Anime 7');
    expect(find.text('Saved'), findsOneWidget);
  });

  test('updating removes duplicate titles already on the list', () async {
    final path = '${Directory.systemTemp.createTempSync('hyeti').path}/life.db';
    var db = await AppDb.open(factory: databaseFactoryFfi, path: path);
    await db.raw.execute(
      "INSERT INTO events (id, date, title, category, start_min, end_min) "
      "VALUES (9, '2026-11-20', 'Dune', 'watch', 1200, 1320)",
    );
    for (final (kind, title, extId, eventId) in [
      ('movie', 'Dune', null, null),
      ('movie', 'dune', null, 9),
      ('movie', 'Dune', 'tmdb:movie:1', null),
      ('series', 'Dune', null, null),
      ('anime', 'Berserk', 'anilist:33', null),
      ('anime', 'Berserk', 'anilist:21560', null),
    ]) {
      await db.raw.insert('watch_items', {'kind': kind, 'title': title, 'ext_id': extId, 'event_id': eventId});
    }
    // Put the file back to how that version of the app left it: no later columns, and its version number.
    await db.raw.execute('ALTER TABLE notes DROP COLUMN sketch');
    await db.raw.execute('PRAGMA user_version = 3');
    await db.raw.close();

    db = await AppDb.open(factory: databaseFactoryFfi, path: path);
    final rows = await db.query('SELECT kind, title, ext_id, event_id FROM watch_items ORDER BY id');
    await db.raw.close();

    expect(rows, [
      // The linked movie stays, and keeps the calendar block planned for its copy.
      {'kind': 'movie', 'title': 'Dune', 'ext_id': 'tmdb:movie:1', 'event_id': 9},
      // A series of the same name is a different thing.
      {'kind': 'series', 'title': 'Dune', 'ext_id': null, 'event_id': null},
      // Two linked works sharing a name are both real.
      {'kind': 'anime', 'title': 'Berserk', 'ext_id': 'anilist:33', 'event_id': null},
      {'kind': 'anime', 'title': 'Berserk', 'ext_id': 'anilist:21560', 'event_id': null},
    ]);
  });

  testWidgets('a title saved twice shows once, under Coming up only', (tester) async {
    await tester.runAsync(() async {
      for (final (kind, title, extId, date) in [
        ('series', 'Frieren', 'tmdb:tv:5', '2020-01-05'),
        ('anime', 'Frieren', 'anilist:5', '2999-01-01'),
        ('movie', 'Dune', 'tmdb:movie:1', '2021-09-15'),
      ]) {
        await appDb.insert(
          'INSERT INTO watch_items (kind, title, release_date, detail, ext_id) VALUES (?, ?, ?, ?, ?)',
          [kind, title, date, '', extId],
        );
      }
    });
    await start(tester);

    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('2 saved · 1 coming up'), findsOneWidget);
    // The one card is the copy still ahead, so it sits above the "Out now" heading.
    final card = tester.getTopLeft(find.text('Frieren')).dy;
    expect(card, greaterThan(tester.getTopLeft(find.text('COMING UP')).dy));
    expect(card, lessThan(tester.getTopLeft(find.text('OUT NOW OR UNDATED')).dy));

    // Nothing was merged in storage, and removing the card clears both copies.
    expect(await tester.runAsync(() => appDb.query('SELECT * FROM watch_items')), hasLength(3));
    await tester.tap(find.text('Remove').hitTestable().first);
    await settle(tester);
    expect(find.text('Frieren'), findsNothing);
    expect(await tester.runAsync(() => appDb.query('SELECT * FROM watch_items')), hasLength(1));

    await tapText(tester, 'Undo');
    expect(find.text('Frieren'), findsOneWidget);
    expect(await tester.runAsync(() => appDb.query('SELECT * FROM watch_items')), hasLength(3));

    // Let the message's own timer run out.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('tapping Saved takes the title back off the list', (tester) async {
    fakeAnilist((_) => anilistPage([anime(7)], more: false));
    await start(tester);
    await tester.tap(find.text('Anime').hitTestable().first);
    await settle(tester);

    await tapText(tester, 'Save');
    expect(await tester.runAsync(() => appDb.query('SELECT * FROM watch_items')), hasLength(1));

    await tapText(tester, 'Saved');
    expect(await tester.runAsync(() => appDb.query('SELECT * FROM watch_items')), isEmpty);
    expect(find.text('Save'), findsOneWidget);

    await tapText(tester, 'Undo');
    expect(find.text('Saved'), findsOneWidget);

    // Let the message's own timer run out.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
