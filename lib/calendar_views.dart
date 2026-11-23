import 'package:material_ui/material_ui.dart';

import 'date.dart';
import 'db.dart';
import 'theme.dart';
import 'ui.dart';

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
      // The weekly routine is the same every day, so its blocks earn no dot: only what is different that day does
      // (a match, something added for that day). A past day where everything was ticked off gets a check instead.
      final dots = {
        for (final e in dayEvents)
          if (e['routine_id'] == null) _colorOf(e),
      }.take(4);
      final allDone = key.compareTo(today) < 0 && dayEvents.isNotEmpty && dayEvents.every((e) => e['done'] == 1);
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
                      height: 8,
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
                          if (allDone && dots.isEmpty) Icon(Icons.check, size: 8, color: c.success),
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
