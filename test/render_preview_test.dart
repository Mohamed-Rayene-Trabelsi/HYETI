// Draws screens of the app to PNG files under test/preview/ so they can be looked at without a phone.
// Run with: flutter test test/render_preview_test.dart --update-goldens
//
// It is a drawing tool, not a check: without --update-goldens it does nothing, so a small rendering
// difference between machines can never fail the test suite.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/date.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/sketch.dart';
import 'package:personal_mobile_app/ui.dart';
import 'package:personal_mobile_app/update.dart';
import 'package:personal_mobile_app/watch_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Real fonts from the Flutter SDK, so text is readable in the pictures.
Future<void> loadFonts() async {
  final flutter =
      Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final dir = '$flutter/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String name) async => ByteData.sublistView(await File('$dir/$name').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    roboto.addFont(read(f));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
  }
}

Future<void> openTab(WidgetTester tester, String name) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(name)));
  await settle(tester);
}

Future<void> snap(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/$name.png'));

/// A dark theme, a week of routine blocks and a few gym sets, so the screens have something to show.
Future<void> seed() async {
  final today = todayKey();
  await appDb.setSetting('theme', 'dark');
  await appDb.setSetting('tmdb_key', 'preview');
  for (final (title, category, days, start, end) in [
    ('Deep work', 'work', '0,1,2,3,4,5,6', 540, 660),
    ('Lunch', 'food', '0,1,2,3,4,5,6', 780, 825),
    ('Gym', 'gym', '0,1,2,3,4,5,6', 1080, 1170),
    ('Dinner', 'food', '0,1,2,3,4,5,6', 1200, 1245),
    ('Gaming', 'game', '0,1,2,3,4,5,6', 1260, 1350),
  ]) {
    await appDb.run(
      'INSERT INTO routines (title, category, days, start_min, end_min, flex_min, created_date) '
      'VALUES (?, ?, ?, ?, ?, 15, ?)',
      [title, category, days, start, end, addDays(today, -10)],
    );
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  await appDb.run("INSERT INTO notes (title, body, updated_at) VALUES ('Groceries', 'Eggs, rice, chicken', ?)", [now]);
  // A little house: walls, roof, door, and a sun.
  await appDb.run('INSERT INTO notes (title, sketch, pinned, updated_at) VALUES (?, ?, 1, ?)', [
    'House idea',
    encodeSketch(const [
      Stroke(0, 0.014, [Offset(0.25, 0.6), Offset(0.25, 1.0), Offset(0.75, 1.0), Offset(0.75, 0.6), Offset(0.25, 0.6)]),
      Stroke(0xFFEF5350, 0.014, [Offset(0.18, 0.62), Offset(0.5, 0.35), Offset(0.82, 0.62)]),
      Stroke(0xFF4F8CFF, 0.014, [Offset(0.45, 1.0), Offset(0.45, 0.8), Offset(0.57, 0.8), Offset(0.57, 1.0)]),
      Stroke(0xFFFFA726, 0.03, [
        Offset(0.8, 0.2),
        Offset(0.84, 0.16),
        Offset(0.88, 0.2),
        Offset(0.84, 0.24),
        Offset(0.8, 0.2),
      ]),
    ]),
    now,
  ]);
  for (final (exercise, muscle, weight, date) in [
    ('Bench press', 'Chest', 60.0, addDays(today, -6)),
    ('Bench press', 'Chest', 62.5, today),
    ('Squat', 'Quads', 80.0, addDays(today, -9)),
    ('Pull-up', 'Back', 0.0, addDays(today, -1)),
  ]) {
    await appDb.run('INSERT INTO workout_sets (date, muscle, exercise, weight, reps) VALUES (?, ?, ?, ?, 8)', [
      date,
      muscle,
      exercise,
      weight,
    ]);
  }
}

/// Stands in for the Watch tab's online sources: a few movies from TMDB and a few fixtures from FotMob.
void fakeWatchServices() {
  final today = DateTime.now();
  String kickOff(int days, int hour) =>
      DateTime(today.year, today.month, today.day + days, hour).toUtc().toIso8601String();
  Map<String, Object?> match(int id, int days, int hour, (int, String) home, (int, String) away) => {
    'id': '$id',
    'home': {'id': home.$1, 'name': home.$2},
    'away': {'id': away.$1, 'name': away.$2},
    'tournament': {'name': 'Africa Cup of Nations Qualification'},
    'status': {'utcTime': kickOff(days, hour), 'finished': false, 'started': false, 'cancelled': false},
  };
  const tunisia = (6719, 'Tunisia'), uganda = (5890, 'Uganda');
  httpClient = MockClient((request) async {
    final Object body;
    if (request.url.host == 'api.themoviedb.org') {
      body = {
        'total_pages': 1,
        'results': [
          for (final (id, title, score) in [
            (1, 'The Long Road', 7.9),
            (2, 'Night Harbour', 7.1),
            (3, 'Paper Kites', 6.6),
          ])
            {
              'id': id,
              'title': title,
              'release_date': addDays(todayKey(), -20),
              'vote_count': 900,
              'vote_average': score,
            },
        ],
      };
    } else {
      final q = request.url.queryParameters;
      body = switch (request.url.path) {
        '/api/data/search/suggest' => [
          {
            'suggestions': [
              {'type': 'team', 'id': '6719', 'name': 'Tunisia', 'leagueId': 0},
              {'type': 'team', 'id': '1129301', 'name': 'Tunisia (W)', 'leagueId': 0},
            ],
          },
        ],
        '/api/data/teams' => {
          'fixtures': {
            'allFixtures': {
              'fixtures': q['id'] == '6719' ? [match(1, 4, 19, tunisia, uganda)] : [],
            },
          },
        },
        _ => {
          'details': {'name': 'Premier League'},
          'fixtures': {
            'allMatches': [
              match(2, 1, 13, (8650, 'Liverpool'), (8455, 'Chelsea')),
              match(3, 1, 16, (10261, 'Newcastle United'), (8586, 'Tottenham Hotspur')),
              match(4, 2, 17, (9825, 'Arsenal'), (8456, 'Manchester City')),
            ],
          },
        },
      };
    }
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
}

void main() {
  if (!autoUpdateGoldenFiles) return;

  setUp(() async {
    sqfliteFfiInit();
    appDb = await AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    // Past the Watch tab's first-time questions, showing everything; the setup has tests of its own.
    await appDb.setSetting('watch_prefs', {'setUp': true});
  });

  tearDown(() => appDb.raw.close());

  testWidgets('screens', (tester) async {
    await tester.runAsync(loadFonts);
    // A phone of about the size and density of a current Android handset.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.runAsync(seed);
    fakeWatchServices();

    await tester.pumpWidget(const LifeApp());
    await settle(tester);
    await snap(tester, 'calendar_day');

    await tester.tap(find.text('Add').hitTestable());
    await settle(tester);
    await tester.tap(find.text('Every week'));
    await settle(tester);
    await snap(tester, 'calendar_add');
    await tester.tap(find.text('Close'));
    await settle(tester);

    await tester.tap(find.text('Month'));
    await settle(tester);
    await snap(tester, 'calendar_month');

    await openTab(tester, 'Notes');
    await snap(tester, 'notes');
    await tester.tap(find.text('House idea'));
    await settle(tester);
    await snap(tester, 'notes_sketch');
    await tester.tap(find.text('‹ Done'));
    await settle(tester);

    await openTab(tester, 'Body');
    await snap(tester, 'body_front');
    await tester.tap(find.text('Back').hitTestable().first);
    await settle(tester);
    await snap(tester, 'body_back');

    await tester.runAsync(() async {
      await appDb.setSetting('goal', {'name': 'New bike', 'target': 600});
      await appDb.run(
        "INSERT INTO transactions (date, kind, amount, label) VALUES (?, 'income', 900, 'Pay'), (?, 'saving', 380, '')",
        [todayKey(), todayKey()],
      );
    });
    await openTab(tester, 'Wallet');
    // The seeded savings pass half the goal, which is cheered; the picture is of the jar, not the message.
    messengerKey.currentState?.hideCurrentSnackBar();
    await settle(tester);
    await snap(tester, 'wallet');
    await tester.tap(find.text('Take out').hitTestable());
    await settle(tester);
    await tester.tap(find.text('−\$20').hitTestable());
    await settle(tester);
    await snap(tester, 'jar_take_out');
    await tester.tap(find.text('Keep it in the jar'));
    await settle(tester);
    await tester.tap(find.text('Close'));
    await settle(tester);
    await tester.tap(find.text('Add').hitTestable());
    await settle(tester);
    await snap(tester, 'wallet_add');
    await tester.tap(find.text('Close'));
    await settle(tester);
    await tester.tap(find.text('Drop in').hitTestable());
    await settle(tester);
    await tester.tap(find.text('+\$10').hitTestable());
    await settle(tester);
    await snap(tester, 'jar_source');
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    await tester.tap(find.text('Close'));
    await settle(tester);
    await openTab(tester, 'Body');

    await tester.tap(find.text('Bench press').hitTestable().first);
    await settle(tester);
    await snap(tester, 'body_log_set');
    await tester.tap(find.text('Close'));
    await settle(tester);

    await openTab(tester, 'Watch');
    await tester.tap(find.text('Shows'));
    await settle(tester);
    await snap(tester, 'watch_shows');
    await tester.runAsync(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await appDb.run(
        'INSERT INTO reading (title, kind, status, chapter, total, link, genres, updated_at) VALUES '
        "('Solo Leveling', 'manhwa', 'reading', 142, 200, 'https://example.com', 'Action,Fantasy', ?), "
        "('Vinland Saga', 'manga', 'reading', 120.5, NULL, '', 'Action,Drama', ?), "
        "('Omniscient Reader', 'manhwa', 'completed', 250, 250, '', 'Fantasy', ?), "
        "('Lookism', 'manhwa', 'plan', 0, NULL, '', 'Drama', ?)",
        [now, now - 1, now - 2, now - 3],
      );
    });
    await tester.tap(find.text('Manga').hitTestable());
    await settle(tester);
    await snap(tester, 'watch_manga');
    await tester.tap(find.text('Import / export').hitTestable());
    await settle(tester);
    await snap(tester, 'manga_import');
    await tester.tap(find.text('Close'));
    await settle(tester);
    await tester.tap(find.text('Football').hitTestable());
    await settle(tester);
    await snap(tester, 'football_welcome');
    await tester.tap(find.text('Get started').hitTestable());
    await settle(tester);
    await tester.enterText(find.byType(TextField).hitTestable().first, 'tun');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tester.tap(find.text('Tunisia').hitTestable());
    await settle(tester);
    await snap(tester, 'football_setup');
    await tester.tap(find.text('Next').hitTestable());
    await settle(tester);
    await tester.tap(find.text('Skip').hitTestable());
    await settle(tester);
    await tester.tap(find.text('Premier League').hitTestable());
    await settle(tester);
    await tester.tap(find.text('Done').hitTestable());
    await settle(tester);
    await tester.tap(find.text('Save').hitTestable().first);
    await settle(tester);
    await snap(tester, 'watch_football');
    await openTab(tester, 'Body');

    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    await snap(tester, 'settings');
    await tester.tap(find.text('Watch').hitTestable().last);
    await settle(tester);
    await snap(tester, 'settings_watch');
    await tester.tap(find.byIcon(Icons.arrow_back).hitTestable());
    await settle(tester);
    // The Watch tab's first-time questions.
    await tester.runAsync(() => appDb.setSetting('watch_prefs', {'setUp': false}));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.arrow_back).hitTestable());
    await settle(tester);
    await openTab(tester, 'Watch');
    await snap(tester, 'watch_setup');
    await tester.runAsync(() => appDb.setSetting('watch_prefs', {'setUp': true}));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    await tester.tap(find.text('Appearance'));
    await settle(tester);

    for (final theme in ['Web Slinger', 'Dark Knight', 'Five-Leaf Clover']) {
      await tester.tap(find.text(theme));
      await settle(tester);
      await snap(tester, 'theme_${theme.toLowerCase().replaceAll(RegExp('[^a-z]+'), '_')}');
    }
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byIcon(Icons.arrow_back).hitTestable().last);
      await settle(tester);
    }
    await snap(tester, 'body_clover');

    showUpdateSheet(
      tester.element(find.byType(NavigationBar)),
      const Release(version: '9.9.9', notes: 'Faster calendar.\nNew themes.', url: 'https://example.test/HYETI.apk'),
    );
    await settle(tester);
    await snap(tester, 'update_sheet');
  });
}
