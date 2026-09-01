/// Gabor patch model + generator.
///
/// A Gabor patch is a sinusoidal grating multiplied by a Gaussian envelope.
/// It is the canonical stimulus for orientation/contrast discrimination in
/// the primary visual cortex (V1) — the same class of images used in
/// psychophysics research for decades.
///
///   G(x,y) = exp( -(x'² + γ²·y'²) / (2σ²) ) · cos(2π·f·x' + φ)
///   x' = (x-cx)·cosθ + (y-cy)·sinθ
///   y' = -(x-cx)·sinθ + (y-cy)·cosθ
///
/// The "curved" variant modulates the phase φ as a function of x' so the
/// stripes bend instead of staying straight.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A single Gabor patch, fully described by its generating parameters.
class GaborPatch {
  /// Orientation of the grating in radians.
  final double theta;

  /// Spatial frequency (cycles per unit length of the patch).
  final double frequency;

  /// Standard deviation of the Gaussian envelope (patch "size").
  final double sigma;

  /// Phase offset in radians.
  final double phase;

  /// Aspect ratio (gamma) — elongation of the envelope.
  final double aspect;

  /// Amplitude / contrast multiplier in [0, 1].
  final double contrast;

  /// Curvature strength. 0 = straight stripes, >0 = bent stripes.
  /// When non-zero the phase becomes quadratic in x': φ(x') = phase + k·x'²
  final double curvature;

  const GaborPatch({
    this.theta = 0,
    this.frequency = 5,
    this.sigma = 0.3,
    this.phase = 0,
    this.aspect = 1.0,
    this.contrast = 1.0,
    this.curvature = 0,
  });

  /// Generate a raw grayscale float buffer in [-1, 1] of size [size]×[size].
  /// Coordinates are normalized to [-1, 1] on both axes.
  Float32List render(int size) {
    final out = Float32List(size * size);
    final c = math.cos(theta);
    final s = math.sin(theta);
    final half = size / 2.0;
    final sigmaN = sigma; // envelope sigma already in normalized units
    final twoSigmaSq = 2.0 * sigmaN * sigmaN;
    final aspectSq = aspect * aspect;

    for (var py = 0; py < size; py++) {
      // normalized y in [-1, 1]
      final ny = (py - half) / half;
      final yBase = py * size;
      for (var px = 0; px < size; px++) {
        final nx = (px - half) / half;
        // rotate into grating frame
        final xp = nx * c + ny * s;
        final yp = -nx * s + ny * c;
        // gaussian envelope
        final env = math.exp(-(xp * xp + aspectSq * yp * yp) / twoSigmaSq);
        // phase: constant + curvature bend
        final phi = phase + curvature * xp * xp;
        final grating = math.cos(2.0 * math.pi * frequency * xp + phi);
        out[yBase + px] = contrast * env * grating;
      }
    }
    return out;
  }

  /// Render to a displayable grayscale image (Image-compatible RGBA bytes).
  ///
  /// Maps [-1,1] → dark/light around a mid-gray background so the patch is
  /// actually visible on screen.
  Uint8List renderRgba(int size, {int bg = 0xFF1A1A1D}) {
    final g = render(size);
    final out = Uint8List(size * size * 4);
    final bgR = (bg >> 16) & 0xFF;
    final bgG = (bg >> 8) & 0xFF;
    final bgB = bg & 0xFF;
    var i = 0;
    for (var p = 0; p < size * size; p++) {
      final v = g[p]; // in [-1, 1]
      final n = (v + 1.0) / 2.0; // [0, 1]
      out[i++] = (bgR + (255 - bgR) * n).round().clamp(0, 255).toInt(); // R
      out[i++] = (bgG + (255 - bgG) * n).round().clamp(0, 255).toInt(); // G
      out[i++] = (bgB + (255 - bgB) * n).round().clamp(0, 255).toInt(); // B
      out[i++] = 255; // A
    }
    return out;
  }
}

/// Difficulty rules: which parameter axes may vary between the target and
/// the distractor patches, and by how much. Tighter tolerances = harder.
enum Difficulty {
  easy('Easy', 3),
  medium('Medium', 4),
  hard('Hard', 5),
  expert('Expert', 6);

  const Difficulty(this.label, this.grid);
  final String label;
  final int grid;

  /// Weight used in scoring.
  double get weight => switch (this) {
        Difficulty.easy => 1.0,
        Difficulty.medium => 1.5,
        Difficulty.hard => 2.0,
        Difficulty.expert => 2.5,
      };

  /// Max orientation delta (radians) between target and distractors.
  double get maxThetaDelta => switch (this) {
        Difficulty.easy => 1.05, // ~60°
        Difficulty.medium => 0.52, // ~30°
        Difficulty.hard => 0.26, // ~15°
        Difficulty.expert => 0.17, // ~10°
      };

  /// Min orientation delta so distractors never accidentally match.
  double get minThetaDelta => switch (this) {
        Difficulty.easy => 0.52, // ~30°
        Difficulty.medium => 0.26, // ~15°
        Difficulty.hard => 0.09, // ~5°
        Difficulty.expert => 0.09, // ~5°
      };

  /// Whether frequency may also drift (medium+) or phase (hard+).
  bool get varyFrequency =>
      this != Difficulty.easy; // medium, hard, expert
  bool get varyPhase => this == Difficulty.hard || this == Difficulty.expert;

  /// Contrast reduction for expert.
  double get contrastScale => this == Difficulty.expert ? 0.6 : 1.0;
}

/// A generated trial: one target patch plus a set of distractor patches.
class GaborTrial {
  final GaborPatch target;
  final List<GaborPatch> distractors;
  final int answerIndex; // which distractors slot is actually the target

  GaborTrial({
    required this.target,
    required this.distractors,
    required this.answerIndex,
  });
}

/// Randomly generates a trial for a given difficulty and grid size, with an
/// optional curved-stripe mode (which slightly bends the phase).
class TrialGenerator {
  final math.Random _rng;
  final bool curved;

  TrialGenerator({int? seed, this.curved = false})
      : _rng = math.Random(seed);

  static const double _baseFreq = 4.5;
  static const double _sigma = 0.35;
  static const double _aspect = 1.0;
  static const double _curvature = 24.0;

  GaborTrial generate(Difficulty d) {
    final n = d.grid;
    final cellCount = n * n;

    final target = _randomPatch(d, contrastScale: contrastOf(d));
    final answer = _rng.nextInt(cellCount);

    final distractors = <GaborPatch>[];
    for (var i = 0; i < cellCount; i++) {
      if (i == answer) {
        // the matching cell shows the target itself
        distractors.add(target);
      } else {
        distractors.add(_distractor(target, d));
      }
    }

    return GaborTrial(
      target: target,
      distractors: distractors,
      answerIndex: answer,
    );
  }

  double contrastOf(Difficulty d) => d.contrastScale;

  GaborPatch _randomPatch(Difficulty d, {double? contrastScale}) {
    final c = contrastOf(d);
    return GaborPatch(
      theta: _rng.nextDouble() * 2 * math.pi,
      frequency: _baseFreq,
      sigma: _sigma,
      phase: _rng.nextDouble() * 2 * math.pi,
      aspect: _aspect,
      contrast: c,
      curvature: curved ? _curvature : 0,
    );
  }

  GaborPatch _distractor(GaborPatch base, Difficulty d) {
    // Controlled single/limited-axis deviation so the brain discriminates
    // orientation (and sometimes frequency/phase), not random noise.
    final maxD = d.maxThetaDelta;
    final minD = d.minThetaDelta;
    var delta = minD + _rng.nextDouble() * (maxD - minD);
    if (_rng.nextBool()) delta = -delta;
    final theta = _wrapPi(base.theta + delta);

    final freq = d.varyFrequency
        ? base.frequency + (_rng.nextDouble() * 0.4 - 0.2)
        : base.frequency;

    final phase = d.varyPhase
        ? base.phase + (_rng.nextDouble() * 1.5 - 0.75)
        : base.phase;

    return GaborPatch(
      theta: theta,
      frequency: freq,
      sigma: base.sigma,
      phase: phase,
      aspect: base.aspect,
      contrast: base.contrast,
      curvature: base.curvature,
    );
  }

  double _wrapPi(double a) {
    if (a > math.pi) return a - 2 * math.pi;
    if (a < -math.pi) return a + 2 * math.pi;
    return a;
  }
}