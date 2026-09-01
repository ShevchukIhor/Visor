import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/db/vision_db.dart';
import '../core/theme/visor_theme.dart';

/// Analytics: score trend chart + session history list.
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
                      child: Text('Score trend',
                          style: TextStyle(
                              color: VisorTheme.textDim, fontSize: 13)),
                    ),
                    SizedBox(
                      height: 180,
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: _ScoreChart(sessions: _sessions),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('History',
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
      separatorBuilder: (_, __) => const SizedBox(height: 6),
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
                    Text('${s.grid}×${s.grid} · ${s.pattern} · ${s.durationS ~/ 60} min',
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

class _ScoreChart extends StatelessWidget {
  final List<VisionSession> sessions;
  const _ScoreChart({required this.sessions});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ChartPainter(
        scores: sessions.reversed
            .map((s) => s.score)
            .toList(),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> scores;
  _ChartPainter({required this.scores});

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;
    const pad = 8.0;
    final maxScore = scores.reduce(math.max).clamp(1.0, double.infinity);
    final minScore = scores.reduce(math.min);
    final range = math.max(maxScore - minScore, 1.0);
    final denom = math.max(scores.length - 1, 1);

    final pts = <Offset>[];
    for (var i = 0; i < scores.length; i++) {
      final x = pad + (size.width - 2 * pad) * (i / denom);
      final y = size.height -
          pad -
          (size.height - 2 * pad) * ((scores[i] - minScore) / range * 0.9);
      pts.add(Offset(x, y));
    }

    final line = Paint()
      ..color = VisorTheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = VisorTheme.primary.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    final dot = Paint()..color = VisorTheme.primary;

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final fillPath = Path.from(path)
      ..lineTo(pts.last.dx, size.height - pad)
      ..lineTo(pts.first.dx, size.height - pad)
      ..close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, line);
    for (final p in pts) {
      canvas.drawCircle(p, 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.scores != scores;
}