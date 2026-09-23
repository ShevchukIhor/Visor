import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/gabor/gabor_patch.dart';

void main() {
  group('GaborPatch', () {
    test('render produces a buffer of the correct size', () {
      const patch = GaborPatch();
      final buf = patch.render(64);
      expect(buf.length, 64 * 64);
    });

    test('values are bounded in [-1, 1]', () {
      const patch = GaborPatch(theta: 0.5, contrast: 1.0);
      final buf = patch.render(32);
      double maxV = -1e9, minV = 1e9;
      for (final v in buf) {
        if (v > maxV) maxV = v;
        if (v < minV) minV = v;
      }
      expect(maxV, lessThanOrEqualTo(1.0001));
      expect(minV, greaterThanOrEqualTo(-1.0001));
    });

    test('two patches with different theta differ measurably', () {
      const a = GaborPatch(theta: 0.0);
      const b = GaborPatch(theta: math.pi / 2); // 90° apart
      final ba = a.render(48);
      final bb = b.render(48);
      var diff = 0.0;
      for (var i = 0; i < ba.length; i++) {
        diff += (ba[i] - bb[i]).abs();
      }
      // 90° orientation difference must produce a large mean difference.
      expect(diff / ba.length, greaterThan(0.1));
    });

    test('renders RGBA with correct byte length', () {
      const patch = GaborPatch();
      final rgba = patch.renderRgba(32);
      expect(rgba.length, 32 * 32 * 4);
    });

    test('renderRgba maps the signal symmetrically about the ramp midpoint',
        () {
      // A Gabor's excursion must be symmetric about the mean-luminance field,
      // or bright and dark stripes carry different contrast. The mapping is
      // checked against the raw signal rather than against the extremes: a
      // discrete pixel grid never samples the exact peak or trough.
      const patch = GaborPatch();
      const dark = 0xFF1A1A1D;
      const darkR = (dark >> 16) & 0xFF;
      final midpoint = (darkR + 255) / 2;
      final half = (255 - darkR) / 2;

      final signal = patch.render(64);
      final rgba = patch.renderRgba(64, darkLevel: dark);

      for (var p = 0; p < signal.length; p++) {
        // luminance = midpoint + signal * half  <=>  equal swing either way.
        expect(rgba[p * 4], closeTo(midpoint + signal[p] * half, 1),
            reason: 'pixel $p, signal ${signal[p]}');
      }

      // Where the envelope has vanished the signal is 0 -> the ramp midpoint,
      // NOT darkLevel: this variant paints no background.
      expect(signal[0].abs(), lessThan(1e-3)); // gaussian tail, not exactly 0
      expect(rgba[0], closeTo(midpoint, 1));

      // Fully opaque.
      for (var i = 3; i < rgba.length; i += 4) {
        expect(rgba[i], 255);
      }
    });

    test('darkLevel actually moves the dark end of the ramp', () {
      const patch = GaborPatch();
      final dim = patch.renderRgba(32, darkLevel: 0xFF000000);
      final bright = patch.renderRgba(32, darkLevel: 0xFF808080);
      var minDim = 255, minBright = 255;
      for (var i = 0; i < dim.length; i += 4) {
        if (dim[i] < minDim) minDim = dim[i];
        if (bright[i] < minBright) minBright = bright[i];
      }
      expect(minDim, lessThan(minBright));
    });

    test('renderRgbaCircular is a circle: transparent corners, opaque center',
        () {
      const patch = GaborPatch();
      final rgba = renderRgbaCircular(patch, 64);
      expect(rgba.length, 64 * 64 * 4);
      // Corner pixel (0,0) must be fully transparent.
      expect(rgba[3], 0);
      expect(rgba[(63 * 64) * 4 + 3], 0); // bottom-left corner
      // Center pixel must be (nearly) opaque.
      expect(rgba[(32 * 64 + 32) * 4 + 3], greaterThan(200));
      // Mid-gray-centric grayscale: R == G == B everywhere.
      for (var i = 0; i < rgba.length; i += 4) {
        expect(rgba[i], rgba[i + 1]);
        expect(rgba[i], rgba[i + 2]);
      }
    });

    test('renderRgbaCircular is premultiplied (RGB <= alpha) everywhere', () {
      // ui.decodeImageFromPixels expects premultiplied alpha; straight-alpha
      // input (RGB > alpha, e.g. gray corners with a=0) renders as opaque
      // squares. This invariant guards against that regression.
      const patch = GaborPatch();
      final rgba = renderRgbaCircular(patch, 48);
      for (var i = 0; i < rgba.length; i += 4) {
        final a = rgba[i + 3];
        expect(rgba[i], lessThanOrEqualTo(a),
            reason: 'pixel ${i ~/ 4}: R=${rgba[i]} > A=$a');
      }
      // Corners must be fully black-and-transparent in premultiplied form.
      expect(rgba[0], 0);
      expect(rgba[3], 0);
    });
  });

  group('TrialGenerator', () {
    test('target has exactly one matching spot', () {
      final gen = TrialGenerator(seed: 42);
      final trial = gen.generate(Difficulty.easy);
      expect(trial.distractors.length, 9); // 3x3
      expect(trial.answerIndex, inInclusiveRange(0, 8));
    });

    test('distractor orientation deviates from target within easy range', () {
      final gen = TrialGenerator(seed: 7);
      final trial = gen.generate(Difficulty.easy);
      for (var i = 0; i < trial.distractors.length; i++) {
        if (i == trial.answerIndex) continue;
        final d = _angularDiff(trial.target.theta,
            trial.distractors[i].theta);
        expect(d, greaterThanOrEqualTo(0.5)); // ≥ ~29° for easy
        expect(d, lessThanOrEqualTo(math.pi)); // ≤ 180°
      }
    });

    test('expert distractors deviate less than easy', () {
      final gen = TrialGenerator(seed: 3);
      final easy = gen.generate(Difficulty.easy);
      final expert = gen.generate(Difficulty.expert);
      double maxEasy = 0, maxExpert = 0;
      for (var i = 0; i < easy.distractors.length; i++) {
        if (i == easy.answerIndex) continue;
        final d = _angularDiff(easy.target.theta, easy.distractors[i].theta);
        if (d > maxEasy) maxEasy = d;
      }
      for (var i = 0; i < expert.distractors.length; i++) {
        if (i == expert.answerIndex) continue;
        final d =
            _angularDiff(expert.target.theta, expert.distractors[i].theta);
        if (d > maxExpert) maxExpert = d;
      }
      expect(maxExpert, lessThan(maxEasy));
    });

    test('grid is filled for every difficulty', () {
      final gen = TrialGenerator(seed: 11);
      for (final d in Difficulty.values) {
        final trial = gen.generate(d);
        expect(trial.distractors.length, d.grid * d.grid,
            reason: '${d.name} grid');
        expect(trial.answerIndex, inInclusiveRange(0, d.grid * d.grid - 1));
        // The answer cell shows the target itself.
        expect(identical(trial.distractors[trial.answerIndex], trial.target),
            isTrue);
      }
    });
  });
}

double _angularDiff(double a, double b) {
  var d = (a - b).abs();
  if (d > math.pi) d = 2 * math.pi - d;
  return d;
}
