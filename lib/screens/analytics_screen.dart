import 'package:flutter/material.dart';

import '../core/analytics/chart_math.dart';
import '../core/db/vision_db.dart';
import '../core/theme/visor_theme.dart';
import '../widgets/accuracy_chart.dart';

/// Analytics: daily accuracy chart + session history list.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<VisionSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await VisionDb.instance.allSessions();
    if (!mounted) return;
    setState(() {
      _sessions = s;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final legend = legendOf(aggregateByDay(_sessions.map(toSample).toList()));
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: const Text('Analytics'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(
                  child: Text('No sessions yet',
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
                        child: AccuracyChart(sessions: _sessions),
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

  Widget _historyList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (ctx, i) {
        final s = _sessions[i];
        final dt = s.startedAt;
        final date =
            '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
                    Text(
                        '${s.grid}\u00D7${s.grid} \u00B7 ${s.pattern} \u00B7 ${s.durationS ~/ 60} min',
                        style: const TextStyle(
                            color: VisorTheme.text, fontSize: 14)),
                    Text(date,
                        style: const TextStyle(
                            color: VisorTheme.textDim, fontSize: 11)),
                  ],
                ),
              ),
              Text('${s.correct}/${s.total}',
                  style: const TextStyle(
                      color: VisorTheme.text, fontSize: 14)),
              const SizedBox(width: 12),
              Text(
                s.score.toStringAsFixed(0),
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
