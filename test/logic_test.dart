import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_mobile_app/body_map.dart';
import 'package:personal_mobile_app/date.dart';
import 'package:personal_mobile_app/muscles.dart';
import 'package:personal_mobile_app/jar.dart';
import 'package:personal_mobile_app/screens/calendar.dart';
import 'package:personal_mobile_app/receipt.dart';
import 'package:personal_mobile_app/screens/nutrition.dart';
import 'package:personal_mobile_app/screens/wallet.dart';
import 'package:personal_mobile_app/ui.dart';

void main() {
  group('dates', () {
    test('adds days across month and year ends', () {
      expect(addDays('2026-12-31', 1), '2027-01-01');
      expect(addDays('2026-03-01', -1), '2026-02-28');
      expect(addMonths('2026-11-13', 2), '2027-01-01');
    });

    test('finds the start of the week', () {
      // 13 November 2026 is a Friday.
      expect(weekdayOf('2026-11-13'), 4);
      expect(weekStart('2026-11-13'), '2026-11-09');
      expect(startOfWeek('2026-11-13', 'sun'), '2026-11-08');
      expect(startOfWeek('2026-11-08', 'sun'), '2026-11-08');
      expect(startOfWeek('2026-11-08', 'mon'), '2026-11-02');
    });

    test('counts days and lists ranges', () {
      expect(daysBetween('2026-03-01', '2026-04-01'), 31);
      expect(daysBetween('2026-11-13', '2026-11-10'), -3);
      expect(dateRange('2026-02-27', '2026-03-01'), ['2026-02-27', '2026-02-28', '2026-03-01']);
    });

    test('formats', () {
      expect(formatDay('2026-11-13'), 'Fri, 13 Nov');
      expect(formatMonth('2026-11-13'), 'November 2026');
      expect(formatTime(545), '09:05');
      expect(formatTime(1440), '00:00');
      expect(isDateKey('2026-02-30'), isFalse);
      expect(isDateKey('2026-02-28'), isTrue);
    });
  });

  group('numbers', () {
    test('plain numbers drop needless decimals', () {
      expect(plainNumber(60), '60');
      expect(plainNumber(100.0), '100');
      expect(plainNumber(62.5), '62.5');
      expect(plainNumber(0), '0');
    });

    test('money groups thousands and places the currency', () {
      expect(formatMoney(1234.5, r'$'), r'$1,234.5');
      expect(formatMoney(1000000, 'TND'), '1,000,000 TND');
      expect(formatMoney(-20, '€'), '€-20');
      expect(formatMoney(100, r'$'), r'$100');
    });

    test('amounts must be above zero', () {
      expect(parseAmount('12,50'), 12.5);
      expect(parseAmount(r'$ 40'), 40);
      expect(parseAmount('0'), isNull);
      expect(parseAmount('abc'), isNull);
    });
  });

  group('nutrition plan', () {
    test('suggests targets from body stats', () {
      final plan = suggestPlan(sex: 'male', age: '25', height: '178', weight: '75', activity: 1.55, goal: 0);
      // Resting 10*75 + 6.25*178 - 5*25 + 5 = 1742.5; × 1.55 = 2700.875 → 2700.
      // Protein 75 × 1.8 = 135 g; fat 2700 × 0.25 / 9 = 75 g; carbs (2700 − 540 − 675) / 4 = 371 g.
      expect(plan, (kcal: 2700, protein: 135, carbs: 371, fat: 75));
    });

    test('needs plausible stats', () {
      expect(suggestPlan(sex: 'male', age: '', height: '178', weight: '75', activity: 1.2, goal: 0), isNull);
      expect(suggestPlan(sex: 'female', age: '30', height: '300', weight: '60', activity: 1.2, goal: 0), isNull);
    });
  });

  test('a block name suggests its icon, by whole words', () {
    expect(guessCategory('Gym with Sam'), 'gym');
    expect(guessCategory('Reading club'), 'read');
    expect(guessCategory('Sunday brunch'), 'food');
    expect(guessCategory('Physics lecture'), 'study');
    expect(guessCategory('Something else'), isNull);
  });

  test('months are added keeping the day, or the last day of a shorter month', () {
    expect(addMonthsKeepDay('2026-01-15', 1), '2026-02-15');
    expect(addMonthsKeepDay('2026-01-31', 1), '2026-02-28');
    expect(addMonthsKeepDay('2028-01-31', 1), '2028-02-29');
    expect(addMonthsKeepDay('2026-11-30', 3), '2027-02-28');
    expect(addMonthsKeepDay('2026-03-10', 12), '2027-03-10');
  });

  group('savings jar', () {
    test('fills towards the goal and stops at full', () {
      expect(jarFill(50, 200), 0.25);
      expect(jarFill(500, 200), 1);
      expect(jarFill(50, null), 0);
      expect(jarFill(50, 0), 0);
    });

    test('cheers once for each quarter passed, the biggest first', () {
      expect(jarMilestone(0.2, 0.3), 25);
      expect(jarMilestone(0.3, 0.4), isNull);
      expect(jarMilestone(0.1, 0.8), 75);
      expect(jarMilestone(0.9, 1), 100);
      expect(jarMilestone(0.6, 0.4), isNull);
    });
  });

  group('receipts', () {
    test('finds the total, the shop and the date', () {
      final r = parseReceipt('''
SUPER MARKET CENTRAL
12 Main Street
Tel 71 234 567
14/11/2026 18:42
Milk 1L        1.85
Bread          0.90
Chicken       12.40
SUBTOTAL      15.15
TAX            1.06
TOTAL         16.21
CASH          20.00
CHANGE         3.79
''');
      expect(r.amount, 16.21);
      expect(r.label, 'Super Market Central');
      expect(r.date, '2026-11-14');
    });

    test('reads three-decimal currencies and totals printed on the next line', () {
      final r = parseReceipt(
        'Monoprix\n2026-03-02\nEau 1,200\nPain 0,450\nNET A PAYER\n12,650\nESPECES 20,000',
        currency: 'TND',
      );
      expect(r.amount, 12.65);
      expect(r.date, '2026-03-02');
      // The same figures in a two-decimal currency are thousands.
      expect(parseReceipt('Total 12,650').amount, 12650);
    });

    test('falls back to the largest price, and leaves blanks when nothing is there', () {
      expect(parseReceipt('Cafe Luna\nEspresso 2.50\nCroissant 3.20\nMerci').amount, 3.2);
      final empty = parseReceipt('hello');
      expect(empty.amount, isNull);
      expect(empty.date, isNull);
    });

    test('puts a total back on the row its label was printed on, even in a tilted photo', () {
      // The reader returns the left column, then the right one; the photo leans down to the right by 5%.
      Rect box(double x, double y, double w) => Rect.fromLTWH(x, y + x * 0.05, w, 30);
      final text = receiptRows([
        ('MAGASIN GENERAL', box(100, 20, 400), 0.05),
        ('Eau', box(40, 100, 80), 0.05),
        ('Pain', box(40, 150, 80), 0.05),
        ('TOTAL TTC', box(40, 200, 200), 0.05),
        ('1,200', box(600, 100, 90), 0.05),
        ('0,450', box(600, 150, 90), 0.05),
        ('1,650', box(600, 200, 90), 0.05),
      ]);
      expect(text, 'MAGASIN GENERAL\nEau  1,200\nPain  0,450\nTOTAL TTC  1,650');
      expect(parseReceipt(text, currency: 'TND').amount, 1.65);
      expect(receiptRows([]), '');
    });

    test('copes with the text reader\'s slips', () {
      // Letters for digits, a spaced-out decimal mark, a currency stuck to the number, a misread label.
      expect(parseReceipt('Cafe\nT0TAL  12.5O').amount, 12.5);
      expect(parseReceipt('Cafe\nTOTAI 8 . 75 EUR').amount, 8.75);
      expect(parseReceipt('Cafe\nNET A PAVER  14,500DT').amount, 14.5);
      expect(parseReceipt('Cafe\nTotal  l6.21 \$').amount, 16.21);
      // A custom three-decimal symbol, and a receipt that names its dinars when the setting is something else.
      expect(parseReceipt('Cafe\nTotal 3,500', currency: 'DT').amount, 3.5);
      expect(parseReceipt('Cafe\nTotal 3,500 TND').amount, 3.5);
      // Tax and subtotal lines are still not the total, however they are spelled.
      expect(parseReceipt('Sous-total 10,000\nTVA 1,900\nNet à payer 11,900', currency: 'TND').amount, 11.9);
    });

    test('offers the other prices on the receipt to pick from', () {
      final r = parseReceipt('Shop\nTea 4.50\nCake 6.25\nTOTAL 10.75\nCASH 20.00\nCHANGE 9.25');
      expect(r.amount, 10.75);
      expect(r.amounts, [6.25, 4.5]);
    });
  });

  group('body figure', () {
    test('every muscle can be picked on one side or the other, and the back only on the back', () {
      for (final m in muscles) {
        expect(muscleOnSide(m, 'front') || muscleOnSide(m, 'back'), isTrue, reason: m);
      }
      expect(muscleOnSide('Chest', 'front'), isTrue);
      expect(muscleOnSide('Chest', 'back'), isFalse);
      expect(muscleOnSide('Shoulders', 'front') && muscleOnSide('Shoulders', 'back'), isTrue);
      // The trapezius drawn beside the neck on the front does not make the back pickable there.
      expect(muscleOnSide('Back', 'front'), isFalse);
      expect(muscleOnSide('Back', 'back'), isTrue);
    });
  });
}
