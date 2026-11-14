// Draws screens of the app to PNG files under test/preview/ so they can be looked at without a phone.
// Run with: flutter test test/render_preview_test.dart --update-goldens
//
// It is a drawing tool, not a check: without --update-goldens it does nothing, so a small rendering
// difference between machines can never fail the test suite.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/date.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/sketch.dart';
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

void main() {
  if (!autoUpdateGoldenFiles) return;

  setUp(() async {
    sqfliteFfiInit();
    appDb = await AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });

  tearDown(() => appDb.raw.close());

  testWidgets('screens', (tester) async {
    await tester.runAsync(loadFonts);
    // A phone of about the size and density of a current Android handset.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.runAsync(seed);

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

    await tester.tap(find.text('Week'));
    await settle(tester);
    await snap(tester, 'calendar_week');

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

    await tester.tap(find.text('Bench press').hitTestable().first);
    await settle(tester);
    await snap(tester, 'body_log_set');
    await tester.tap(find.text('Close'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    await snap(tester, 'settings');

    for (final theme in ['Web Slinger', 'Dark Knight', 'Five-Leaf Clover']) {
      await tester.tap(find.text(theme));
      await settle(tester);
      await snap(tester, 'theme_${theme.toLowerCase().replaceAll(RegExp('[^a-z]+'), '_')}');
    }
    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);
    await snap(tester, 'body_clover');
  });
}
