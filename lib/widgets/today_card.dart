import 'package:flutter/material.dart';

import '../core/db/vision_db.dart';
import '../core/theme/visor_theme.dart';
import '../core/training/template_repo.dart';
import '../core/training/training_step.dart';
import '../screens/session_runner.dart';
import '../screens/week_plan_screen.dart';

/// The routine assigned to today's weekday, or an invitation to plan the
/// week. It is a suggestion, not a gate: the dashboard's menu still reaches
/// every training mode in one tap.
class TodayCard extends StatefulWidget {
  const TodayCard({super.key, required this.onChanged});

  /// Called after the card has caused a state change (a session ran, or the
  /// week was planned) so the dashboard can refresh its stats.
  final VoidCallback onChanged;

  @override
  State<TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<TodayCard> {
  TemplateRepo? _repo;
  Template? _today;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final db = await VisionDb.instance.db;
    if (!mounted) return;
    _repo = TemplateRepo(db);
    await _load();
  }

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    final t = await repo.forWeekday(DateTime.now().weekday);
    if (!mounted) return;
    setState(() {
      _today = t;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 92);
    final t = _today;
    final weekday = _weekdayName(DateTime.now().weekday);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VisorTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: VisorTheme.primary.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(weekday.toUpperCase(),
                  style: const TextStyle(
                      color: VisorTheme.textDim,
                      fontSize: 11,
                      letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Text(t?.name ?? 'No routine for $weekday',
                  style: const TextStyle(
                      color: VisorTheme.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              if (t != null) ...[
                const SizedBox(height: 3),
                Text('${t.steps.length} steps · ~${(t.totalSeconds / 60).round()} min',
                    style: const TextStyle(
                        color: VisorTheme.textDim, fontSize: 12)),
              ],
            ],
          ),
        ),
        if (t != null && isRunnable(t.steps))
          FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SessionRunner(template: t)),
            ).then((_) => widget.onChanged()),
            child: const Text('Start'),
          )
        else
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WeekPlanScreen()),
            ).then((_) => _load()),
            child: const Text('Plan week'),
          ),
      ]),
    );
  }
}

/// DateTime.weekday is 1-7, Monday first (ISO).
String _weekdayName(int weekday) => const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][weekday - 1];
