import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/analytics/chart_math.dart';
import '../core/db/drill.dart';
import '../core/gabor/gabor_patch.dart';
import '../core/theme/visor_theme.dart';

/// Daily Gabor accuracy over a calendar window, drawn with [LineChart].
///
/// The axis is time, not session order: a day is one point wherever it falls
/// in the window, so a gap in training reads as a gap. Accuracy rather than the
/// weighted score keeps the series comparable with itself when the user changes
/// level; the level itself is the dot's colour.
class AccuracyChart extends StatelessWidget {
  final List<Drill> drills;

  /// "Today" for the right edge of the axis. Injectable so the layout can be
  /// rendered against fixed dates in tests; the app leaves it null.
  final DateTime? now;

  const AccuracyChart({super.key, required this.drills, this.now});

  @override
  Widget build(BuildContext context) {
    final points = aggregateByDay(gaborSamples(drills).toList());
    if (points.isEmpty) return const SizedBox.shrink();
    return _chart(points);
  }

  /// Split the day points into contiguous runs of adjacent days. fl_chart
  /// connects the points of one bar with a line, so a run is one bar and the
  /// line never bridges a skipped day: a gap in training reads as a gap.
  List<List<DayPoint>> _runs(List<DayPoint> points) {
    final runs = <List<DayPoint>>[];
    for (final p in points) {
      if (runs.isNotEmpty &&
          dayOrdinal(p.day) - dayOrdinal(runs.last.last.day) == 1) {
        runs.last.add(p);
      } else {
        runs.add([p]);
      }
    }
    return runs;
  }

  Widget _chart(List<DayPoint> points) {
    final window = chartWindow(points, now ?? DateTime.now());
    var minX = dayOrdinal(window.firstDay).toDouble();
    var maxX = dayOrdinal(window.lastDay).toDouble();
    // A one-day window has no span to scale against; widen it a day each side
    // so the single point is centred and the axis labels stay whole dates.
    if (maxX - minX < 1) {
      minX -= 1;
      maxX += 1;
    }
    final days = window.days;
    final int xInterval = days <= 7 ? 1 : (days / 3).ceil();

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: 0,
        maxY: 100,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => VisorTheme.surface,
            getTooltipItems: (touched) => [
              for (final s in touched)
                LineTooltipItem(
                  '${_dateLabel(s.x)} · ${s.y.toStringAsFixed(0)}%',
                  const TextStyle(color: VisorTheme.text, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (final run in _runs(points))
            LineChartBarData(
              spots: [
                for (final p in run)
                  FlSpot(dayOrdinal(p.day).toDouble(), p.mean),
              ],
              isCurved: false,
              barWidth: 2.5,
              color: VisorTheme.primary,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, xPercent, bar, index) {
                  final p = run[index];
                  final r = 3.0 + math.min(p.sessions - 1, 5) * 0.7;
                  return FlDotCirclePainter(
                    color: p.difficulty.color,
                    radius: r,
                  );
                },
              ),
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 50,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}%',
                style: const TextStyle(
                    color: VisorTheme.textDim, fontSize: 10),
              ),
            ),
          ),
          rightTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: xInterval.toDouble(),
              getTitlesWidget: (value, meta) => Text(
                _dateLabel(value),
                style: const TextStyle(
                    color: VisorTheme.textDim, fontSize: 10),
              ),
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 50,
          getDrawingHorizontalLine: (value) => FlLine(
            color: VisorTheme.textDim.withValues(alpha: 0.25),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  /// Invert [dayOrdinal]: days since the epoch back to a local calendar date.
  DateTime _dateFromOrdinal(double ordinal) {
    final ms = ordinal.toInt() * Duration.millisecondsPerDay;
    final utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return DateTime(utc.year, utc.month, utc.day);
  }

  String _dateLabel(double ordinal) {
    final d = _dateFromOrdinal(ordinal);
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
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
