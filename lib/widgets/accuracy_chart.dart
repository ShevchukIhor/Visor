import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/analytics/chart_math.dart';
import '../core/db/drill.dart';
import '../core/gabor/gabor_patch.dart';
import '../core/theme/visor_theme.dart';

class AccuracyChart extends StatelessWidget {
  final List<Drill> drills;

  /// "Today" for the right edge of the axis. Injectable so the layout can be
  /// rendered against fixed dates in tests; the app leaves it null.
  final DateTime? now;

  const AccuracyChart({super.key, required this.drills, this.now});

  @override
  Widget build(BuildContext context) {
    final points = aggregateByDay(gaborSamples(drills).toList());
    return CustomPaint(
      painter: AccuracyChartPainter(
        points: points,
        window: chartWindow(points, now ?? DateTime.now()),
      ),
    );
  }
}

SessionSample toSample(Drill d) => SessionSample.fromCounts(
      at: d.startedAt,
      correct: d.correct,
      total: d.trials,
      difficulty: difficultyByName(_difficultyOf(d)),
    );

/// Drills the chart (and the legend that describes it) actually plot: Gabor
/// games with at least one answered trial. Kept as the one place this
/// predicate lives — the chart and the legend must never disagree about which
/// drills they are describing.
Iterable<SessionSample> gaborSamples(Iterable<Drill> drills) => [
      for (final d in drills)
        if (d.task == taskGaborGrid && d.trials > 0) toSample(d),
    ];

/// The difficulty moved into the params JSON in schema v4.
String _difficultyOf(Drill d) {
  if (d.params == null) return '';
  final m = jsonDecode(d.params!) as Map<String, Object?>;
  return (m['difficulty'] as String?) ?? '';
}

/// Colour ramp for the difficulty a day was trained at: calm green through to
/// red as the level rises, reusing the existing palette rather than inventing
/// four new colours.
extension _DifficultyColor on Difficulty {
  Color get color => switch (this) {
        Difficulty.easy => VisorTheme.success,
        Difficulty.medium => VisorTheme.primary,
        Difficulty.hard => VisorTheme.accent,
        Difficulty.expert => VisorTheme.danger,
      };
}

/// Which difficulties appear in the data, hardest last — the chart legend only
/// names levels the user has actually trained.
List<Difficulty> legendOf(List<DayPoint> points) {
  final present = points.map((p) => p.difficulty).toSet().toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  return present;
}

class AccuracyChartLegend extends StatelessWidget {
  final List<Difficulty> difficulties;
  const AccuracyChartLegend({super.key, required this.difficulties});

  @override
  Widget build(BuildContext context) {
    if (difficulties.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 4,
        children: [
          for (final d in difficulties)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: d.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(d.label,
                  style: const TextStyle(
                      color: VisorTheme.textDim, fontSize: 11)),
            ]),
        ],
      ),
    );
  }
}

/// Daily accuracy over a calendar window.
///
/// The axis is time, not session order: a day is one point wherever it falls
/// in the window, so a gap in training reads as a gap. Accuracy rather than
/// the weighted score keeps the series comparable with itself when the user
/// changes level; the level itself is the dot's colour.
class AccuracyChartPainter extends CustomPainter {
  final List<DayPoint> points;
  final ChartWindow window;
  AccuracyChartPainter({required this.points, required this.window});

  static const double padL = 34;
  static const double padR = 14;
  static const double padT = 22;
  static const double padB = 20;

  /// Days on the axis beyond which per-day labels stop fitting.
  static const int maxDayLabels = 7;

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  void _label(Canvas canvas, TextPainter tp, String text, TextStyle style,
      double centreX, double y, double w) {
    tp.text = TextSpan(text: text, style: style);
    tp.layout(maxWidth: double.infinity);
    // Measured, not a fixed offset: the last label used to clip off the right
    // edge on narrow screens.
    final x = (centreX - tp.width / 2)
        .clamp(0.0, math.max(w - tp.width, 0.0))
        .toDouble();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final plotW = math.max(w - padL - padR, 1).toDouble();
    final plotH = math.max(h - padT - padB, 1).toDouble();
    final baseY = padT + plotH;

    final tp = TextPainter(textDirection: TextDirection.ltr);
    // fontFamily matches VisorTheme.theme: a CustomPainter builds its own
// TextStyle and would otherwise label the axes in the platform default.
    const dimStyle = TextStyle(
        color: VisorTheme.textDim, fontSize: 10, fontFamily: 'Roboto');

    // Accuracy is a percentage, so the axis is fixed 0..100 — no data-driven
    // ceiling that would squash a run of good days into the top of the plot.
    double yFor(double accuracy) => baseY - (accuracy / 100) * plotH;

    final grid = Paint()
      ..color = VisorTheme.textDim.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (final pct in [0.0, 50.0, 100.0]) {
      final y = yFor(pct);
      canvas.drawLine(Offset(padL, y), Offset(padL + plotW, y), grid);
      _label(canvas, tp, pct.toStringAsFixed(0), dimStyle, padL - 14, y - 7,
          padL - 2);
    }

    double x(DayPoint p) => window.xFor(p.day, padL, plotW);

    // X labels: every day while they fit, otherwise the two ends and the
    // middle of the window.
    final days = window.days;
    final ticks = <DateTime>[];
    if (days <= maxDayLabels) {
      for (var i = 0; i < days; i++) {
        ticks.add(DateTime(
            window.firstDay.year, window.firstDay.month, window.firstDay.day + i));
      }
    } else {
      for (final f in [0, days ~/ 2, days - 1]) {
        ticks.add(DateTime(
            window.firstDay.year, window.firstDay.month, window.firstDay.day + f));
      }
    }
    for (final d in ticks) {
      _label(canvas, tp, _date(d), dimStyle,
          window.xFor(d, padL, plotW), baseY + 6, w);
    }

    // Spread of the day: a thin whisker from its worst to its best session, so
    // the mean is not mistaken for a single measurement.
    final whisker = Paint()
      ..color = VisorTheme.textDim.withValues(alpha: 0.45)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final p in points) {
      if (p.sessions < 2) continue;
      canvas.drawLine(
          Offset(x(p), yFor(p.worst)), Offset(x(p), yFor(p.best)), whisker);
    }

    // Trend line. A segment that bridges skipped days is dashed: the user did
    // not train through it, so a solid line would invent data.
    final line = Paint()
      ..color = VisorTheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < points.length; i++) {
      final a = Offset(x(points[i - 1]), yFor(points[i - 1].mean));
      final b = Offset(x(points[i]), yFor(points[i].mean));
      final adjacent =
          dayOrdinal(points[i].day) - dayOrdinal(points[i - 1].day) == 1;
      if (adjacent) {
        canvas.drawLine(a, b, line);
      } else {
        _dashed(canvas, a, b, line);
      }
    }

    // Dots, sized by how many sessions the day holds.
    for (final p in points) {
      final r = 3.0 + math.min(p.sessions - 1, 5) * 0.7;
      canvas.drawCircle(Offset(x(p), yFor(p.mean)), r,
          Paint()..color = p.difficulty.color);
    }

    final last = points.last;
    final lastY = yFor(last.mean);
    _label(
      canvas,
      tp,
      '${last.mean.toStringAsFixed(0)}%',
      const TextStyle(
          color: VisorTheme.text,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: 'Roboto'),
      x(last),
      math.max(lastY - 20, 4),
      w,
    );
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final step = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final end = math.min(t + dash, total);
      canvas.drawLine(a + step * t, a + step * end, paint);
      t = end + gap;
    }
  }

  @override
  bool shouldRepaint(covariant AccuracyChartPainter old) =>
      old.window != window || !listEquals(old.points, points);
}
