import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'db.dart';
import 'theme.dart';
import 'ui.dart';

/// Every sketch has the same shape (width : height), so it draws the same in the editor and in the list.
const sketchAspect = 3 / 4;

/// One line of a sketch. Points and width are fractions of the canvas width, so a sketch scales to any size.
class Stroke {
  const Stroke(this.color, this.width, this.points);

  /// An ARGB colour, or 0 for "ink": the theme's text colour, so it reads in light and dark.
  final int color;
  final double width;
  final List<Offset> points;
}

/// Pen colours after ink. Like calendar categories, they are the same in every theme.
const _penColors = [0, 0xFFEF5350, 0xFFFFA726, 0xFF3DBE7F, 0xFF4F8CFF, 0xFFB57BFF];
const _thinnest = 0.004, _thickest = 0.045;

/// Points are stored flat: x, y, x, y, …
List<Offset> _points(List<num> flat) => [
  for (var i = 0; i + 1 < flat.length; i += 2) Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
];

/// Reads the `sketch` column of a note. Anything unreadable is an empty sketch.
List<Stroke> decodeSketch(String? json) {
  if (json == null || json.isEmpty) return [];
  try {
    final strokes = (jsonDecode(json) as Map<String, dynamic>)['strokes'] as List;
    return [
      for (final s in strokes.cast<Map<String, dynamic>>())
        Stroke(s['c'] as int, (s['w'] as num).toDouble(), _points((s['p'] as List).cast<num>())),
    ];
  } catch (_) {
    return [];
  }
}

String encodeSketch(List<Stroke> strokes) {
  double short(double v) => (v * 10000).round() / 10000;
  return jsonEncode({
    'strokes': [
      for (final s in strokes)
        {
          'c': s.color,
          'w': s.width,
          'p': [
            for (final p in s.points) ...[short(p.dx), short(p.dy)],
          ],
        },
    ],
  });
}

class SketchPainter extends CustomPainter {
  const SketchPainter(this.strokes, {required this.ink, this.live});

  final List<Stroke> strokes;
  final Color ink;

  /// The line being drawn right now.
  final Stroke? live;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width;
    canvas.clipRect(Offset.zero & size);
    for (final s in [...strokes, ?live]) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color == 0 ? ink : Color(s.color)
        ..strokeWidth = s.width * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final points = [for (final p in s.points) p * k];
      if (points.length == 1) {
        canvas.drawCircle(points.first, s.width * k / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      // Curves through the midpoints, so a quick stroke is smooth rather than a chain of straight bits.
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final mid = (points[i - 1] + points[i]) / 2;
        path.quadraticBezierTo(points[i - 1].dx, points[i - 1].dy, mid.dx, mid.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(SketchPainter old) => true;
}

/// Distance from [p] to the segment [a]–[b].
double _distance(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final length = ab.distanceSquared;
  if (length == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

bool _touches(Stroke s, Offset p) {
  final reach = 0.02 + s.width / 2;
  if (s.points.length == 1) return (p - s.points.first).distance <= reach;
  for (var i = 1; i < s.points.length; i++) {
    if (_distance(p, s.points[i - 1], s.points[i]) <= reach) return true;
  }
  return false;
}

/// Full-screen drawing page. Saves when closed; a blank untitled sketch is discarded.
class SketchEditor extends StatefulWidget {
  const SketchEditor({super.key, this.note});

  final Rec? note;

  @override
  State<SketchEditor> createState() => _SketchEditorState();
}

class _SketchEditorState extends State<SketchEditor> {
  late final _title = TextEditingController(text: widget.note?['title'] as String? ?? '');
  late bool _pinned = widget.note?['pinned'] == 1;
  bool _closing = false;

  /// Every state the drawing has been in; undo and redo step through it.
  late List<List<Stroke>> _history = [decodeSketch(widget.note?['sketch'] as String?)];
  int _at = 0;

  int _color = 0;
  double _width = 0.014;
  bool _erasing = false;

  /// The finger that is drawing; a second finger is ignored.
  int? _pointer;
  Stroke? _live;

  /// While the eraser is down: what is left so far.
  List<Stroke>? _erased;

  List<Stroke> get _strokes => _history[_at];

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _commit(List<Stroke> next) {
    _history = [..._history.take(_at + 1), next];
    _at++;
  }

  void _down(PointerDownEvent e, double k) {
    if (_pointer != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _pointer = e.pointer;
    final p = e.localPosition / k;
    setState(() {
      if (_erasing) {
        _erased = _strokes.where((s) => !_touches(s, p)).toList();
      } else {
        _live = Stroke(_color, _width, [p]);
      }
    });
  }

  void _move(PointerMoveEvent e, double k) {
    if (e.pointer != _pointer) return;
    final p = e.localPosition / k;
    if (_erasing) {
      final left = _erased!.where((s) => !_touches(s, p)).toList();
      if (left.length != _erased!.length) setState(() => _erased = left);
    } else if ((p - _live!.points.last).distance > 0.003) {
      setState(() => _live!.points.add(p));
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    setState(() {
      if (_live != null) {
        _commit([..._strokes, _live!]);
      } else if (_erased != null && _erased!.length != _strokes.length) {
        _commit(_erased!);
      }
      _live = null;
      _erased = null;
    });
  }

  Future<void> _saveAndClose() async {
    if (_closing) return;
    _closing = true;
    final note = widget.note;
    final title = _title.text.trim();
    final sketch = encodeSketch(_strokes);
    final empty = title.isEmpty && _strokes.isEmpty;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (note != null && empty) {
      await appDb.run('DELETE FROM notes WHERE id = ?', [note['id']]);
    } else if (note != null) {
      final changed = title != note['title'] || sketch != note['sketch'];
      await appDb.run('UPDATE notes SET title = ?, sketch = ?, pinned = ?, updated_at = ? WHERE id = ?', [
        title,
        sketch,
        _pinned ? 1 : 0,
        changed ? now : note['updated_at'],
        note['id'],
      ]);
    } else if (!empty) {
      await appDb.insert('INSERT INTO notes (title, sketch, pinned, updated_at) VALUES (?, ?, ?, ?)', [
        title,
        sketch,
        _pinned ? 1 : 0,
        now,
      ]);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (_closing) return;
    _closing = true;
    await deleteWithUndo('notes', widget.note!, 'Sketch deleted');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = _erased ?? _strokes;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndClose();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Spacing.sm,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Row(
                    spacing: Spacing.sm,
                    children: [
                      AppButton('‹ Done', kind: ButtonKind.plain, small: true, onPressed: _saveAndClose),
                      const Spacer(),
                      AppButton(
                        _pinned ? 'Pinned ✓' : 'Pin',
                        kind: ButtonKind.soft,
                        small: true,
                        onPressed: () => setState(() => _pinned = !_pinned),
                      ),
                      if (widget.note != null)
                        AppButton('Delete', kind: ButtonKind.danger, small: true, onPressed: _delete),
                    ],
                  ),
                ),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.text),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Sketch title',
                    hintStyle: TextStyle(color: c.textDim),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: sketchAspect,
                      child: LayoutBuilder(
                        builder: (context, box) => Listener(
                          key: const Key('sketch-canvas'),
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (e) => _down(e, box.maxWidth),
                          onPointerMove: (e) => _move(e, box.maxWidth),
                          onPointerUp: _up,
                          onPointerCancel: _up,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(Radii.md),
                              border: Border.all(color: c.border, width: 0.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Radii.md),
                              child: CustomPaint(
                                painter: SketchPainter(shown, ink: c.text, live: _live),
                                child: shown.isEmpty && _live == null
                                    ? Center(child: T('Draw with your finger', dim: true))
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final color in _penColors)
                      _Tool(
                        label: 'Pen colour',
                        selected: !_erasing && color == _color,
                        onTap: () => setState(() {
                          _color = color;
                          _erasing = false;
                        }),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(color: color == 0 ? c.text : Color(color), shape: BoxShape.circle),
                        ),
                      ),
                    AppChip(
                      'Erase',
                      icon: Icons.backspace_outlined,
                      selected: _erasing,
                      onPressed: () => setState(() => _erasing = !_erasing),
                    ),
                  ],
                ),
                Row(
                  spacing: Spacing.sm,
                  children: [
                    // A dot the size the pen will draw, then the slider that sets it.
                    SizedBox(
                      width: 24,
                      height: 40,
                      child: Center(
                        child: Container(
                          width: 3 + 19 * (_width - _thinnest) / (_thickest - _thinnest),
                          height: 3 + 19 * (_width - _thinnest) / (_thickest - _thinnest),
                          decoration: BoxDecoration(
                            color: _color == 0 ? c.text : Color(_color),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: c.accent,
                          inactiveTrackColor: c.border,
                          thumbColor: c.accent,
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                        ),
                        child: Slider(
                          key: const Key('pen-width'),
                          semanticFormatterCallback: (v) => 'Pen width ${(100 * v / _thickest).round()}%',
                          min: _thinnest,
                          max: _thickest,
                          value: _width,
                          onChanged: (v) => setState(() {
                            _width = v;
                            _erasing = false;
                          }),
                        ),
                      ),
                    ),
                    _Tool(
                      label: 'Undo',
                      onTap: _at > 0 ? () => setState(() => _at--) : null,
                      child: Icon(Icons.undo, size: 21, color: c.text),
                    ),
                    _Tool(
                      label: 'Redo',
                      onTap: _at < _history.length - 1 ? () => setState(() => _at++) : null,
                      child: Icon(Icons.redo, size: 21, color: c.text),
                    ),
                    _Tool(
                      label: 'Clear the sketch',
                      // Clearing is one more step in the history, so Undo brings the drawing back.
                      onTap: _strokes.isNotEmpty ? () => setState(() => _commit(const [])) : null,
                      child: Icon(Icons.delete_sweep_outlined, size: 21, color: c.danger),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A square button in the drawing toolbar. Faded when [onTap] is null.
class _Tool extends StatelessWidget {
  const _Tool({required this.label, required this.child, required this.onTap, this.selected = false});

  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: Material(
          color: c.surfaceAlt,
          shape: buttonShape.copyWith(
            side: BorderSide(color: selected ? c.accent : c.border, width: selected ? 2 : 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    tick();
                    onTap!();
                  },
            child: SizedBox(width: 40, height: 40, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}
