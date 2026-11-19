import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/football.dart';
import 'package:personal_mobile_app/genres.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/watch_prefs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show openTab, settle, tapText;

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

  testWidgets('Watch asks what you are into, and then shows only that', (tester) async {
    await start(tester);
    await openTab(tester, 'Watch');
    expect(find.text('What are you into?'), findsOneWidget);
    expect(find.text('My list'), findsNothing, reason: 'nothing else shows until it is answered');

    // Everything is ticked to begin with; untick all but movies.
    await tapText(tester, 'Series');
    await tapText(tester, 'Anime');
    await tapText(tester, 'Manga');
    await tapText(tester, 'Football');
    await tapText(tester, 'Next');
    expect(find.text('Which genres do you enjoy?'), findsOneWidget);
    await tapText(tester, 'Sci-Fi');
    await tapText(tester, 'Done');

    final prefs = watchPrefs();
    expect(prefs.setUp, isTrue);
    expect(prefs.kinds, {'movie'});
    expect(prefs.genres, ['Sci-Fi']);
    expect(footballPrefs().off, isTrue, reason: 'leaving football out hides its tab');
    expect(find.text('My list'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Anime'), findsNothing);
    expect(find.text('Manga'), findsNothing);

    // The picked genre counts for suggestions before anything is saved.
    final taste = await tester.runAsync(loadTaste);
    expect(taste!.isEmpty, isFalse);
    expect(taste.top(1), ['Sci-Fi']);
  });

  testWidgets('Settings → Watch turns tabs on and off, and can ask again', (tester) async {
    await tester.runAsync(() async {
      await appDb.setSetting('watch_prefs', {
        'setUp': true,
        'kinds': ['movie', 'series'],
      });
      await appDb.setSetting('football', const FootballPrefs(setUp: true, off: true).toJson());
    });
    await start(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined).hitTestable());
    await settle(tester);
    expect(find.text('Movies, Series'), findsOneWidget);

    await tapText(tester, 'Watch');
    expect(find.text('Movies and series need a free TMDB key'), findsOneWidget);
    await tapText(tester, 'Anime');
    expect(watchPrefs().kinds, {'movie', 'series', 'anime'});

    await tester.ensureVisible(find.text('Ask me again'));
    await tapText(tester, 'Ask me again');
    expect(watchPrefs().setUp, isFalse);
    expect(watchPrefs().kinds, {'movie', 'series', 'anime'}, reason: 'the answers are kept as the starting point');
  });
}
