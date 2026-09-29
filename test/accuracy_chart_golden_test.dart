import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/analytics/chart_math.dart';
import 'package:visor/core/db/vision_db.dart';
import 'package:visor/core/gabor/gabor_patch.dart';
import 'package:visor/core/theme/visor_theme.dart';
import 'package:visor/widgets/accuracy_chart.dart';

/// Visual regression gate for the trend chart. "Today" is injected, so the
/// image is stable: regenerate it with `--update-goldens` only when the chart
/// is meant to change, and look at the result before committing it.
void main() {
  const fontPath = '/usr/share/fonts/noto/NotoSans-Regular.ttf';
  // Without a real font the axis labels render as boxes and the image would
  // never match, so the gate skips rather than failing for the wrong reason.
  final hasFont = File(fontPath).existsSync();

  setUpAll(() async {
    // The default test font paints boxes instead of glyphs, which hides exactly
    // the label clipping this chart had to fix.
    if (!hasFont) return;
    final bytes = File(fontPath).readAsBytesSync().buffer.asByteData();
    // 'FlutterTest' is the family unstyled text falls back to in tests; the
    // painter builds its own TextStyle, so without this the axis labels would
    // render as boxes and any clipping would stay invisible.
    for (final family in ['Roboto', 'FlutterTest']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });

  int id = 0;
  VisionSession session(
    DateTime at, {
    int correct = 8,
    int total = 10,
    Difficulty difficulty = Difficulty.easy,
  }) =>
      VisionSession(
        id: ++id,
        startedAt: at,
        durationS: 60,
        difficulty: difficulty.name,
        grid: difficulty.grid,
        pattern: 'straight',
        correct: correct,
        total: total,
        score: VisionDb.computeScore(
            correct: correct, total: total, d: difficulty),
      );

  Widget frame(String caption, List<VisionSession> sessions, DateTime now) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text(caption,
              style: const TextStyle(color: VisorTheme.textDim, fontSize: 12)),
        ),
        SizedBox(
          height: 190,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AccuracyChart(sessions: sessions, now: now),
          ),
        ),
        AccuracyChartLegend(
          difficulties:
              legendOf(aggregateByDay(sessions.map(toSample).toList())),
        ),
      ],
    );
  }

  testWidgets('trend chart layouts', (tester) async {
    tester.view.physicalSize = const Size(820, 1240);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Fixed "today" so the image is byte-identical on any day it is generated.
    final now = DateTime(2026, 3, 15);
    DateTime day(int ago, [int hour = 10]) =>
        DateTime(now.year, now.month, now.day - ago, hour);

    final fourDays = [
      session(day(3), correct: 5, difficulty: Difficulty.easy),
      session(day(2), correct: 7, difficulty: Difficulty.easy),
      session(day(2, 20), correct: 9, difficulty: Difficulty.medium),
      session(day(1), correct: 6, difficulty: Difficulty.medium),
      session(day(0), correct: 9, difficulty: Difficulty.hard),
      session(day(0, 12), correct: 7, difficulty: Difficulty.hard),
      session(day(0, 18), correct: 8, difficulty: Difficulty.hard),
    ];

    final withGap = [
      session(day(6), correct: 4, difficulty: Difficulty.easy),
      session(day(5), correct: 6, difficulty: Difficulty.easy),
      // three days off
      session(day(1), correct: 8, difficulty: Difficulty.medium),
      session(day(0), correct: 9, difficulty: Difficulty.expert),
    ];

    final month = [
      for (var d = 29; d >= 0; d--)
        if (d % 4 != 0)
          session(day(d),
              // a rising trend with day-to-day wobble
              correct: (4 + (29 - d) ~/ 6 + (d % 3)).clamp(0, 10),
              difficulty: Difficulty.values[((29 - d) ~/ 8).clamp(0, 3)]),
    ];

    final single = [session(day(0), correct: 7, difficulty: Difficulty.medium)];

    await tester.pumpWidget(MaterialApp(
      theme: VisorTheme.theme,
      home: Scaffold(
        backgroundColor: VisorTheme.bg,
        body: SingleChildScrollView(
          child: Column(
            children: [
              frame('4 consecutive days, 7 sessions', fourDays, now),
              frame('a three-day gap', withGap, now),
              frame('a month of history', month, now),
              frame('one single session', single, now),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SingleChildScrollView),
      matchesGoldenFile('goldens/accuracy_chart.png'),
    );
    // Skipped where no system font is installed to render the axis labels with.
  }, skip: !hasFont);
}
