import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/date.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/screens/watch.dart' show footballError;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show openTab, settle;

void main() {
  test('football errors tell being offline from FotMob changing', () {
    expect(footballError(const SocketException('no route')), contains('internet'));
    expect(footballError(TimeoutException('slow')), contains('internet'));
    expect(footballError(const FormatException('bad json')), contains('unofficial'));
    expect(footballError(Exception('FotMob answered 500')), contains('unofficial'));
  });

  group('with the app', () {
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

    testWidgets('logging a set ticks off today\'s gym block and starts a rest', (tester) async {
      await tester.runAsync(
        () => appDb.insert(
          'INSERT INTO routines (title, category, days, start_min, end_min, created_date) VALUES (?, ?, ?, ?, ?, ?)',
          ['Gym', 'gym', '0,1,2,3,4,5,6', 18 * 60, 19 * 60, todayKey()],
        ),
      );
      await start(tester);
      await openTab(tester, 'Body');
      await tester.tap(find.text('Log set').hitTestable().last);
      await settle(tester);
      await tester.tap(find.text('Log set').hitTestable().last);
      await settle(tester);

      final gym = await tester.runAsync(
        () => appDb.query("SELECT done FROM events WHERE date = ? AND category = 'gym'", [todayKey()]),
      );
      expect(gym, [
        {'done': 1},
      ]);
      await settle(tester);
      // Counting down from 1:30 (the clock may already have moved a second while the sheet settled).
      int left() {
        final text = tester.widgetList<Text>(find.textContaining('Rest ')).single.data!;
        final m = RegExp(r'(\d+):(\d\d)').firstMatch(text)!;
        return int.parse(m[1]!) * 60 + int.parse(m[2]!);
      }

      final before = left();
      expect(before, inInclusiveRange(85, 90));
      await tester.pump(const Duration(seconds: 2));
      expect(left(), before - 2);
      await tester.tap(find.text('+15 s'));
      await settle(tester);
      expect(left(), inInclusiveRange(before - 2 + 15 - 2, before - 2 + 15));
      expect(appDb.setting('rest_seconds', 0), 105);

      await tester.tap(find.text('Skip rest'));
      await settle(tester);
      expect(find.textContaining('Rest '), findsNothing);
    });

    testWidgets('the wallet shows where this month\'s money went, by label', (tester) async {
      final today = todayKey();
      await tester.runAsync(() async {
        for (final (amount, label) in [(40.0, 'Groceries'), (25.0, 'Groceries'), (30.0, 'Transport'), (5.0, '')]) {
          await appDb.insert("INSERT INTO transactions (date, kind, amount, label) VALUES (?, 'expense', ?, ?)", [
            today,
            amount,
            label,
          ]);
        }
      });
      await start(tester);
      await openTab(tester, 'Wallet');
      expect(find.textContaining('WHERE IT WENT'), findsOneWidget);
      expect(find.text(r'$65'), findsOneWidget);
      expect(find.text(r'$30'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.textContaining('Give expenses a label'), findsOneWidget);
    });
  });
}
