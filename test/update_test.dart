import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/update.dart';
import 'package:personal_mobile_app/watch_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show settle, tapText;

/// Makes GitHub answer with a release tagged [tag], and counts the times it was asked.
List<Uri> fakeGitHub(String tag, {int status = 200}) {
  final asked = <Uri>[];
  httpClient = MockClient((request) async {
    asked.add(request.url);
    return http.Response(
      jsonEncode({
        'tag_name': tag,
        'body': 'Faster calendar.',
        'assets': [
          {'name': 'HYETI.apk', 'browser_download_url': 'https://example.test/HYETI.apk'},
        ],
      }),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return asked;
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
    await tester.pumpWidget(const LifeApp(checkForUpdates: true));
    await settle(tester);
  }

  test('appVersion matches the version in pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(appVersion, line.substring('version:'.length).trim().split('+').first);
  });

  test('versions compare by their numbers, not as text', () {
    expect(isNewer('1.0.5', '1.0.4'), isTrue);
    expect(isNewer('v1.0.10', '1.0.9'), isTrue);
    expect(isNewer('2.0', '1.9.9'), isTrue);
    expect(isNewer('1.1.0+7', '1.0.4'), isTrue);
    expect(isNewer('1.0.4', '1.0.4'), isFalse);
    expect(isNewer('v1.0.4', '1.0.4'), isFalse);
    expect(isNewer('1.0', '1.0.0'), isFalse);
    expect(isNewer('1.0.3', '1.0.4'), isFalse);
    expect(isNewer('nonsense', '1.0.4'), isFalse);
  });

  test('a release is read from GitHub, with a fallback link when the APK is not attached', () async {
    final asked = fakeGitHub('v9.9.9');
    final release = await fetchLatestRelease();
    expect(asked.single.toString(), 'https://api.github.com/repos/Mohamed-Rayene-Trabelsi/HYETI/releases/latest');
    expect(release.version, '9.9.9');
    expect(release.notes, 'Faster calendar.');
    expect(release.url, 'https://example.test/HYETI.apk');

    final bare = parseRelease({'tag_name': 'v2.0.0', 'body': null, 'assets': <Object>[]});
    expect(bare.notes, '');
    expect(bare.url, 'https://github.com/Mohamed-Rayene-Trabelsi/HYETI/releases/latest/download/HYETI.apk');
  });

  testWidgets('a newer release is offered on start, and skipping it keeps it quiet', (tester) async {
    fakeGitHub('v9.9.9');
    await start(tester);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Version 9.9.9 is out. This phone has $appVersion.'), findsOneWidget);
    expect(find.text('Faster calendar.'), findsOneWidget);

    await tapText(tester, 'Skip this version');
    expect(find.text('Update available'), findsNothing);
    expect(appDb.setting('skipped_version', ''), '9.9.9');

    // The next start finds the same release and says nothing.
    await tester.pumpWidget(const SizedBox());
    await start(tester);
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('"Later" closes the offer without skipping the version', (tester) async {
    fakeGitHub('v9.9.9');
    await start(tester);
    await tapText(tester, 'Later');
    expect(find.text('Update available'), findsNothing);
    expect(appDb.setting('skipped_version', ''), '');
  });

  testWidgets('nothing is offered when up to date or when GitHub cannot be reached', (tester) async {
    fakeGitHub('v$appVersion');
    await start(tester);
    expect(find.text('Update available'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    fakeGitHub('v9.9.9', status: 404);
    await start(tester);
    expect(find.text('Update available'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings can check on request, even for a skipped version', (tester) async {
    await tester.runAsync(() => appDb.setSetting('skipped_version', '9.9.9'));
    fakeGitHub('v$appVersion');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LifeApp());
    await settle(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(tester);

    await tapText(tester, 'Check for updates');
    expect(find.text('This is the newest version.'), findsOneWidget);

    fakeGitHub('v9.9.9');
    await tapText(tester, 'Check for updates');
    expect(find.text('Update available'), findsOneWidget);
  });
}
