import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
import 'package:visor/core/training/training_step.dart';
import 'package:visor/screens/template_editor_screen.dart';

/// Failure-path coverage for the editor's save.
///
/// Deliberately does not set up `sqflite_common_ffi`: `VisionDb.instance.db`
/// fails naturally in a bare widget test (no database factory is configured),
/// which is exactly the failure the guarded `_save` must surface instead of
/// leaving the Save button disabled forever with the edits silently lost.
void main() {
  testWidgets('a failed save surfaces the error and re-enables Save',
      (tester) async {
    final template = Template(
      id: 0,
      name: 'Save me',
      builtin: false,
      steps: [ExerciseStep(type: ExerciseType.pursuit, seconds: 60)],
    );
    await tester.pumpWidget(
        MaterialApp(home: TemplateEditorScreen(template: template)));
    await tester.pump();

    await tester.tap(find.text('Save'));
    // Let the rejected database open settle, then render the error state.
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Could not save this routine'), findsOneWidget);
    expect(find.text('Retry save'), findsOneWidget);
    final saveButton =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
    expect(saveButton.onPressed, isNotNull,
        reason: 'a failed save must re-enable Save, not disable it forever');
  });
}
