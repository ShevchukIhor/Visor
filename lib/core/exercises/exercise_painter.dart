import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Eye exercise definitions. Each exercise animates a point along a path,
/// which drives vergence/accommodation/saccadic/pursuit training.
enum ExerciseType {
  convergence('Convergence Training',
      'Train your eyes to converge and diverge together'),
  nearFar('Near-Far Cycles',
      'Alternating near/far focus with timed holds — trains accommodation'),
  focusShift('Focus Shifting',
      'Jump your focus between widely spaced targets'),
  saccadic('Saccadic Jumps',
      'Jump your eyes rapidly between target positions'),
  pursuit('Smooth Pursuit',
      'Follow a dot as it glides along a curved path'),
  figure8('Figure-8 Tracking', 'Track a moving point with your eyes'),
  peripheral('Peripheral Awareness',
      'Detect brief flashes at the edges without moving your eyes'),
  orbs('Floating Orbs',
      'Gabor patches drift and slowly grow — relax and follow them');

  const ExerciseType(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

/// Normalized position in [0,1]×[0,1] for the moving target at progress t∈[0,1].
Offset exercisePath(ExerciseType type, double t) {
  const c = Offset(0.5, 0.5);
  switch (type) {
    case ExerciseType.convergence:
      // Move toward/away from the nose (center, slightly lower).
      final r = 0.5 * (0.5 - 0.5 * math.cos(2 * math.pi * t));
      return Offset(c.dx, c.dy + r * math.sin(2 * math.pi * t));
    case ExerciseType.nearFar:
      // Size-driven accommodation exercise — position stays centered.
      return c;
    case ExerciseType.focusShift:
      return focusShiftPoint(t);
    case ExerciseType.saccadic:
      // Pseudo-random jumps (deterministic hash so it's smooth per tick).
      final i = (t * 10).floor();
      final x = 0.15 + 0.7 * _hash(i);
      final y = 0.15 + 0.7 * _hash(i * 31 + 7);
      return Offset(x, y);
    case ExerciseType.pursuit:
      // Smooth curve (Lissajous-like).
      return Offset(
        0.5 + 0.35 * math.sin(2 * math.pi * t),
        0.5 + 0.3 * math.sin(4 * math.pi * t),
      );
    case ExerciseType.figure8:
      // Lemniscate (infinity) path.
      final a = 2 * math.pi * t;
      final denom = 1 + math.sin(a) * math.sin(a);
      return Offset(
        0.5 + 0.35 * math.cos(a) / denom,
        0.5 + 0.35 * math.sin(a) * math.cos(a) / denom,
      );
    case ExerciseType.peripheral:
      // Peripheral flashes — point stays center, ring flashes at edges.
      return c;
    case ExerciseType.orbs:
      return c;
  }
}

/// Focus Shifting: anchor points spread wide across the screen, cycling
/// through several different diagonals so the eye never repeats one line.
Offset focusShiftPoint(double t) {
  const pairs = [
    [Offset(0.12, 0.16), Offset(0.88, 0.84)], // main diagonal ↘
    [Offset(0.88, 0.18), Offset(0.12, 0.82)], // anti-diagonal ↙
    [Offset(0.10, 0.62), Offset(0.90, 0.38)], // shallow diagonal
    [Offset(0.30, 0.90), Offset(0.70, 0.10)], // steep diagonal
  ];
  final leg = (t * 8).floor();
  final pair = pairs[(leg >> 1) % pairs.length];
  return pair[leg & 1];
}

/// Near↔Far accommodation cycle mapped from loop progress t∈[0,1], paced
/// like a deep breath: steady "inhale" (approach), a held pause up close,
/// a slower "exhale" (retreat), and a rest before the next cycle.
/// Returns 0.0 = far (small, sharp target) … 1.0 = near (large, soft).
double nearFarPhase(double t) {
  const farHold = 0.30; // steady far view
  const inhale = 0.20; // even, deep approach
  const nearHold = 0.15; // pause up close
  const exhale = 0.30; // slow retreat
  // the remaining 5% is the far rest before the next cycle (patch swap)
  if (t < farHold) return 0.0;
  if (t < farHold + inhale) {
    return _smooth((t - farHold) / inhale);
  }
  if (t < farHold + inhale + nearHold) return 1.0;
  if (t < farHold + inhale + nearHold + exhale) {
    return _smooth(1.0 - (t - farHold - inhale - nearHold) / exhale);
  }
  return 0.0; // far rest
}

/// Pseudo-random flash angle (radians) on the peripheral ring for flash
/// slot [slot] within session [seed]. Deliberately NOT clockwise-ordered.
double peripheralAngle(int slot, int seed) {
  return _hash(slot * 131 + seed * 7919 + 17) * 2 * math.pi;
}

/// Duration (seconds) of one orb's small→large→fade cycle.
const double kOrbCycleSeconds = 24.0;

/// Random waypoint for an orb trajectory (normalized, with margins).
/// [end] 0 = cycle start point, 1 = cycle end point.
Offset orbWaypoint(int cycle, int orbIndex, int end, int seed) {
  final h1 = _hash(cycle * 37 + orbIndex * 101 + end * 17 + seed * 7 + 3);
  final h2 = _hash(cycle * 53 + orbIndex * 211 + end * 23 + seed * 13 + 5);
  return Offset(0.15 + 0.7 * h1, 0.15 + 0.7 * h2);
}

/// Deterministic pseudo-random in [0,1].
double _hash(int n) {
  final x = math.sin(n * 12.9898) * 43758.5453;
  return x - x.floor();
}

/// Hermite smoothstep in [0,1].
double _smooth(double u) {
  final v = u.clamp(0.0, 1.0);
  return v * v * (3 - 2 * v);
}

/// Sinusoidal ease in/out in [0,1].
double _easeInOut(double u) =>
    0.5 - 0.5 * math.cos(math.pi * u.clamp(0.0, 1.0));

/// Animation painter for a single exercise.
class ExercisePainter extends CustomPainter {
  final ExerciseType type;
  final double progress; // 0..1
  final Color color;

  /// Session-level random seed for pseudo-random paths (peripheral/orbs).
  final int seed;

  /// Elapsed seconds since the screen opened (drives the orbs' slow cycles,
  /// independent of the 8s repeating animation loop).
  final double orbsTime;

  /// Pre-rendered circular Gabor patch image (Floating Orbs, and Near-Far
  /// when [nearFarGabor] is on).
  final ui.Image? gaborImage;

  /// Near-Far only: draw the target as a Gabor sphere instead of a round dot.
  final bool nearFarGabor;

  ExercisePainter(
    this.type,
    this.progress, {
    this.color = const Color(0xFF4D9FFF),
    this.seed = 0,
    this.orbsTime = 0,
    this.gaborImage,
    this.nearFarGabor = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (type == ExerciseType.nearFar) {
      _paintNearFar(canvas, size);
      return;
    }
    if (type == ExerciseType.peripheral) {
      _paintPeripheral(canvas, size);
      return;
    }
    if (type == ExerciseType.orbs) {
      _paintOrbs(canvas, size);
      return;
    }

    final p = exercisePath(type, progress);
    final center = Offset(p.dx * size.width, p.dy * size.height);

    // Default: smooth moving dot with a faint guidance ring in the center.
    _dot(canvas, center, size.width * 0.03, color);
    _refPaint.color = color.withValues(alpha: 0.1);
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.width * 0.005, _refPaint);
  }

  /// Accommodation drill: the target is small and sharp when "far" and
  /// grows into a large soft disc when "near", holding at each extreme.
  void _paintNearFar(Canvas canvas, Size size) {
    final n = nearFarPhase(progress);
    final cx = size.width / 2;
    final cy = size.height / 2;

    final minR = size.shortestSide * 0.018;
    final maxR = size.shortestSide * 0.30;
    final r = minR + (maxR - minR) * n;

    // Soft halo that blooms as the target comes "near".
    _glow(canvas, Offset(cx, cy), r * 1.5, 12 + 36 * n,
        color.withValues(alpha: 0.10 + 0.18 * n));

    final img = nearFarGabor ? gaborImage : null;
    if (img != null) {
      // Gabor sphere: scales from small (far) to large (near), softening
      // slightly at the near end so the eye feels the defocus.
      _gaborPaint.color = Colors.white.withValues(alpha: 0.95 - 0.25 * n);
      canvas.drawImageRect(
        img,
        _srcRect(img),
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        _gaborPaint,
      );
    } else {
      // Main disc: crisp when far, softer when near.
      _dot(canvas, Offset(cx, cy), r, color.withValues(alpha: 0.95 - 0.30 * n));
    }

    _label(
      canvas,
      size,
      n < 0.5 ? 'FAR' : 'NEAR',
      color.withValues(alpha: 0.55),
    );
  }

  /// Central fixation dot plus a brief flash at a random angle on a ring.
  void _paintPeripheral(Canvas canvas, Size size) {
    _dot(canvas, Offset(size.width / 2, size.height / 2), 6, color);
    final slot = (progress * 8).floor();
    final flashAngle = peripheralAngle(slot, seed);
    final ringR = size.width * 0.42;
    final flashPos = Offset(
      size.width / 2 + ringR * math.cos(flashAngle),
      size.height / 2 + ringR * math.sin(flashAngle),
    );
    final flashPhase = progress * 8 - slot; // blink within slot
    if (flashPhase < 0.5) {
      _dot(canvas, flashPos, 8, color.withValues(alpha: 0.9));
    }
  }

  /// Two Gabor "orbs" in antiphase; each spawns small at a random point,
  /// drifts along a random path while slowly growing, then fades out.
  void _paintOrbs(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    final minR = shortest * 0.05;
    final maxR = shortest * 0.15; // matches the Gabor patches in the game

    for (var i = 0; i < 2; i++) {
      final t0 = orbsTime / kOrbCycleSeconds + i * 0.5;
      final cycle = t0.floor();
      final p = t0 - cycle;

      // Fade in over the first 12%, fade out over the last 12%.
      final alpha = (p / 0.12).clamp(0.0, 1.0) *
          ((1.0 - p) / 0.12).clamp(0.0, 1.0);
      if (alpha <= 0) continue;

      final growth = _easeInOut(p / 0.9);
      final r = minR + (maxR - minR) * growth;

      final a = orbWaypoint(cycle, i, 0, seed);
      final b = orbWaypoint(cycle, i, 1, seed);
      final drift = _smooth(p);
      final pos = Offset(
        (a.dx + (b.dx - a.dx) * drift) * size.width,
        (a.dy + (b.dy - a.dy) * drift) * size.height,
      );

      final img = gaborImage;
      if (img != null) {
        _gaborPaint.color = Colors.white.withValues(alpha: 0.95 * alpha);
        canvas.save();
        // Slow gentle rotation while drifting.
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(0.3 * math.sin(t0 * math.pi));
        canvas.translate(-pos.dx, -pos.dy);
        canvas.drawImageRect(
          img,
          _srcRect(img),
          Rect.fromCircle(center: pos, radius: r),
          _gaborPaint,
        );
        canvas.restore();
      } else {
        // Fallback soft orb until the Gabor image has decoded.
        _glow(canvas, pos, r * 1.6, 18, color.withValues(alpha: 0.15 * alpha));
        _dot(canvas, pos, r, color.withValues(alpha: 0.85 * alpha));
      }
    }
  }

  /// Paints reused every frame. `paint` runs once per frame on the UI
  /// thread, so a static Paint costs nothing and spares the GC one object
  /// per frame per call — at 121 frames/s those add up to a scavenger run
  /// every few seconds, and each run is one dropped frame.
  static final Paint _glowPaint = Paint();
  static final Paint _dotPaint = Paint();
  static final Paint _refPaint = Paint()
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  static final Paint _gaborPaint = Paint()..filterQuality = FilterQuality.high;

  /// Gradient stop storage, mutated in place each frame: `Gradient.radial`
  /// copies both lists synchronously, so sharing them across frames is safe
  /// and spares two list allocations per frame.
  static final List<Color> _glowColors =
      [const Color(0x00000000), const Color(0x00000000), const Color(0x00000000)];
  static final List<double> _glowStops = [0, 0, 0];

  /// Source rects for Gabor images, cached by dimension (they never change
  /// once decoded).
  static final Map<String, Rect> _srcRects = {};

  /// Laid-out label paragraphs, cached by (text, color, width). The label
  /// only ever switches between FAR and NEAR, so laying it out once per pair
  /// keeps the 120Hz paint path free of text layout — the most expensive
  /// CPU op this painter used to do every frame.
  static final Map<String, ui.Paragraph> _labelCache = {};

  ui.Paragraph _labelParagraph(String text, Color color, double width) {
    final key = '$text|${color.toARGB32()}|${width.round()}';
    final cached = _labelCache[key];
    if (cached != null) return cached;
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
    )
      ..pushStyle(ui.TextStyle(
        color: color,
        fontSize: 16,
        letterSpacing: 4,
        fontWeight: ui.FontWeight.w600,
      ))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    if (_labelCache.length >= 8) {
      // Bound the cache: the app uses two entries, tests a few more.
      _labelCache.remove(_labelCache.keys.first)?.dispose();
    }
    _labelCache[key] = paragraph;
    return paragraph;
  }

  void _label(Canvas canvas, Size size, String text, Color color) {
    final p = _labelParagraph(text, color, size.width);
    canvas.drawParagraph(
      p,
      Offset((size.width - p.longestLine) / 2, size.height * 0.10),
    );
  }

  /// Soft glow as a radial-gradient disc: the same look as a
  /// Gaussian-blurred circle, but a single-pass GPU shader instead of a
  /// per-frame multi-pass blur over a disc that is up to two-thirds of the
  /// screen wide. [r] is the core radius and [sigma] the blur radius the
  /// old `MaskFilter.blur` used, so the falloff matches: the edge spreads
  /// over roughly ±2σ.
  void _glow(
      Canvas canvas, Offset center, double r, double sigma, Color color) {
    final outer = r + 2 * sigma;
    _glowColors[0] = color;
    _glowColors[1] = color.withValues(alpha: color.a * 0.5);
    _glowColors[2] = color.withValues(alpha: 0);
    _glowStops[0] = math.max(0.0, (r - 2 * sigma) / outer);
    _glowStops[1] = r / outer;
    _glowStops[2] = 1.0;
    _glowPaint.shader = ui.Gradient.radial(center, outer, _glowColors, _glowStops);
    canvas.drawCircle(center, outer, _glowPaint);
  }

  /// The full-bleed source rect of a decoded Gabor image, cached by
  /// dimension.
  Rect _srcRect(ui.Image img) {
    final key = '${img.width}x${img.height}';
    final cached = _srcRects[key];
    if (cached != null) return cached;
    final rect = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    _srcRects[key] = rect;
    return rect;
  }

  void _dot(Canvas canvas, Offset pos, double r, Color c) {
    _dotPaint.color = c;
    canvas.drawCircle(pos, r, _dotPaint);
  }

  @override
  bool shouldRepaint(covariant ExercisePainter old) =>
      old.progress != progress ||
      old.type != type ||
      old.color != color ||
      old.seed != seed ||
      old.orbsTime != orbsTime ||
      old.gaborImage != gaborImage ||
      old.nearFarGabor != nearFarGabor;
}
