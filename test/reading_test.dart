import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/genres.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/reading.dart';
import 'package:personal_mobile_app/screens/reading.dart';
import 'package:personal_mobile_app/watch_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show field, openTab, settle, tapText;

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUp(() async {
    sqfliteFfiInit();
    appDb = await AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    // Past the Watch tab's first-time questions, showing everything; the setup has tests of its own.
    await appDb.setSetting('watch_prefs', {'setUp': true});
  });

  tearDown(() => appDb.raw.close());

  group('CSV', () {
    test('reads quoted fields, commas, quotes and line breaks inside them', () {
      expect(parseCsv('a,"b, c","say ""hi"""\r\n"two\nlines",x,\n'), [
        ['a', 'b, c', 'say "hi"'],
        ['two\nlines', 'x', ''],
      ]);
    });

    test('reads a list exported by this app back as it was', () {
      final rows = [
        {
          'title': 'Solo Leveling, Part 2',
          'kind': 'manhwa',
          'status': 'reading',
          'chapter': 45.5,
          'total': 200,
          'link': 'https://example.com/sl',
          'ext_id': 'anilist:105398',
          'genres': 'Action,Fantasy',
        },
        {'title': 'Berserk', 'kind': 'manga', 'status': 'paused', 'chapter': 0, 'total': null, 'link': ''},
      ];
      final back = parseReadingCsv(readingToCsv(rows));
      expect(back, hasLength(2));
      expect(back[0].title, 'Solo Leveling, Part 2');
      expect(back[0].kind, 'manhwa');
      expect(back[0].chapter, 45.5);
      expect(back[0].total, 200);
      expect(back[0].link, 'https://example.com/sl');
      expect(back[0].extId, 'anilist:105398');
      expect(back[0].genres, ['Action', 'Fantasy']);
      expect(back[1].status, 'paused');
      expect(back[1].total, isNull);
    });

    test('understands the column names other trackers use, and semicolons', () {
      final entries = parseReadingCsv(
        'Series Title;My Status;Chapters Read;Series Chapters;Type\n'
        'Tower of God;Plan to Read;0;;Webtoon\n'
        'One Piece;Currently reading;Ch. 1130;;Manga\n'
        ';Reading;3;;\n',
      );
      expect(
        [for (final e in entries) (e.title, e.status, e.chapter, e.kind)],
        [('Tower of God', 'plan', 0, 'manhwa'), ('One Piece', 'reading', 1130, 'manga')],
      );
    });

    test('a file with no header is taken in this app\'s column order', () {
      final entries = parseReadingCsv('Omniscient Reader,manhwa,completed,250,250\n');
      expect(entries.single.title, 'Omniscient Reader');
      expect(entries.single.status, 'completed');
      expect(entries.single.total, 250);
    });
  });

  test('links to a file on GitHub, GitLab or a gist are turned into the raw file', () {
    expect(
      csvLinkUri('https://github.com/me/lists/blob/main/manga/reading.csv').toString(),
      'https://raw.githubusercontent.com/me/lists/main/manga/reading.csv',
    );
    expect(
      csvLinkUri('https://gist.github.com/me/abc123').toString(),
      'https://gist.githubusercontent.com/me/abc123/raw',
    );
    expect(
      csvLinkUri('https://gitlab.com/me/lists/-/blob/main/r.csv').toString(),
      'https://gitlab.com/me/lists/-/raw/main/r.csv',
    );
    expect(csvLinkUri('https://example.com/r.csv').toString(), 'https://example.com/r.csv');
    expect(csvLinkUri('not a link'), isNull);
  });

  test('importing updates titles already on the list and never moves a chapter back', () async {
    await importReading([const ReadingEntry(title: 'Blue Lock', chapter: 200)]);
    final result = await importReading([
      const ReadingEntry(title: 'blue lock!', chapter: 150, status: 'paused', total: 300),
      const ReadingEntry(title: 'Vagabond', chapter: 10),
    ]);
    expect(result, (added: 1, updated: 1));
    final rows = await appDb.query('SELECT title, chapter, status, total FROM reading ORDER BY id');
    expect(rows, [
      {'title': 'Blue Lock', 'chapter': 200, 'status': 'paused', 'total': 300},
      {'title': 'Vagabond', 'chapter': 10, 'status': 'reading', 'total': null},
    ]);
  });

  test('importing from a link reads the raw file and refuses a web page', () async {
    final asked = <Uri>[];
    httpClient = MockClient((request) async {
      asked.add(request.url);
      if (request.url.path.endsWith('page.csv')) return http.Response('<!doctype html><html></html>', 200);
      return http.Response('title,chapter\nKingdom,800\n', 200);
    });
    final entries = await fetchReadingCsv('https://github.com/me/lists/blob/main/reading.csv');
    expect(asked.single.host, 'raw.githubusercontent.com');
    expect(entries.single.title, 'Kingdom');
    expect(fetchReadingCsv('https://example.com/page.csv'), throwsA(isA<LinkError>()));
  });

  test('genres from every source come out under one set of names', () {
    expect(tmdbGenres('series', [10759, 10765]), ['Action', 'Adventure', 'Sci-Fi', 'Fantasy']);
    expect(tmdbGenres('movie', [878, 99999]), ['Sci-Fi']);
    expect(anilistGenres(['Mahou Shoujo', 'Ecchi', 'Slice of Life']), ['Fantasy', 'Slice of Life']);
    expect(tmdbGenreId('series', 'Fantasy'), 10765);
    expect(tmdbGenreId('movie', 'Mecha'), isNull);
  });

  test('the taste follows what is saved, and suggestions are ranked by it', () async {
    await appDb.run(
      "INSERT INTO watch_items (kind, title, ext_id, genres) VALUES ('anime', 'A', 'anilist:1', 'Action,Comedy'), "
      "('movie', 'B', 'tmdb:movie:2', 'Action')",
    );
    await importReading([
      const ReadingEntry(title: 'Dropped one', status: 'dropped', genres: ['Horror']),
    ]);
    final taste = await loadTaste();
    expect(taste.top(), ['Action', 'Comedy']);
    expect(taste.weights.containsKey('Horror'), isFalse, reason: 'something dropped says little about taste');
    expect(taste.saved, {'anilist:1', 'tmdb:movie:2'});

    Found f(String id, List<String> genres) =>
        Found(extId: id, kind: 'anime', title: id, releaseDate: null, note: '', rating: '', genres: genres);
    final ranked = rankForYou([
      f('x', ['Drama']),
      f('y', ['Action', 'Comedy']),
      f('z', ['Comedy']),
    ], taste);
    expect([for (final r in ranked) r.extId], ['y', 'z', 'x']);
  });

  test('anime "For you" asks for what saved anime are like and leaves out what is saved', () async {
    await appDb.run(
      "INSERT INTO watch_items (kind, title, ext_id, genres) VALUES ('anime', 'Frieren', 'anilist:154587', 'Fantasy')",
    );
    final queries = <String>[];
    httpClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      queries.add(body['query'] as String);
      final media = {
        'id': 21,
        'title': {'english': 'One Piece', 'romaji': null},
        'averageScore': 88,
        'status': 'RELEASING',
        'format': 'TV',
        'episodes': null,
        'genres': ['Fantasy', 'Action'],
        'isAdult': false,
        'nextAiringEpisode': null,
        'startDate': {'year': 1999, 'month': 10, 'day': 20},
        'coverImage': {'medium': null},
      };
      if ((body['query'] as String).contains('recommendations')) {
        expect(body['variables']['ids'], [154587]);
        return _json({
          'data': {
            'Page': {
              'media': [
                {
                  'title': {'english': 'Frieren', 'romaji': null},
                  'recommendations': {
                    'nodes': [
                      {'mediaRecommendation': media},
                    ],
                  },
                },
              ],
            },
          },
        });
      }
      expect(body['variables']['exclude'], [154587]);
      expect(body['variables']['genres'], ['Fantasy']);
      return _json({
        'data': {
          'Page': {
            'pageInfo': {'hasNextPage': false},
            'media': [media],
          },
        },
      });
    });
    final page = await fetchAnime('', taste: await loadTaste());
    expect(queries, hasLength(2));
    expect(page.items.single.title, 'One Piece');
    expect(page.items.single.reason, 'Because you saved Frieren');
  });

  testWidgets('a title added by hand moves on a chapter at a time and finishes on the last', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LifeApp());
    await settle(tester);
    await openTab(tester, 'Watch');
    await tapText(tester, 'Manga');
    expect(find.text('Nothing on your reading list'), findsOneWidget);

    await tapText(tester, 'Add');
    await tester.enterText(field(0), 'Dandadan');
    await tester.enterText(field(1), '9');
    await tester.enterText(field(2), '10');
    await tapText(tester, 'Save');
    expect(find.text('Chapter 9 of 10'), findsOneWidget);

    await tapText(tester, '+1 chapter');
    expect(find.text('Chapter 10 of 10'), findsOneWidget);
    final row = (await tester.runAsync(() => appDb.query('SELECT * FROM reading')))!.single;
    expect(row['status'], 'completed');
  });

  testWidgets('a CSV file is imported from the Import and export sheet', (tester) async {
    final real = pickCsvText;
    addTearDown(() => pickCsvText = real);
    pickCsvText = () async => 'title,type,status,chapter\nVinland Saga,manga,reading,120\nLookism,manhwa,plan,0\n';
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LifeApp());
    await settle(tester);
    await openTab(tester, 'Watch');
    await tapText(tester, 'Manga');
    await tapText(tester, 'Import a list');
    await tapText(tester, 'Open CSV file');
    expect(find.text('Added 2 titles.'), findsOneWidget);
    await tapText(tester, 'Close');
    expect(find.text('Vinland Saga'), findsOneWidget);
    expect(find.text('Chapter 120'), findsOneWidget);
  });
}
