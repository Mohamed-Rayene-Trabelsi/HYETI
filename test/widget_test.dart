import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/date.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Database calls finish on a real event loop, so let them land and then draw.
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

int selectedTab(WidgetTester tester) => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

/// Taps the copy of [text] the user could actually touch. Other tabs stay alive off screen,
/// so the same label can exist several times; one scrolled out of view is brought in first.
Future<void> tapText(WidgetTester tester, String text) async {
  var target = find.text(text).hitTestable();
  if (target.evaluate().isEmpty) {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    target = find.text(text).hitTestable();
  }
  await tester.tap(target.last);
  await settle(tester);
}

Finder field(int index) => find.byType(TextField).hitTestable().at(index);

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
  }

  testWidgets('every tab opens without errors, and settings open from the gear', (tester) async {
    await start(tester);
    for (final (tab, marker) in [
      ('Body', 'CHEST EXERCISES'),
      ('Wallet', 'THIS WEEK'),
      ('Watch', 'Your list is empty'),
      ('Notes', 'No notes yet'),
      ('Calendar', 'Set up your week'),
    ]) {
      await openTab(tester, tab);
      expect(find.text(marker).hitTestable(), findsOneWidget, reason: tab);
    }

    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    expect(find.text('Everything is stored on this phone'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);
    expect(find.text('Set up your week').hitTestable(), findsOneWidget);
  });

  testWidgets('swiping sideways moves between tabs', (tester) async {
    await start(tester);
    expect(selectedTab(tester), 0);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await settle(tester);
    expect(selectedTab(tester), 1);
    expect(find.text('CHEST EXERCISES').hitTestable(), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1200);
    await settle(tester);
    expect(selectedTab(tester), 0);
  });

  testWidgets('back from another tab returns to the first tab', (tester) async {
    await start(tester);
    await openTab(tester, 'Notes');
    expect(selectedTab(tester), 4);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(selectedTab(tester), 0);
  });

  testWidgets('the sample routine fills today', (tester) async {
    await start(tester);
    await tapText(tester, 'Use a sample routine');

    expect(find.text('Set up your week'), findsNothing);
    final routines = await tester.runAsync(() => appDb.query('SELECT * FROM routines'));
    expect(routines, hasLength(5));
    final today = await tester.runAsync(() => appDb.query('SELECT * FROM events WHERE date = ?', [todayKey()]));
    // Lunch, dinner and gaming run every day; work and gym depend on the weekday.
    expect(today!.length, greaterThanOrEqualTo(3));
    expect(find.text('0 of ${today.length} done'), findsOneWidget);
  });

  testWidgets('week and month views draw the routine', (tester) async {
    await start(tester);
    await tapText(tester, 'Use a sample routine');
    await tapText(tester, 'Week');
    expect(find.text('Lunch'), findsWidgets);
    await tapText(tester, 'Month');
    expect(find.text(formatMonth(todayKey())), findsOneWidget);
  });

  testWidgets('the top bar with the settings gear stays on every tab', (tester) async {
    await start(tester);
    for (final tab in ['Body', 'Wallet', 'Watch', 'Notes', 'Calendar']) {
      await openTab(tester, tab);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget, reason: tab);
      expect(find.text(formatTime(nowMinutes())), findsOneWidget, reason: tab);
    }
  });

  testWidgets('a block is added from the sheet with an activity and a one-tap length', (tester) async {
    await start(tester);
    await tapText(tester, 'Add');
    await tapText(tester, 'Study');
    await tapText(tester, '1h30');
    await tapText(tester, 'Add to calendar');

    final rows = await tester.runAsync(() => appDb.query('SELECT * FROM events'));
    expect(rows, hasLength(1));
    final block = rows!.single;
    expect(block['category'], 'study');
    expect(block['title'], 'Study');
    expect((block['end_min'] as int) - (block['start_min'] as int), 90);
    expect(block['date'], todayKey());
  });

  testWidgets('with a TMDB key saved, the watch tab no longer asks for keys', (tester) async {
    await tester.runAsync(() => appDb.setSetting('tmdb_key', 'abc'));
    await start(tester);
    await openTab(tester, 'Watch');
    expect(find.byIcon(Icons.key_outlined), findsNothing);
    await tapText(tester, 'Movies');
    expect(find.text('Add OMDb key'), findsNothing);
    expect(find.text('A free key is needed'), findsNothing);
  });

  testWidgets('a transaction shows up in the wallet totals and can be edited', (tester) async {
    await start(tester);
    await openTab(tester, 'Wallet');
    await tapText(tester, 'Add');
    await tester.enterText(field(0), '1200');
    await tester.enterText(field(1), 'Salary');
    await tapText(tester, 'Income');
    await tapText(tester, 'Save');

    expect(find.text(r'Available: $1,200'), findsOneWidget);

    await tapText(tester, 'Salary');
    expect(find.text('Edit transaction'), findsOneWidget);
    await tester.enterText(field(0), '1500');
    await tapText(tester, 'Save');

    expect(find.text(r'Available: $1,500'), findsOneWidget);
    final rows = await tester.runAsync(() => appDb.query('SELECT * FROM transactions'));
    expect(rows, hasLength(1));
  });

  testWidgets('a logged set appears in today\'s workout, and removing it can be undone', (tester) async {
    await start(tester);
    await openTab(tester, 'Body');
    // Tapping an exercise opens its logger; plus and minus nudge the numbers.
    await tapText(tester, 'Bench press');
    await tester.enterText(field(0), '60');
    await tester.enterText(field(1), '7');
    await tester.tap(find.bySemanticsLabel('More Weight (kg)'));
    await tester.tap(find.bySemanticsLabel('More Reps'));
    await tapText(tester, 'Log set');
    expect(find.textContaining('Set 1 logged'), findsOneWidget);
    await tapText(tester, 'Close');

    expect(find.text('62.5 kg × 8'), findsOneWidget);
    expect(find.text('1 set today'), findsOneWidget);

    await tapText(tester, '62.5 kg × 8');
    expect(find.text('62.5 kg × 8'), findsNothing);

    await tapText(tester, 'Undo');
    expect(find.text('62.5 kg × 8'), findsOneWidget);

    // Let the message's own timer run out.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a note is saved when the editor closes', (tester) async {
    await start(tester);
    await openTab(tester, 'Notes');
    await tapText(tester, 'New note');
    await tester.enterText(field(0), 'Groceries');
    await tester.enterText(field(1), 'Eggs and rice');
    await tapText(tester, '‹ Done');

    expect(find.text('1 note'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
  });

  testWidgets('a colour theme chosen in settings recolours the app and is remembered', (tester) async {
    await start(tester);
    final before = Theme.of(tester.element(find.byType(NavigationBar, skipOffstage: false))).colorScheme.primary;

    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    await tapText(tester, 'Dark Knight');

    expect(appDb.setting('palette', 'indigo'), 'bat');
    final after = Theme.of(tester.element(find.byType(NavigationBar, skipOffstage: false))).colorScheme.primary;
    expect(after, isNot(before));

    // The custom theme offers its own accent colours.
    await tapText(tester, 'Custom');
    expect(find.text('Accent colour'), findsOneWidget);
    expect(appDb.setting('palette', 'indigo'), 'custom');
  });

  testWidgets('the day list ticks a block off', (tester) async {
    await start(tester);
    await tapText(tester, 'Use a sample routine');
    final total = (await tester.runAsync(() => appDb.query('SELECT * FROM events WHERE date = ?', [todayKey()])))!
        .length;

    await tester.tap(find.bySemanticsLabel('Mark Lunch done').hitTestable());
    await settle(tester);
    expect(find.text('1 of $total done'), findsOneWidget);
  });

  testWidgets('erasing clears data and settings', (tester) async {
    await tester.runAsync(() async {
      await appDb.setSetting('theme', 'dark');
      await appDb.insert("INSERT INTO notes (title, body, updated_at) VALUES ('a', 'b', 1)");
      await appDb.eraseAll();
    });
    expect(appDb.setting('theme', 'system'), 'system');
    expect(await tester.runAsync(() => appDb.query('SELECT * FROM notes')), isEmpty);
  });

  testWidgets('a deleted row is restored exactly', (tester) async {
    final restored = await tester.runAsync(() async {
      await appDb.insert(
        "INSERT INTO transactions (date, kind, amount, label) VALUES ('2026-11-13', 'expense', 12.5, 'x')",
      );
      final before = (await appDb.query('SELECT * FROM transactions')).single;
      await appDb.run('DELETE FROM transactions WHERE id = ?', [before['id']]);
      await appDb.restore('transactions', before);
      return [before, (await appDb.query('SELECT * FROM transactions')).single];
    });
    expect(restored![1], restored[0]);
  });
}
