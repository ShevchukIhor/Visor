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
                      child: Text(
                          'Score trend',
                          style: TextStyle(
                              color: VisorTheme.textDim, fontSize: 13)),
                    ),
                    SizedBox(
                      height: 200,
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: _ScoreChart(sessions: _sessions),
                      ),
                    ),
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

class _ScoreChart extends StatelessWidget {
  final List<VisionSession> sessions;
  const _ScoreChart({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final pts = sessions
        .map((s) => _ChartPoint(s.score, s.startedAt, s.id))
        .toList()
      // Deterministic order: time, then id. A plain time sort is unstable,
      // so two sessions recorded in the same millisecond could swap and
      // reshape the line (the 100-peak would jump off the middle).
      ..sort((a, b) {
        final c = a.time.compareTo(b.time);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return CustomPaint(painter: _ChartPainter(points: pts));
  }
}

class _ChartPoint {
  final double score;
  final DateTime time;
  final int id;
  const _ChartPoint(this.score, this.time, this.id);
}

class _ChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  _ChartPainter({required this.points});

  static const double padL = 34;
  static const double padR = 14;
  static const double padT = 22;
  static const double padB = 20;

  /// Round a raw max up to a clean ceiling (0-based scale so height is
  /// proportional to the real value, not to a min..max window).
  static double niceCeil(double v) {
    if (v <= 0) return 10;
    final exp = (math.log(v) / math.log(10)).floorToDouble();
    final mag = math.pow(10.0, exp).toDouble();
    final n = v / mag;
    final nice = [1.0, 2.0, 2.5, 5.0, 10.0]
        .firstWhere((c) => n <= c, orElse: () => 10.0);
    return nice * mag;
  }

  /// Snap a label value to a clean number so gridlines/labels are round
  /// (e.g. yMax=100 -> "0/50/100", not "0/55/100").
  static double _niceLabel(double v, double yMax) {
    final f = v / yMax;
    final snapped = (f * 2.0).roundToDouble() / 2.0;
    return snapped * yMax;
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  void _label(
      Canvas canvas,
      TextPainter tp,
      String text,
      TextStyle style,
      Offset pos) {
    tp.text = TextSpan(text: text, style: style);
    tp.layout(maxWidth: double.infinity);
    tp.paint(canvas, pos);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final plotW = math.max(w - padL - padR, 1);
    final plotH = math.max(h - padT - padB, 1);
    final baseY = padT + plotH;

    final maxScore = points.reduce((a, b) => a.score > b.score ? a : b).score;
    final yMax = niceCeil(maxScore);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    final dimStyle = TextStyle(color: VisorTheme.textDim, fontSize: 10);

    // grid: 0 / 50% / 100% with numeric Y labels.
    final grid = Paint()
      ..color = VisorTheme.textDim.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = padT + plotH * (1 - f);
      canvas.drawLine(Offset(padL, y), Offset(padL + plotW, y), grid);
      _label(
          canvas,
          tp,
          _niceLabel(f * yMax, yMax).toStringAsFixed(0),
          dimStyle,
          Offset(padL - 28, y - 7));
    }

    final n = points.length;
    Offset xy(int i) {
      final x = padL + (n <= 1 ? plotW / 2 : plotW * (i / (n - 1)));
      final y = baseY - (points[i].score / yMax) * plotH;
      return Offset(x, y);
    }

    // x-axis date labels (first / last).
    if (n >= 2) {
      _label(canvas, tp, _date(points.first.time), dimStyle,
          Offset(padL, baseY + 6));
      _label(canvas, tp, _date(points.last.time), dimStyle,
          Offset(padL + plotW - 28, baseY + 6));
    }

    if (n == 1) {
      final p = xy(0);
      canvas.drawCircle(p, 4, Paint()..color = VisorTheme.primary);
      _label(
          canvas,
          tp,
          points.first.score.toStringAsFixed(0),
          TextStyle(
              color: VisorTheme.text,
              fontSize: 12,
              fontWeight: FontWeight.bold),
          Offset(p.dx - 12, p.dy - 22));
      return;
    }

    final pts = [for (var i = 0; i < n; i++) xy(i)];

    final line = Paint()
      ..color = VisorTheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = VisorTheme.primary.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final dot = Paint()..color = VisorTheme.primary;

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final fillPath = Path.from(path)
      ..lineTo(pts.last.dx, baseY)
      ..lineTo(pts.first.dx, baseY)
      ..close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, line);
    for (final p in pts) {
      canvas.drawCircle(p, 3, dot);
    }

    final lp = pts.last;
    _label(
        canvas,
        tp,
        points.last.score.toStringAsFixed(0),
        TextStyle(
            color: VisorTheme.text, fontSize: 12, fontWeight: FontWeight.bold),
        Offset(lp.dx - 12, lp.dy - 20 < 4 ? 4 : lp.dy - 20));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.points != points;
}