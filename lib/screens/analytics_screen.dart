import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/analytics/chart_math.dart';
import '../core/db/drill.dart';
import '../core/db/vision_db.dart';
import '../core/exercises/exercise_painter.dart';
import '../core/theme/visor_theme.dart';
import '../widgets/accuracy_chart.dart';

/// Display name for a history row: an exercise resolves its `params.type`
/// to the human title ("Convergence Training"), anything else keeps the raw
/// task id so a future task type still renders.
String taskDisplayName(Drill d) {
  if (d.task != taskExercise || d.params == null) return d.task;
  try {
    final m = jsonDecode(d.params!) as Map<String, Object?>;
    final type = m['type'] as String?;
    for (final e in ExerciseType.values) {
      if (e.name == type) return e.title;
    }
  } catch (_) {
    // malformed params: fall through to the raw task id
  }
  return d.task;
}

/// Analytics: daily accuracy chart + drill history list.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<Drill> _drills = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await VisionDb.instance.allDrills();
    if (!mounted) return;
    setState(() {
      _drills = d;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final legend = legendOf(aggregateByDay(gaborSamples(_drills).toList()));
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: const Text('Analytics'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _drills.isEmpty
              ? const Center(
                  child: Text('No drills yet',
                      style: TextStyle(color: VisorTheme.textDim)))
              : Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                          'Daily accuracy',
                          style: TextStyle(
                              color: VisorTheme.textDim, fontSize: 13)),
                    ),
                    SizedBox(
                      height: 200,
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: AccuracyChart(drills: _drills),
                      ),
                    ),
                    const SizedBox(height: 6),
                    AccuracyChartLegend(difficulties: legend),
                    const SizedBox(height: 8),
                    const Text(
                        'History',
                        style: TextStyle(
                            color: VisorTheme.textDim, fontSize: 13)),
                    Expanded(child: _historyList()),
                  ],
                ),
    );
  }

  /// Grid size and stripe pattern, stored in `params` for the Gabor game.
  /// Other tasks (an exercise, later a measured drill) have no such shape.
  (int, String)? _gaborParams(Drill d) {
    if (d.task != taskGaborGrid || d.params == null) return null;
    final m = jsonDecode(d.params!) as Map<String, Object?>;
    final grid = m['grid'] as int?;
    final pattern = m['pattern'] as String?;
    if (grid == null || pattern == null) return null;
    return (grid, pattern);
  }

  Widget _historyList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _drills.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (ctx, i) {
        final d = _drills[i];
        final dt = d.startedAt;
        final date =
            '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        final gabor = _gaborParams(d);
        final label = gabor != null
            ? '${gabor.$1}\u00D7${gabor.$1} \u00B7 ${gabor.$2} \u00B7 ${d.durationS ~/ 60} min'
            : '${taskDisplayName(d)} \u00B7 ${d.durationS ~/ 60} min';
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: VisorTheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: VisorTheme.text, fontSize: 14)),
                    Text(date,
                        style: const TextStyle(
                            color: VisorTheme.textDim, fontSize: 11)),
                  ],
                ),
              ),
              if (d.trials > 0) ...[
                Text('${d.correct}/${d.trials}',
                    style: const TextStyle(
                        color: VisorTheme.text, fontSize: 14)),
                const SizedBox(width: 12),
              ],
              Text(
                d.score?.toStringAsFixed(0) ?? '\u2014',
                style: const TextStyle(
                    color: VisorTheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      },
    );
  }
}
