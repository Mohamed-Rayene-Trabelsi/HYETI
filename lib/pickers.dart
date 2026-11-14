import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'calendar_views.dart';
import 'date.dart';
import 'theme.dart';
import 'ui.dart';

/// The closed state of a picker: looks like a text field, opens on tap.
class _PickerButton extends StatelessWidget {
  const _PickerButton({required this.label, required this.value, required this.open, required this.onTap});

  final String label;
  final String value;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.xs,
      children: [
        T(label, variant: TextVariant.label, dim: true),
        Semantics(
          button: true,
          expanded: open,
          label: '$label: $value',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(Radii.button),
                border: Border.all(color: open ? c.accent : c.border, width: 0.5),
              ),
              child: T(value),
            ),
          ),
        ),
      ],
    );
  }
}

/* ---------- Date ---------- */

/// A date chosen from a small month calendar that opens under the field.
class DateField extends StatefulWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.optional = false,
  });

  final String label;

  /// 'YYYY-MM-DD', or '' when nothing is chosen.
  final String value;
  final ValueChanged<String> onChanged;
  final bool optional;

  @override
  State<DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<DateField> {
  bool _open = false;
  late String _month = monthStart(widget.value.isEmpty ? todayKey() : widget.value);

  void _pick(String date) {
    widget.onChanged(date);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final shown = value.isEmpty ? 'Not set' : '${formatDay(value)} ${value.substring(0, 4)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.sm,
      children: [
        _PickerButton(label: widget.label, value: shown, open: _open, onTap: () => setState(() => _open = !_open)),
        if (_open) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppButton(
                '‹',
                kind: ButtonKind.soft,
                small: true,
                onPressed: () => setState(() => _month = addMonths(_month, -1)),
              ),
              T(formatMonth(_month), variant: TextVariant.label),
              AppButton(
                '›',
                kind: ButtonKind.soft,
                small: true,
                onPressed: () => setState(() => _month = addMonths(_month, 1)),
              ),
            ],
          ),
          MonthGrid(
            firstCell: startOfWeek(_month, 'mon'),
            month: _month.substring(0, 7),
            selected: value,
            onSelect: _pick,
          ),
          if (widget.optional && value.isNotEmpty)
            AppButton('Clear date', kind: ButtonKind.plain, small: true, onPressed: () => _pick('')),
        ],
        if (!_open && widget.optional && value.isEmpty) const T('Optional', variant: TextVariant.small, dim: true),
      ],
    );
  }
}

/* ---------- Start and end time ---------- */

const _minutes = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];

/// Start and end times side by side; tapping one opens an hour and minute grid under both.
class TimeRangeField extends StatefulWidget {
  const TimeRangeField({super.key, required this.start, required this.end, required this.onChanged});

  /// Minutes since midnight.
  final int start;
  final int end;
  final void Function(int start, int end) onChanged;

  @override
  State<TimeRangeField> createState() => _TimeRangeFieldState();
}

class _TimeRangeFieldState extends State<TimeRangeField> {
  /// 'start', 'end', or null when closed.
  String? _open;

  void _set(int next) {
    if (_open == 'start') {
      // Moving the start keeps the block's length, as calendars do.
      widget.onChanged(next, math.min(next + (widget.end - widget.start), 1439));
    } else {
      widget.onChanged(widget.start, next);
    }
  }

  void _toggle(String which) => setState(() => _open = _open == which ? null : which);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = _open == 'end' ? widget.end : widget.start;
    final hour = value ~/ 60;
    final minute = value % 60;

    Widget grid(List<int> values, int selected, int Function(int) toMinutes, String Function(int) describe) {
      return LayoutBuilder(
        builder: (context, box) {
          const gap = 6.0, perRow = 6;
          final width = (box.maxWidth - gap * (perRow - 1)) / perRow;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final v in values)
                Semantics(
                  button: true,
                  selected: v == selected,
                  label: describe(v),
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => _set(toMinutes(v)),
                    child: Container(
                      // A hair narrower than an exact sixth, so rounding never wraps the row early.
                      width: width - 0.01,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: v == selected ? c.accent : c.surfaceAlt,
                        borderRadius: BorderRadius.circular(Radii.button),
                      ),
                      child: T(
                        v.toString().padLeft(2, '0'),
                        variant: TextVariant.label,
                        color: v == selected ? c.onAccent : c.text,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.sm,
      children: [
        Row(
          spacing: Spacing.sm,
          children: [
            Expanded(
              child: _PickerButton(
                label: 'Starts',
                value: formatTime(widget.start),
                open: _open == 'start',
                onTap: () => _toggle('start'),
              ),
            ),
            Expanded(
              child: _PickerButton(
                label: 'Ends',
                value: formatTime(widget.end),
                open: _open == 'end',
                onTap: () => _toggle('end'),
              ),
            ),
          ],
        ),
        if (_open != null) ...[
          const T('Hour', variant: TextVariant.small, dim: true),
          grid([for (var h = 0; h < 24; h++) h], hour, (h) => h * 60 + minute, (h) => "$h o'clock"),
          const T('Minute', variant: TextVariant.small, dim: true),
          grid(_minutes, minute, (m) => hour * 60 + m, (m) => '$m minutes'),
          AppButton('Done', kind: ButtonKind.soft, small: true, onPressed: () => setState(() => _open = null)),
        ],
      ],
    );
  }
}
