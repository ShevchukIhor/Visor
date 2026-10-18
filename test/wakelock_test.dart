import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
import 'package:visor/core/training/training_step.dart';
import 'package:visor/screens/exercises_screen.dart';
import 'package:visor/screens/session_runner.dart';

import 'wakelock_mock.dart';

/// Wakelock coverage: the screen must stay on while a drill's timer runs,
/// because an exercise has no touch input to reset the device's screen
/// timeout. The wakelock is taken when the timer starts and released when
/// it stops — never while a picker or a static card is showing.
void main() {
  Template routine(List<TrainingStep> steps) =>
      Template(id: 1, name: 'Test routine', builtin: false, steps: steps);

  /// A home screen that pushes [screen] on demand, so the pushed route can
  /// actually be popped (popping the root route is a no-op).
  Widget harness(Widget screen) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => screen),
              ),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a routine holds the wakelock for its whole run',
      (tester) async {
    final calls = mockWakelock(tester);
    await tester.pumpWidget(MaterialApp(
      home: SessionRunner(template: routine([
        ExerciseStep(type: ExerciseType.pursuit, seconds: 3),
      ])),
    ));
    await tester.pump(); // autoStart postFrameCallback
    expect(calls, [true],
        reason: 'the routine takes the wakelock on start');

    await tester.pumpWidget(const SizedBox());
    expect(calls, [true, false],
        reason: 'leaving the routine releases the wakelock');
  });

  testWidgets('a standalone exercise holds the wakelock only while running',
      (tester) async {
    final calls = mockWakelock(tester);
    await tester.pumpWidget(harness(
        ExerciseRunner(type: ExerciseType.pursuit)));
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle(); // route transition; no animation yet

    expect(calls, isEmpty,
        reason: 'the duration picker must not hold the screen');

    await tester.tap(find.text('30s'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(calls, [true], reason: 'starting the drill takes the wakelock');

    // The whole 30 s duration elapses in one pump of the fake clock.
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(calls, [true, false],
        reason: 'finishing releases the wakelock — the card is static');
  });

  testWidgets('an early exercise exit releases the wakelock', (tester) async {
    final calls = mockWakelock(tester);
    await tester.pumpWidget(harness(
        ExerciseRunner(type: ExerciseType.pursuit)));
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(calls, [true]);

    // The running drill repeats its animation, so a bare pumpAndSettle
    // would never settle: drive the dialog with bounded pumps instead.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // dialog in
    expect(find.text('Exit exercise?'), findsOneWidget);
    await tester.tap(find.text('Exit'));
    // The tap pops the dialog; `_exit`'s continuation (which pops the
    // exercise's own route) runs as a microtask after this frame, so the
    // route's exit transition only starts now. The next pump must elapse
    // real fake time for that transition to complete and the dispose —
    // which releases the wakelock — to run.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ExerciseRunner), findsNothing);
    expect(calls, [true, false],
        reason: 'the dispose path releases the wakelock');
  });
}
