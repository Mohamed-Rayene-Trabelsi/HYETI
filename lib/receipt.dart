import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'date.dart';

/// What could be read off a receipt. Anything not found is left empty for the user to fill in.
class Receipt {
  const Receipt({this.amount, this.label = '', this.date});

  final double? amount;
  final String label;

  /// 'YYYY-MM-DD'.
  final String? date;
}

/// Takes a picture (or picks one) and returns the text on it; null when the user backs out.
/// The text is read on the phone, and the picture is not kept. Tests swap this for a fake.
Future<String?> Function({required bool camera}) readReceiptText = _readFromPicture;

Future<String?> _readFromPicture({required bool camera}) async {
  final picture = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 2200,
    imageQuality: 92,
  );
  if (picture == null) return null;
  final reader = TextRecognizer();
  try {
    return (await reader.processImage(InputImage.fromFilePath(picture.path))).text;
  } finally {
    await reader.close();
    // The picker leaves its own copy in the app's cache; a camera shot has no other use.
    if (camera) File(picture.path).delete().ignore();
  }
}

/// Currencies written with three decimals, where "12,500" is twelve and a half rather than twelve thousand.
const _threeDecimals = {'TND', 'KWD', 'BHD', 'JOD', 'OMR', 'LYD', 'IQD'};

/// Lines that name the amount to pay, strongest first.
const _finalTotals = [
  'grand total',
  'total ttc',
  'net a payer',
  'net à payer',
  'total a payer',
  'total à payer',
  'amount due',
  'balance due',
  'total due',
  'montant total',
];
const _totals = ['total', 'montant', 'amount', 'somme'];

/// Lines whose number is not what was paid for the goods.
const _notTheTotal = [
  'subtotal',
  'sub total',
  'sub-total',
  'sous total',
  'sous-total',
  'total ht',
  'tax',
  'tva',
  'vat',
  'change',
  'rendu',
  'cash',
  'espece',
  'espèce',
  'discount',
  'remise',
  'items',
  'articles',
];

final _number = RegExp(r'\d{1,3}(?: \d{3})+(?:[.,]\d{1,3})?|\d+(?:[.,]\d{3})*(?:[.,]\d{1,3})?');
final _isoDate = RegExp(r'\b(20\d{2})[/.\-](\d{1,2})[/.\-](\d{1,2})\b');
final _dayDate = RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})\b');

/// The amounts written on one line, as (value, had a decimal part).
List<(double, bool)> _amounts(String line, bool threeDecimals) {
  final found = <(double, bool)>[];
  for (final m in _number.allMatches(line)) {
    final token = m[0]!.replaceAll(' ', '');
    final cut = token.lastIndexOf(RegExp('[.,]'));
    final after = cut < 0 ? 0 : token.length - cut - 1;
    // Two digits after the last mark are cents; three are thousands, except in three-decimal currencies.
    final decimal = cut >= 0 && (after < 3 || threeDecimals);
    final whole = (decimal ? token.substring(0, cut) : token).replaceAll(RegExp('[.,]'), '');
    if (whole.length > 7) continue; // a phone number, a barcode, a till id
    final value = double.tryParse(decimal ? '$whole.${token.substring(cut + 1)}' : whole);
    if (value != null && value > 0) found.add((value, decimal));
  }
  return found;
}

String? _dateIn(String text) {
  String? check(int y, int m, int d) {
    if (m > 12 && d <= 12) (m, d) = (d, m); // written month first
    final date = DateTime(y, m, d);
    if (date.month != m || date.day != d) return null;
    // A receipt is from the past; anything else is some other number.
    if (y < 2000 || date.isAfter(DateTime.now().add(const Duration(days: 1)))) return null;
    return toKey(date);
  }

  for (final m in _isoDate.allMatches(text)) {
    final date = check(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    if (date != null) return date;
  }
  for (final m in _dayDate.allMatches(text)) {
    final year = int.parse(m[3]!);
    final date = check(year < 100 ? 2000 + year : year, int.parse(m[2]!), int.parse(m[1]!));
    if (date != null) return date;
  }
  return null;
}

String _shopName(List<String> lines) {
  for (final line in lines) {
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(line).length;
    final digits = RegExp(r'\d').allMatches(line).length;
    if (letters < 3 || digits >= letters) continue;
    final lower = line.toLowerCase();
    if (['receipt', 'ticket', 'facture', 'invoice', 'welcome', 'bienvenue'].any(lower.contains)) continue;
    var name = line.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^[^\p{L}\d]+|[^\p{L}\d]+$', unicode: true), '');
    // Shop names are usually shouted in capitals; calm them down.
    if (name == name.toUpperCase()) {
      name = name.toLowerCase().replaceAllMapped(
        RegExp(r'(^|[\s\-])(\p{L})', unicode: true),
        (m) => '${m[1]}${m[2]!.toUpperCase()}',
      );
    }
    return name.length > 40 ? name.substring(0, 40).trim() : name;
  }
  return '';
}

/// Picks the total, the shop and the date out of the text of a receipt.
Receipt parseReceipt(String text, {String currency = r'$'}) {
  final threeDecimals = _threeDecimals.contains(currency.toUpperCase());
  final lines = [
    for (final l in text.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  // Dates and times would otherwise be read as amounts.
  String bare(String line) =>
      line.replaceAll(_isoDate, ' ').replaceAll(_dayDate, ' ').replaceAll(RegExp(r'\b\d{1,2}:\d{2}(:\d{2})?\b'), ' ');

  double? amount;
  var best = 0;
  for (final (i, line) in lines.indexed) {
    final lower = line.toLowerCase();
    final rank = _finalTotals.any(lower.contains)
        ? 2
        : _totals.any(lower.contains) && !_notTheTotal.any(lower.contains)
        ? 1
        : 0;
    if (rank == 0 || rank < best) continue;
    // The figure is at the end of the line, or alone on the next one.
    var onLine = _amounts(bare(line), threeDecimals);
    if (onLine.isEmpty && i + 1 < lines.length) onLine = _amounts(bare(lines[i + 1]), threeDecimals);
    if (onLine.isEmpty) continue;
    amount = onLine.last.$1;
    best = rank;
  }
  if (amount == null) {
    // No line says "total": the largest price on the receipt is the best guess.
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (['cash', 'change', 'rendu', 'espece', 'espèce'].any(lower.contains)) continue;
      for (final (value, decimal) in _amounts(bare(line), threeDecimals)) {
        if (decimal && (amount == null || value > amount)) amount = value;
      }
    }
  }
  return Receipt(amount: amount, label: _shopName(lines), date: _dateIn(text));
}
