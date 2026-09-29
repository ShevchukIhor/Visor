import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
import 'package:visor/core/gabor/gabor_patch.dart';
import 'package:visor/core/training/training_step.dart';

void main() {
  group('Template', () {
    test('total time is the sum of its steps', () {
      final t = Template(id: 1, name: 'x', builtin: false, steps: [
        ExerciseStep(type: ExerciseType.pursuit, seconds: 60),
        RestStep(cue: 'blink', seconds: 15),
        GaborGameStep(difficulty: Difficulty.medium, seconds: 180),
      ]);
      expect(t.totalSeconds, 255);
    });
  });

  group('isRunnable', () {
    test('a template with no steps cannot start a session', () {
      expect(isRunnable([]), isFalse);
    });

    test('a template of nothing but rest cannot start a session', () {
      expect(
        isRunnable([
          RestStep(cue: 'blink', seconds: 30),
          RestStep(cue: 'relax', seconds: 30),
        ]),
        isFalse,
      );
    });

    test('one real step is enough', () {
      expect(
        isRunnable([
          RestStep(cue: 'blink', seconds: 30),
          ExerciseStep(type: ExerciseType.orbs, seconds: 60),
        ]),
        isTrue,
      );
    });
  });

  group('load categories', () {
    test('each exercise maps to the system it actually loads', () {
      expect(ExerciseType.convergence.load, ExerciseLoad.vergence);
      expect(ExerciseType.nearFar.load, ExerciseLoad.accommodation);
      expect(ExerciseType.focusShift.load, ExerciseLoad.saccadic);
      expect(ExerciseType.saccadic.load, ExerciseLoad.saccadic);
      expect(ExerciseType.pursuit.load, ExerciseLoad.pursuit);
      expect(ExerciseType.figure8.load, ExerciseLoad.pursuit);
      expect(ExerciseType.peripheral.load, ExerciseLoad.peripheral);
      expect(ExerciseType.orbs.load, ExerciseLoad.relax);
    });

    test('the two tracking drills share a category', () {
      expect(ExerciseType.pursuit.load, ExerciseType.figure8.load);
      expect(ExerciseType.pursuit.load, ExerciseLoad.pursuit);
    });
  });

  group('templateWarnings', () {
    test('a well-formed routine warns about nothing', () {
      final w = templateWarnings([
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
        RestStep(cue: 'blink', seconds: 15),
        ExerciseStep(type: ExerciseType.pursuit, seconds: 60),
        ExerciseStep(type: ExerciseType.saccadic, seconds: 45),
      ]);
      expect(w, isEmpty);
    });

    test('two steps of the same load in a row are flagged', () {
      final w = templateWarnings([
        ExerciseStep(type: ExerciseType.pursuit, seconds: 60),
        ExerciseStep(type: ExerciseType.figure8, seconds: 60),
      ]);
      expect(w, hasLength(1));
      expect(w.single, contains('Smooth Pursuit'));
      expect(w.single, contains('Figure-8'));
    });

    test('vergence work without a rest after it is flagged', () {
      final w = templateWarnings([
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
        ExerciseStep(type: ExerciseType.saccadic, seconds: 45),
      ]);
      expect(w, hasLength(1));
      expect(w.single.toLowerCase(), contains('rest'));
    });

    test('vergence as the last step needs no rest after it', () {
      final w = templateWarnings([
        ExerciseStep(type: ExerciseType.saccadic, seconds: 45),
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
      ]);
      expect(w, isEmpty);
    });

    test('a vergence pair earns both warnings, which say different things', () {
      // Two facts about one pair, deliberately not merged: they load the same
      // system, and vergence work wants a rest after it.
      final w = templateWarnings([
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
      ]);
      expect(w, hasLength(2));
      expect(w.where((s) => s.contains('same system')), hasLength(1));
      expect(w.where((s) => s.toLowerCase().contains('rest')), hasLength(1));
    });
  });
}
