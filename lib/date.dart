/// Dates are stored as local 'YYYY-MM-DD' strings and times as minutes since midnight.
library;

String _pad(int n) => n.toString().padLeft(2, '0');

String toKey(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

DateTime fromKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String todayKey() => toKey(DateTime.now());

String addDays(String key, int n) {
  final d = fromKey(key);
  return toKey(DateTime(d.year, d.month, d.day + n));
}

/// 0 = Monday … 6 = Sunday.
int weekdayOf(String key) => fromKey(key).weekday - 1;

/// Monday of the week containing [key].
String weekStart(String key) => addDays(key, -weekdayOf(key));

const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdaysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// First day of the week containing [key]; [first] is 'mon' or 'sun'.
String startOfWeek(String key, String first) {
  final monday0 = weekdayOf(key);
  return addDays(key, -(first == 'sun' ? (monday0 + 1) % 7 : monday0));
}

String monthStart(String key) => '${key.substring(0, 7)}-01';

String addMonths(String key, int n) {
  final d = fromKey(monthStart(key));
  return toKey(DateTime(d.year, d.month + n, 1));
}

/// e.g. "November 2026"
String formatMonth(String key) {
  final d = fromKey(key);
  return '${_monthsLong[d.month - 1]} ${d.year}';
}

/// Every date from [from] to [to], inclusive.
List<String> dateRange(String from, String to) {
  final out = <String>[];
  for (var k = from; k.compareTo(to) <= 0; k = addDays(k, 1)) {
    out.add(k);
  }
  return out;
}

String formatDay(String key) {
  final d = fromKey(key);
  return '${weekdays[weekdayOf(key)]}, ${d.day} ${_months[d.month - 1]}';
}

int daysBetween(String a, String b) {
  final da = fromKey(a), db = fromKey(b);
  // UTC so a daylight-saving change never makes a day 23 or 25 hours long.
  return DateTime.utc(db.year, db.month, db.day).difference(DateTime.utc(da.year, da.month, da.day)).inDays;
}

String relativeDay(String key) {
  final diff = daysBetween(todayKey(), key);
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return formatDay(key);
}

String formatTime(int min) {
  final m = ((min % 1440) + 1440) % 1440;
  return '${_pad(m ~/ 60)}:${_pad(m % 60)}';
}

bool isDateKey(String text) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return false;
  return toKey(fromKey(text)) == text;
}

int nowMinutes() {
  final d = DateTime.now();
  return d.hour * 60 + d.minute;
}
