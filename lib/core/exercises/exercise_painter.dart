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
      'Gabor patches drift and slowly grow — relax and follow them'),
  contrast('Contrast Sensitivity',
      'Detect low-contrast objects against backgrounds'),
  visualSearch('Visual Search',
      'Find target objects among distractors'),
  visualMemory('Visual Memory',
      'Remember and reproduce visual patterns'),
  visualAttention('Visual Attention',
      'Maintain focus and detect rare events');

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
      // Pure cosine approach with subtle breathing — no artificial jitter.
      final r = 0.5 * (0.5 - 0.5 * math.cos(2 * math.pi * t));
      return Offset(c.dx, c.dy + r * math.sin(2 * math.pi * t));
    case ExerciseType.nearFar:
      // Size-driven accommodation exercise — position stays centered.
      return c;
    case ExerciseType.focusShift:
      return focusShiftPoint(t);
    case ExerciseType.saccadic:
      // Smooth saccadic jumps with 120ms ease-in-out interpolation.
      // Each jump takes 0.1 of the cycle (800ms at 8s loop), with the
      // actual movement happening in the first 15% (120ms).
      final jumpDuration = 0.1;
      final moveDuration = 0.015; // 120ms at 8s loop
      final i = (t / jumpDuration).floor();
      final progressInJump = (t / jumpDuration) - i;
      // Ease: fast move, then hold
      final eased = progressInJump < moveDuration
          ? _easeInOut(progressInJump / moveDuration)
          : 1.0;
      // Previous position
      final prevI = (i - 1).clamp(0, 99);
      final prevX = 0.15 + 0.7 * _hash(prevI);
      final prevY = 0.15 + 0.7 * _hash(prevI * 31 + 7);
      // Target position
      final targetX = 0.15 + 0.7 * _hash(i);
      final targetY = 0.15 + 0.7 * _hash(i * 31 + 7);
      // Interpolate
      final x = prevX + (targetX - prevX) * eased;
      final y = prevY + (targetY - prevY) * eased;
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
    case ExerciseType.contrast:
      // Contrast sensitivity: target fades in and out at center
      return c;
    case ExerciseType.visualSearch:
      // Visual search: target appears at random positions
      final i = (t * 6).floor();
      final x = 0.15 + 0.7 * _hash(i * 7 + 13);
      final y = 0.15 + 0.7 * _hash(i * 11 + 23);
      return Offset(x, y);
    case ExerciseType.visualMemory:
      // Visual memory: pattern appears at center
      return c;
    case ExerciseType.visualAttention:
      // Visual attention: target appears at random positions with pauses
      final i = (t * 4).floor();
      final x = 0.15 + 0.7 * _hash(i * 17 + 31);
      final y = 0.15 + 0.7 * _hash(i * 19 + 41);
      return Offset(x, y);
  }
}

/// Focus Shifting: anchor points spread wide across the screen, cycling
/// through several different diagonals so the eye never repeats one line.
/// Smooth interpolation between positions for natural eye movement.
Offset focusShiftPoint(double t) {
  const pairs = [
    [Offset(0.12, 0.16), Offset(0.88, 0.84)], // main diagonal ↘
    [Offset(0.88, 0.18), Offset(0.12, 0.82)], // anti-diagonal ↙
    [Offset(0.10, 0.62), Offset(0.90, 0.38)], // shallow diagonal
    [Offset(0.30, 0.90), Offset(0.70, 0.10)], // steep diagonal
  ];

  // Each leg takes 1/8 of the cycle
  final legDuration = 1.0 / 8.0;
  final legIndex = (t / legDuration).floor();
  final legProgress = (t / legDuration) - legIndex;

  // Smoothstep easing for natural movement
  final easedProgress = legProgress * legProgress * (3 - 2 * legProgress);

  final pair = pairs[(legIndex >> 1) % pairs.length];
  final from = pair[legIndex & 1];
  final to = pair[(legIndex + 1) & 1];

  // Interpolate between positions
  return Offset(
    from.dx + (to.dx - from.dx) * easedProgress,
    from.dy + (to.dy - from.dy) * easedProgress,
  );
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

  /// Trail length (number of past positions to draw).
  final int trailLength;

  ExercisePainter(
    this.type,
    this.progress, {
    this.color = const Color(0xFF4D9FFF),
    this.seed = 0,
    this.orbsTime = 0,
    this.gaborImage,
    this.nearFarGabor = false,
    this.trailLength = 8,
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
    if (type == ExerciseType.contrast) {
      _paintContrast(canvas, size);
      return;
    }
    if (type == ExerciseType.visualSearch) {
      _paintVisualSearch(canvas, size);
      return;
    }
    if (type == ExerciseType.visualMemory) {
      _paintVisualMemory(canvas, size);
      return;
    }
    if (type == ExerciseType.visualAttention) {
      _paintVisualAttention(canvas, size);
      return;
    }

    final p = exercisePath(type, progress);
    final center = Offset(p.dx * size.width, p.dy * size.height);

    // Draw continuous trail with exponential alpha decay
    const trailSteps = 5;
    for (var i = 1; i <= trailSteps; i++) {
      final trailProgress = (progress - i * 0.015).clamp(0.0, 1.0);
      final trailPos = exercisePath(type, trailProgress);
      final trailCenter = Offset(trailPos.dx * size.width, trailPos.dy * size.height);
      // Exponential decay: each step is 60% as visible as the previous
      final trailAlpha = 0.25 * math.pow(0.6, i - 1);
      final trailRadius = size.width * 0.03 * math.pow(0.85, i - 1);
      if (trailRadius > 0) {
        _dot(canvas, trailCenter, trailRadius, color.withValues(alpha: trailAlpha));
      }
    }

    // Main target with gentle pulsing glow (slower, subtler)
    final pulse = 0.95 + 0.05 * math.sin(progress * 8);
    _glow(canvas, center, size.width * 0.03 * pulse, 8, color.withValues(alpha: 0.15));
    _dot(canvas, center, size.width * 0.03, color);

    // Faint guidance ring only for tracking exercises (not for convergence, near-far, etc.)
    if (type == ExerciseType.pursuit ||
        type == ExerciseType.figure8 ||
        type == ExerciseType.saccadic) {
      _refPaint.color = color.withValues(alpha: 0.1);
      canvas.drawCircle(
          Offset(size.width / 2, size.height / 2), size.width * 0.005, _refPaint);
    }
  }

  /// Accommodation drill: the target is small and sharp when "far" and
  /// grows into a large soft disc when "near", holding at each extreme.
  /// Non-linear perspective scaling for more realistic depth perception.
  void _paintNearFar(Canvas canvas, Size size) {
    final n = nearFarPhase(progress);
    final cx = size.width / 2;
    final cy = size.height / 2;

    final minR = size.shortestSide * 0.018;
    final maxR = size.shortestSide * 0.30;

    // Perspective scaling: objects grow faster as they get closer
    // Using inverse perspective: size ∝ 1/distance
    final k = 2.0;
    final perspectiveFactor = n / (1 + k * (1 - n));
    final r = minR + (maxR - minR) * perspectiveFactor;

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

    // Smooth crossfade between FAR and NEAR labels
    final farAlpha = (1.0 - n).clamp(0.0, 1.0) * 0.55;
    final nearAlpha = n.clamp(0.0, 1.0) * 0.55;
    if (farAlpha > 0.01) {
      _label(canvas, size, 'FAR', color.withValues(alpha: farAlpha));
    }
    if (nearAlpha > 0.01) {
      _label(canvas, size, 'NEAR', color.withValues(alpha: nearAlpha));
    }
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

  /// Contrast Sensitivity: a circle that fades in and out with varying
  /// contrast against the background.
  void _paintContrast(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.shortestSide * 0.08;

    // Contrast cycles: target fades from visible to nearly invisible
    final contrastPhase = progress * 4;
    final contrast = 0.3 + 0.7 * _smooth(0.5 + 0.5 * math.sin(contrastPhase));

    // Background grid for reference
    _drawGrid(canvas, size);

    // Target circle with varying contrast
    _dot(canvas, Offset(cx, cy), r, color.withValues(alpha: contrast));
  }

  /// Visual Search: one target among several distractors.
  void _paintVisualSearch(Canvas canvas, Size size) {
    final slot = (progress * 6).floor();
    final targetAngle = _hash(slot * 7 + 13) * 2 * math.pi;
    final targetPos = Offset(
      size.width / 2 + size.width * 0.3 * math.cos(targetAngle),
      size.height / 2 + size.height * 0.3 * math.sin(targetAngle),
    );

    // Draw distractors
    for (var i = 0; i < 5; i++) {
      final angle = _hash(slot * 11 + i * 17 + 23) * 2 * math.pi;
      final pos = Offset(
        size.width / 2 + size.width * 0.3 * math.cos(angle),
        size.height / 2 + size.height * 0.3 * math.sin(angle),
      );
      _dot(canvas, pos, size.width * 0.02, color.withValues(alpha: 0.4));
    }

    // Draw target (slightly different color)
    _dot(canvas, targetPos, size.width * 0.025, color);
  }

  /// Visual Memory: show a random pattern briefly, then hide it.
  /// Pattern changes each cycle to train working memory.
  void _paintVisualMemory(Canvas canvas, Size size) {
    // Show for first half of cycle, hide for second half
    final showing = progress < 0.5;

    // Generate random pattern positions based on seed and cycle
    // Use orbsTime to track total elapsed time for cycle counting
    final cycle = (orbsTime / 8.0).floor();

    if (showing) {
      // Show pattern with 4 dots at random positions
      final cx = size.width / 2;
      final cy = size.height / 2;
      for (var i = 0; i < 4; i++) {
        final angle = _hash(cycle * 100 + i * 10 + 1) * 2 * math.pi;
        final radius = 0.1 + _hash(cycle * 100 + i * 10 + 2) * 0.2;
        final pos = Offset(
          cx + size.width * radius * math.cos(angle),
          cy + size.height * radius * math.sin(angle),
        );
        _dot(canvas, pos, size.width * 0.02, color);
      }
    }
    // When not showing, screen is empty (user must recall pattern)
  }

  /// Visual Attention: rare target appears among frequent distractors.
  void _paintVisualAttention(Canvas canvas, Size size) {
    final slot = (progress * 8).floor();
    final isTarget = slot % 4 == 0; // 25% of slots are targets

    for (var i = 0; i < 6; i++) {
      final angle = _hash(slot * 13 + i * 19 + 31) * 2 * math.pi;
      final pos = Offset(
        size.width / 2 + size.width * 0.35 * math.cos(angle),
        size.height / 2 + size.height * 0.35 * math.sin(angle),
      );
      final alpha = isTarget && i == 0 ? 1.0 : 0.3;
      final radius = isTarget && i == 0 ? size.width * 0.03 : size.width * 0.02;
      _dot(canvas, pos, radius, color.withValues(alpha: alpha));
    }
  }

  /// Draw a subtle reference grid.
  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // Vertical lines
    for (var x = 0.0; x < size.width; x += size.width / 8) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    // Horizontal lines
    for (var y = 0.0; y < size.height; y += size.height / 8) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
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
