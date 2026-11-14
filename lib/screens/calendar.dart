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
  });

  final String title;
  final String category;
  final int start;
  final int end;
  final int flex;

  /// Weekdays (0 = Monday) when the block repeats, null for a single day.
  final List<int>? days;
}

const _sampleRoutine = [
  BlockValues(title: 'Deep work', category: 'work', start: 540, end: 660, flex: 15, days: [0, 1, 2, 3, 4]),
  BlockValues(title: 'Lunch', category: 'food', start: 780, end: 825, flex: 15, days: [0, 1, 2, 3, 4, 5, 6]),
  BlockValues(title: 'Gym', category: 'gym', start: 1080, end: 1170, flex: 30, days: [0, 1, 3, 4]),
  BlockValues(title: 'Dinner', category: 'food', start: 1200, end: 1245, flex: 15, days: [0, 1, 2, 3, 4, 5, 6]),
  BlockValues(title: 'Gaming', category: 'game', start: 1260, end: 1350, flex: 30, days: [0, 1, 2, 3, 4, 5, 6]),
];

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

  String get _firstDay => appDb.setting('week_start', 'mon');
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
    final routines = await appDb.query('SELECT * FROM routines ORDER BY start_min, id');
    // The user moved on while this was loading; a newer load is on its way.
    if (from != _from || to != _to) return;
    _events = events;
    _offDates = [for (final r in off) r['date'] as String];
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

  void _openNew({int? start}) {
    final date = _date;
    showSheet(
      context,
      title: 'New · ${formatDay(date)}',
      builder: (sheet) => BlockForm(
        repeat: 'choose',
        start: start,
        end: start == null ? null : math.min(start + 60, 1439),
        onSave: (v) async {
          if (v.days != null) {
            await _saveRoutine(v, null);
          } else {
            await appDb.run(
              'INSERT INTO events (date, title, category, start_min, end_min, flex_min) VALUES (?, ?, ?, ?, ?, ?)',
              [date, v.title, v.category, v.start, v.end, v.flex],
            );
          }
          if (sheet.mounted) Navigator.pop(sheet);
        },
      ),
    );
  }

  void _openEdit(Rec e) {
    final fromRoutine = e['routine_id'] != null;
    showSheet(
      context,
      title: 'Edit block',
      builder: (sheet) => BlockForm(
        repeat: 'never',
        initial: e,
        deleteLabel: fromRoutine ? 'Skip on this day' : 'Delete',
        onSave: (v) async {
          await appDb.run(
            'UPDATE events SET title = ?, category = ?, start_min = ?, end_min = ?, flex_min = ?, shift_min = 0 '
            'WHERE id = ?',
            [v.title, v.category, v.start, v.end, v.flex, e['id']],
          );
          if (sheet.mounted) Navigator.pop(sheet);
        },
        onDelete: () async {
          if (fromRoutine) {
            // Routine blocks are hidden rather than deleted so they are not copied back in.
            await appDb.run('UPDATE events SET hidden = 1 WHERE id = ?', [e['id']]);
            showUndo(
              'Skipped ${e['title']} on this day',
              () => appDb.run('UPDATE events SET hidden = 0 WHERE id = ?', [e['id']]),
            );
          } else {
            await deleteWithUndo('events', e, 'Deleted ${e['title']}');
          }
          if (sheet.mounted) Navigator.pop(sheet);
        },
      ),
    );
  }

  void _openLate() {
    showSheet(
      context,
      title: 'Running late',
      builder: (sheet) => FormColumn(
        children: [
          const T(
            'Pushes every block you have not finished yet. Blocks pushed past their buffer are flagged.',
            dim: true,
          ),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final m in const [10, 15, 30, 45, 60])
                AppButton(
                  '+$m min',
                  kind: ButtonKind.soft,
                  onPressed: () async {
                    await appDb.run(
                      'UPDATE events SET shift_min = shift_min + ? WHERE date = ? AND done = 0 AND end_min + shift_min > ?',
                      [m, todayKey(), nowMinutes()],
                    );
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openRoutines() => showSheet(context, title: 'Weekly routine', builder: (_) => const _RoutineList());

  Future<void> _addSample() {
    return appDb.transaction((txn) async {
      for (final v in _sampleRoutine) {
        await _insertRoutine(txn, v);
      }
    });
  }

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
    final delayed = dayBlocks.any((e) => (e['shift_min'] as int) > 0);
    final now = nowMinutes();
    final canRunLate = isToday && dayBlocks.any((e) => e['done'] != 1 && _endOf(e) > now);
    // First run: nothing set up yet. Checked only once the data has loaded, so it never flashes.
    final needsSetup = ready && _routines.isEmpty && _events.isEmpty;

    final relative = relativeDay(date);
    final named = relative != formatDay(date);
    String dayMonth(String key) => formatDay(key).split(', ')[1];
    final rangeLabel = _view == 'month'
        ? formatMonth(date)
        : '${dayMonth(_weekFrom)} – ${dayMonth(addDays(_weekFrom, 6))}';

    // Quick actions for the day on show; they sit inside the day card.
    final chips = [
      if (!isToday)
        AppChip(
          'Today',
          icon: Icons.today,
          onPressed: () => _go(date: today),
        ),
      AppChip(
        'Day off',
        icon: isOff ? Icons.check : Icons.beach_access_outlined,
        selected: isOff,
        color: c.warn,
        onPressed: () => appDb.run(
          isOff ? 'DELETE FROM day_offs WHERE date = ?' : 'INSERT OR IGNORE INTO day_offs (date) VALUES (?)',
          [date],
        ),
      ),
      if (canRunLate) AppChip('Running late', icon: Icons.schedule, onPressed: _openLate),
      if (delayed)
        AppChip(
          'Clear delays',
          icon: Icons.restart_alt,
          onPressed: () => appDb.run('UPDATE events SET shift_min = 0 WHERE date = ?', [date]),
        ),
    ];

    return Screen(
      title: relative,
      subtitle: named ? '${formatDay(date)} ${date.substring(0, 4)}' : formatMonth(date),
      actions: [HeaderIcon(Icons.repeat, label: 'Weekly routine', onPressed: _openRoutines)],
      fabLabel: 'Add',
      onFab: _openNew,
      children: [
        Segmented<String>(
          value: _view,
          onChanged: (v) => _go(view: v),
          options: const {'day': 'Day', 'week': 'Week', 'month': 'Month'},
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
              _NavArrow(
                icon: Icons.chevron_left,
                hint: _view == 'month' ? 'Previous month' : 'Previous week',
                onTap: () => _step(-1),
              ),
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
              _NavArrow(
                icon: Icons.chevron_right,
                hint: _view == 'month' ? 'Next month' : 'Next week',
                onTap: () => _step(1),
              ),
            ],
          ),
        if (needsSetup)
          Empty(
            icon: Icons.event_repeat,
            title: 'Set up your week',
            hint:
                'Add repeating blocks for gym, meals, work and gaming. They fill your calendar automatically '
                'and can bend when life gets in the way.',
            action: Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              alignment: WrapAlignment.center,
              children: [
                AppButton('Use a sample routine', onPressed: _addSample),
                AppButton('Build my own', kind: ButtonKind.soft, onPressed: () => openRoutineForm(context, null)),
              ],
            ),
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
        if (_view == 'week' && !needsSetup)
          Timeline(
            days: dateRange(_from, _to),
            events: _events,
            offDates: _offDates,
            hourHeight: 38,
            onPressEvent: _openEdit,
            onPressSlot: (d, start) {
              _go(date: d);
              _openNew(start: start);
            },
            onPressDay: (d) => _go(date: d, view: 'day'),
          ),
        // Day and month views share the same summary and list for the chosen day.
        if (_view != 'week' && !needsSetup) ...[
          _DayCard(
            blocks: dayBlocks,
            doneCount: doneCount,
            isToday: isToday,
            isOff: isOff,
            now: now,
            chips: chips,
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
    required this.chips,
    required this.onToggle,
  });

  final List<Rec> blocks;
  final int doneCount;
  final bool isToday;
  final bool isOff;
  final int now;
  final List<Widget> chips;
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
        Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: chips),
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
    final c = context.colors;
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

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: c.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ),
    );
  }

  Widget _row(BuildContext context, Rec e) {
    final c = context.colors;
    final start = _startOf(e), end = _endOf(e);
    final shift = e['shift_min'] as int, flex = e['flex_min'] as int;
    final done = e['done'] == 1;
    final late = shift > flex;
    final current = now != null && !done && start <= now! && now! < end;
    final color = categoryOf(e['category'] as String).color;
    final detail = shift > 0
        ? '${_span(end - start)} · $shift min late${late ? ', past buffer' : ''}'
        : '${_span(end - start)}${flex > 0 ? ' · $flex min buffer' : ''}';

    return Semantics(
      button: true,
      label: 'Edit ${e['title']}, ${formatTime(start)} to ${formatTime(end)}${done ? ', done' : ''}',
      child: InkWell(
        onTap: () => onEdit(e),
        child: Container(
          // The block happening right now is picked out.
          color: current ? c.accent.withValues(alpha: 0.10) : null,
          padding: const EdgeInsets.fromLTRB(Spacing.md, 9, Spacing.sm, 9),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Spacing.md,
              children: [
                SizedBox(
                  width: 44,
                  child: Opacity(
                    opacity: done ? 0.5 : 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        T(
                          formatTime(start),
                          variant: TextVariant.label,
                          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                        T(
                          formatTime(end),
                          variant: TextVariant.small,
                          dim: true,
                          style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: done ? color.withValues(alpha: 0.4) : color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Opacity(
                    opacity: done ? 0.5 : 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                          color: shift > 0 ? (late ? c.warn : c.success) : c.textDim,
                          style: const TextStyle(fontSize: 12),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(7),
                            color: done ? c.success : null,
                            border: Border.all(color: done ? c.success : c.textDim, width: 2),
                          ),
                          child: done ? Icon(Icons.check, size: 16, color: c.background) : null,
                        ),
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

  /// Free time between two blocks; tapping it starts a new block there.
  Widget _gap(BuildContext context, int from, int to) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Free for ${_span(to - from)} from ${formatTime(from)}. Add something here',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onAddAt(from),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.md, 3, Spacing.md, 3),
          child: Row(
            spacing: Spacing.md,
            children: [
              SizedBox(
                width: 44,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.add, size: 14, color: c.textDim),
                ),
              ),
              Expanded(
                child: T(
                  'Free · ${_span(to - from)}',
                  variant: TextVariant.small,
                  dim: true,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------- Weekly routine ---------- */

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
      onDelete: routine == null
          ? null
          : () async {
              await _deleteRoutine(routine);
              if (sheet.mounted) Navigator.pop(sheet);
            },
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

const _buffers = [0, 10, 15, 30, 45];

/// Form for a calendar block: a one-off on one day, or a weekly routine.
class BlockForm extends StatefulWidget {
  const BlockForm({
    super.key,
    this.initial,
    this.start,
    this.end,
    required this.repeat,
    required this.onSave,
    this.onDelete,
    this.deleteLabel = 'Delete',
  });

  /// An events or routines row to edit.
  final Rec? initial;

  /// Times for a new block, when it was started by tapping the timeline.
  final int? start;
  final int? end;

  /// 'choose' lets the user pick; 'always' / 'never' fix it.
  final String repeat;
  final ValueChanged<BlockValues> onSave;
  final VoidCallback? onDelete;
  final String deleteLabel;

  @override
  State<BlockForm> createState() => _BlockFormState();
}

class _BlockFormState extends State<BlockForm> {
  late final _title = TextEditingController(text: widget.initial?['title'] as String? ?? '');
  late String _category = widget.initial?['category'] as String? ?? 'work';
  late int _start = widget.initial?['start_min'] as int? ?? widget.start ?? 9 * 60;
  late int _end = widget.initial?['end_min'] as int? ?? widget.end ?? 10 * 60;
  late int _flex = widget.initial?['flex_min'] as int? ?? 15;
  late bool _repeats = widget.repeat == 'always';
  late List<int> _days = switch (widget.initial?['days']) {
    final String days when days.isNotEmpty => days.split(',').map(int.parse).toList(),
    _ => [0, 1, 2, 3, 4],
  };
  String _error = '';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    if (_end <= _start) return setState(() => _error = 'The end time has to be after the start time.');
    if (_repeats && _days.isEmpty) return setState(() => _error = 'Pick at least one day.');
    final title = _title.text.trim();
    widget.onSave(
      BlockValues(
        title: title.isEmpty ? categoryOf(_category).label : title,
        category: _category,
        start: _start,
        end: _end,
        flex: _flex,
        days: _repeats ? ([..._days]..sort()) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FormColumn(
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final cat in categories)
              AppChip(
                cat.label,
                color: cat.color,
                selected: cat.key == _category,
                onPressed: () => setState(() => _category = cat.key),
              ),
          ],
        ),
        Field(label: 'Name', controller: _title, hint: categoryOf(_category).label),
        TimeRangeField(
          start: _start,
          end: _end,
          onChanged: (s, e) => setState(() {
            _start = s;
            _end = e;
            _error = '';
          }),
        ),
        if (_end > _start) T('Lasts ${_span(_end - _start)}', variant: TextVariant.small, dim: true),
        const T('Buffer for delays (traffic, queues)', variant: TextVariant.label, dim: true),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final b in _buffers)
              AppChip(b == 0 ? 'None' : '$b min', selected: b == _flex, onPressed: () => setState(() => _flex = b)),
          ],
        ),
        if (widget.repeat == 'choose')
          Segmented<bool>(
            value: _repeats,
            onChanged: (v) => setState(() => _repeats = v),
            options: const {false: 'Just this day', true: 'Every week'},
          ),
        if (_repeats)
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final (i, name) in weekdays.indexed)
                AppChip(
                  name,
                  selected: _days.contains(i),
                  onPressed: () => setState(() => _days = _days.contains(i) ? ([..._days]..remove(i)) : [..._days, i]),
                ),
            ],
          ),
        if (_error.isNotEmpty) T(_error, color: context.colors.danger),
        AppButton('Save', onPressed: _save),
        if (widget.onDelete != null) AppButton(widget.deleteLabel, kind: ButtonKind.danger, onPressed: widget.onDelete),
      ],
    );
  }
}
