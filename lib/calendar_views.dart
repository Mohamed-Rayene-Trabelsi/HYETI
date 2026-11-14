import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'date.dart';
import 'db.dart';
import 'theme.dart';
import 'ui.dart';

int _start(Rec e) => (e['start_min'] as int) + (e['shift_min'] as int);
int _end(Rec e) => (e['end_min'] as int) + (e['shift_min'] as int);
Color _colorOf(Rec e) => categoryOf(e['category'] as String).color;

/// On a day off, work blocks are left out.
bool _hiddenByDayOff(Rec e, List<String> offDates) => e['category'] == 'work' && offDates.contains(e['date']);

/* ---------- Month grid ---------- */

class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.firstCell,
    required this.month,
    required this.selected,
    this.events = const [],
    this.offDates = const [],
    required this.onSelect,
    this.rows,
    this.compact = false,
  });

  /// The date shown in the top-left cell (the start of the week holding the 1st).
  final String firstCell;

  /// 'YYYY-MM' of the month on show; other days are dimmed.
  final String month;
  final String selected;
  final List<Rec> events;
  final List<String> offDates;
  final ValueChanged<String> onSelect;

  /// How many weeks to show; worked out from the month when left out.
  final int? rows;

  /// Tighter cells, for when the grid shares the screen with other things.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = todayKey();
    // Five rows are enough unless the month spills into a sixth week.
    final rows = this.rows ?? (addDays(firstCell, 35).substring(0, 7) == month ? 6 : 5);
    final byDate = <String, List<Rec>>{};
    for (final e in events) {
      if (!_hiddenByDayOff(e, offDates)) (byDate[e['date'] as String] ??= []).add(e);
    }

    Widget cell(String key) {
      final inMonth = key.substring(0, 7) == month;
      final isSelected = key == selected;
      final isToday = key == today;
      final isOff = offDates.contains(key);
      final dayEvents = byDate[key] ?? const <Rec>[];
      final dots = {for (final e in dayEvents) _colorOf(e)}.take(4);
      final numberColor = isSelected
          ? c.onAccent
          : isToday
          ? c.accent
          : inMonth
          ? c.text
          : c.textDim.withValues(alpha: 0.45);
      return Expanded(
        child: Semantics(
          button: true,
          selected: isSelected,
          label: '${formatDay(key)}, ${dayEvents.length} planned${isOff ? ', day off' : ''}',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(key),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 44 : 52),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: compact ? 3 : 5),
                child: Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? c.accent : null,
                        border: !isSelected && isToday ? Border.all(color: c.accent, width: 1.5) : null,
                      ),
                      child: T('${fromKey(key).day}', variant: TextVariant.label, color: numberColor),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 3,
                        children: [
                          if (isOff)
                            Container(
                              width: 10,
                              height: 3,
                              decoration: BoxDecoration(color: c.warn, borderRadius: BorderRadius.circular(2)),
                            ),
                          for (final color in dots)
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(compact ? 4 : Spacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                    child: T(
                      weekdays[weekdayOf(addDays(firstCell, i))],
                      variant: TextVariant.small,
                      dim: true,
                      align: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          for (var r = 0; r < rows; r++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (var col = 0; col < 7; col++) cell(addDays(firstCell, r * 7 + col))],
            ),
        ],
      ),
    );
  }
}

/* ---------- Day / week timeline ---------- */

const double _gutter = 44;

/// Side-by-side columns for blocks that overlap in time.
List<({Rec e, int col, int of})> _layOut(List<Rec> events) {
  final ends = <int>[];
  final sorted = [...events]..sort((a, b) => _start(a) - _start(b));
  final placed = <(Rec, int)>[];
  for (final e in sorted) {
    var col = ends.indexWhere((end) => end <= _start(e));
    if (col < 0) {
      col = ends.length;
      ends.add(0);
    }
    ends[col] = _end(e);
    placed.add((e, col));
  }
  return [for (final (e, col) in placed) (e: e, col: col, of: ends.length)];
}

class Timeline extends StatelessWidget {
  const Timeline({
    super.key,
    required this.days,
    required this.events,
    required this.offDates,
    required this.hourHeight,
    required this.onPressEvent,
    this.onPressSlot,
    this.onPressDay,
    this.onToggle,
  });

  /// One date for the day view, seven for the week view.
  final List<String> days;
  final List<Rec> events;
  final List<String> offDates;
  final double hourHeight;
  final ValueChanged<Rec> onPressEvent;

  /// Tapping empty space: the date and the time (minutes) that was tapped.
  final void Function(String date, int minute)? onPressSlot;

  /// Week view: tapping a column heading opens that day.
  final ValueChanged<String>? onPressDay;

  /// Day view: the tick box on each block.
  final ValueChanged<Rec>? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = todayKey();
    final compact = days.length > 1;
    final shown = events.where((e) => !_hiddenByDayOff(e, offDates)).toList();
    // Only the hours that hold something are drawn (8 to 20 when the range is empty), so less scrolling.
    final earliest = shown.isEmpty ? 8 * 60 : shown.fold(1440, (min, e) => math.min(min, _start(e)));
    final latest = shown.isEmpty ? 20 * 60 : shown.fold(0, (max, e) => math.max(max, math.min(_end(e), 1440)));
    final firstHour = earliest ~/ 60;
    final lastHour = math.max(firstHour + 1, (latest + 59) ~/ 60);
    final hourCount = lastHour - firstHour + 1;
    double y(int min) => (math.min(min, lastHour * 60) - firstHour * 60) / 60 * hourHeight;
    final now = nowMinutes();

    Widget block(Rec e, int col, int of, double columnWidth) {
      final start = _start(e), end = _end(e);
      final shift = e['shift_min'] as int, flex = e['flex_min'] as int;
      final done = e['done'] == 1;
      final color = _colorOf(e);
      final height = math.max(y(end) - y(start) - 2, compact ? 16.0 : 30.0);
      final late = shift > flex;
      final struck = done ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
      return Positioned(
        top: y(start) + 1,
        height: height,
        left: columnWidth * col / of,
        width: columnWidth / of,
        child: Semantics(
          button: true,
          label: '${e['title']}, ${formatTime(start)} to ${formatTime(end)}${done ? ', done' : ''}',
          child: GestureDetector(
            onTap: () => onPressEvent(e),
            child: Opacity(
              opacity: done ? 0.5 : 1,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                clipBehavior: Clip.hardEdge,
                padding: EdgeInsets.only(left: compact ? 2 : Spacing.sm, right: compact ? 1 : Spacing.sm),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border(
                    left: BorderSide(color: color, width: compact ? 3 : 4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  spacing: Spacing.sm,
                  children: [
                    Expanded(
                      child: compact
                          ? T(
                              e['title'] as String,
                              variant: TextVariant.small,
                              maxLines: math.max(1, height ~/ 14),
                              style: const TextStyle(fontSize: 10, height: 1.3).merge(struck),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                T(e['title'] as String, variant: TextVariant.label, maxLines: 1, style: struck),
                                if (height >= 44)
                                  T(
                                    '${formatTime(start)}–${formatTime(end)}'
                                    '${shift > 0
                                        ? ' · $shift min late${late ? ', past buffer' : ''}'
                                        : flex > 0
                                        ? ' · $flex min buffer'
                                        : ''}',
                                    variant: TextVariant.small,
                                    dim: true,
                                    maxLines: 1,
                                    color: shift > 0 ? (late ? c.warn : c.success) : null,
                                  ),
                              ],
                            ),
                    ),
                    if (onToggle != null)
                      Semantics(
                        checked: done,
                        label: 'Mark ${e['title']} done',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onToggle!(e),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: done ? c.success : null,
                                border: Border.all(color: done ? c.success : c.textDim, width: 2),
                              ),
                              child: done ? Icon(Icons.check, size: 16, color: c.background) : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget column(String d) {
      final dayEvents = shown.where((e) => e['date'] == d).toList();
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Tapping empty space starts a new block at that time, snapped to the half hour.
          onTapUp: (details) {
            final minute = firstHour * 60 + details.localPosition.dy / hourHeight * 60;
            onPressSlot?.call(d, ((minute ~/ 30) * 30).clamp(0, 1380));
          },
          child: Container(
            decoration: BoxDecoration(
              color: offDates.contains(d) ? c.surfaceAlt : null,
              border: compact ? Border(left: BorderSide(color: c.border, width: 0.5)) : null,
            ),
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final p in _layOut(dayEvents)) block(p.e, p.col, p.of, box.maxWidth),
                  if (d == today && now >= firstHour * 60)
                    Positioned(
                      top: y(now) - 3,
                      left: -4,
                      right: 0,
                      child: IgnorePointer(
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle),
                            ),
                            Expanded(child: Container(height: 2, color: c.danger)),
                          ],
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

    return Container(
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.only(right: Spacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Column(
        children: [
          if (compact)
            Container(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: _gutter),
                  for (final d in days)
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Open ${formatDay(d)}',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onPressDay?.call(d),
                          child: Column(
                            spacing: 2,
                            children: [
                              T(weekdays[weekdayOf(d)], variant: TextVariant.small, dim: true),
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: d == today ? c.accent : null),
                                child: T(
                                  '${fromKey(d).day}',
                                  variant: TextVariant.label,
                                  color: d == today ? c.onAccent : c.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: Spacing.md),
            child: SizedBox(
              height: (hourCount - 1) * hourHeight + Spacing.lg,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var h = firstHour; h < firstHour + hourCount; h++)
                    Positioned(
                      top: y(h * 60) - 8,
                      left: 0,
                      right: 0,
                      height: 16,
                      child: Row(
                        children: [
                          SizedBox(
                            width: _gutter,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: T(
                                formatTime(h * 60),
                                variant: TextVariant.small,
                                dim: true,
                                align: TextAlign.right,
                                style: const TextStyle(fontSize: 11, height: 1.2),
                              ),
                            ),
                          ),
                          Expanded(child: Container(height: 0.5, color: c.border)),
                        ],
                      ),
                    ),
                  Positioned.fill(
                    left: _gutter,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final d in days) column(d)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
