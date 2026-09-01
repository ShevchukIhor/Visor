import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Eye exercise definitions. Each exercise animates a point along a path,
/// which drives vergence/accommodation/saccadic/pursuit training.
enum ExerciseType {
  convergence('Convergence Training',
      'Train your eyes to converge and diverge together'),
  nearFar('Near-Far Cycles',
      'Structured alternating near/far focus with timed countdowns'),
  focusShift('Focus Shifting',
      'Alternate focus between near and far objects'),
  saccadic('Saccadic Jumps',
      'Jump your eyes rapidly between target positions'),
  pursuit('Smooth Pursuit',
      'Follow a dot as it glides along a curved path'),
  figure8('Figure-8 Tracking', 'Track a moving point with your eyes'),
  peripheral('Peripheral Awareness',
      'Detect brief dots at the edges without moving your eyes'),
  orbs('Floating Orbs',
      'Softly glowing orbs drift away — relaxes tired eyes');

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
      // Alternate near (large, fast outward) and far (small, inward).
      final r = 0.3 + 0.2 * math.sin(2 * math.pi * t);
      return Offset(c.dx, c.dy - r);
    case ExerciseType.focusShift:
      // Jump between two anchor points.
      final i = (t * 8).floor() % 2;
      return i == 0 ? const Offset(0.3, 0.4) : const Offset(0.7, 0.6);
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
      // Drift toward viewer (scale grows) along a slow arc.
      return Offset(
        0.5 + 0.1 * math.sin(2 * math.pi * t),
        0.5 + 0.1 * math.cos(2 * math.pi * t),
      );
  }
}

/// Deterministic pseudo-random in [0,1].
double _hash(int n) {
  final x = math.sin(n * 12.9898) * 43758.5453;
  return x - x.floor();
}

/// Animation painter for a single exercise.
class ExercisePainter extends CustomPainter {
  final ExerciseType type;
  final double progress; // 0..1
  final Color color;

  ExercisePainter(this.type, this.progress, {this.color = const Color(0xFF4D9FFF)});

  @override
  void paint(Canvas canvas, Size size) {
    final p = exercisePath(type, progress);
    final center = Offset(p.dx * size.width, p.dy * size.height);

    if (type == ExerciseType.peripheral) {
      // Central fixation point + peripheral flash ring.
      _dot(canvas, Offset(size.width / 2, size.height / 2), 6, color);
      final flashIndex = (progress * 8).floor();
      final flashAngle = flashIndex * (2 * math.pi / 8);
      final ringR = size.width * 0.42;
      final flashPos = Offset(
        size.width / 2 + ringR * math.cos(flashAngle),
        size.height / 2 + ringR * math.sin(flashAngle),
      );
      final flashPhase = progress * 8 - flashIndex; // blink within slot
      if (flashPhase < 0.5) {
        _dot(canvas, flashPos, 8, color.withOpacity(0.9));
      }
      return;
    }

    if (type == ExerciseType.orbs) {
      // Glowing orb with soft halo, size grows as it "approaches".
      final grow = 0.5 + progress; // 0.5..1.5 scale
      final radius = (10 * grow).clamp(6.0, 22.0);
      final halo = Paint()
        ..color = color.withOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(center, radius * 1.8, halo);
      _dot(canvas, center, radius, color.withOpacity(0.85));
      return;
    }

    // Default: smooth moving dot with a faint trail/manual guidance ring.
    _dot(canvas, center, size.width * 0.03, color);
    // Optional small crosshair at center for focus reference.
    final ref = Paint()
      ..color = color.withOpacity(0.1)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.width * 0.005, ref);
  }

  void _dot(Canvas canvas, Offset pos, double r, Color c) {
    final p = Paint()..color = c;
    canvas.drawCircle(pos, r, p);
  }

  @override
  bool shouldRepaint(covariant ExercisePainter old) =>
      old.progress != progress ||
      old.type != type ||
      old.color != color;
}