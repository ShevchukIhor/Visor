import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
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

    test('renderRgbaCircular is a circle: transparent corners, opaque center', () {
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
  });

  group('Focus Shifting path', () {
    test('anchor points are widely spaced', () {
      // Within each leg, the two anchors must be far apart (whole-screen span).
      for (var leg = 0; leg < 8; leg += 2) {
        final a = focusShiftPoint(leg / 8.0 + 0.001);
        final b = focusShiftPoint((leg + 1) / 8.0 + 0.001);
        final dist = (a - b).distance;
        expect(dist, greaterThan(0.6),
            reason: 'leg $leg anchors too close: $dist');
      }
    });

    test('alternates between multiple diagonals, not just one', () {
      // Collect anchor pairs across the loop; expect ≥ 3 distinct pairs.
      final pairs = <String>{};
      for (var leg = 0; leg < 8; leg += 2) {
        final a = focusShiftPoint(leg / 8.0 + 0.001);
        final b = focusShiftPoint((leg + 1) / 8.0 + 0.001);
        pairs.add('$a->$b');
      }
      expect(pairs.length, greaterThanOrEqualTo(3));
    });
  });

  group('Near-Far phase', () {
    test('holds at far (0) then near (1)', () {
      expect(nearFarPhase(0.1), 0.0); // far hold
      expect(nearFarPhase(0.6), 1.0); // near hold
    });

    test('transitions are smooth and bounded', () {
      double prev = nearFarPhase(0);
      for (var i = 1; i <= 200; i++) {
        final v = nearFarPhase(i / 200);
        expect(v, inInclusiveRange(0.0, 1.0));
        expect((v - prev).abs(), lessThan(0.2),
            reason: 'phase jump at ${i / 200}');
        prev = v;
      }
    });

    test('ends the loop back at far so repeat() has no visible jump', () {
      expect(nearFarPhase(0.999), closeTo(0.0, 0.05));
      expect(nearFarPhase(0.0), 0.0);
    });
  });

  group('Peripheral flash angles', () {
    test('are not in clockwise slot order', () {
      // A clockwise sequence increases by 2π/8 each slot; a random one
      // must differ from that ordering for at least some slots.
      var clockwise = 0;
      for (var slot = 0; slot < 8; slot++) {
        final a = peripheralAngle(slot, 42);
        final expected = slot * 2 * math.pi / 8;
        final d = (a - expected).abs() % (2 * math.pi);
        if (d < 0.2 || d > 2 * math.pi - 0.2) clockwise++;
      }
      expect(clockwise, lessThan(3),
          reason: 'flashes look ordered like a clock');
    });

    test('deterministic per (slot, seed) and vary with seed', () {
      expect(peripheralAngle(3, 7), peripheralAngle(3, 7));
      expect(peripheralAngle(3, 7), isNot(peripheralAngle(3, 8)));
    });

    test('stay within [0, 2π)', () {
      for (var slot = 0; slot < 32; slot++) {
        final a = peripheralAngle(slot, slot * 11);
        expect(a, inInclusiveRange(0.0, 2 * math.pi));
      }
    });
  });

  group('Orb waypoints', () {
    test('stay on screen with margins', () {
      for (var cycle = 0; cycle < 6; cycle++) {
        for (var orb = 0; orb < 2; orb++) {
          for (var end = 0; end < 2; end++) {
            final p = orbWaypoint(cycle, orb, end, 5);
            expect(p.dx, inInclusiveRange(0.15, 0.85));
            expect(p.dy, inInclusiveRange(0.15, 0.85));
          }
        }
      }
    });

    test('consecutive cycles have different trajectories', () {
      final first = orbWaypoint(0, 0, 0, 1);
      final second = orbWaypoint(1, 0, 0, 1);
      expect(first, isNot(second));
    });
  });
}

double _angularDiff(double a, double b) {
  var d = (a - b).abs();
  if (d > math.pi) d = 2 * math.pi - d;
  return d;
}