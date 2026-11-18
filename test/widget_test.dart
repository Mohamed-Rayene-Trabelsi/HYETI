import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/date.dart';
import 'package:personal_mobile_app/receipt.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/jar.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/sketch.dart';
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

/// A week of repeating blocks, as someone might set up: lunch, dinner and gaming every day, work and gym some days.
Future<void> addRoutine(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final (title, category, days, start, end) in [
      ('Deep work', 'work', '0,1,2,3,4', 540, 660),
      ('Lunch', 'food', '0,1,2,3,4,5,6', 780, 825),
      ('Gym', 'gym', '0,1,3,4', 1080, 1170),
      ('Dinner', 'food', '0,1,2,3,4,5,6', 1200, 1245),
      ('Gaming', 'game', '0,1,2,3,4,5,6', 1260, 1350),
    ]) {
      await appDb.run(
        'INSERT INTO routines (title, category, days, start_min, end_min, flex_min, created_date) '
        'VALUES (?, ?, ?, ?, ?, 15, ?)',
        [title, category, days, start, end, todayKey()],
      );
    }
  });
  await settle(tester);
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
  }

  testWidgets('every tab opens without errors, and settings open from the gear', (tester) async {
    await start(tester);
    for (final (tab, marker) in [
      ('Body', 'CHEST EXERCISES'),
      ('Wallet', 'THIS WEEK'),
      ('Watch', 'Your list is empty'),
      ('Notes', 'No notes yet'),
      ('Calendar', 'Plan your days'),
    ]) {
      await openTab(tester, tab);
      expect(find.text(marker).hitTestable(), findsOneWidget, reason: tab);
    }

    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    expect(find.text('Everything is stored on this phone. No account, no sync, no ads.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);
    expect(find.text('Plan your days').hitTestable(), findsOneWidget);
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

  testWidgets('repeating blocks fill today', (tester) async {
    await start(tester);
    await addRoutine(tester);

    expect(find.text('Plan your days'), findsNothing);
    final today = await tester.runAsync(() => appDb.query('SELECT * FROM events WHERE date = ?', [todayKey()]));
    // Lunch, dinner and gaming run every day; work and gym depend on the weekday.
    expect(today!.length, greaterThanOrEqualTo(3));
    expect(find.text('0 of ${today.length} done'), findsOneWidget);
  });

  testWidgets('the month view draws the routine, and there is no week view', (tester) async {
    await start(tester);
    await addRoutine(tester);
    expect(find.text('Week'), findsNothing);
    await tapText(tester, 'Month');
    expect(find.text(formatMonth(todayKey())), findsOneWidget);
  });

  testWidgets('quick setup adds one repeating block after another from the same sheet', (tester) async {
    await start(tester);
    await tapText(tester, 'Quick setup');
    for (final name in ['Gym', 'Lunch']) {
      await tester.enterText(field(0), name);
      await settle(tester);
      await tapText(tester, 'Add to calendar');
    }
    expect(find.text('Added Lunch. Add another, or close when you are done.'), findsOneWidget);

    final routines = await tester.runAsync(() => appDb.query('SELECT * FROM routines ORDER BY id'));
    expect([for (final r in routines!) r['title']], ['Gym', 'Lunch']);
    // The name picked the icon, and each repeats on the weekday it was set up on.
    expect([for (final r in routines) r['category']], ['gym', 'food']);
    expect(routines.first['days'], '${weekdayOf(todayKey())}');
  });

  testWidgets('a repeating block can be removed from every week, and put back', (tester) async {
    await start(tester);
    await addRoutine(tester);
    await tapText(tester, 'Lunch');
    await tapText(tester, 'Remove from every week');

    Future<List<Object?>> titles() async => [
      for (final r in (await tester.runAsync(() => appDb.query('SELECT title FROM routines')))!) r['title'],
    ];
    expect(await titles(), isNot(contains('Lunch')));
    expect(find.text('Lunch'), findsNothing);

    await tapText(tester, 'Undo');
    expect(await titles(), contains('Lunch'));
    expect(find.text('Lunch'), findsOneWidget);
  });

  testWidgets('a single block can be removed from the calendar', (tester) async {
    await start(tester);
    await tester.runAsync(
      () => appDb.run(
        "INSERT INTO events (date, title, category, start_min, end_min, flex_min) VALUES (?, 'Dentist', 'health', "
        '600, 660, 15)',
        [todayKey()],
      ),
    );
    await settle(tester);
    await tapText(tester, 'Dentist');
    await tapText(tester, 'Remove from calendar');
    expect(await tester.runAsync(() => appDb.query('SELECT * FROM events')), isEmpty);
  });

  testWidgets('weekly days off are set in settings and leave work off the calendar', (tester) async {
    await start(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    await tapText(tester, 'Days off');
    final today = weekdays[weekdayOf(todayKey())];
    await tapText(tester, today);
    expect(appDb.setting<List<dynamic>>('off_weekdays', const []), [weekdayOf(todayKey())]);
    // Tapping again makes it a normal day once more.
    await tapText(tester, today);
    expect(appDb.setting<List<dynamic>>('off_weekdays', const []), isEmpty);
  });

  testWidgets('the top bar with the settings gear stays on every tab', (tester) async {
    await start(tester);
    for (final tab in ['Body', 'Wallet', 'Watch', 'Notes', 'Calendar']) {
      await openTab(tester, tab);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget, reason: tab);
      expect(find.text(formatTime(nowMinutes())), findsOneWidget, reason: tab);
    }
  });

  testWidgets('a block is added from the sheet with a name, a day and a one-tap length', (tester) async {
    await start(tester);
    await tapText(tester, 'Add');
    await tester.enterText(field(0), 'Study for the exam');
    await settle(tester);
    await tapText(tester, 'Tomorrow');
    await tapText(tester, '1h30');
    await tapText(tester, 'Add to calendar');

    final rows = await tester.runAsync(() => appDb.query('SELECT * FROM events'));
    final block = rows!.single;
    expect(block['title'], 'Study for the exam');
    expect(block['category'], 'study');
    expect((block['end_min'] as int) - (block['start_min'] as int), 90);
    expect(block['date'], addDays(todayKey(), 1));
    // The calendar moves to the day the block went on.
    expect(find.text('Tomorrow'), findsOneWidget);
  });

  testWidgets('picking an icon by hand sticks, whatever the name says', (tester) async {
    await start(tester);
    await tapText(tester, 'Add');
    await tester.tap(find.bySemanticsLabel('Icon: Other'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Reading'));
    await settle(tester);
    await tester.enterText(field(0), 'Gym');
    await settle(tester);
    await tapText(tester, 'Add to calendar');
    expect((await tester.runAsync(() => appDb.query('SELECT * FROM events')))!.single['category'], 'read');
  });

  testWidgets('with a TMDB key saved, the watch tab no longer asks for keys', (tester) async {
    await tester.runAsync(() => appDb.setSetting('tmdb_key', 'abc'));
    await start(tester);
    await openTab(tester, 'Watch');
    expect(find.byIcon(Icons.key_outlined), findsNothing);
    await tapText(tester, 'Shows');
    expect(find.text('Add OMDb key'), findsNothing);
    expect(find.text('A free key is needed'), findsNothing);
  });

  testWidgets('money dropped in the savings jar is saved and fills it', (tester) async {
    await start(tester);
    await tester.runAsync(() => appDb.setSetting('goal', {'name': 'Bike', 'target': 40}));
    await openTab(tester, 'Wallet');
    expect(find.text('0% of \$40'), findsOneWidget);

    await tapText(tester, 'Drop in');
    await tapText(tester, '+\$10');

    final rows = await tester.runAsync(() => appDb.query("SELECT * FROM transactions WHERE kind = 'saving'"));
    expect(rows!.single['amount'], 10);
    expect(find.text('25% of \$40'), findsOneWidget);
    // Passing a quarter of the goal is cheered.
    expect(find.text(jarCheers[25]!), findsOneWidget);
  });

  testWidgets('taking money out of the jar asks first, and only goes ahead when told to', (tester) async {
    await start(tester);
    await tester.runAsync(() async {
      await appDb.setSetting('goal', {'name': 'Bike', 'target': 40});
      await appDb.insert("INSERT INTO transactions (date, kind, amount, label) VALUES (?, 'saving', 30, '')", [
        todayKey(),
      ]);
    });
    await openTab(tester, 'Wallet');
    expect(find.text('75% of \$40'), findsOneWidget);

    // The "i" explains the jar.
    await tester.tap(find.byIcon(Icons.info_outline).hitTestable());
    await settle(tester);
    expect(find.text('How the jar works'), findsOneWidget);
    await tapText(tester, 'Close');

    // Backing out of the "are you sure?" leaves the jar alone.
    await tapText(tester, 'Take out');
    expect(find.text('−\$50'), findsNothing, reason: 'only amounts that are in the jar are offered');
    await tapText(tester, '−\$10');
    expect(find.text('Are you sure?'), findsOneWidget);
    await tapText(tester, 'Keep it in the jar');
    expect(await tester.runAsync(() => appDb.query("SELECT * FROM transactions WHERE kind = 'withdraw'")), isEmpty);

    await tapText(tester, '−\$10');
    await tapText(tester, 'Momma raised a financial failure, I GUESS ?');
    final out = await tester.runAsync(() => appDb.query("SELECT * FROM transactions WHERE kind = 'withdraw'"));
    expect(out!.single['amount'], 10);
    expect(find.text('50% of \$40'), findsOneWidget);
    expect(find.text('Taken from the jar'), findsOneWidget);
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

  testWidgets('scanning a receipt fills in the transaction', (tester) async {
    final real = readReceiptText;
    addTearDown(() => readReceiptText = real);
    readReceiptText = ({required bool camera}) async => 'CORNER SHOP\n02/01/2026\nTea 4.50\nTOTAL 23.75';
    await start(tester);
    await openTab(tester, 'Wallet');
    await tapText(tester, 'Add');
    await tapText(tester, 'Scan receipt');

    expect(tester.widget<TextField>(field(0)).controller!.text, '23.75');
    expect(tester.widget<TextField>(field(1)).controller!.text, 'Corner Shop');
    await tapText(tester, 'Save');
    final row = (await tester.runAsync(() => appDb.query('SELECT * FROM transactions')))!.single;
    expect(row['amount'], 23.75);
    expect(row['kind'], 'expense');
    expect(row['date'], '2026-01-02');
  });

  testWidgets('a misread receipt total is fixed by tapping another amount from it', (tester) async {
    final real = readReceiptText;
    addTearDown(() => readReceiptText = real);
    // The "total" line is really the items count's price; the right figure is elsewhere on the receipt.
    readReceiptText = ({required bool camera}) async => 'CORNER SHOP\nTea  4.50\nCake  6.25\nTOTAL  4.50\nDue 10.75';
    await start(tester);
    await openTab(tester, 'Wallet');
    await tapText(tester, 'Add');
    await tapText(tester, 'Scan receipt');

    expect(tester.widget<TextField>(field(0)).controller!.text, '4.5');
    expect(find.textContaining('Tap the right amount'), findsOneWidget);
    await tapText(tester, '10.75');
    expect(tester.widget<TextField>(field(0)).controller!.text, '10.75');
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

  testWidgets('a sketch is drawn, saved as a note, and reopens with undo and clear', (tester) async {
    await start(tester);
    await openTab(tester, 'Notes');
    await tester.tap(find.byIcon(Icons.brush_outlined).hitTestable());
    await settle(tester);
    await tester.enterText(field(0), 'Floor plan');
    final canvas = find.byKey(const Key('sketch-canvas'));
    await tester.drag(canvas, const Offset(80, 60));
    await tester.drag(canvas, const Offset(-60, 90));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    // The slider sets how thick the next line is.
    await tester.drag(find.byKey(const Key('pen-width')), const Offset(200, 0));
    await tester.pump();
    await tester.drag(canvas, const Offset(40, -70));
    await tester.pump();
    await tapText(tester, '‹ Done');

    expect(find.text('1 note'), findsOneWidget);
    expect(find.text('Floor plan'), findsOneWidget);
    var row = (await tester.runAsync(() => appDb.query('SELECT * FROM notes')))!.single;
    final strokes = decodeSketch(row['sketch'] as String?);
    expect(strokes, hasLength(2));
    expect(strokes[1].width, greaterThan(strokes[0].width));

    // Clearing the drawing but keeping the title keeps the note; it is still a sketch.
    await tapText(tester, 'Floor plan');
    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pump();
    await tapText(tester, '‹ Done');
    row = (await tester.runAsync(() => appDb.query('SELECT * FROM notes')))!.single;
    expect(decodeSketch(row['sketch'] as String?), isEmpty);
    expect(row['sketch'], isNotNull);
  });

  testWidgets('an undo message leaves by itself, or when something else is touched', (tester) async {
    await tester.runAsync(() => appDb.insert("INSERT INTO notes (title, body, updated_at) VALUES ('Old', 'x', 1)"));
    await start(tester);
    await openTab(tester, 'Notes');

    await tapText(tester, 'Old');
    await tapText(tester, 'Delete');
    expect(find.text('Note deleted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Note deleted'), findsNothing);

    await tester.runAsync(() => appDb.insert("INSERT INTO notes (title, body, updated_at) VALUES ('Older', 'x', 1)"));
    await settle(tester);
    await tapText(tester, 'Older');
    await tapText(tester, 'Delete');
    expect(find.text('Note deleted'), findsOneWidget);
    await openTab(tester, 'Wallet');
    expect(find.text('Note deleted'), findsNothing);
    expect(await tester.runAsync(() => appDb.query('SELECT * FROM notes')), isEmpty);
  });

  testWidgets('choosing a country sets the currency', (tester) async {
    await start(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    expect(find.text('Week starts on'), findsNothing);
    await tapText(tester, 'Country and units');
    await tapText(tester, 'Country');
    await tester.enterText(field(0), 'tunis');
    await settle(tester);
    await tapText(tester, 'Tunisia');

    expect(appDb.setting('currency', r'$'), 'TND');
    expect(find.text('Tunisia'), findsOneWidget);
    expect(tester.widget<TextField>(field(0)).controller!.text, 'TND');
  });

  testWidgets('a colour theme chosen in settings recolours the app and is remembered', (tester) async {
    await start(tester);
    final before = Theme.of(tester.element(find.byType(NavigationBar, skipOffstage: false))).colorScheme.primary;

    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    await tapText(tester, 'Appearance');
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
    await addRoutine(tester);
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
