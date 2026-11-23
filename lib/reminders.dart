import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'date.dart';
import 'db.dart';
import 'screens/calendar.dart' show fillRoutineDays, offDatesBetween;

/// How far ahead reminders are scheduled. They are planned again every time the app opens or anything changes, so
/// this only matters when the app stays closed for days.
const reminderDays = 7;

/// iPhones keep at most 64 waiting notifications per app; stay under that.
const maxReminders = 60;

/// The `id` of the "membership ends soon" reminder; block reminders use their event id.
const membershipReminderId = 1 << 30;

/// Lead time choices: minutes before a block → label.
const reminderLeads = {
  0: 'At the start',
  5: '5 min before',
  10: '10 min before',
  15: '15 min before',
  30: '30 min before',
};

/// Minutes before each block to remind, or null when reminders are off (or were never turned on).
int? reminderLead() => appDb.setting<int?>('reminder_lead', null);

/// "15 min before blocks", or "Off".
String reminderSummary() {
  final lead = reminderLead();
  if (lead == null) return 'Off';
  return lead == 0 ? 'When blocks start' : '$lead min before blocks';
}

/// One notification to show at [at].
class PlannedReminder {
  const PlannedReminder({required this.id, required this.at, required this.title, required this.body});

  final int id;
  final DateTime at;
  final String title;
  final String body;

  @override
  String toString() => '$at $title · $body';
}

/// The reminders for [blocks] (rows of `events`, with their date and times), [lead] minutes before each starts, that
/// are still ahead of [now]. Ticked-off blocks get none, and work blocks get none on [offDates]. Also one for the gym
/// membership's last days when [membershipEnd] ('YYYY-MM-DD') is set. Soonest first, at most [maxReminders].
List<PlannedReminder> planReminders({
  required List<Rec> blocks,
  required int lead,
  required DateTime now,
  Set<String> offDates = const {},
  String? membershipEnd,
}) {
  final out = <PlannedReminder>[];
  for (final b in blocks) {
    final date = b['date'] as String;
    if (b['done'] == 1 || b['hidden'] == 1) continue;
    if (b['category'] == 'work' && offDates.contains(date)) continue;
    final start = (b['start_min'] as int) + (b['shift_min'] as int? ?? 0);
    final end = (b['end_min'] as int) + (b['shift_min'] as int? ?? 0);
    final day = fromKey(date);
    final at = DateTime(day.year, day.month, day.day, 0, start - lead);
    if (!at.isAfter(now)) continue;
    final title = b['title'] as String;
    out.add(
      PlannedReminder(
        id: b['id'] as int,
        at: at,
        title: lead == 0 ? '$title now' : '$title in $lead min',
        body: '${formatTime(start)} – ${formatTime(end)}',
      ),
    );
  }
  if (membershipEnd != null && isDateKey(membershipEnd)) {
    // Three days ahead, mid-morning, so there is time to renew.
    final end = fromKey(membershipEnd);
    final at = DateTime(end.year, end.month, end.day - 3, 10);
    if (at.isAfter(now)) {
      out.add(
        PlannedReminder(
          id: membershipReminderId,
          at: at,
          title: 'Gym membership ends in 3 days',
          body: 'It runs out on ${formatDay(membershipEnd)}. Renew it from the Body tab.',
        ),
      );
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.take(maxReminders).toList();
}

/// Where reminders go: the phone's notifications. Tests swap in a fake.
abstract class ReminderScheduler {
  /// Asks to show notifications. True when allowed.
  Future<bool> requestPermission();

  /// Cancels every waiting reminder and schedules [reminders] instead.
  Future<void> replaceAll(List<PlannedReminder> reminders);
}

ReminderScheduler reminderScheduler = _PhoneScheduler();

/// Plans the coming reminders from the calendar and hands them to [reminderScheduler]; with reminders off, cancels
/// them all. Never throws: a reminder that cannot be scheduled is not worth a crash.
Future<void> syncReminders({DateTime? now}) async {
  try {
    final lead = reminderLead();
    if (lead == null) {
      await reminderScheduler.replaceAll(const []);
      return;
    }
    final today = todayKey();
    final last = addDays(today, reminderDays);
    await fillRoutineDays(today, last);
    final blocks = await appDb.query('SELECT * FROM events WHERE date BETWEEN ? AND ? AND hidden = 0', [today, last]);
    final membership = appDb.setting<Map<String, Object?>?>('membership', null);
    await reminderScheduler.replaceAll(
      planReminders(
        blocks: blocks,
        lead: lead,
        now: now ?? DateTime.now(),
        offDates: await offDatesBetween(today, last),
        membershipEnd: membership?['end'] as String?,
      ),
    );
  } catch (e) {
    debugPrint('Reminders: $e');
  }
}

/// Turns reminders on, [lead] minutes before blocks, after asking the phone for permission. False when the person
/// said no, in which case reminders stay as they were.
Future<bool> turnOnReminders(int lead) async {
  bool allowed;
  try {
    allowed = await reminderScheduler.requestPermission();
  } catch (e) {
    debugPrint('Reminders: $e');
    allowed = false;
  }
  if (!allowed) return false;
  await appDb.setSetting('reminder_lead', lead);
  await syncReminders();
  return true;
}

Future<void> turnOffReminders() async {
  await appDb.setSetting('reminder_lead', null);
  await syncReminders();
}

Timer? _debounce;

/// Keeps reminders in step with the calendar: plans them now, and again a moment after anything is saved.
/// Called once from `main`; not in tests.
void keepRemindersInStep() {
  unawaited(syncReminders());
  appDb.addListener(() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncReminders);
  });
}

class _PhoneScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  Future<void> _init() => _ready ??= () async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // An unknown zone name: times are then read as UTC, which beats no reminders at all.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_mark'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }();

  @override
  Future<bool> requestPermission() async {
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true, badge: false) ?? false;
    return false;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    await _init();
    await _plugin.cancelAll();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        'Reminders',
        channelDescription: 'Before calendar blocks and when the gym membership is about to end',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(),
    );
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }
}
