import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:visor/screens/dashboard_screen.dart';
import 'package:visor/screens/week_plan_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = p.join(await databaseFactoryFfi.getDatabasesPath(), 'visor.db');
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  });

  test('streakLabel and sessionsLabel pluralise', () {
    // "0-day" / "1 sessions" read as broken English; the labels must not.
    expect(streakLabel(0), '0 days');
    expect(streakLabel(1), '1 day');
    expect(streakLabel(5), '5 days');
    expect(sessionsLabel(0), '0 sessions');
    expect(sessionsLabel(1), '1 session');
    expect(sessionsLabel(3), '3 sessions');
  });

  testWidgets('the dashboard renders pluralised stats', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
      // The stats load from the database; poll until they have.
      for (var i = 0;
          i < 40 && find.text('0 days').evaluate().isEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    expect(find.text('0 days'), findsOneWidget);
    expect(find.text('0 sessions'), findsOneWidget);
  });

  testWidgets('the dashboard offers a Weekly plan entry that opens the plan',
      (tester) async {
    // The dashboard's menu column is tall; the default 800x600 test surface
    // overflows it, so give the test room.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
      await tester.pump();
      expect(find.text('Weekly plan'), findsOneWidget);

      await tester.tap(find.text('Weekly plan'));
      // The tap, the push, and the new route's first frame each take a pump.
      for (var i = 0;
          i < 20 && find.byType(WeekPlanScreen).evaluate().isEmpty;
          i++) {
        await tester.pump();
      }
      // The tap must push the plan screen.
      expect(find.byType(WeekPlanScreen), findsOneWidget);
    });
  });

  testWidgets('the dashboard scrolls to reveal the last menu button',
      (tester) async {
    // The default 800x600 test surface: the dashboard's content is taller than
    // the screen, so it must scroll (not overflow).
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
      await tester.pump();
    });
    // The last menu button sits below the fold.
    final before = tester.getTopLeft(find.text('Support Visor')).dy;
    // Scrolling must move it up into the visible area.
    await tester.drag(find.byType(MaterialApp), const Offset(0, -400));
    await tester.pump();
    final after = tester.getTopLeft(find.text('Support Visor')).dy;
    expect(after, lessThan(before),
        reason: 'the dashboard must scroll to reveal the last menu button');
  });
}
