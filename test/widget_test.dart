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
  });
}

double _angularDiff(double a, double b) {
  var d = (a - b).abs();
  if (d > math.pi) d = 2 * math.pi - d;
  return d;
}