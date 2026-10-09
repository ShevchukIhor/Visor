import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/db/drill.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
import 'package:visor/screens/analytics_screen.dart';

Drill exercise(String? params) => Drill(
      startedAt: DateTime(2026, 10, 9, 17, 30),
      task: taskExercise,
      durationS: 60,
      params: params,
    );

void main() {
  group('taskDisplayName', () {
    test('an exercise resolves params.type to its human title', () {
      expect(
        taskDisplayName(exercise('{"type":"convergence"}')),
        'Convergence Training',
      );
    });

    test('every exercise type resolves to its title', () {
      for (final e in ExerciseType.values) {
        expect(taskDisplayName(exercise('{"type":"${e.name}"}')), e.title);
      }
    });

    test('missing, unknown or malformed params fall back to the task id', () {
      expect(taskDisplayName(exercise(null)), 'exercise');
      expect(taskDisplayName(exercise('{"type":"insane"}')), 'exercise');
      expect(taskDisplayName(exercise('not json')), 'exercise');
      expect(taskDisplayName(exercise('{"grid":3}')), 'exercise');
    });

    test('a non-exercise task keeps its raw id', () {
      final d = Drill(
        startedAt: DateTime(2026, 10, 9),
        task: taskGaborGrid,
        durationS: 60,
        params: '{"grid":3,"pattern":"straight"}',
      );
      expect(taskDisplayName(d), taskGaborGrid);
    });
  });
}
