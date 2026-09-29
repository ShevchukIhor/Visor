/// Routine building blocks and the rules the editor applies to them.
///
/// No direct Flutter dependency, though `ExerciseType` arrives through
/// `exercise_painter.dart`, which does import Flutter. The rules below need no
/// widget to exercise, which is what makes them directly testable.
library;

import 'dart:convert';

import '../db/drill.dart';
import '../exercises/exercise_painter.dart';
import '../gabor/gabor_patch.dart';

/// What a step loads. Used to warn about badly shaped routines; a chain of
/// arbitrary animations is just a longer animation.
enum ExerciseLoad {
  vergence,
  accommodation,
  saccadic,
  pursuit,
  peripheral,
  relax,
}

extension ExerciseLoadOf on ExerciseType {
  ExerciseLoad get load => switch (this) {
        ExerciseType.convergence => ExerciseLoad.vergence,
        ExerciseType.nearFar => ExerciseLoad.accommodation,
        ExerciseType.focusShift => ExerciseLoad.saccadic,
        ExerciseType.saccadic => ExerciseLoad.saccadic,
        ExerciseType.pursuit => ExerciseLoad.pursuit,
        ExerciseType.figure8 => ExerciseLoad.pursuit,
        ExerciseType.peripheral => ExerciseLoad.peripheral,
        ExerciseType.orbs => ExerciseLoad.relax,
      };
}

sealed class TrainingStep {
  const TrainingStep({required this.seconds});
  final int seconds;

  /// Label shown in the editor and in the session's top bar.
  String get title;
}

class ExerciseStep extends TrainingStep {
  const ExerciseStep({
    required this.type,
    required super.seconds,
    this.gaborTarget = false,
  });

  final ExerciseType type;

  /// Near-Far only: the sphere is a Gabor patch rather than a plain dot. The
  /// standalone runner exposes this as a chip; a template fixes it.
  final bool gaborTarget;

  @override
  String get title => type.title;
}

class GaborGameStep extends TrainingStep {
  const GaborGameStep({
    required this.difficulty,
    required super.seconds,
    this.curved = false,
  });

  final Difficulty difficulty;
  final bool curved;

  @override
  String get title => 'Gabor Game · ${difficulty.label}';
}

class RestStep extends TrainingStep {
  const RestStep({required this.cue, required super.seconds});
  final String cue;

  @override
  String get title => 'Rest';
}

/// Reserved for the psychophysical engine. Not rendered until that lands.
class DrillStep extends TrainingStep {
  const DrillStep({required this.task, required super.seconds});
  final String task;

  @override
  String get title => task;
}

class Template {
  const Template({
    required this.id,
    required this.name,
    required this.builtin,
    required this.steps,
  });

  final int id;
  final String name;
  final bool builtin;
  final List<TrainingStep> steps;

  int get totalSeconds =>
      steps.fold(0, (sum, s) => sum + s.seconds);
}

/// Whether a step list is worth starting. Rest is not training, so a routine
/// made only of rest has nothing to run.
bool isRunnable(List<TrainingStep> steps) =>
    steps.any((s) => s is! RestStep);

/// Advisory notes for the editor. These never block saving or running — they
/// describe load, and the user is allowed to disagree.
List<String> templateWarnings(List<TrainingStep> steps) {
  final out = <String>[];
  for (var i = 0; i < steps.length - 1; i++) {
    final a = steps[i];
    final b = steps[i + 1];
    if (a is! ExerciseStep) continue;
    if (b is ExerciseStep && a.type.load == b.type.load) {
      out.add('${a.type.title} and ${b.type.title} load the same system '
          'back to back — consider separating them.');
    }
    if (a.type.load == ExerciseLoad.vergence && b is! RestStep) {
      out.add('${a.type.title} is vergence work; a rest step after it '
          'reduces eye strain.');
    }
  }
  return out;
}

/// The `drills` row for a finished exercise, or null when it did not finish.
///
/// Returning null rather than writing an "incomplete" row is the guard: an
/// exercise the user walked out of is not training, and the streak must not
/// see it.
Drill? drillForExercise({
  required ExerciseType type,
  required int seconds,
  required bool completed,
  required DateTime endedAt,
  int? templateId,
}) {
  if (!completed) return null;
  return Drill(
    startedAt: endedAt.subtract(Duration(seconds: seconds)),
    task: taskExercise,
    durationS: seconds,
    completed: true,
    templateId: templateId,
    params: jsonEncode({'type': type.name}),
  );
}
