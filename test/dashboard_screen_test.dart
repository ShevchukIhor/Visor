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
}
