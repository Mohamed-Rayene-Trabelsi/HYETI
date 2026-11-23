import 'dart:convert';

import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';

import 'update.dart' show appVersion;
import 'watch_api.dart' show httpClient;

/// A food with what 100 g of it holds, from the built-in basics or from Open Food Facts.
class FoodFacts {
  const FoodFacts({
    required this.name,
    this.brand = '',
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.portion,
    this.portionName = '',
    this.code = '',
  });

  final String name;
  final String brand;

  /// Per 100 g.
  final double kcal, protein, carbs, fat;

  /// A usual amount in grams (one egg, a serving on the pack); null when unknown.
  final double? portion;

  /// What [portion] is, e.g. "1 egg"; empty for a plain serving.
  final String portionName;

  /// The barcode, for Open Food Facts products.
  final String code;

  String get label => brand.isEmpty ? name : '$name · $brand';

  /// What [grams] of it holds: (kcal, protein, carbs, fat).
  ({double kcal, double protein, double carbs, double fat}) of(double grams) {
    double scale(double per100) => (per100 * grams / 100 * 10).round() / 10;
    return (kcal: scale(kcal).roundToDouble(), protein: scale(protein), carbs: scale(carbs), fat: scale(fat));
  }
}

/// Everyday foods that packs and barcodes do not cover well, per 100 g (cooked where it says so). Rounded,
/// typical values; good enough for a daily total.
const basicFoods = [
  FoodFacts(name: 'Chicken breast, cooked', kcal: 165, protein: 31, carbs: 0, fat: 3.6, portion: 150),
  FoodFacts(name: 'Rice, white, cooked', kcal: 130, protein: 2.7, carbs: 28, fat: 0.3, portion: 180),
  FoodFacts(name: 'Pasta, cooked', kcal: 158, protein: 5.8, carbs: 31, fat: 0.9, portion: 200),
  FoodFacts(name: 'Couscous, cooked', kcal: 112, protein: 3.8, carbs: 23, fat: 0.2, portion: 180),
  FoodFacts(name: 'Egg', kcal: 143, protein: 12.6, carbs: 0.7, fat: 9.5, portion: 50, portionName: '1 egg'),
  FoodFacts(name: 'Oats', kcal: 389, protein: 16.9, carbs: 66, fat: 6.9, portion: 50),
  FoodFacts(name: 'Bread, white', kcal: 265, protein: 9, carbs: 49, fat: 3.2, portion: 30, portionName: '1 slice'),
  FoodFacts(name: 'Potato, boiled', kcal: 87, protein: 1.9, carbs: 20, fat: 0.1, portion: 200),
  FoodFacts(name: 'Sweet potato, baked', kcal: 90, protein: 2, carbs: 21, fat: 0.2, portion: 200),
  FoodFacts(name: 'Lentils, cooked', kcal: 116, protein: 9, carbs: 20, fat: 0.4, portion: 200),
  FoodFacts(name: 'Beef mince, cooked', kcal: 250, protein: 26, carbs: 0, fat: 15, portion: 150),
  FoodFacts(name: 'Salmon, cooked', kcal: 206, protein: 22, carbs: 0, fat: 12, portion: 150),
  FoodFacts(name: 'Tuna, canned in water', kcal: 116, protein: 26, carbs: 0, fat: 1, portion: 100),
  FoodFacts(name: 'Greek yogurt, plain', kcal: 73, protein: 10, carbs: 3.9, fat: 2, portion: 170),
  FoodFacts(name: 'Milk, whole', kcal: 61, protein: 3.2, carbs: 4.8, fat: 3.3, portion: 250, portionName: '1 glass'),
  FoodFacts(name: 'Cheese, cheddar', kcal: 403, protein: 25, carbs: 1.3, fat: 33, portion: 30),
  FoodFacts(name: 'Whey protein', kcal: 400, protein: 80, carbs: 8, fat: 6, portion: 30, portionName: '1 scoop'),
  FoodFacts(name: 'Banana', kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, portion: 120, portionName: '1 banana'),
  FoodFacts(name: 'Apple', kcal: 52, protein: 0.3, carbs: 14, fat: 0.2, portion: 180, portionName: '1 apple'),
  FoodFacts(name: 'Orange', kcal: 47, protein: 0.9, carbs: 12, fat: 0.1, portion: 130, portionName: '1 orange'),
  FoodFacts(name: 'Avocado', kcal: 160, protein: 2, carbs: 8.5, fat: 14.7, portion: 100, portionName: '½ avocado'),
  FoodFacts(name: 'Broccoli', kcal: 34, protein: 2.8, carbs: 7, fat: 0.4, portion: 100),
  FoodFacts(name: 'Almonds', kcal: 579, protein: 21, carbs: 22, fat: 50, portion: 30),
  FoodFacts(name: 'Peanut butter', kcal: 588, protein: 25, carbs: 20, fat: 50, portion: 32, portionName: '2 tbsp'),
  FoodFacts(name: 'Olive oil', kcal: 884, protein: 0, carbs: 0, fat: 100, portion: 10, portionName: '1 tbsp'),
];

/// The basics whose name holds every word of [query].
List<FoodFacts> matchBasics(String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  return [
    for (final f in basicFoods)
      if (words.every(f.name.toLowerCase().contains)) f,
  ];
}

const _timeout = Duration(seconds: 15);
final _headers = {'User-Agent': 'HYETI/$appVersion (personal planner app)'};

double? _num(Object? v) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s.replaceFirst(',', '.')),
  _ => null,
};

/// An Open Food Facts product, or null when it has no calories to go on.
FoodFacts? parseProduct(Map<String, dynamic> p) {
  final n = (p['nutriments'] as Map?) ?? const {};
  final kcal = _num(n['energy-kcal_100g']) ?? (_num(n['energy_100g']) == null ? null : _num(n['energy_100g'])! / 4.184);
  final name = (p['product_name'] as String? ?? '').trim();
  if (kcal == null || name.isEmpty) return null;
  final brands = p['brands'];
  final brand = switch (brands) {
    List l when l.isNotEmpty => '${l.first}',
    String s => s.split(',').first.trim(),
    _ => '',
  };
  final serving = _num(p['serving_quantity']);
  return FoodFacts(
    name: name,
    brand: brand,
    kcal: kcal,
    protein: _num(n['proteins_100g']) ?? 0,
    carbs: _num(n['carbohydrates_100g']) ?? 0,
    fat: _num(n['fat_100g']) ?? 0,
    portion: serving != null && serving > 0 ? serving : null,
    code: '${p['code'] ?? ''}',
  );
}

const _fields = 'code,product_name,brands,nutriments,serving_quantity';

/// Packed foods matching [query] from Open Food Facts (free, no key). Throws when offline.
Future<List<FoodFacts>> searchProducts(String query) async {
  final res = await httpClient
      .get(
        Uri.https('search.openfoodfacts.org', '/search', {'q': query, 'page_size': '20', 'fields': _fields}),
        headers: _headers,
      )
      .timeout(_timeout);
  if (res.statusCode != 200) throw Exception('Open Food Facts answered ${res.statusCode}');
  final hits = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['hits'] as List? ?? const [];
  return [
    for (final h in hits.cast<Map<String, dynamic>>())
      if (parseProduct(h) case final FoodFacts f) f,
  ];
}

/// The product with barcode [code], or null when Open Food Facts does not know it. Throws when offline.
Future<FoodFacts?> productByBarcode(String code) async {
  final res = await httpClient
      .get(Uri.https('world.openfoodfacts.org', '/api/v2/product/$code.json', {'fields': _fields}), headers: _headers)
      .timeout(_timeout);
  if (res.statusCode == 404) return null;
  if (res.statusCode != 200) throw Exception('Open Food Facts answered ${res.statusCode}');
  final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  if (body['status'] != 1 || body['product'] is! Map) return null;
  return parseProduct({...(body['product'] as Map<String, dynamic>), 'code': code});
}

/// Takes a picture of a barcode and returns its number; null when the person backs out, '' when no barcode could
/// be read. Read on the phone; the picture is not kept. Tests swap this for a fake.
Future<String?> Function() readBarcode = () async {
  final picture = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 90);
  if (picture == null) return null;
  final scanner = BarcodeScanner(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upca, BarcodeFormat.upce],
  );
  try {
    final found = await scanner.processImage(InputImage.fromFilePath(picture.path));
    return found.map((b) => b.rawValue).whereType<String>().firstOrNull ?? '';
  } finally {
    await scanner.close();
  }
};
