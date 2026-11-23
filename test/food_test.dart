import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/db.dart';
import 'package:personal_mobile_app/food_search.dart';
import 'package:personal_mobile_app/main.dart';
import 'package:personal_mobile_app/watch_api.dart' show httpClient;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show field, openTab, settle, tapText;

Map<String, Object?> product(String code, String name) => {
  'code': code,
  'product_name': name,
  'brands': ['Chobani'],
  'serving_quantity': 170,
  'nutriments': {'energy-kcal_100g': 60, 'proteins_100g': 10, 'carbohydrates_100g': 4, 'fat_100g': 0.5},
};

/// Answers Open Food Facts' search and barcode lookups; returns the URLs asked for.
List<Uri> fakeFoodFacts() {
  final asked = <Uri>[];
  httpClient = MockClient((request) async {
    asked.add(request.url);
    final body = request.url.host == 'search.openfoodfacts.org'
        ? {
            'hits': [product('111', 'Greek Yogurt')],
          }
        : request.url.path.endsWith('/0000.json')
        ? {'status': 0}
        : {'status': 1, 'product': product('', 'Skyr')};
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
  return asked;
}

void main() {
  test('basics match every word typed, in any order', () {
    expect(matchBasics('egg').map((f) => f.name), ['Egg']);
    expect(matchBasics('cooked rice').map((f) => f.name), ['Rice, white, cooked']);
    expect(matchBasics(' '), isEmpty);
  });

  test('amounts scale from 100 g', () {
    final egg = matchBasics('egg').single;
    final two = egg.of(100);
    expect(two.kcal, 143);
    final one = egg.of(egg.portion!);
    expect(one.kcal, 72);
    expect(one.protein, 6.3);
  });

  test('Open Food Facts products are read, and ones without calories skipped', () {
    final yogurt = parseProduct(product('1', 'Greek Yogurt'))!;
    expect(yogurt.label, 'Greek Yogurt · Chobani');
    expect(yogurt.portion, 170);
    expect(parseProduct({'product_name': 'Mystery', 'nutriments': <String, Object?>{}}), isNull);
    // Energy only in kJ: turned into kcal.
    final kj = parseProduct({
      'product_name': 'Crackers',
      'brands': 'Brand A, Brand B',
      'nutriments': {'energy_100g': 1673.6},
    })!;
    expect(kj.kcal.round(), 400);
    expect(kj.brand, 'Brand A');
  });

  group('Log food', () {
    setUp(() async {
      sqfliteFfiInit();
      appDb = await AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    });

    tearDown(() => appDb.raw.close());

    Future<void> openSheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const LifeApp());
      await settle(tester);
      await openTab(tester, 'Body');
      await tapText(tester, 'Nutrition');
      await tester.tap(find.text('Log food').hitTestable().last);
      await settle(tester);
    }

    testWidgets('a search fills in the numbers, and the amount scales them', (tester) async {
      final asked = fakeFoodFacts();
      await openSheet(tester);
      await tester.enterText(field(0), 'yogurt');
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(asked.single.queryParameters['q'], 'yogurt');
      expect(find.text('Greek yogurt, plain'), findsOneWidget, reason: 'the basics come first');
      expect(find.text('Greek Yogurt · Chobani'), findsOneWidget);

      await tapText(tester, 'Greek Yogurt · Chobani');
      expect(find.text('Greek Yogurt · Chobani, 170 g'), findsOneWidget);
      expect(find.text('102'), findsOneWidget); // kcal for 170 g

      await tapText(tester, '100 g');
      expect(find.text('60'), findsOneWidget);
      await tester.tap(find.text('Log food').hitTestable().last);
      await settle(tester);
      final logged = await tester.runAsync(() => appDb.query('SELECT name, kcal, protein FROM food_logs'));
      expect(logged, [
        {'name': 'Greek Yogurt · Chobani, 100 g', 'kcal': 60.0, 'protein': 10.0},
      ]);
    });

    testWidgets('a barcode finds the product, or says it is unknown', (tester) async {
      fakeFoodFacts();
      readBarcode = () async => '5000';
      await openSheet(tester);
      await tapText(tester, 'Scan a barcode');
      expect(find.text('Skyr · Chobani, 170 g'), findsOneWidget);

      readBarcode = () async => '0000';
      await tapText(tester, 'Scan a barcode');
      expect(find.textContaining('not in Open Food Facts yet'), findsOneWidget);
    });
  });
}
