import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../calendar_views.dart';
import '../date.dart';
import '../db.dart';
import '../pickers.dart';
import '../theme.dart';
import '../ui.dart';

/// What the block form hands back.
class BlockValues {
  const BlockValues({
    required this.title,
    required this.category,
    required this.start,
    required this.end,
    required this.flex,
    this.days,
    this.date,
  });

  final String title;
  final String category;
  final int start;
  final int end;
  final int flex;

  /// Weekdays (0 = Monday) when the block repeats, null for a single day.
  final List<int>? days;

  /// The day of a single block.
  final String? date;
}

Future<void> _insertRoutine(DatabaseExecutor db, BlockValues v) {
  return db.execute(
    'INSERT INTO routines (title, category, days, start_min, end_min, flex_min, created_date) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [v.title, v.category, (v.days ?? []).join(','), v.start, v.end, v.flex, todayKey()],
  );
}

/// Routine changes rebuild upcoming days from the new times; days already ticked off keep their history.
Future<void> _saveRoutine(BlockValues v, Rec? existing) {
  return appDb.transaction((txn) async {
    if (existing == null) return _insertRoutine(txn, v);
    await txn.execute(
      'UPDATE routines SET title = ?, category = ?, days = ?, start_min = ?, end_min = ?, flex_min = ? WHERE id = ?',
      [v.title, v.category, v.days!.join(','), v.start, v.end, v.flex, existing['id']],
    );
    await txn.execute('DELETE FROM events WHERE routine_id = ? AND date >= ? AND done = 0', [
      existing['id'],
      todayKey(),
    ]);
  });
}

Future<void> _deleteRoutine(Rec routine) {
  return appDb.transaction((txn) async {
    await txn.execute('DELETE FROM events WHERE routine_id = ? AND date >= ? AND done = 0', [
      routine['id'],
      todayKey(),
    ]);
    await txn.execute('DELETE FROM routines WHERE id = ?', [routine['id']]);
  });
}

int _startOf(Rec e) => (e['start_min'] as int) + (e['shift_min'] as int);
int _endOf(Rec e) => (e['end_min'] as int) + (e['shift_min'] as int);

/// e.g. 45 → "45 min", 80 → "1 h 20 min".
String _span(int minutes) {
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return '${minutes ~/ 60} h${m > 0 ? ' $m min' : ''}';
}

/// The weekdays (0 = Monday) that are always days off, as chosen in Settings. Work blocks are left out on them.
List<int> offWeekdays() => [for (final d in appDb.setting<List<dynamic>>('off_weekdays', const [])) d as int];

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with Live {
  String _view = 'day';
  String _date = todayKey();

  /// What "today" was when the screen last looked, to notice midnight passing.
  String _lastToday = todayKey();
  Timer? _clock;

  List<Rec> _events = [];
  List<String> _offDates = [];
  List<Rec> _routines = [];

  // Weeks run Monday to Sunday.
  String get _firstDay => 'mon';
  String get _weekFrom => startOfWeek(_date, _firstDay);
  String get _gridFrom => startOfWeek(monthStart(_date), _firstDay);

  // The dates loaded: the week around the day (for the week strip), or the whole weeks that cover the month.
  String get _from => _view == 'month' ? _gridFrom : _weekFrom;
  String get _to => _view == 'month' ? addDays(_gridFrom, 41) : addDays(_weekFrom, 6);

  @override
  void initState() {
    super.initState();
    // Keeps the "now" line, the now/next card and the day itself current while the app stays open.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (todayKey() != _lastToday) {
        reload();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Future<void> load() async {
    // A new day started: if the screen was on "today", follow it.
    final today = todayKey();
    if (today != _lastToday) {
      if (_date == _lastToday) _date = today;
      _lastToday = today;
    }

    final from = _from, to = _to;
    // Copy the routine blocks that apply to each date in the range into that day, once.
    await appDb.raw.transaction((txn) async {
      for (final date in dateRange(from, to)) {
        await txn.execute(
          'INSERT OR IGNORE INTO events (routine_id, date, title, category, start_min, end_min, flex_min) '
          'SELECT id, ?, title, category, start_min, end_min, flex_min FROM routines '
          'WHERE created_date <= ? AND instr(days, ?) > 0',
          [date, date, '${weekdayOf(date)}'],
        );
      }
    });
    final events = await appDb.query(
      'SELECT * FROM events WHERE date BETWEEN ? AND ? AND hidden = 0 ORDER BY date, start_min + shift_min, id',
      [from, to],
    );
    final off = await appDb.query('SELECT date FROM day_offs WHERE date BETWEEN ? AND ?', [from, to]);
    // Days off are the weekdays chosen in Settings, plus single dates (holidays) added there.
    final weekly = offWeekdays();
    final routines = await appDb.query('SELECT * FROM routines ORDER BY start_min, id');
    // The user moved on while this was loading; a newer load is on its way.
    if (from != _from || to != _to) return;
    _events = events;
    _offDates = [
      for (final r in off) r['date'] as String,
      for (final d in dateRange(from, to))
        if (weekly.contains(weekdayOf(d))) d,
    ];
    _routines = routines;
  }

  void _go({String? date, String? view}) {
    setState(() {
      _date = date ?? _date;
      _view = view ?? _view;
    });
    reload();
  }

  void _step(int dir) {
    tick();
    _go(date: _view == 'month' ? addMonths(_date, dir) : addDays(_date, dir * 7));
  }

  /* ---------- Sheets ---------- */

  /// Puts a new block on the calendar: every week from now on, or once on its day.
  Future<void> _addBlock(BlockValues v) async {
    if (v.days != null) {
      await _saveRoutine(v, null);
    } else {
      await appDb.run(
        'INSERT INTO events (date, title, category, start_min, end_min, flex_min) VALUES (?, ?, ?, ?, ?, ?)',
        [v.date, v.title, v.category, v.start, v.end, v.flex],
      );
    }
  }

  void _openNew({int? start}) {
    showSheet(
      context,
      title: 'New block',
      builder: (sheet) => BlockForm(
        repeat: 'choose',
        start: start,
        date: _date,
        onSave: (v) async {
          await _addBlock(v);
          if (sheet.mounted) Navigator.pop(sheet);
          // A single block on another day: go and show it there.
          if (v.days == null && v.date != _date) _go(date: v.date);
        },
      ),
    );
  }

  /// The same sheet as "Add", set to repeat every week, and kept open to add one thing after another.
  void _openQuickSetup() {
    showSheet(
      context,
      title: 'Quick setup',
      builder: (sheet) =>
          BlockForm(repeat: 'choose', repeatByDefault: true, again: true, date: _date, onSave: _addBlock),
    );
  }

  void _openEdit(Rec e) {
    final routineId = e['routine_id'] as int?;
    showSheet(
      context,
      title: 'Edit block',
      builder: (sheet) {
        void close() {
          if (sheet.mounted) Navigator.pop(sheet);
        }

        return BlockForm(
          repeat: 'never',
          initial: e,
          onSave: (v) async {
            await appDb.run(
              'UPDATE events SET date = ?, title = ?, category = ?, start_min = ?, end_min = ?, flex_min = ?, '
              'shift_min = 0 WHERE id = ?',
              [v.date, v.title, v.category, v.start, v.end, v.flex, e['id']],
            );
            close();
          },
          actions: [
            if (routineId != null) ...[
              AppButton(
                'Skip this day',
                kind: ButtonKind.soft,
                icon: Icons.event_busy_outlined,
                onPressed: () async {
                  // Routine blocks are hidden rather than deleted so they are not copied back in.
                  await appDb.run('UPDATE events SET hidden = 1 WHERE id = ?', [e['id']]);
                  showUndo(
                    'Skipped ${e['title']} on this day',
                    () => appDb.run('UPDATE events SET hidden = 0 WHERE id = ?', [e['id']]),
                  );
                  close();
                },
              ),
              AppButton(
                'Remove from every week',
                kind: ButtonKind.danger,
                icon: Icons.delete_outline,
                onPressed: () async {
                  final routine = (await appDb.query('SELECT * FROM routines WHERE id = ?', [routineId])).firstOrNull;
                  if (routine != null) await removeRoutineWithUndo(routine);
                  close();
                },
              ),
            ] else
              AppButton(
                'Remove from calendar',
                kind: ButtonKind.danger,
                icon: Icons.delete_outline,
                onPressed: () async {
                  await deleteWithUndo('events', e, 'Removed ${e['title']}');
                  close();
                },
              ),
          ],
        );
      },
    );
  }

  void _openRoutines() => showSheet(context, title: 'Weekly routine', builder: (_) => const _RoutineList());

  Future<void> _toggle(Rec e) {
    HapticFeedback.lightImpact();
    return appDb.run('UPDATE events SET done = ? WHERE id = ?', [e['done'] == 1 ? 0 : 1, e['id']]);
  }

  /* ---------- Build ---------- */

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = todayKey();
    final date = _date;
    final isOff = _offDates.contains(date);
    final dayBlocks = _events.where((e) => e['date'] == date && !(isOff && e['category'] == 'work')).toList();
    final doneCount = dayBlocks.where((e) => e['done'] == 1).length;
    final isToday = date == today;
    final now = nowMinutes();
    // First run: nothing set up yet. Checked only once the data has loaded, so it never flashes.
    final needsSetup = ready && _routines.isEmpty && _events.isEmpty;

    final relative = relativeDay(date);
    final named = relative != formatDay(date);
    final rangeLabel = formatMonth(date);

    return Screen(
      title: relative,
      // Only a named day ("Tomorrow") needs its date spelled out: the top bar shows today's, the title shows any
      // other day's, and the month view has its own month header.
      subtitle: named && !isToday ? '${formatDay(date)} ${date.substring(0, 4)}' : null,
      actions: [
        if (!isToday)
          HeaderIcon(
            Icons.today,
            label: 'Back to today',
            onPressed: () => _go(date: today),
          ),
        HeaderIcon(Icons.repeat, label: 'Weekly routine', onPressed: _openRoutines),
      ],
      fabLabel: 'Add',
      onFab: _openNew,
      children: [
        Segmented<String>(
          value: _view,
          onChanged: (v) => _go(view: v),
          options: const {'day': 'Day', 'month': 'Month'},
        ),
        if (_view == 'day')
          // The week at a glance, with arrows to move a week: tap a day to open it.
          Row(
            spacing: Spacing.sm,
            children: [
              _NavArrow(icon: Icons.chevron_left, hint: 'Previous week', small: true, onTap: () => _step(-1)),
              Expanded(
                child: MonthGrid(
                  firstCell: _weekFrom,
                  month: date.substring(0, 7),
                  selected: date,
                  events: _events,
                  offDates: _offDates,
                  rows: 1,
                  compact: true,
                  onSelect: (d) {
                    tick();
                    _go(date: d);
                  },
                ),
              ),
              _NavArrow(icon: Icons.chevron_right, hint: 'Next week', small: true, onTap: () => _step(1)),
            ],
          )
        else
          Row(
            spacing: Spacing.md,
            children: [
              _NavArrow(icon: Icons.chevron_left, hint: 'Previous month', onTap: () => _step(-1)),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Go to today',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _go(date: today),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          T(rangeLabel, variant: TextVariant.heading),
                          if (!isToday) T('Back to today', variant: TextVariant.small, color: c.accent),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _NavArrow(icon: Icons.chevron_right, hint: 'Next month', onTap: () => _step(1)),
            ],
          ),
        if (needsSetup)
          Empty(
            icon: Icons.event_repeat,
            title: 'Plan your days',
            hint: 'Add what you do, like gym, meals or classes. Make it repeat every week and it fills in by itself.',
            action: AppButton('Quick setup', icon: Icons.bolt, onPressed: _openQuickSetup),
          ),
        if (_view == 'month')
          MonthGrid(
            firstCell: _gridFrom,
            month: date.substring(0, 7),
            selected: date,
            events: _events,
            offDates: _offDates,
            compact: true,
            onSelect: (d) {
              tick();
              _go(date: d);
            },
          ),
        // Day and month views share the same summary and list for the chosen day.
        if (!needsSetup) ...[
          _DayCard(
            blocks: dayBlocks,
            doneCount: doneCount,
            isToday: isToday,
            isOff: isOff,
            now: now,
            onToggle: _toggle,
          ),
          if (ready)
            _Agenda(
              blocks: dayBlocks,
              now: isToday ? now : null,
              emptyText: isOff ? 'Day off — nothing planned.' : 'Nothing planned. Tap “Add” to put something here.',
              onEdit: _openEdit,
              onToggle: _toggle,
              onAddAt: (start) => _openNew(start: start),
            ),
        ],
      ],
    );
  }
}

/// What is happening now or next (today only), how much of the day is ticked off, and the day's quick actions.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.blocks,
    required this.doneCount,
    required this.isToday,
    required this.isOff,
    required this.now,
    required this.onToggle,
  });

  final List<Rec> blocks;
  final int doneCount;
  final bool isToday;
  final bool isOff;
  final int now;
  final ValueChanged<Rec> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = blocks.where((e) => e['done'] != 1).toList();
    final current = open.where((e) => _startOf(e) <= now && now < _endOf(e)).firstOrNull;
    final next = open.where((e) => _startOf(e) > now).firstOrNull;
    final overdue = open.where((e) => _endOf(e) <= now).length;

    Widget? focus;
    if (!isToday || blocks.isEmpty) {
      focus = null;
    } else if (current != null) {
      focus = _focus(
        context,
        tag: 'NOW',
        color: categoryOf(current['category'] as String).color,
        title: current['title'] as String,
        detail: 'Until ${formatTime(_endOf(current))} · ${_span(_endOf(current) - now)} left',
        trailing: AppButton(
          'Done',
          kind: ButtonKind.soft,
          small: true,
          icon: Icons.check,
          onPressed: () => onToggle(current),
        ),
      );
    } else if (next != null) {
      focus = _focus(
        context,
        tag: 'UP NEXT',
        color: categoryOf(next['category'] as String).color,
        title: next['title'] as String,
        detail: 'At ${formatTime(_startOf(next))} · in ${_span(_startOf(next) - now)}',
      );
    } else if (open.isEmpty) {
      focus = _focus(context, tag: 'TODAY', color: c.success, title: 'All done', detail: 'Everything is ticked off.');
    } else {
      focus = _focus(
        context,
        tag: 'TODAY',
        color: c.warn,
        title: 'Nothing else scheduled',
        detail: '$overdue ${overdue == 1 ? 'block is' : 'blocks are'} past their time and not ticked off.',
      );
    }

    // Another day with nothing on it: the list below says so, and an empty card would only add noise.
    if (focus == null && blocks.isEmpty) return const SizedBox.shrink();
    return AppCard(
      padding: const EdgeInsets.all(Spacing.md),
      spacing: Spacing.md,
      children: [
        ?focus,
        if (blocks.isNotEmpty)
          Row(
            spacing: Spacing.md,
            children: [
              Expanded(child: ProgressBar(doneCount / blocks.length, color: c.success)),
              T('$doneCount of ${blocks.length} done', variant: TextVariant.label),
            ],
          ),
      ],
    );
  }

  Widget _focus(
    BuildContext context, {
    required String tag,
    required Color color,
    required String title,
    required String detail,
    Widget? trailing,
  }) {
    return Row(
      spacing: Spacing.md,
      children: [
        Container(
          width: 4,
          height: 52,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              T(tag, variant: TextVariant.small, dim: true, style: const TextStyle(letterSpacing: 0.6, fontSize: 11)),
              T(title, variant: TextVariant.heading, maxLines: 1),
              T(detail, variant: TextVariant.small, dim: true, maxLines: 1),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.icon, required this.hint, required this.onTap, this.small = false});

  final IconData icon;
  final String hint;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = small ? 34.0 : 44.0;
    return Semantics(
      button: true,
      label: hint,
      child: Material(
        color: c.surfaceAlt,
        shape: buttonShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: c.textDim, size: small ? 22 : 26),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.category);

  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: categoryOf(category).color, shape: BoxShape.circle),
    );
  }
}

/// The day as a list: each block in time order, with the free time between them shown as one slim line.
/// Far shorter than an hour-by-hour grid, so a whole day usually fits on screen.
class _Agenda extends StatelessWidget {
  const _Agenda({
    required this.blocks,
    required this.now,
    required this.emptyText,
    required this.onEdit,
    required this.onToggle,
    required this.onAddAt,
  });

  /// In start-time order.
  final List<Rec> blocks;

  /// The current time in minutes when the day on show is today, otherwise null.
  final int? now;
  final String emptyText;
  final ValueChanged<Rec> onEdit;
  final ValueChanged<Rec> onToggle;
  final ValueChanged<int> onAddAt;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) {
      return AppCard(center: true, children: [T(emptyText, dim: true, align: TextAlign.center)]);
    }

    final rows = <Widget>[];
    int? busyUntil;
    for (final e in blocks) {
      final start = _startOf(e), end = _endOf(e);
      if (busyUntil != null && start - busyUntil >= 30) rows.add(_gap(context, busyUntil, start));
      rows.add(_row(context, e));
      busyUntil = busyUntil == null || end > busyUntil ? end : busyUntil;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: rows);
  }

  Widget _row(BuildContext context, Rec e) {
    final c = context.colors;
    final start = _startOf(e), end = _endOf(e);
    final done = e['done'] == 1;
    final current = now != null && !done && start <= now! && now! < end;
    final category = categoryOf(e['category'] as String);
    final color = category.color;
    // One quiet line: when, and how long.
    final detail = '${formatTime(start)} – ${formatTime(end)} · ${_span(end - start)}';

    return Semantics(
      button: true,
      label: 'Edit ${e['title']}, ${formatTime(start)} to ${formatTime(end)}${done ? ', done' : ''}',
      child: Material(
        // A soft wash of the activity's colour; the block happening right now is outlined in it.
        color: Color.alphaBlend(color.withValues(alpha: done ? 0.04 : (current ? 0.18 : 0.09)), c.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: current ? BorderSide(color: color, width: 1.5) : BorderSide(color: c.border, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onEdit(e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.md, 10, Spacing.xs, 10),
            child: Row(
              spacing: Spacing.md,
              children: [
                Opacity(
                  opacity: done ? 0.45 : 1,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(Radii.button),
                    ),
                    child: Icon(category.icon, size: 20, color: color),
                  ),
                ),
                Expanded(
                  child: Opacity(
                    opacity: done ? 0.5 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 1,
                      children: [
                        T(
                          e['title'] as String,
                          variant: TextVariant.label,
                          maxLines: 1,
                          style: TextStyle(fontSize: 15, decoration: done ? TextDecoration.lineThrough : null),
                        ),
                        T(
                          detail,
                          variant: TextVariant.small,
                          maxLines: 1,
                          color: c.textDim,
                          style: const TextStyle(fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  ),
                ),
                Semantics(
                  checked: done,
                  label: 'Mark ${e['title']} done',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onToggle(e),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done ? c.success : null,
                          border: Border.all(color: done ? c.success : c.textDim.withValues(alpha: 0.6), width: 1.5),
                        ),
                        child: done ? Icon(Icons.check, size: 15, color: c.background) : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Free time between two blocks, as a faint divider; tapping it starts a new block there.
  Widget _gap(BuildContext context, int from, int to) {
    final c = context.colors;
    final line = Expanded(child: Container(height: 0.5, color: c.border));
    return Semantics(
      button: true,
      label: 'Free for ${_span(to - from)} from ${formatTime(from)}. Add something here',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onAddAt(from),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 3),
          child: Row(
            spacing: Spacing.sm,
            children: [
              line,
              Icon(Icons.add, size: 13, color: c.textDim),
              T(
                '${_span(to - from)} free',
                variant: TextVariant.small,
                dim: true,
                style: const TextStyle(fontSize: 12),
              ),
              line,
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------- Weekly routine ---------- */

/// Removes a repeating block from every week ahead, with an undo that brings it back.
Future<void> removeRoutineWithUndo(Rec routine) async {
  await _deleteRoutine(routine);
  // Days ahead are copied from the routine again as they are shown, so restoring the row is enough.
  showUndo('Removed ${routine['title']} from every week', () => appDb.restore('routines', routine));
}

void openRoutineForm(BuildContext context, Rec? routine) {
  showSheet(
    context,
    title: routine == null ? 'New repeating block' : 'Edit repeating block',
    builder: (sheet) => BlockForm(
      repeat: 'always',
      initial: routine,
      onSave: (v) async {
        await _saveRoutine(v, routine);
        if (sheet.mounted) Navigator.pop(sheet);
      },
      actions: [
        if (routine != null)
          AppButton(
            'Remove from every week',
            kind: ButtonKind.danger,
            icon: Icons.delete_outline,
            onPressed: () async {
              await removeRoutineWithUndo(routine);
              if (sheet.mounted) Navigator.pop(sheet);
            },
          ),
      ],
    ),
  );
}

class _RoutineList extends StatefulWidget {
  const _RoutineList();

  @override
  State<_RoutineList> createState() => _RoutineListState();
}

class _RoutineListState extends State<_RoutineList> with Live {
  List<Rec> _routines = [];

  @override
  Future<void> load() async {
    _routines = await appDb.query('SELECT * FROM routines ORDER BY start_min, id');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FormColumn(
      children: [
        const T(
          'These repeat every week. Changing one updates the days ahead; days you already ticked off stay as they were.',
          variant: TextVariant.small,
          dim: true,
        ),
        if (ready && _routines.isEmpty) const T('No repeating blocks yet.', dim: true),
        for (final r in _routines)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openRoutineForm(context, r),
            child: Container(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
              ),
              child: Row(
                spacing: Spacing.md,
                children: [
                  _Dot(r['category'] as String),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        T(r['title'] as String, variant: TextVariant.heading),
                        T(
                          '${formatTime(r['start_min'] as int)}–${formatTime(r['end_min'] as int)} · '
                          '${_daysLabel(r['days'] as String)}',
                          variant: TextVariant.small,
                          dim: true,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.textDim),
                ],
              ),
            ),
          ),
        AppButton('Add repeating block', icon: Icons.add, onPressed: () => openRoutineForm(context, null)),
      ],
    );
  }
}

/// "Every day", "Weekdays", "Weekends", or the day names.
String _daysLabel(String days) {
  final list = days.split(',').map(int.parse).toList()..sort();
  final key = list.join();
  if (key == '0123456') return 'Every day';
  if (key == '01234') return 'Weekdays';
  if (key == '56') return 'Weekends';
  return list.map((d) => weekdays[d]).join(' ');
}

/* ---------- Block form ---------- */

/// One-tap lengths: minutes → the short label on the button.
const _lengths = {15: '15m', 30: '30m', 45: '45m', 60: '1h', 90: '1h30', 120: '2h', 180: '3h'};

/// Words that point to an activity, so typing a name picks its icon. A word matches when it starts with one of
/// these, so "reading" finds "read" but "brunch" does not find "run".
const _nameHints = {
  'gym': ['gym', 'workout', 'run', 'training', 'lift', 'football', 'swim', 'yoga', 'sport', 'cardio'],
  'food': ['lunch', 'dinner', 'breakfast', 'brunch', 'meal', 'eat', 'cook', 'snack'],
  'sleep': ['sleep', 'nap', 'bed'],
  'study': ['study', 'class', 'exam', 'homework', 'lecture', 'revis', 'course', 'school', 'uni'],
  'work': ['work', 'meeting', 'office', 'job', 'shift', 'call'],
  'game': ['game', 'gaming', 'play'],
  'watch': ['movie', 'film', 'series', 'tv', 'anime', 'watch', 'netflix'],
  'read': ['read', 'book'],
  'social': ['friend', 'party', 'coffee', 'date', 'hangout'],
  'family': ['family', 'mom', 'mum', 'dad', 'kids', 'parents'],
  'chores': ['clean', 'laundry', 'chore', 'dishes', 'tidy'],
  'errand': ['shop', 'grocer', 'errand', 'market', 'bank', 'post'],
  'travel': ['drive', 'flight', 'travel', 'commute', 'bus', 'train', 'trip'],
  'health': ['doctor', 'dentist', 'health', 'meds', 'therapy', 'pharmacy'],
  'hobby': ['draw', 'music', 'guitar', 'piano', 'hobby', 'paint', 'sketch'],
};

/// The activity a block's name suggests, or null when nothing fits.
String? guessCategory(String name) {
  final words = name.toLowerCase().split(RegExp(r'[^\p{L}]+', unicode: true)).where((w) => w.isNotEmpty);
  for (final MapEntry(key: key, value: hints) in _nameHints.entries) {
    if (words.any((w) => hints.any(w.startsWith))) return key;
  }
  return null;
}

/// The sheet for a calendar block, new or edited: a name with its icon, when (once on a day, or every week on
/// chosen weekdays), and a start time with a one-tap length.
class BlockForm extends StatefulWidget {
  const BlockForm({
    super.key,
    this.initial,
    this.start,
    this.date,
    required this.repeat,
    this.repeatByDefault = false,
    required this.onSave,
    this.actions = const [],
    this.again = false,
  });

  /// An events or routines row to edit.
  final Rec? initial;

  /// A start time for a new block, when it was started by tapping a free gap in the day.
  final int? start;

  /// The day a new one-off block goes on; today when not given.
  final String? date;

  /// 'choose' lets the user pick once or every week; 'always' / 'never' fix it.
  final String repeat;
  final bool repeatByDefault;
  final Future<void> Function(BlockValues) onSave;

  /// More buttons under Save, such as the ways to remove the block.
  final List<Widget> actions;

  /// Stays open after saving, emptied for the next block: the quick setup adds several in a row.
  final bool again;

  @override
  State<BlockForm> createState() => _BlockFormState();
}

class _BlockFormState extends State<BlockForm> {
  late final _title = TextEditingController(text: widget.initial?['title'] as String? ?? '');
  late String _category = widget.initial?['category'] as String? ?? 'other';

  /// Once an icon is picked by hand, typing the name no longer changes it.
  late bool _iconChosen = widget.initial != null;
  bool _iconsOpen = false;

  late String _date = widget.initial?['date'] as String? ?? widget.date ?? todayKey();
  late String _shownMonth = monthStart(_date);
  bool _calendarOpen = false;

  late int _start = widget.initial?['start_min'] as int? ?? widget.start ?? _suggestedStart();
  late int _length = widget.initial == null
      ? 60
      : math.max(5, (widget.initial!['end_min'] as int) - (widget.initial!['start_min'] as int));

  /// Kept for blocks saved before the "running late" buffer was taken out; no longer shown.
  late final int _flex = widget.initial?['flex_min'] as int? ?? 15;
  late bool _repeats = widget.repeat == 'always' || (widget.repeat == 'choose' && widget.repeatByDefault);
  late List<int> _days = switch (widget.initial?['days']) {
    final String days when days.isNotEmpty => days.split(',').map(int.parse).toList(),
    _ => [weekdayOf(_date)],
  };
  String _error = '';

  /// After a quick-setup save: what was just added.
  String _added = '';
  bool _saving = false;

  /// The next full hour today, or nine in the morning on any other day.
  int _suggestedStart() {
    final date = widget.date ?? todayKey();
    if (date != todayKey()) return 9 * 60;
    return math.min((nowMinutes() ~/ 60 + 1) * 60, 22 * 60);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _named(String name) {
    if (_iconChosen) return;
    final guess = guessCategory(name);
    if (guess != null && guess != _category) setState(() => _category = guess);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_repeats && _days.isEmpty) return setState(() => _error = 'Pick at least one day.');
    final title = _title.text.trim().isEmpty ? categoryOf(_category).label : _title.text.trim();
    setState(() {
      _saving = true;
      _error = '';
    });
    await widget.onSave(
      BlockValues(
        title: title,
        category: _category,
        start: _start,
        end: math.min(_start + _length, 1439),
        flex: _flex,
        days: _repeats ? ([..._days]..sort()) : null,
        date: _date,
      ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (widget.again) {
        // Ready for the next one: same day and time, nothing else carried over.
        _title.clear();
        _category = 'other';
        _iconChosen = false;
        _iconsOpen = false;
        _added = 'Added $title. Add another, or close when you are done.';
      }
    });
  }

  Widget _label(String text) => T(text, variant: TextVariant.label, dim: true);

  /// The chosen icon, big and tappable, beside the name.
  Widget _iconTile(BuildContext context) {
    final c = context.colors;
    final cat = categoryOf(_category);
    return Semantics(
      button: true,
      expanded: _iconsOpen,
      label: 'Icon: ${cat.label}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          tick();
          setState(() => _iconsOpen = !_iconsOpen);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: cat.color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(Radii.button),
            border: Border.all(color: _iconsOpen ? cat.color : c.border, width: _iconsOpen ? 1.5 : 0.5),
          ),
          child: Icon(cat.icon, color: cat.color, size: 24),
        ),
      ),
    );
  }

  /// Every icon, without labels, eight to a row.
  Widget _iconGrid(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 6.0, perRow = 8;
        final size = (box.maxWidth - gap * (perRow - 1)) / perRow - 0.01;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final cat in categories)
              Semantics(
                button: true,
                selected: cat.key == _category,
                label: cat.label,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () {
                    tick();
                    setState(() {
                      _category = cat.key;
                      _iconChosen = true;
                      _iconsOpen = false;
                    });
                  },
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: cat.key == _category ? cat.color.withValues(alpha: 0.2) : c.surfaceAlt,
                      borderRadius: BorderRadius.circular(Radii.button - 2),
                      border: cat.key == _category ? Border.all(color: cat.color, width: 1.5) : null,
                    ),
                    child: Icon(cat.icon, size: 20, color: cat.color),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Today, tomorrow, or another day from a small month calendar.
  Widget _dayChoice(BuildContext context) {
    final today = todayKey(), tomorrow = addDays(today, 1);
    void pick(String date) => setState(() {
      _date = date;
      _calendarOpen = false;
      _days = [weekdayOf(date)];
    });
    final other = _date != today && _date != tomorrow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.sm,
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            AppChip('Today', selected: _date == today, onPressed: () => pick(today)),
            AppChip('Tomorrow', selected: _date == tomorrow, onPressed: () => pick(tomorrow)),
            AppChip(
              other ? formatDay(_date) : 'Another day',
              icon: Icons.calendar_month_outlined,
              selected: other || _calendarOpen,
              onPressed: () => setState(() {
                _calendarOpen = !_calendarOpen;
                _shownMonth = monthStart(_date);
              }),
            ),
          ],
        ),
        if (_calendarOpen) ...[
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(() => _shownMonth = addMonths(_shownMonth, -1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: T(formatMonth(_shownMonth), variant: TextVariant.label, align: TextAlign.center),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => setState(() => _shownMonth = addMonths(_shownMonth, 1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          MonthGrid(
            firstCell: startOfWeek(_shownMonth, 'mon'),
            month: _shownMonth.substring(0, 7),
            selected: _date,
            onSelect: (d) {
              tick();
              pick(d);
            },
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FormColumn(
      children: [
        if (_added.isNotEmpty) T(_added, variant: TextVariant.small, color: c.success),
        Row(
          spacing: Spacing.sm,
          children: [
            _iconTile(context),
            Expanded(
              child: Field(
                controller: _title,
                hint: 'What is it? Gym, lunch, class…',
                autofocus: widget.initial == null,
                textInputAction: TextInputAction.done,
                onChanged: _named,
              ),
            ),
          ],
        ),
        if (_iconsOpen) _iconGrid(context),
        if (widget.repeat == 'choose')
          Segmented<bool>(
            value: _repeats,
            onChanged: (v) => setState(() => _repeats = v),
            options: const {false: 'Once', true: 'Every week'},
          ),
        if (_repeats)
          // All seven days in one row, so the week reads left to right.
          Row(
            spacing: 6,
            children: [
              for (final (i, name) in weekdays.indexed)
                Expanded(
                  child: _Toggle(
                    name: name,
                    selected: _days.contains(i),
                    onTap: () => setState(() => _days = _days.contains(i) ? ([..._days]..remove(i)) : [..._days, i]),
                  ),
                ),
            ],
          )
        else
          _dayChoice(context),
        _label('Time · ${_span(_length)}'),
        StartTimeField(start: _start, length: _length, onChanged: (s) => setState(() => _start = s)),
        // Every length in one row; ones that would run past midnight are left out.
        Row(
          spacing: 6,
          children: [
            for (final MapEntry(key: m, value: name) in _lengths.entries)
              if (_start + m <= 1439)
                Expanded(
                  child: _Toggle(name: name, selected: m == _length, onTap: () => setState(() => _length = m)),
                ),
          ],
        ),
        if (_error.isNotEmpty) T(_error, color: c.danger),
        AppButton(
          widget.initial == null ? 'Add to calendar' : 'Save changes',
          icon: Icons.check,
          onPressed: _saving ? null : _save,
        ),
        ...widget.actions,
      ],
    );
  }
}

/// One cell in a full-width row of choices: a weekday, or a length.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.name, required this.selected, required this.onTap});

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          tick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.accent : c.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.button),
            border: Border.all(color: selected ? c.accent : c.border, width: 0.5),
          ),
          child: T(name, variant: TextVariant.small, color: selected ? c.onAccent : c.textDim, maxLines: 1),
        ),
      ),
    );
  }
}
