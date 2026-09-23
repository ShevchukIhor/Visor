import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/exercises/exercise_painter.dart';

void main() {
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

  group('Exercise paths', () {
    test('every exercise stays on screen for the whole loop', () {
      for (final type in ExerciseType.values) {
        for (var i = 0; i <= 100; i++) {
          final p = exercisePath(type, i / 100);
          expect(p.dx, inInclusiveRange(0.0, 1.0),
              reason: '${type.name} x at t=${i / 100}');
          expect(p.dy, inInclusiveRange(0.0, 1.0),
              reason: '${type.name} y at t=${i / 100}');
        }
      }
    });
  });
}
