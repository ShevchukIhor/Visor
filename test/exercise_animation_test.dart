import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
import 'dart:math' as math;

void main() {
  group('Convergence Training', () {
    test('moves in smooth vertical oscillation without horizontal wobble', () {
      // At t=0, should be at center
      final p0 = exercisePath(ExerciseType.convergence, 0.0);
      expect(p0.dx, closeTo(0.5, 0.001));

      // At t=0.25, should be at maximum downward displacement
      final p25 = exercisePath(ExerciseType.convergence, 0.25);
      expect(p25.dx, closeTo(0.5, 0.001)); // No horizontal movement
      expect(p25.dy, greaterThan(0.5)); // Below center

      // At t=0.5, should be back at center
      final p50 = exercisePath(ExerciseType.convergence, 0.5);
      expect(p50.dx, closeTo(0.5, 0.001));
      expect(p50.dy, closeTo(0.5, 0.001));
    });
  });

  group('Saccadic Jumps', () {
    test('interpolates smoothly between jump positions', () {
      // Check at t=0.1 (second jump) where prevI=0, targetI=1
      // At start of move phase (t=0.1), should be at previous position
      final p10 = exercisePath(ExerciseType.saccadic, 0.1);
      // At end of move phase (t=0.115), should be at target
      final p115 = exercisePath(ExerciseType.saccadic, 0.115);
      // Positions should be different (movement occurred)
      expect(p10, isNot(equals(p115)));
    });

    test('holds position after move phase completes', () {
      // After move phase (t=0.115) until next jump (t=0.2)
      final p12 = exercisePath(ExerciseType.saccadic, 0.12);
      final p15 = exercisePath(ExerciseType.saccadic, 0.15);
      final p19 = exercisePath(ExerciseType.saccadic, 0.19);
      // All should be at the same position (holding)
      expect(p12, equals(p15));
      expect(p15, equals(p19));
    });
  });

  group('Focus Shifting', () {
    test('uses smoothstep easing between positions', () {
      // Each leg takes 1/8 of the cycle
      // At midpoint of leg, should be at eased position
      final pMid = exercisePath(ExerciseType.focusShift, 0.0625);
      // Should be between start and end positions
      expect(pMid.dx, greaterThan(0.0));
      expect(pMid.dx, lessThan(1.0));
    });
  });

  group('Near-Far Phase', () {
    test('returns 0.0 during far hold', () {
      expect(nearFarPhase(0.0), equals(0.0));
      expect(nearFarPhase(0.15), equals(0.0));
    });

    test('returns 1.0 during near hold', () {
      expect(nearFarPhase(0.55), equals(1.0));
      expect(nearFarPhase(0.6), equals(1.0));
    });

    test('transitions smoothly between far and near', () {
      // During inhale phase (0.3 to 0.5)
      final p1 = nearFarPhase(0.35);
      final p2 = nearFarPhase(0.4);
      final p3 = nearFarPhase(0.45);
      expect(p1, lessThan(p2));
      expect(p2, lessThan(p3));
    });
  });


}
