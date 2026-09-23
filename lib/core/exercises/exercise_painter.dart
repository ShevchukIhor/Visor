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
    final ref = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.width * 0.005, ref);
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
    final halo = Paint()
      ..color = color.withValues(alpha: 0.10 + 0.18 * n)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + 36 * n);
    canvas.drawCircle(Offset(cx, cy), r * 1.5, halo);

    final img = nearFarGabor ? gaborImage : null;
    if (img != null) {
      // Gabor sphere: scales from small (far) to large (near), softening
      // slightly at the near end so the eye feels the defocus.
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      final paint = Paint()
        ..filterQuality = FilterQuality.high
        ..color = Colors.white.withValues(alpha: 0.95 - 0.25 * n);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        rect,
        paint,
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
        final rect = Rect.fromCircle(center: pos, radius: r);
        final paint = Paint()
          ..filterQuality = FilterQuality.high
          ..color = Colors.white.withValues(alpha: 0.95 * alpha);
        canvas.save();
        // Slow gentle rotation while drifting.
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(0.3 * math.sin(t0 * math.pi));
        canvas.translate(-pos.dx, -pos.dy);
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          rect,
          paint,
        );
        canvas.restore();
      } else {
        // Fallback soft orb until the Gabor image has decoded.
        final halo = Paint()
          ..color = color.withValues(alpha: 0.15 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
        canvas.drawCircle(pos, r * 1.6, halo);
        _dot(canvas, pos, r, color.withValues(alpha: 0.85 * alpha));
      }
    }
  }

  void _label(Canvas canvas, Size size, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 15,
          letterSpacing: 4,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height * 0.10));
  }

  void _dot(Canvas canvas, Offset pos, double r, Color c) {
    final p = Paint()..color = c;
    canvas.drawCircle(pos, r, p);
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
