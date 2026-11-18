import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/*
 * The figure is drawn on a 200 × 400 grid with the centre line at x = 100.
 * Every path below is the figure's left half; the right half is the same path mirrored.
 */

const _gridWidth = 200.0, _gridHeight = 400.0;

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
  'M100.6 40L92.5 40'
  'C92.5 50 91 55 85 58' // neck into the trapezius
  'C77 61 67 62 60 65' // slope to the shoulder
  'C50 68 44 77 43 89' // deltoid
  'C42 101 41 111 39 123' // upper arm
  'C37 132 34 140 33 150' // elbow
  'C31 164 29 178 27 192' // forearm down to the wrist
  'C25 200 22 211 24 221' // hand
  'C26 229 33 228 35 220'
  'C37 213 38 205 38.5 197'
  'C42 183 46 167 48 153' // inner forearm
  'C49 143 52 135 54 125' // inner elbow
  'C56 115 58 107 60 99' // up to the armpit
  'C60 113 62 129 65 143' // ribs
  'C67 153 68 161 67 171' // waist
  'C65 182 62 194 61 207' // hip
  'C58 228 59 254 63 276' // outer thigh
  'C62 286 60 296 61 308' // knee
  'C61 328 65 348 68 366' // calf down to the ankle
  'C68 374 64 381 62 387' // foot
  'C61 393 70 395 85 395'
  'C89 395 89 389 87 383'
  'C85 376 84 370 84 364' // inner ankle
  'C87 346 90 328 90 310' // inner calf
  'C90 298 88 288 88 278' // inner knee
  'C90 254 94 228 98 206' // inner thigh
  'L100.6 204Z',
);

const _deltoid = 'M60 67C52 69 46 77 45.5 89C45.5 95 47 100 50 104C55 98 60 90 63.5 80C65 74 64 69 60 67Z';
const _forearm = [
  'M36 146.5C34 159 31.3 174 29.3 190L35 192.5C38 178 41.3 164 43 150C41.5 144.5 38.5 144.5 36 146.5Z',
  'M45 149.5C44 164 40.3 180 37 193L38.8 194C42.3 183 46.2 169 47.5 156C47.2 152.5 46.3 150.5 45 149.5Z',
];

class _Part {
  _Part(this.muscle, List<String> paths) : paths = [for (final d in paths) _svg(d)];
  final String muscle;
  final List<Path> paths;
}

final _front = [
  // The top of the trapezius shows from the front, either side of the neck.
  _Part('Back', ['M91.5 49C90.5 55 87 58.5 81 60.5L69 64.5C78 65 86 64 92.5 61Z']),
  _Part('Shoulders', [_deltoid]),
  _Part('Chest', ['M66.5 71C75 66.5 90 66.5 98.6 70.5V97C92 104 78 105 70.5 99C65 92 63.5 81 66.5 71Z']),
  _Part('Biceps', ['M50 107C46 117 44 127 46 139C49 142 53 140 55 135C58 126 60 116 60 107C57 103 53 104 50 107Z']),
  _Part('Forearms', _forearm),
  _Part('Core', [
    // Serratus, obliques, three pairs of abdominals, and the lower abdomen.
    'M65.5 104L73 108.5L72.5 113.5L66 110Z',
    'M66.3 113.5L73 117.5L72.6 122.5L67 119.5Z',
    'M67.2 123L73.2 126.5L73 131.5L68.2 129Z',
    'M75 107C74.5 119 72.5 129 70.5 135C69.5 143 69.5 151 70.5 159L83 169V109C80 109 77.5 108 75 107Z',
    'M88 105H98.6V117H88C86.6 117 85.5 116 85.5 114.5V107.5C85.5 106 86.6 105 88 105Z',
    'M88 120H98.6V132H88C86.6 132 85.5 131 85.5 129.5V122.5C85.5 121 86.6 120 88 120Z',
    'M88 135H98.6V147H88C86.6 147 85.5 146 85.5 144.5V137.5C85.5 136 86.6 135 88 135Z',
    'M85.5 150H98.6V179C93 177 88 171 85.5 164Z',
  ]),
  _Part('Quads', [
    // Outer sweep, the middle of the thigh, and the inner thigh narrowing to the knee.
    'M62.5 213C59.5 233 60.5 258 65.5 278C68 282.5 71.5 282.5 73.5 279C71.5 258 72 234 75.5 211.5C71 208.5 66 209.5 62.5 213Z',
    'M78 210.5C74.5 232 74.5 258 76.5 279C78.5 282.5 81.5 282.5 83 279C85.5 262 86 236 85 210.5C83 208.5 80 208.5 78 210.5Z',
    'M87.5 211C88.5 232 88.5 258 85.5 279.5C87 282 88.3 280 88.4 276C89.2 262 91 248 93 237C94.8 228 96.2 220 97 212C94.5 209.5 90.5 209.5 87.5 211Z',
  ]),
  _Part('Calves', [
    'M64 297C62 313 64 335 68 355L72 355C72 335 72 315 70 295C68 293 66 294 64 297Z',
    'M74 295C75 315 75 337 75 357L80 357C84 339 87.5 319 87.5 301C84 295 78 293 74 295Z',
  ]),
];

final _back = [
  _Part('Back', [
    // Trapezius, the muscles over the shoulder blade, lat, lower back.
    'M100.6 45C96 54 82 60 68 64.5C78 68 90 84 100.6 112Z',
    'M67 71C74 73 82 79 90 89C84 93 76 95 68 93C65 86 65 78 67 71Z',
    'M66 97C74 99 84 97 92 93C96 105 98 121 98.6 141L96 153L74 143C69 129 66 113 66 97Z',
    'M87 155L98.6 159V185C95 185 92 183 90 179C87.5 172 86.5 163 87 155Z',
  ]),
  _Part('Shoulders', [_deltoid]),
  _Part('Triceps', [
    'M49 106C46 117 44 128 46 139C48 141 50 140 51.5 137C52.5 127 52.5 115 52 105Z',
    'M54 105C54.5 115 54.5 127 53.5 137C56 133 58 125 60 107C58 104 56 104 54 105Z',
  ]),
  _Part('Forearms', _forearm),
  _Part('Glutes', ['M63.5 188C60.5 202 63.5 216 76.5 221C89.5 221 98.2 214 98.6 204V188C88 183 73.5 183 63.5 188Z']),
  _Part('Hamstrings', [
    'M62 226C60 246 62 264 66 274C70 277 73 277 76 275C74.5 258 74.5 242 76 229C71 229 66 228 62 226Z',
    'M78.5 229C77.5 244 77.5 260 79.5 275C82.5 275 85 273 86 269C89.5 256 93 242 95 227C90 229 84 229 78.5 229Z',
  ]),
  _Part('Calves', [
    // The two heads of the calf.
    'M63.5 292C60.5 310 63.5 330 70.5 346H75V289C70.5 288 66.5 289 63.5 292Z',
    'M77.5 289V346H80.5C86.5 330 89.5 310 87.5 292C84.5 289 80.5 288 77.5 289Z',
  ]),
];

List<_Part> _parts(String side) => side == 'front' ? _front : _back;

/// Which side shows more of [muscles]: 'front' or 'back'. The front wins a tie.
String bestSide(Iterable<String> muscles) {
  // The sliver of trapezius on the front does not make the front the place to look at the back.
  int shown(List<_Part> parts) => muscles.where((m) => parts.any((p) => p.muscle == m)).length;
  final front = muscles.where((m) => m != 'Back' && _front.any((p) => p.muscle == m)).length;
  return shown(_back) > front ? 'back' : 'front';
}

/// Invisible tap targets laid over the drawing. Later entries sit on top of earlier ones.
List<Rect> _both(double x, double y, double w, double h) => [
  Rect.fromLTWH(x, y, w, h),
  Rect.fromLTWH(_gridWidth - x - w, y, w, h),
];

final _shoulderHit = _both(41, 63, 24, 42);
final _upperArmHit = _both(38, 104, 23, 40);
final _forearmHit = _both(22, 144, 28, 50);

final _hits = <String, List<(String, List<Rect>)>>{
  'front': [
    ('Core', [const Rect.fromLTWH(65, 103, 70, 78)]),
    ('Chest', _both(65, 65, 35, 39)),
    ('Shoulders', _shoulderHit),
    ('Biceps', _upperArmHit),
    ('Forearms', _forearmHit),
    ('Quads', _both(57, 205, 43, 74)),
    ('Calves', _both(59, 288, 32, 76)),
  ],
  'back': [
    ('Back', [const Rect.fromLTWH(65, 44, 70, 140)]),
    ('Shoulders', _shoulderHit),
    ('Triceps', _upperArmHit),
    ('Forearms', _forearmHit),
    ('Glutes', _both(59, 185, 41, 38)),
    ('Hamstrings', _both(57, 224, 43, 56)),
    ('Calves', _both(59, 284, 32, 68)),
  ],
};

/// Whether [muscle] can be picked on [side] of the figure; some are on both.
/// The sliver of trapezius on the front does not count: the back is shown on the back.
bool muscleOnSide(String muscle, String side) => _hits[side]!.any((hit) => hit.$1 == muscle);

/// The figure alone, not tappable: a small picture of which muscles a workout trains.
/// [lit] muscles are drawn in the accent colour (or [litColor]).
class BodyFigure extends StatelessWidget {
  const BodyFigure({super.key, required this.side, required this.lit, this.litColor, this.height = 80});

  /// 'front' or 'back'.
  final String side;
  final Set<String> lit;
  final Color? litColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: _gridWidth * height / _gridHeight,
      height: height,
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _BodyPainter(
            parts: _parts(side),
            selected: null,
            lit: lit,
            stale: const [],
            body: Color.lerp(c.surface, c.text, 0.16)!,
            muscle: Color.lerp(c.surface, c.text, 0.3)!,
            litColor: litColor ?? c.accent,
            staleColor: c.warn,
            accent: c.accent,
            // At this size the lines between muscles would swallow them.
            gapWidth: 0.9,
          ),
        ),
      ),
    );
  }
}

/// A front or back muscle illustration whose groups can be tapped.
/// [planned] muscles (in the workout being looked at) are tinted with the accent; [stale] ones
/// (not trained recently) in amber, so both stand out.
class BodyMap extends StatelessWidget {
  const BodyMap({
    super.key,
    required this.side,
    required this.selected,
    required this.stale,
    required this.onSelect,
    this.planned = const {},
    this.height = 300,
  });

  /// 'front' or 'back'.
  final String side;
  final String? selected;
  final Set<String> planned;
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
                  parts: _parts(side),
                  selected: selected,
                  lit: planned,
                  stale: stale,
                  // The body sits a little above the card it is on; muscles a step above that.
                  body: Color.lerp(c.surface, c.text, 0.12)!,
                  muscle: Color.lerp(c.surface, c.text, 0.28)!,
                  litColor: Color.lerp(c.surface, c.accent, 0.5)!,
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
                  label: i == 0 ? '$muscle, $side${stale.contains(muscle) ? ', not trained recently' : ''}' : null,
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
    required this.lit,
    required this.stale,
    required this.body,
    required this.muscle,
    required this.litColor,
    required this.staleColor,
    required this.accent,
    this.gapWidth = 1.5,
  });

  final List<_Part> parts;
  final String? selected;
  final Set<String> lit;
  final List<String> stale;
  final Color body, muscle, litColor, staleColor, accent;
  final double gapWidth;

  bool get front => identical(parts, _front);

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
    // The head: a skull with a slightly narrower jaw.
    canvas.drawPath(
      _svg(
        'M100 4C109 4 115 11 115 21C115 29 113 36 109 41C106 44.5 103 46 100 46'
        'C97 46 94 44.5 91 41C87 36 85 29 85 21C85 11 91 4 100 4Z',
      ),
      skin,
    );
    _mirrored(canvas, () => canvas.drawPath(_silhouette, skin));

    // Kneecaps and collarbones: not muscles, but without them the figure reads as a mannequin.
    final bone = Paint()..color = Color.lerp(body, muscle, 0.45)!;
    _mirrored(canvas, () {
      if (front) {
        canvas.drawPath(_svg('M70 284C70 280 82 280 82 284C82 290 80 294 76 294C72 294 70 290 70 284Z'), bone);
        canvas.drawPath(_svg('M70 66.5C79 65.5 90 66 97 68.5L97 66.5C90 63.5 79 63.5 70 66.5Z'), bone);
      } else {
        canvas.drawPath(_svg('M69 280C72 284 80 284 84 280L83 277C79 280 73 280 70 277Z'), bone);
      }
    });

    // A thin line in the body colour keeps neighbouring muscles visibly apart.
    final gap = Paint()
      ..color = body
      ..style = PaintingStyle.stroke
      ..strokeWidth = gapWidth
      ..strokeJoin = StrokeJoin.round;
    for (final part in parts) {
      final fill = Paint()
        ..color = part.muscle == selected
            ? accent
            : lit.contains(part.muscle)
            ? litColor
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
      old.litColor != litColor ||
      old.staleColor != staleColor ||
      old.accent != accent ||
      old.lit.join() != lit.join() ||
      old.stale.join() != stale.join();
}
