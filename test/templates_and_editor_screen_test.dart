import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:visor/core/db/vision_db.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
import 'package:visor/core/training/template_repo.dart';
import 'package:visor/core/training/training_step.dart';
import 'package:visor/screens/template_editor_screen.dart';
import 'package:visor/screens/templates_screen.dart';

/// Widget-level coverage for the routine list and editor.
///
/// Both screens go through the real `VisionDb.instance` singleton, matching
/// every other screen in the app (`TemplateRepo` is not injected into them).
/// So — unlike `template_repo_test.dart`, which builds its own throwaway
/// database — these tests configure `sqflite_common_ffi` as the global
/// factory and let the screens open the app's real (file-backed) database,
/// wiped clean before each test. Real disk I/O does not resolve inside
/// flutter_test's fake-async pump zone, so every interaction that waits on
/// it runs inside `tester.runAsync`.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Start from a clean file so a stale schema from a previous run can't
    // leak into these tests.
    final path =
        p.join(await databaseFactoryFfi.getDatabasesPath(), 'visor.db');
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  });

  setUp(() async {
    final db = await VisionDb.instance.db;
    await db.delete('template_steps');
    await db.delete('templates');
    await db.delete('week_plan');
  });

  testWidgets('a routine with nothing runnable disables Start and says why',
      (tester) async {
    await tester.runAsync(() async {
      final repo = TemplateRepo(await VisionDb.instance.db);
      await repo.save(Template(
        id: 0,
        name: 'Rest only',
        builtin: false,
        steps: [RestStep(cue: 'Breathe', seconds: 30)],
      ));

      await tester.pumpWidget(const MaterialApp(home: TemplatesScreen()));
      // Not pumpAndSettle: the loading state shows an indeterminate
      // CircularProgressIndicator, whose animation never stops, so
      // pumpAndSettle would spin until it times out. Poll instead, bounded,
      // until the real database read finishes and the spinner is gone.
      for (var i = 0;
          i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    expect(find.text('Rest only'), findsOneWidget);
    expect(find.text('Add an exercise to run this routine'), findsOneWidget);

    final inkWell = tester.widget<InkWell>(find.ancestor(
      of: find.text('Rest only'),
      matching: find.byType(InkWell),
    ));
    expect(inkWell.onTap, isNull,
        reason: 'a routine with no runnable step must not be startable');
  });

  testWidgets(
      'reordering steps in the editor and saving persists the new order',
      (tester) async {
    // No explicit platform override needed: flutter_test's binding already
    // reports TargetPlatform.android by default (see
    // foundation/_platform_io.dart), which is what makes
    // ReorderableListView drag on a long press anywhere on the item, same
    // as on a real phone — its desktop mode (a separate drag-handle icon,
    // no long press) never applies here.
    final template = Template(
      id: 0,
      name: 'Reorder me',
      builtin: false,
      steps: [
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
        ExerciseStep(type: ExerciseType.pursuit, seconds: 60),
        ExerciseStep(type: ExerciseType.saccadic, seconds: 45),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TemplateEditorScreen(template: template)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Drag the first step past the second, swapping their order. A long
    // press must hold before moving — ReorderableListView starts a drag on
    // long-press on mobile, and moving too soon is read as a scroll. Landing
    // exactly on the next item's center is not enough to cross its reorder
    // threshold (verified empirically), so overshoot by the same distance.
    final start = tester.getCenter(find.text(ExerciseType.convergence.title));
    final target = tester.getCenter(find.text(ExerciseType.pursuit.title));
    final drag = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await drag.moveTo(target + (target - start));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    // The database write and read-back are real disk I/O, which doesn't
    // resolve inside flutter_test's fake-async pump zone.
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = (await TemplateRepo(await VisionDb.instance.db).all())
          .singleWhere((t) => t.name == 'Reorder me');
      expect(saved.steps.map((s) => s.title), [
        ExerciseType.pursuit.title,
        ExerciseType.convergence.title,
        ExerciseType.saccadic.title,
      ]);
    });
  });

  testWidgets('warnings render as a list without disabling Save',
      (tester) async {
    // A vergence pair earns two distinct, deliberately non-deduplicated
    // warnings (see templateWarnings): they load the same system, and
    // vergence work wants a rest step after it.
    final template = Template(
      id: 0,
      name: 'Warn me',
      builtin: false,
      steps: [
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
      ],
    );
    await tester.pumpWidget(
        MaterialApp(home: TemplateEditorScreen(template: template)));
    await tester.pump();

    expect(find.textContaining('same system'), findsOneWidget);
    expect(find.textContaining('reduces eye strain'), findsOneWidget);

    final saveButton =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
    expect(saveButton.onPressed, isNotNull,
        reason: 'warnings are advisory and must never disable Save');
  });
}
