import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/*
 * The figure is drawn on a 200 × 384 grid with the centre line at x = 100.
 * Every path below is the figure's left half; the right half is the same path mirrored.
 */

const _gridWidth = 200.0, _gridHeight = 384.0;

/// Builds a path from SVG path data. Understands absolute M, L, H, V, C and Z only.
Path _svg(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLHVCZ]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m[0]!).toList();
  var i = 0;
  var x = 0.0, y = 0.0;
  var command = '';
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if ('MLHVCZ'.contains(tokens[i])) {
      command = tokens[i++];
      if (command == 'Z') path.close();
      continue;
    }
    switch (command) {
      case 'M':
        x = next();
        y = next();
        path.moveTo(x, y);
        command = 'L';
      case 'L':
        x = next();
        y = next();
        path.lineTo(x, y);
      case 'H':
        x = next();
        path.lineTo(x, y);
      case 'V':
        y = next();
        path.lineTo(x, y);
      case 'C':
        final x1 = next(), y1 = next(), x2 = next(), y2 = next();
        x = next();
        y = next();
        path.cubicTo(x1, y1, x2, y2, x, y);
      default:
        throw FormatException('Unsupported path data: $d');
    }
  }
  return path;
}

/// One half of the body as a single outline: neck, shoulder, arm and hand, back up to the armpit,
/// then down the side of the torso, round the leg and foot, and up the inner leg to the centre line.
final _silhouette = _svg(
  'M100.6 40L92 40'
  'C92 46 91 50 86 52' // neck into the trapezius
  'C78 55 68 56 61 59' // slope to the shoulder
  'C52 62 47 70 46 82' // deltoid
  'C45 94 44 104 42 116' // upper arm
  'C40 124 37 132 36 142' // elbow and forearm
  'C35 154 33 164 31 174' // down to the wrist
  'C29 180 27 188 29 196' // hand
  'C31 201 36 200 38 194'
  'C40 188 41 182 41 176'
  'C44 164 48 152 50 140' // inner forearm
  'C51 132 53 126 55 118' // inner elbow
  'C57 108 59 100 61 92' // up to the armpit
  'C62 106 64 122 66 136' // ribs
  'C67 146 67 154 65 164' // waist
  'C62 176 59 190 58 204' // hip
  'C57 222 59 246 63 266' // outer thigh
  'C62 276 60 286 61 298' // knee and calf
  'C62 318 66 336 68 352' // down to the ankle
  'C67 360 63 368 62 374' // foot
  'C62 379 70 380 86 380'
  'C88 380 88 374 86 370'
  'C84 362 83 356 83 350' // inner ankle
  'C85 334 88 316 88 300' // inner calf
  'C88 288 86 278 86 268' // inner knee
  'C88 246 93 220 98 198' // inner thigh
  'L100.6 196Z',
);

const _deltoid = 'M61 61C53 63 48 71 48 82C48 88 50 92 53 95C57 90 61 83 64 73C65 67 64 63 61 61Z';
const _upperArm = 'M49 98C46 108 44 118 46 128C49 131 52 129 54 125C57 116 59 107 59 99C56 96 52 96 49 98Z';
const _forearm = 'M40 135C38 146 36 158 34 169L40 171C43 161 47 150 49 139C47 134 43 133 40 135Z';

class _Part {
  _Part(this.muscle, List<String> paths) : paths = [for (final d in paths) _svg(d)];
  final String muscle;
  final List<Path> paths;
}

final _front = [
  _Part('Shoulders', [_deltoid]),
  _Part('Chest', ['M67 68C76 63 90 63 98.6 67V93C91 100 77 100 70 94C65 87 64 76 67 68Z']),
  _Part('Biceps', [_upperArm]),
  _Part('Forearms', [_forearm]),
  _Part('Core', [
    // Obliques, three pairs of abdominals, and the lower abdomen.
    'M68 101C67 118 67 136 69 153L82 165V104C77 105 72 104 68 101Z',
    'M88 103H98.6V115H88C86.6 115 85.5 114 85.5 112.5V105.5C85.5 104 86.6 103 88 103Z',
    'M88 118H98.6V130H88C86.6 130 85.5 129 85.5 127.5V120.5C85.5 119 86.6 118 88 118Z',
    'M88 133H98.6V145H88C86.6 145 85.5 144 85.5 142.5V135.5C85.5 134 86.6 133 88 133Z',
    'M85.5 148H98.6V174C93 172 88 167 85.5 161Z',
  ]),
  _Part('Quads', [
    // Outer and inner thigh.
    'M61 201C59 222 61 246 66 263C70 266 74 266 77 264C74 244 73 222 75 199C70 198 65 199 61 201Z',
    'M78 199C76 222 77 244 80 264C83 264 85 262 86 258C90 243 95 222 97 203C91 199 84 198 78 199Z',
  ]),
  _Part('Calves', ['M65 281C63 298 65 322 69 343H79C83 322 86 300 86 281C80 277 71 277 65 281Z']),
];

final _back = [
  _Part('Back', [
    // Trapezius, lat, lower back.
    'M100.6 43C95 50 80 55 67 59C78 64 90 78 100.6 100Z',
    'M67 72C65 94 67 118 73 138L96 150C98 132 98 116 97 104C88 92 78 80 69 68Z',
    'M86 154H100.6V176H88C86 170 85 162 86 154Z',
  ]),
  _Part('Shoulders', [_deltoid]),
  _Part('Triceps', [_upperArm]),
  _Part('Forearms', [_forearm]),
  _Part('Glutes', ['M63 179C60 193 64 206 77 210C90 210 98 204 99 194V179C88 175 73 175 63 179Z']),
  _Part('Hamstrings', [
    'M61 216C60 236 62 253 66 263C70 266 74 266 77 264C75 248 75 232 76 219C71 219 66 218 61 216Z',
    'M79 219C78 234 78 250 80 264C83 264 85 262 86 258C90 246 93 232 95 217C90 219 84 219 79 219Z',
  ]),
  _Part('Calves', [
    // The two heads of the calf.
    'M63 279C60 296 63 316 70 332H74.5V276C70 275 66 276 63 279Z',
    'M77 276V332H80C86 316 89 296 86 279C83 276 80 275 77 276Z',
  ]),
];

/// Which side of the figure a muscle is drawn on; some are on both.
bool muscleOnSide(String muscle, String side) =>
    (side == 'front' ? _front : _back).any((part) => part.muscle == muscle);

/// Invisible tap targets laid over the drawing. Later entries sit on top of earlier ones.
List<Rect> _both(double x, double y, double w, double h) => [
  Rect.fromLTWH(x, y, w, h),
  Rect.fromLTWH(_gridWidth - x - w, y, w, h),
];

final _shoulderHit = _both(43, 57, 23, 40);
final _upperArmHit = _both(39, 96, 22, 37);
final _forearmHit = _both(28, 133, 24, 44);

final _hits = <String, List<(String, List<Rect>)>>{
  'front': [
    ('Core', [const Rect.fromLTWH(66, 100, 68, 76)]),
    ('Chest', _both(66, 62, 34, 38)),
    ('Shoulders', _shoulderHit),
    ('Biceps', _upperArmHit),
    ('Forearms', _forearmHit),
    ('Quads', _both(57, 196, 43, 72)),
    ('Calves', _both(59, 274, 31, 74)),
  ],
  'back': [
    ('Back', [const Rect.fromLTWH(66, 42, 68, 136)]),
    ('Shoulders', _shoulderHit),
    ('Triceps', _upperArmHit),
    ('Forearms', _forearmHit),
    ('Glutes', _both(59, 177, 41, 36)),
    ('Hamstrings', _both(57, 214, 43, 54)),
    ('Calves', _both(59, 272, 31, 64)),
  ],
};

/// A front or back muscle illustration whose groups can be tapped.
/// [stale] muscles (not trained recently) are tinted so they stand out.
class BodyMap extends StatelessWidget {
  const BodyMap({
    super.key,
    required this.side,
    required this.selected,
    required this.stale,
    required this.onSelect,
    this.height = 300,
  });

  /// 'front' or 'back'.
  final String side;
  final String? selected;
  final List<String> stale;
  final ValueChanged<String> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scale = height / _gridHeight;
    return SizedBox(
      width: _gridWidth * scale,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _BodyPainter(
                  parts: side == 'front' ? _front : _back,
                  selected: selected,
                  stale: stale,
                  // The body sits a little above the card it is on; muscles a step above that.
                  body: Color.lerp(c.surface, c.text, 0.11)!,
                  muscle: Color.lerp(c.surface, c.text, 0.27)!,
                  staleColor: Color.lerp(c.surface, c.warn, 0.8)!,
                  accent: c.accent,
                ),
              ),
            ),
          ),
          for (final (muscle, boxes) in _hits[side]!)
            for (final (i, b) in boxes.indexed)
              Positioned(
                left: b.left * scale,
                top: b.top * scale,
                width: b.width * scale,
                height: b.height * scale,
                // Only the first of a mirrored pair is announced, so screen readers hear each muscle once.
                child: Semantics(
                  button: i == 0,
                  selected: i == 0 ? muscle == selected : null,
                  label: i == 0 ? '$muscle${stale.contains(muscle) ? ', not trained recently' : ''}' : null,
                  excludeSemantics: i != 0,
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onSelect(muscle)),
                ),
              ),
        ],
      ),
    );
  }
}

class _BodyPainter extends CustomPainter {
  const _BodyPainter({
    required this.parts,
    required this.selected,
    required this.stale,
    required this.body,
    required this.muscle,
    required this.staleColor,
    required this.accent,
  });

  final List<_Part> parts;
  final String? selected;
  final List<String> stale;
  final Color body, muscle, staleColor, accent;

  /// Draws once as given and once flipped across the centre line.
  void _mirrored(Canvas canvas, VoidCallback draw) {
    draw();
    canvas.save();
    canvas.translate(_gridWidth, 0);
    canvas.scale(-1, 1);
    draw();
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _gridWidth);

    final skin = Paint()..color = body;
    canvas.drawOval(Rect.fromCenter(center: const Offset(100, 23), width: 29, height: 38), skin);
    _mirrored(canvas, () => canvas.drawPath(_silhouette, skin));

    // A thin line in the body colour keeps neighbouring muscles visibly apart.
    final gap = Paint()
      ..color = body
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    for (final part in parts) {
      final fill = Paint()
        ..color = part.muscle == selected
            ? accent
            : stale.contains(part.muscle)
            ? staleColor
            : muscle;
      _mirrored(canvas, () {
        for (final path in part.paths) {
          canvas.drawPath(path, fill);
          canvas.drawPath(path, gap);
        }
      });
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.parts != parts ||
      old.selected != selected ||
      old.body != body ||
      old.muscle != muscle ||
      old.staleColor != staleColor ||
      old.accent != accent ||
      old.stale.join() != stale.join();
}
