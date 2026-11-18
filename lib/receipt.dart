import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'date.dart';

/// What could be read off a receipt. Anything not found is left empty for the user to fill in.
class Receipt {
  const Receipt({this.amount, this.label = '', this.date, this.amounts = const []});

  final double? amount;
  final String label;

  /// 'YYYY-MM-DD'.
  final String? date;

  /// Other prices on the receipt, largest first, so a wrong total can be swapped for the right one with a tap.
  /// Never contains [amount].
  final List<double> amounts;
}

/// Takes a picture (or picks one) and returns the text on it, one printed row per line; null when the user backs out.
/// The text is read on the phone, and the picture is not kept. Tests swap this for a fake.
Future<String?> Function({required bool camera}) readReceiptText = _readFromPicture;

Future<String?> _readFromPicture({required bool camera}) async {
  final picture = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 2400,
    imageQuality: 95,
  );
  if (picture == null) return null;
  final reader = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final read = await reader.processImage(InputImage.fromFilePath(picture.path));
    return receiptRows([
      for (final block in read.blocks)
        for (final line in block.lines) (line.text, line.boundingBox, _slope(line.cornerPoints)),
    ]);
  } catch (e, stack) {
    debugPrint('Receipt scan failed: $e\n$stack');
    rethrow;
  } finally {
    await reader.close();
    // The picker leaves its own copy in the app's cache; a camera shot has no other use.
    if (camera) File(picture.path).delete().ignore();
  }
}

/// How far a line of text leans, as rise over run along its top edge; 0 when the corners are missing.
double _slope(List<math.Point<int>> corners) {
  if (corners.length < 2) return 0;
  final dx = (corners[1].x - corners[0].x).toDouble();
  return dx.abs() < 1 ? 0 : (corners[1].y - corners[0].y) / dx;
}

/// Puts lines of text read from a picture back into the rows they were printed in.
///
/// The text reader groups words by column, so a receipt's "TOTAL" on the left and its amount on the right come back
/// far apart. Lines whose middles sit at the same height (after undoing any tilt of the photo) are one row, read left
/// to right. Pieces of a row are joined with two spaces so separate prices never merge into one number.
String receiptRows(List<(String, Rect, double)> lines) {
  if (lines.isEmpty) return '';
  final slopes = [for (final l in lines) l.$3]..sort();
  final slope = slopes[slopes.length ~/ 2];
  final heights = [for (final l in lines) l.$2.height]..sort();
  final lineHeight = math.max(heights[heights.length ~/ 2], 1.0);

  // The height of a line's middle once the picture is turned level.
  double level((String, Rect, double) l) => l.$2.center.dy - slope * l.$2.center.dx;

  final sorted = [...lines]..sort((a, b) => level(a).compareTo(level(b)));
  final rows = <(double, List<(String, Rect, double)>)>[];
  for (final line in sorted) {
    final y = level(line);
    if (rows.isNotEmpty && (y - rows.last.$1).abs() < lineHeight * 0.55) {
      final (rowY, pieces) = rows.removeLast();
      pieces.add(line);
      rows.add(((rowY * (pieces.length - 1) + y) / pieces.length, pieces));
    } else {
      rows.add((y, [line]));
    }
  }
  return [
    for (final (_, pieces) in rows)
      ([...pieces]..sort((a, b) => a.$2.left.compareTo(b.$2.left))).map((p) => p.$1.trim()).join('  '),
  ].join('\n');
}

/// Currencies written with three decimals, where "12,500" is twelve and a half rather than twelve thousand.
const _threeDecimals = {'TND', 'DT', 'د.ت', 'KWD', 'BHD', 'JOD', 'OMR', 'LYD', 'IQD', 'KD', 'BD', 'OR', 'JD', 'LD'};

/// Words on a receipt that give away a three-decimal currency.
/// Not `\b`: the code is often stuck to the number ("14,500DT").
final _threeDecimalWords = RegExp(
  r'(?<![a-z])(TND|DT|KWD|BHD|JOD|OMR|LYD|dinars?|millimes?)(?![a-z])|د\.ت',
  caseSensitive: false,
);

/// Lines that name the amount to pay, strongest first. Written without spaces or accents, as [_squash] leaves a line.
const _finalTotals = [
  'grandtotal',
  'totalttc',
  'netapayer',
  'netpayer',
  'totalapayer',
  'montantapayer',
  'amountdue',
  'balancedue',
  'totaldue',
  'totaltopay',
  'montanttotal',
  'totalgeneral',
];
const _totals = ['total', 'montant', 'amount', 'somme', 'apayer'];

/// Lines whose number is not what was paid for the goods.
const _notTheTotal = [
  'subtotal',
  'soustotal',
  'totalht',
  'montantht',
  'tax',
  'tva',
  'vat',
  'timbre',
  'change',
  'rendu',
  'monnaie',
  'cash',
  'espece',
  'recu',
  'discount',
  'remise',
  'items',
  'articles',
  'qty',
  'quantite',
];

/// Lines that only say how the bill was paid or what came back.
const _payment = ['cash', 'change', 'rendu', 'monnaie', 'espece', 'recu', 'carte', 'card', 'visa'];

/// A line lowercased, without accents or anything but letters, so "NET À PAYER" and "Net a payer:" read the same.
/// Digits the text reader takes for letters inside a word ("T0TAL", "TOTA1") are read as those letters.
String _squash(String line) {
  const plain = {'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'ô': 'o'};
  var s = line.toLowerCase();
  plain.forEach((from, to) => s = s.replaceAll(from, to));
  s = s
      .replaceAll(RegExp(r'ù|û|ü'), 'u')
      .replaceAll('ç', 'c')
      .replaceAllMapped(
        RegExp(r'(?<=[a-z])[015](?=[a-z])|(?<=[a-z]{2})[015]\b|\b[015](?=[a-z]{2})'),
        (m) => const {'0': 'o', '1': 'l', '5': 's'}[m[0]]!,
      );
  return s.replaceAll(RegExp('[^a-z]'), '');
}

/// Whether [word] is in [squashed], allowing one wrong letter in words of five letters or more (the text reader's
/// usual slip: "TOTAI", "T0TAL", "NET A PAVER").
bool _has(String squashed, String word) {
  if (squashed.contains(word)) return true;
  if (word.length < 5) return false;
  for (var i = 0; i + word.length <= squashed.length; i++) {
    var wrong = 0;
    for (var j = 0; j < word.length && wrong < 2; j++) {
      if (squashed.codeUnitAt(i + j) != word.codeUnitAt(j)) wrong++;
    }
    if (wrong < 2) return true;
  }
  return false;
}

/// Undoes the text reader's slips inside numbers: letters taken for digits ("12.5O0", "l6.21") and a decimal mark
/// read with spaces around it ("12 . 500").
String _cleanNumbers(String line) {
  var s = line;
  for (var i = 0; i < 2; i++) {
    // Twice, so runs like "1OO" are fixed in full.
    s = s.replaceAllMapped(
      RegExp(r'(?<=\d|\d[.,])[OoQDlI|SB](?=[.,]?\d)|(?<=\d[.,]\d*)[Oo]\b|(?<![\p{L}\d])[lI|](?=\d)', unicode: true),
      (m) => const {'O': '0', 'o': '0', 'Q': '0', 'D': '0', 'l': '1', 'I': '1', '|': '1', 'S': '5', 'B': '8'}[m[0]]!,
    );
  }
  return s.replaceAllMapped(RegExp(r'(\d)(?: +([.,]) *| *([.,]) +)(\d)'), (m) => '${m[1]}${m[2] ?? m[3]}${m[4]}');
}

final _number = RegExp(r'\d{1,3}(?: \d{3})+(?:[.,]\d{1,3})?|\d+(?:[.,]\d{3})*(?:[.,]\d{1,3})?');
final _isoDate = RegExp(r'\b(20\d{2})[/.\-](\d{1,2})[/.\-](\d{1,2})\b');
final _dayDate = RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})\b');
final _time = RegExp(r'\b\d{1,2}[:h]\d{2}(:\d{2})?\b');

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
    final squashed = _squash(line);
    if (['receipt', 'ticket', 'facture', 'invoice', 'welcome', 'bienvenue', 'merci'].any(squashed.contains)) continue;
    // The shop's name is on a row of its own; keep the first piece if the row was joined from several.
    var name = line.split('  ').first;
    name = name.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^[^\p{L}\d]+|[^\p{L}\d]+$', unicode: true), '');
    if (RegExp(r'\p{L}', unicode: true).allMatches(name).length < 3) continue;
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

/// Whether the prices on a receipt look three-decimal ("1,200", "0,450") with none written with cents.
bool _looksThreeDecimal(List<String> lines) {
  var three = 0, two = 0;
  for (final line in lines) {
    for (final m in RegExp(r'\d[.,](\d{2,3})\b').allMatches(line)) {
      m[1]!.length == 3 ? three++ : two++;
    }
  }
  return three >= 3 && two == 0;
}

/// Picks the total, the shop and the date out of the text of a receipt.
Receipt parseReceipt(String text, {String currency = r'$'}) {
  final lines = [
    for (final l in text.split('\n'))
      if (l.trim().isNotEmpty) _cleanNumbers(l.trim()),
  ];
  final threeDecimals =
      _threeDecimals.contains(currency.trim().toUpperCase()) ||
      _threeDecimalWords.hasMatch(text) ||
      _looksThreeDecimal(lines);
  // Dates and times would otherwise be read as amounts.
  String bare(String line) => line.replaceAll(_isoDate, ' ').replaceAll(_dayDate, ' ').replaceAll(_time, ' ');

  double? amount;
  var best = 0;
  for (final (i, line) in lines.indexed) {
    final squashed = _squash(line);
    final excluded = _notTheTotal.any(squashed.contains);
    final rank = _finalTotals.any((w) => _has(squashed, w))
        ? 2
        : !excluded && _totals.any((w) => _has(squashed, w))
        ? 1
        : 0;
    if (rank == 0 || rank < best) continue;
    // The figure is at the end of the line, or alone on the next one.
    var onLine = _amounts(bare(line), threeDecimals);
    if (onLine.isEmpty && i + 1 < lines.length && _squash(lines[i + 1]).length < 4) {
      onLine = _amounts(bare(lines[i + 1]), threeDecimals);
    }
    if (onLine.isEmpty) continue;
    amount = onLine.last.$1;
    best = rank;
  }

  // Every price on the receipt, for the user to pick from when the total was misread.
  final prices = <double>{};
  for (final line in lines) {
    if (_payment.any(_squash(line).contains)) continue;
    for (final (value, decimal) in _amounts(bare(line), threeDecimals)) {
      if (decimal) prices.add(value);
    }
  }
  final byValue = prices.toList()..sort((a, b) => b.compareTo(a));
  // No line says "total": the largest price on the receipt is the best guess.
  amount ??= byValue.firstOrNull;
  return Receipt(
    amount: amount,
    label: _shopName(lines),
    date: _dateIn(text),
    amounts: [
      for (final p in byValue)
        if (p != amount) p,
    ].take(6).toList(),
  );
}
