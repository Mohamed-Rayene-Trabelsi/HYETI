import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/date.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/reminders.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show settle, tapText;

class FakeScheduler implements ReminderScheduler {
  FakeScheduler({this.allow = true});

  final bool allow;
  List<PlannedReminder> scheduled = [];
  int asked = 0;

  @override
  Future<bool> requestPermission() async {
    asked++;
    return allow;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async => scheduled = reminders;
}

Rec block(int id, String date, String title, int start, int end, {String category = 'gym', int done = 0}) => {
  'id': id,
  'date': date,
  'title': title,
  'category': category,
  'start_min': start,
  'end_min': end,
  'shift_min': 0,
  'done': done,
  'hidden': 0,
};

void main() {
  group('planReminders', () {
    final now = DateTime(2026, 11, 23, 12, 0);

    test('reminds [lead] minutes before blocks still ahead, soonest first', () {
      final plan = planReminders(
        lead: 10,
        now: now,
        blocks: [
          block(1, '2026-11-23', 'Gym', 18 * 60, 19 * 60 + 30),
          block(2, '2026-11-23', 'Lunch', 11 * 60, 12 * 60, category: 'food'), // already started
          block(3, '2026-11-23', 'Deep work', 14 * 60, 16 * 60, category: 'work'),
          block(4, '2026-11-24', 'Gym', 18 * 60, 19 * 60),
        ],
      );
      expect(plan.map((r) => r.id), [3, 1, 4]);
      expect(plan[1].at, DateTime(2026, 11, 23, 17, 50));
      expect(plan[1].title, 'Gym in 10 min');
      expect(plan[1].body, '18:00 – 19:30');
    });

    test('ticked-off blocks and work on days off stay quiet', () {
      final plan = planReminders(
        lead: 0,
        now: now,
        offDates: {'2026-11-24'},
        blocks: [
          block(1, '2026-11-23', 'Gym', 18 * 60, 19 * 60, done: 1),
          block(2, '2026-11-24', 'Deep work', 9 * 60, 11 * 60, category: 'work'),
          block(3, '2026-11-24', 'Gym', 18 * 60, 19 * 60),
        ],
      );
      expect(plan.map((r) => r.id), [3]);
      expect(plan.single.title, 'Gym now');
    });

    test('a shifted block is reminded at its new time', () {
      final plan = planReminders(
        lead: 5,
        now: now,
        blocks: [block(1, '2026-11-23', 'Gym', 18 * 60, 19 * 60)..['shift_min'] = 30],
      );
      expect(plan.single.at, DateTime(2026, 11, 23, 18, 25));
    });

    test('the gym membership is reminded three days before it ends', () {
      final plan = planReminders(lead: 10, now: now, blocks: const [], membershipEnd: '2026-11-30');
      expect(plan.single.id, membershipReminderId);
      expect(plan.single.at, DateTime(2026, 11, 27, 10));
      expect(planReminders(lead: 10, now: now, blocks: const [], membershipEnd: '2026-11-25'), isEmpty);
    });

    test('never more than an iPhone keeps', () {
      final many = [for (var i = 0; i < 100; i++) block(i, addDays('2026-11-24', i ~/ 10), 'B$i', 600 + i, 700 + i)];
      expect(planReminders(lead: 0, now: now, blocks: many), hasLength(maxReminders));
    });
  });

  group('with the app', () {
    late FakeScheduler fake;

    setUp(() async {
      sqfliteFfiInit();
      appDb = await AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      reminderScheduler = fake = FakeScheduler();
    });

    tearDown(() => appDb.raw.close());

    test('routine blocks of the coming week are reminded; turning off cancels them', () async {
      await appDb.insert(
        'INSERT INTO routines (title, category, days, start_min, end_min, created_date) VALUES (?, ?, ?, ?, ?, ?)',
        ['Gym', 'gym', '0,1,2,3,4,5,6', 23 * 60 + 58, 23 * 60 + 59, todayKey()],
      );
      expect(await turnOnReminders(0), isTrue);
      expect(fake.asked, 1);
      // Today's 23:58 block and the next seven days'.
      expect(fake.scheduled.length, inInclusiveRange(reminderDays, reminderDays + 1));
      expect(fake.scheduled.first.title, 'Gym now');

      await turnOffReminders();
      expect(fake.scheduled, isEmpty);
      expect(reminderLead(), isNull);
    });

    test('a refused permission leaves reminders off', () async {
      reminderScheduler = FakeScheduler(allow: false);
      expect(await turnOnReminders(10), isFalse);
      expect(reminderLead(), isNull);
    });

    testWidgets('the Calendar offers reminders once, and Settings changes them', (tester) async {
      await tester.runAsync(
        () => appDb.insert(
          'INSERT INTO routines (title, category, days, start_min, end_min, created_date) VALUES (?, ?, ?, ?, ?, ?)',
          ['Gym', 'gym', '0,1,2,3,4,5,6', 23 * 60 + 58, 23 * 60 + 59, todayKey()],
        ),
      );
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const LifeApp());
      await settle(tester);

      expect(find.text('Get a reminder before each block?'), findsOneWidget);
      await tapText(tester, 'Turn on');
      expect(find.text('Get a reminder before each block?'), findsNothing);
      expect(reminderLead(), 10);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await settle(tester);
      expect(find.text('10 min before blocks'), findsOneWidget);
      await tapText(tester, 'Reminders');
      await tapText(tester, '30 min before');
      expect(reminderLead(), 30);
      await tapText(tester, 'Off');
      expect(reminderLead(), isNull);
      expect(fake.scheduled, isEmpty);
    });
  });
}
