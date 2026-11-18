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
    builder: (sheet) => _JarDrop(money: money),
  );
}

class _JarDrop extends StatefulWidget {
  const _JarDrop({required this.money});

  final String Function(double) money;

  @override
  State<_JarDrop> createState() => _JarDropState();
}

class _JarDropState extends State<_JarDrop> {
  final _amount = TextEditingController();
  final _label = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _amount.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _drop(double amount) async {
    HapticFeedback.mediumImpact();
    await appDb.insert('INSERT INTO transactions (date, kind, amount, label) VALUES (?, ?, ?, ?)', [
      todayKey(),
      'saving',
      amount,
      _label.text.trim(),
    ]);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FormColumn(
      children: [
        const T('Tap an amount to drop it in.', dim: true),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final n in const [5.0, 10.0, 20.0, 50.0, 100.0])
              AppChip('+${widget.money(n)}', icon: Icons.savings_outlined, onPressed: () => _drop(n)),
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
          hint: 'Birthday money',
          textInputAction: TextInputAction.done,
        ),
        if (_error.isNotEmpty) T(_error, variant: TextVariant.small, color: c.danger),
        AppButton(
          'Drop it in',
          icon: Icons.savings_outlined,
          onPressed: () {
            final n = double.tryParse(_amount.text.replaceFirst(',', '.').replaceAll(RegExp(r'[^\d.]'), ''));
            if (n == null || !n.isFinite || n <= 0) return setState(() => _error = 'Enter an amount above zero.');
            _drop(n);
          },
        ),
      ],
    );
  }
}
