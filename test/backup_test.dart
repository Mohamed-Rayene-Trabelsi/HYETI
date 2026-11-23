import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/backup.dart';
import 'package:personal_mobile_app/date.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show settle, tapText;

Future<void> _addSomeData() async {
  await appDb.insert("INSERT INTO notes (title, body, pinned, updated_at) VALUES ('Groceries', 'Eggs', 1, 0)");
  await appDb.insert(
    "INSERT INTO transactions (date, kind, amount, label, from_wallet) VALUES ('2026-11-20', 'income', 900, 'Pay', 1)",
  );
  await appDb.setSetting('currency', '€');
}

Future<int> _count(String table) async => (await appDb.query('SELECT COUNT(*) AS n FROM $table')).first['n'] as int;

/// [bytes] with the schema version SQLite keeps in the file header set to [version].
Uint8List _withVersion(Uint8List bytes, int version) =>
    Uint8List.fromList(bytes)..buffer.asByteData().setUint32(60, version);

/// Lets real time pass (the database works outside the test's clock) until [finder] finds something, or 10 s.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await settle(tester);
}

void main() {
  setUp(() async {
    sqfliteFfiInit();
    appDb = await AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });

  tearDown(() => appDb.raw.close());

  test('a backup puts back every row and setting', () async {
    await _addSomeData();
    final backup = await appDb.exportBackup();

    await appDb.eraseAll();
    await appDb.insert("INSERT INTO notes (title, body, pinned, updated_at) VALUES ('Made after', '', 0, 0)");
    expect(appDb.setting('currency', r'$'), r'$');

    await appDb.importBackup(backup);
    final notes = await appDb.query('SELECT title, body, pinned FROM notes');
    expect(notes, [
      {'title': 'Groceries', 'body': 'Eggs', 'pinned': 1},
    ]);
    expect(await _count('transactions'), 1);
    expect(appDb.setting('currency', r'$'), '€');
  });

  test('a file that is not a backup is refused, and nothing changes', () async {
    await _addSomeData();
    final notBackup = Uint8List.fromList(List.filled(500, 65));
    await expectLater(appDb.importBackup(notBackup), throwsA(isA<BackupError>()));

    // A real SQLite file, but not one HYETI made (no schema version).
    final empty = _withVersion(await appDb.exportBackup(), 0);
    await expectLater(appDb.importBackup(empty), throwsA(isA<BackupError>()));

    expect(await _count('notes'), 1);
  });

  test('a backup from a newer version of the app is refused', () async {
    await _addSomeData();
    final newer = _withVersion(await appDb.exportBackup(), 99);
    await expectLater(
      appDb.importBackup(newer),
      throwsA(isA<BackupError>().having((e) => e.message, 'message', contains('newer version'))),
    );
    expect(await _count('notes'), 1);
  });

  testWidgets('Settings saves a backup and restores one', (tester) async {
    await tester.runAsync(_addSomeData);
    Uint8List? saved;
    String? savedName;
    saveBackupFile = (name, bytes) async {
      savedName = name;
      saved = bytes;
      return true;
    };
    pickBackupFile = () async => saved;

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LifeApp());
    await settle(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(tester);
    expect(find.text('Never saved'), findsOneWidget);
    await tapText(tester, 'Backup');

    await tester.tap(find.text('Save a backup'));
    await waitFor(tester, find.text('Backup saved. Keep it somewhere off this phone.'));
    expect(savedName, 'HYETI backup ${todayKey()}.hyeti');
    expect(find.text('Backup saved. Keep it somewhere off this phone.'), findsOneWidget);
    expect(appDb.setting('last_backup', ''), todayKey());

    await tester.runAsync(() => appDb.eraseAll());
    await settle(tester);
    await tapText(tester, 'Restore from a backup');
    expect(find.textContaining('replaces everything'), findsOneWidget);
    await tester.tap(find.text('Choose the file'));
    await waitFor(tester, find.textContaining('Restored.'));
    expect(find.textContaining('Restored.'), findsOneWidget);
    expect(await tester.runAsync(() => _count('notes')), 1);
    expect(appDb.setting('currency', r'$'), '€');
  });
}
