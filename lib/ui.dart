import 'dart:async';

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'date.dart';
import 'db.dart';
import 'theme.dart';

/// A number as people write it: 60 rather than 60.0, at most two decimals.
String plainNumber(num n) => n.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// A light tick for selections and toggles.
void tick() => HapticFeedback.selectionClick();

/* ---------- Text ---------- */

enum TextVariant { title, heading, body, label, small, number }

const _styles = <TextVariant, TextStyle>{
  TextVariant.title: TextStyle(fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w700, letterSpacing: -0.4),
  TextVariant.heading: TextStyle(fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600),
  TextVariant.body: TextStyle(fontSize: 16, height: 23 / 16),
  TextVariant.label: TextStyle(fontSize: 14, height: 19 / 14, fontWeight: FontWeight.w600),
  TextVariant.small: TextStyle(fontSize: 13, height: 18 / 13),
  TextVariant.number: TextStyle(
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  ),
};

TextStyle textStyle(BuildContext context, TextVariant variant, {bool dim = false, Color? color}) {
  final c = context.colors;
  return _styles[variant]!.copyWith(color: color ?? (dim ? c.textDim : c.text));
}

class T extends StatelessWidget {
  const T(
    this.text, {
    super.key,
    this.variant = TextVariant.body,
    this.dim = false,
    this.color,
    this.maxLines,
    this.align,
    this.style,
  });

  final String text;
  final TextVariant variant;
  final bool dim;
  final Color? color;
  final int? maxLines;
  final TextAlign? align;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: align,
      style: textStyle(context, variant, dim: dim, color: color).merge(style),
    );
  }
}

/* ---------- Layout ---------- */

/// The one outline every button in the app shares.
const buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.button)));

/// A square icon button for screen headers.
class HeaderIcon extends StatelessWidget {
  const HeaderIcon(this.icon, {super.key, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.surfaceAlt,
        shape: buttonShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 21, color: c.text)),
        ),
      ),
    );
  }
}

/// The bar fixed above the tabs: the time, today's date, and the way into settings.
class TopBar extends StatefulWidget {
  const TopBar({super.key});

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  late int _minute = nowMinutes();
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    // Checked every second, redrawn only when the minute turns.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (nowMinutes() != _minute) setState(() => _minute = nowMinutes());
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = todayKey();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.sm),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: Row(
                spacing: Spacing.md,
                children: [
                  T(formatTime(_minute), variant: TextVariant.number, style: const TextStyle(fontSize: 24)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        T(weekdaysLong[weekdayOf(today)], variant: TextVariant.label, maxLines: 1),
                        T(
                          '${formatDay(today).split(', ')[1]} ${today.substring(0, 4)}',
                          variant: TextVariant.small,
                          dim: true,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  HeaderIcon(
                    Icons.settings_outlined,
                    label: 'Settings',
                    onPressed: () => Navigator.of(context).pushNamed('/settings'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One page of the app: a header, scrolling content, and an optional floating main action.
class Screen extends StatelessWidget {
  const Screen({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.fabLabel,
    this.fabIcon = Icons.add,
    this.onFab,
    this.secondFabLabel,
    this.secondFabIcon = Icons.add,
    this.onSecondFab,
    this.onBack,
    required this.children,
  });

  final String title;
  final String? subtitle;

  /// Header buttons, to the right of the title.
  final List<Widget> actions;

  /// The screen's main action, floating at the bottom right where a thumb reaches it.
  final String? fabLabel;
  final IconData fabIcon;
  final VoidCallback? onFab;

  /// A quieter second action, to the left of the main one.
  final String? secondFabLabel;
  final IconData secondFabIcon;
  final VoidCallback? onSecondFab;

  /// Set on pushed pages: shows a back arrow.
  final VoidCallback? onBack;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _ScreenFrame(screen: this);
}

/// Lays out a [Screen]. Its floating buttons shrink to their icons while the page scrolls down, so they cover less
/// of what is under them, and grow back when it scrolls up or reaches the top.
class _ScreenFrame extends StatefulWidget {
  const _ScreenFrame({required this.screen});

  final Screen screen;

  @override
  State<_ScreenFrame> createState() => _ScreenFrameState();
}

class _ScreenFrameState extends State<_ScreenFrame> {
  bool _compact = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    var compact = _compact;
    if (n.metrics.pixels <= 0) {
      compact = false;
    } else if (n is UserScrollNotification) {
      if (n.direction == ScrollDirection.reverse) compact = true;
      if (n.direction == ScrollDirection.forward) compact = false;
    }
    if (compact != _compact) setState(() => _compact = compact);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.screen;
    final title = w.title, subtitle = w.subtitle, actions = w.actions, children = w.children;
    final fabLabel = w.fabLabel, onFab = w.onFab, fabIcon = w.fabIcon;
    final secondFabLabel = w.secondFabLabel, onSecondFab = w.onSecondFab, secondFabIcon = w.secondFabIcon;
    final onBack = w.onBack;
    final hasFab = fabLabel != null && onFab != null;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              primary: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, hasFab ? 104 : Spacing.xxl),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Spacing.lg,
                    children: [
                      Row(
                        spacing: Spacing.sm,
                        children: [
                          if (onBack != null) HeaderIcon(Icons.arrow_back, label: 'Back', onPressed: onBack),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                T(title, variant: TextVariant.title, maxLines: 1),
                                if (subtitle != null) T(subtitle, dim: true, maxLines: 1),
                              ],
                            ),
                          ),
                          ...actions,
                        ],
                      ),
                      ...children,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasFab)
            Positioned(
              right: Spacing.lg,
              bottom: Spacing.lg,
              child: Row(
                spacing: Spacing.sm,
                children: [
                  if (secondFabLabel != null && onSecondFab != null)
                    _Fab(
                      label: secondFabLabel,
                      icon: secondFabIcon,
                      onPressed: onSecondFab,
                      quiet: true,
                      compact: _compact,
                    ),
                  _Fab(label: fabLabel, icon: fabIcon, onPressed: onFab, compact: _compact),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  const _Fab({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.quiet = false,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  /// Drawn in the card colour rather than the accent.
  final bool quiet;

  /// Only the icon, while the page scrolls down.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = quiet ? c.text : c.onAccent;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: quiet ? c.surfaceAlt : c.accent,
        elevation: 2,
        // A soft shadow: pure black drew a hard dark ring around the button on dark themes.
        shadowColor: const Color(0x59000000),
        shape: quiet ? buttonShape.copyWith(side: BorderSide(color: c.border, width: 0.5)) : buttonShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, compact ? 16 : 20, 0),
            child: SizedBox(
              height: 54,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Spacing.sm,
                  children: [
                    Icon(icon, color: fg, size: 22),
                    if (!compact) T(label, variant: TextVariant.label, color: fg, style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.children,
    this.padding,
    this.spacing = Spacing.sm,
    this.center = false,
    this.onTap,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final double spacing;
  final bool center;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(Radii.lg);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        spacing: spacing,
        children: children,
      ),
    );
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// A list row inside a card, with a hairline above every row but the first.
class ListRow extends StatelessWidget {
  const ListRow({super.key, required this.divider, required this.children, this.onTap});

  final bool divider;
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: context.colors.border, width: 0.5)) : null,
      ),
      child: Row(spacing: Spacing.md, children: children),
    );
    if (onTap == null) return row;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }
}

/// A setting that opens a picker: its name on the left, the current choice on the right, and a chevron.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.divider = false,
    this.placeholder = 'Choose',
  });

  final String label;

  /// The current choice; empty shows [placeholder] in the accent colour.
  final String value;
  final VoidCallback onTap;
  final IconData? icon;
  final bool divider;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '$label: ${value.isEmpty ? placeholder : value}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          tick();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          decoration: BoxDecoration(
            border: divider ? Border(top: BorderSide(color: c.border, width: 0.5)) : null,
          ),
          child: Row(
            spacing: Spacing.md,
            children: [
              if (icon != null) Icon(icon, size: 20, color: c.textDim),
              T(label, variant: TextVariant.label),
              Expanded(
                child: T(
                  value.isEmpty ? placeholder : value,
                  color: value.isEmpty ? c.accent : c.textDim,
                  align: TextAlign.end,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: c.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Padding for a card whose children are [ListRow]s.
const listCardPadding = EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.xs);

class Section extends StatelessWidget {
  const Section({super.key, required this.title, this.right, required this.children});

  final String title;
  final Widget? right;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.sm,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: T(
                title.toUpperCase(),
                variant: TextVariant.label,
                dim: true,
                style: const TextStyle(letterSpacing: 0.6),
              ),
            ),
            ?right,
          ],
        ),
        ...children,
      ],
    );
  }
}

class Empty extends StatelessWidget {
  const Empty({super.key, required this.title, this.hint, this.action, this.icon});

  final String title;
  final String? hint;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      center: true,
      spacing: Spacing.md,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.xl),
      children: [
        if (icon != null)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: c.accent, size: 26),
          ),
        T(title, variant: TextVariant.heading, align: TextAlign.center),
        if (hint != null) T(hint!, dim: true, align: TextAlign.center),
        ?action,
      ],
    );
  }
}

/* ---------- Controls ---------- */

enum ButtonKind { primary, soft, danger, plain }

/// Fills the width it is given in a column; hugs its label in a row.
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = ButtonKind.primary,
    this.small = false,
    this.icon,
    this.wrap = false,
    this.fill,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final bool small;
  final IconData? icon;

  /// Lets a long label take two lines instead of being cut short.
  final bool wrap;

  /// A solid colour for the button instead of its kind's, for the rare pair of actions told apart by colour.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg =
        fill ??
        switch (kind) {
          ButtonKind.primary => c.accent,
          ButtonKind.plain => Colors.transparent,
          _ => c.surfaceAlt,
        };
    // On a custom fill, dark text on bright colours and white on deep ones.
    final fg = fill != null
        ? (fill!.computeLuminance() > 0.35 ? const Color(0xFF0C0D10) : const Color(0xFFFFFFFF))
        : switch (kind) {
            ButtonKind.primary => c.onAccent,
            ButtonKind.danger => c.danger,
            ButtonKind.plain => c.accent,
            ButtonKind.soft => c.text,
          };
    final radius = BorderRadius.circular(Radii.button);
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: bg,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: small ? 40 : 48),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? Spacing.md : Spacing.lg, vertical: wrap ? 10 : 0),
              child: Center(
                heightFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    if (icon != null) Icon(icon, size: small ? 16 : 18, color: fg),
                    Flexible(
                      child: T(
                        label,
                        variant: TextVariant.label,
                        color: fg,
                        maxLines: wrap ? 2 : 1,
                        align: TextAlign.center,
                        style: small ? null : const TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppChip extends StatelessWidget {
  const AppChip(this.label, {super.key, this.selected = false, this.onPressed, this.color, this.icon});

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.accent;
    // Custom colours are all mid-bright, where near-black text reads better than white.
    final fg = selected ? (color != null ? const Color(0xFF0C0D10) : c.onAccent) : c.textDim;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: ShapeDecoration(
          color: selected ? tint : c.surfaceAlt,
          shape: buttonShape.copyWith(side: BorderSide(color: selected ? tint : c.border, width: 0.5)),
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: buttonShape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed == null
                ? null
                : () {
                    tick();
                    onPressed!();
                  },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    if (icon != null) Icon(icon, size: 16, color: fg),
                    Flexible(
                      child: T(label, variant: TextVariant.label, color: fg, maxLines: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of choices with a thumb that slides to the chosen one.
class Segmented<V> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  /// Value → label, in display order.
  final Map<V, String> options;
  final V value;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keys = options.keys.toList();
    final index = keys.indexOf(value);
    final n = keys.length;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.button)),
      child: Stack(
        children: [
          if (index >= 0)
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(Radii.button - 3),
                    boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))],
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final k in keys)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: k == value,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (k == value) return;
                        tick();
                        onChanged(k);
                      },
                      child: Center(
                        child: T(options[k]!, variant: TextVariant.label, dim: k != value, maxLines: 1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

InputDecoration fieldDecoration(BuildContext context, {String? hint, IconData? icon}) {
  final c = context.colors;
  OutlineInputBorder border(Color color, [double width = 0.5]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.button),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: c.textDim.withValues(alpha: 0.7), fontSize: 15),
    prefixIcon: icon == null ? null : Icon(icon, size: 20, color: c.textDim),
    filled: true,
    fillColor: c.surfaceAlt,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 14),
    enabledBorder: border(c.border),
    focusedBorder: border(c.accent, 1.5),
  );
}

/// A labelled text input. Wrap in `Expanded` when several share one row.
class Field extends StatelessWidget {
  const Field({
    super.key,
    this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.keyboardType,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.capitalization = TextCapitalization.sentences,
    this.autocorrect = true,
  });

  final String? label;
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final TextCapitalization capitalization;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.xs,
      children: [
        if (label != null) T(label!, variant: TextVariant.label, dim: true, maxLines: 1),
        TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: textInputAction,
          autofocus: autofocus,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          autocorrect: autocorrect,
          style: TextStyle(fontSize: 15, color: context.colors.text),
          decoration: fieldDecoration(context, hint: hint, icon: icon),
        ),
      ],
    );
  }
}

/// A bar that glides to its new value.
class ProgressBar extends StatelessWidget {
  const ProgressBar(this.value, {super.key, this.color});

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 8,
        color: c.surfaceAlt,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: pct),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(color: color ?? c.accent, borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------- Bottom sheet ---------- */

/// Opens a titled bottom sheet. Close it from inside with `Navigator.pop(context)`.
Future<void> showSheet(BuildContext context, {required String title, required WidgetBuilder builder}) {
  final c = context.colors;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: c.surface,
    barrierColor: c.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg + 4))),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: (media.size.height - media.padding.top) * 0.9),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: Spacing.sm),
                    decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: T(title, variant: TextVariant.heading, maxLines: 1)),
                    AppButton(
                      'Close',
                      kind: ButtonKind.plain,
                      small: true,
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(top: Spacing.md, bottom: Spacing.xl + media.padding.bottom),
                    child: builder(sheetContext),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The usual body of a sheet or form: children stacked full-width with even gaps.
class FormColumn extends StatelessWidget {
  const FormColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Spacing.md,
      children: children,
    );
  }
}

/* ---------- Undo ---------- */

/// Lets any screen or sheet show a message at the bottom of the app.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// The text of an undo message; it also knows where on screen the message is.
class _UndoText extends StatefulWidget {
  const _UndoText(this.message);

  final String message;

  @override
  State<_UndoText> createState() => _UndoTextState();
}

class _UndoTextState extends State<_UndoText> {
  static final showing = <_UndoTextState>{};

  @override
  void initState() {
    super.initState();
    showing.add(this);
  }

  @override
  void dispose() {
    showing.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.message, maxLines: 2, overflow: TextOverflow.ellipsis);
}

/// Takes the undo message away. Given where the screen was touched, it stays if the touch was on the message.
void dismissUndo([Offset? touch]) {
  if (_UndoTextState.showing.isEmpty) return;
  if (touch != null) {
    for (final text in _UndoTextState.showing) {
      final box = text.context.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (touch.dy > top - 28 && touch.dy < top + box.size.height + 28) return;
    }
  }
  messengerKey.currentState?.hideCurrentSnackBar();
}

/// A short message with an Undo button, shown above the floating action. It leaves by itself after a few
/// seconds, or as soon as something else on screen is touched.
void showUndo(String message, Future<void> Function() undo) {
  final messenger = messengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: _UndoText(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        // Without this a message that has a button never times out.
        persist: false,
        margin: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, 84),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        action: SnackBarAction(label: 'Undo', onPressed: undo),
      ),
    );
}

/// Deletes one row and offers to put it back.
Future<void> deleteWithUndo(String table, Rec row, String message) async {
  await appDb.run('DELETE FROM $table WHERE id = ?', [row['id']]);
  showUndo(message, () => appDb.restore(table, row));
}

SystemUiOverlayStyle overlayStyle(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: context.colors.surface,
    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
  );
}
