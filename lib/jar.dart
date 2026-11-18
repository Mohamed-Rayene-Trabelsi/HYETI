import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'date.dart';
import 'db.dart';
import 'theme.dart';
import 'ui.dart';

/// Coins are gold in every theme, like the sketch pens and calendar categories.
const coinGold = Color(0xFFF2C94C);
const _coinRim = Color(0xFFC9A227);
const _coinShine = Color(0xFFFFE69A);

/// How full the jar is for [saved] towards [target]; an unset target is an empty jar.
double jarFill(double saved, double? target) =>
    target == null || target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0).toDouble();

/// The milestone (a quarter, a half, three quarters, full) that [after] reached and [before] had not, or null.
int? jarMilestone(double before, double after) {
  for (final m in const [100, 75, 50, 25]) {
    if (after * 100 >= m && before * 100 < m) return m;
  }
  return null;
}

const jarCheers = {
  25: 'A quarter of the jar. Off to a good start!',
  50: 'The jar is half full!',
  75: 'Three quarters there. Keep it up!',
  100: 'Jar full. Goal reached! 🎉',
};

/// A glass jar of gold coins, filled to [fill] (0–1). When the fill changes the coins pour in and slosh.
class SavingsJar extends StatefulWidget {
  const SavingsJar({super.key, required this.fill, this.onTap, this.width = 96});

  final double fill;
  final VoidCallback? onTap;
  final double width;

  @override
  State<SavingsJar> createState() => _SavingsJarState();
}

class _SavingsJarState extends State<SavingsJar> with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  double _from = 0;

  @override
  void initState() {
    super.initState();
    // The coins pour in when the jar first shows.
    _motion.forward();
  }

  @override
  void didUpdateWidget(SavingsJar old) {
    super.didUpdateWidget(old);
    if (old.fill != widget.fill) {
      _from = _shownFill;
      _motion.forward(from: 0);
    }
  }

  double get _shownFill {
    final t = Curves.easeOutCubic.transform(_motion.value);
    return _from + (widget.fill - _from) * t;
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final percent = (widget.fill * 100).round();
    return Semantics(
      label: 'Savings jar, $percent% full',
      button: widget.onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              },
        child: AnimatedBuilder(
          animation: _motion,
          builder: (context, _) => CustomPaint(
            size: Size(widget.width, widget.width * 4 / 3),
            painter: JarPainter(
              fill: _shownFill,
              // The slosh dies down as the coins settle.
              slosh: (1 - _motion.value) * math.sin(_motion.value * math.pi * 5),
              glass: c.textDim,
              lid: c.surfaceAlt,
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the jar. The home-screen widget draws the same jar in `JarWidget.kt`; keep the two alike.
class JarPainter extends CustomPainter {
  const JarPainter({required this.fill, required this.slosh, required this.glass, required this.lid});

  final double fill;

  /// -1–1: how far the top of the pile tilts right now.
  final double slosh;
  final Color glass;
  final Color lid;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = RRect.fromLTRBR(w * 0.06, h * 0.16, w * 0.94, h, Radius.circular(w * 0.2));
    final lidRect = RRect.fromLTRBR(w * 0.2, 0, w * 0.8, h * 0.13, Radius.circular(w * 0.06));

    // Coins, inside the glass.
    canvas.save();
    canvas.clipRRect(body.deflate(w * 0.03));
    final inner = body.deflate(w * 0.03).outerRect;
    final coinW = w * 0.3, coinH = w * 0.12;
    final level = inner.bottom - inner.height * fill;
    final rise = coinH * 0.62;
    for (var row = 0; inner.bottom - row * rise + coinH * 0.5 > level; row++) {
      final baseY = inner.bottom - row * rise - coinH * 0.15;
      final stagger = row.isOdd ? coinW * 0.5 : 0.0;
      for (var x = inner.left - coinW * 0.5 + stagger; x < inner.right + coinW * 0.5; x += coinW * 0.92) {
        // A little scatter, the same every time, so the pile looks tipped in by hand.
        final jitter = math.sin(row * 12.9898 + x * 0.78) * coinH * 0.18;
        // Near the top, the pile tilts with the slosh.
        final tilt = (baseY - level) < coinH * 2 ? slosh * coinH * 0.9 * ((x - inner.center.dx) / inner.width) : 0.0;
        final y = baseY + jitter + tilt;
        if (y - coinH * 0.5 < level - coinH * 0.25) continue;
        final coin = Rect.fromCenter(center: Offset(x, y), width: coinW, height: coinH);
        canvas.drawOval(coin.shift(Offset(0, coinH * 0.18)), Paint()..color = _coinRim);
        canvas.drawOval(coin, Paint()..color = coinGold);
        canvas.drawOval(
          Rect.fromCenter(
            center: coin.center.translate(-coinW * 0.12, -coinH * 0.12),
            width: coinW * 0.35,
            height: coinH * 0.3,
          ),
          Paint()..color = _coinShine.withValues(alpha: 0.8),
        );
      }
    }
    canvas.restore();

    // The glass, its shine, and the lid.
    canvas.drawRRect(body, Paint()..color = glass.withValues(alpha: 0.08));
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.025)
        ..color = glass.withValues(alpha: 0.55),
    );
    canvas.drawLine(
      Offset(w * 0.2, h * 0.3),
      Offset(w * 0.2, h * 0.62),
      Paint()
        ..strokeWidth = w * 0.045
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.18),
    );
    canvas.drawRRect(lidRect, Paint()..color = lid);
    canvas.drawRRect(
      lidRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.025)
        ..color = glass.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(JarPainter old) => old.fill != fill || old.slosh != slosh || old.glass != glass || old.lid != lid;
}

/// A quick sheet for putting money in the jar: a few one-tap amounts, or any amount typed in.
Future<void> openJarDrop(BuildContext context, {required String Function(double) money}) {
  return showSheet(
    context,
    title: 'Into the jar',
    builder: (sheet) => _JarMove(money: money),
  );
}

/// The same sheet the other way round: money taken back out, after an "are you sure?".
Future<void> openJarTakeOut(BuildContext context, {required double saved, required String Function(double) money}) {
  return showSheet(
    context,
    title: 'Out of the jar',
    builder: (sheet) => _JarMove(money: money, takeOutOf: saved),
  );
}

/// How the jar works, behind the "i" on the jar card.
Future<void> openJarInfo(BuildContext context) {
  return showSheet(
    context,
    title: 'How the jar works',
    builder: (sheet) => const FormColumn(
      children: [
        _InfoLine(
          icon: Icons.flag_outlined,
          title: 'Set a goal',
          text: 'Give it a name and an amount, like a new bike. The jar is full when your savings reach it.',
        ),
        _InfoLine(
          icon: Icons.savings_outlined,
          title: 'Drop money in',
          text:
              'Tap the jar or “Drop in” whenever you put money aside. It is logged as saved, so it no longer counts '
              'as money you can spend.',
        ),
        _InfoLine(
          icon: Icons.celebration_outlined,
          title: 'Watch it fill',
          text: 'The coins rise as you save, and the jar cheers when it is a quarter, half and three quarters full.',
        ),
        _InfoLine(
          icon: Icons.outbox_outlined,
          title: 'Take money out',
          text: 'Needed some of it back? “Take out” moves it back to what you can spend, and the jar drops.',
        ),
        _InfoLine(
          icon: Icons.widgets_outlined,
          title: 'On your home screen',
          text: 'Add the “Savings jar” widget to see the jar without opening the app, and drop money in from there.',
        ),
      ],
    ),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Spacing.md,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: coinGold.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: Icon(icon, size: 19, color: c.text),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              T(title, variant: TextVariant.label),
              T(text, variant: TextVariant.small, dim: true),
            ],
          ),
        ),
      ],
    );
  }
}

/// Asks before money leaves the jar. True when the person goes ahead.
Future<bool> confirmTakeOut(BuildContext context, String amount) async {
  final c = context.colors;
  final sure = await showDialog<bool>(
    context: context,
    barrierColor: c.scrim,
    builder: (dialog) => Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: FormColumn(
          children: [
            const T('Are you sure?', variant: TextVariant.heading),
            T('$amount comes out of your savings jar.', dim: true),
            AppButton(
              'Momma raised a financial failure, I GUESS ?',
              kind: ButtonKind.danger,
              wrap: true,
              onPressed: () => Navigator.pop(dialog, true),
            ),
            AppButton('Keep it in the jar', kind: ButtonKind.soft, onPressed: () => Navigator.pop(dialog, false)),
          ],
        ),
      ),
    ),
  );
  return sure ?? false;
}

class _JarMove extends StatefulWidget {
  const _JarMove({required this.money, this.takeOutOf});

  final String Function(double) money;

  /// What is in the jar, when taking out; null when putting in.
  final double? takeOutOf;

  @override
  State<_JarMove> createState() => _JarMoveState();
}

class _JarMoveState extends State<_JarMove> {
  final _amount = TextEditingController();
  final _label = TextEditingController();
  String _error = '';

  bool get _out => widget.takeOutOf != null;

  @override
  void dispose() {
    _amount.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _move(double amount) async {
    if (_out) {
      if (amount > widget.takeOutOf! + 0.0001) {
        return setState(() => _error = 'There is only ${widget.money(widget.takeOutOf!)} in the jar.');
      }
      if (!await confirmTakeOut(context, widget.money(amount))) return;
    }
    HapticFeedback.mediumImpact();
    await appDb.insert('INSERT INTO transactions (date, kind, amount, label) VALUES (?, ?, ?, ?)', [
      todayKey(),
      _out ? 'withdraw' : 'saving',
      amount,
      _label.text.trim(),
    ]);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = _out ? Icons.outbox_outlined : Icons.savings_outlined;
    final presets = [
      for (final n in const [5.0, 10.0, 20.0, 50.0, 100.0])
        if (!_out || n <= widget.takeOutOf!) n,
    ];
    return FormColumn(
      children: [
        T(
          _out
              ? 'There is ${widget.money(widget.takeOutOf!)} in the jar. Tap an amount to take it out.'
              : 'Tap an amount to drop it in.',
          dim: true,
        ),
        if (presets.isNotEmpty)
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final n in presets)
                AppChip('${_out ? '−' : '+'}${widget.money(n)}', icon: icon, onPressed: () => _move(n)),
            ],
          ),
        Field(
          label: 'Another amount',
          controller: _amount,
          hint: '0',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
        ),
        Field(
          label: 'For (optional)',
          controller: _label,
          hint: _out ? 'Concert tickets' : 'Birthday money',
          textInputAction: TextInputAction.done,
        ),
        if (_error.isNotEmpty) T(_error, variant: TextVariant.small, color: c.danger),
        AppButton(
          _out ? 'Take it out' : 'Drop it in',
          icon: icon,
          kind: _out ? ButtonKind.soft : ButtonKind.primary,
          onPressed: () {
            final n = double.tryParse(_amount.text.replaceFirst(',', '.').replaceAll(RegExp(r'[^\d.]'), ''));
            if (n == null || !n.isFinite || n <= 0) return setState(() => _error = 'Enter an amount above zero.');
            _move(n);
          },
        ),
      ],
    );
  }
}
