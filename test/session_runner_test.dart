import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
import 'package:visor/core/training/training_step.dart';
import 'package:visor/screens/session_runner.dart';

/// Widget-level coverage for `SessionRunner`. Deliberately does not set up
/// `sqflite_common_ffi`: every `VisionDb.instance` write here fails naturally
/// (no database factory is configured in a bare widget test), which is
/// exactly the failure `onRecordFailed` exists to surface — no need to
/// inject a fake failure.
///
/// This must run before the other tests in this file: `VisionDb.instance`
/// is a process-wide singleton that memoizes its (here, permanently failing)
/// database handle on first access, and asserting on that failure only from
/// the test that triggers it first has proven reliable — reusing an
/// already-settled `Future` from an earlier test's now-finished zone did not
/// reliably resurface its rejection in a later test.
void main() {
  Template routine(List<TrainingStep> steps) =>
      Template(id: 1, name: 'Test routine', builtin: false, steps: steps);

  testWidgets(
      'a failing insertDrill surfaces the warning and the Retry save button',
      (tester) async {
    final t = routine([
      ExerciseStep(type: ExerciseType.pursuit, seconds: 1),
    ]);
    await tester.pumpWidget(MaterialApp(home: SessionRunner(template: t)));
    await tester.pump(); // autoStart postFrameCallback
    await tester.pump(const Duration(seconds: 1)); // the step completes

    // The routine is done (single step); its finish card is static, so it's
    // now safe to let everything — including the failing write's rejected
    // Future — settle before asserting on it.
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save 1 step'), findsOneWidget);
    expect(find.text('Retry save'), findsOneWidget);
  });

  testWidgets('a two-step template advances to step 2 after the first '
      "step's duration", (tester) async {
    final t = routine([
      ExerciseStep(type: ExerciseType.pursuit, seconds: 3),
      ExerciseStep(type: ExerciseType.saccadic, seconds: 3),
    ]);
    await tester.pumpWidget(MaterialApp(home: SessionRunner(template: t)));
    // Let the autoStart postFrameCallback run.
    await tester.pump();
    expect(find.textContaining('1/2 · ${ExerciseType.pursuit.title}'),
        findsOneWidget);

    // The first step's whole duration elapses in one tick of fake time.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.textContaining('2/2 · ${ExerciseType.saccadic.title}'),
        findsOneWidget);
    // Pursuit's title must be gone — this is a fresh step, not a relabeled
    // leftover of the first.
    expect(find.textContaining(ExerciseType.pursuit.title), findsNothing);

    // Drain the second step too, so its ticker doesn't outlive the test.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  });

  testWidgets('a RestStep fires its callback after exactly its seconds',
      (tester) async {
    final t = routine([
      RestStep(cue: 'Breathe', seconds: 3),
      ExerciseStep(type: ExerciseType.pursuit, seconds: 2),
    ]);
    await tester.pumpWidget(MaterialApp(home: SessionRunner(template: t)));
    await tester.pump();
    expect(find.textContaining('1/2 · Rest'), findsOneWidget);

    // One second short of the rest's duration: must not have advanced yet.
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('1/2 · Rest'), findsOneWidget);

    // The final second: the rest card must fire onDone now, not later.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('2/2 · ${ExerciseType.pursuit.title}'),
        findsOneWidget);

    // Drain the second step so its ticker doesn't outlive the test.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });
}
