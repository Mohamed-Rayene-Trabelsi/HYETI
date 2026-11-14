import 'package:flutter_test/flutter_test.dart';
import 'package:personal_mobile_app/date.dart';
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
}
