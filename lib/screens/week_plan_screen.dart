import 'package:flutter/material.dart';

import '../core/db/vision_db.dart';
import '../core/reminder/reminder_service.dart';
import '../core/theme/visor_theme.dart';
import '../core/training/template_repo.dart';
import '../core/training/training_step.dart';

/// Assigns a routine (or a rest day) to each weekday. The plan is what the
/// dashboard's Today card shows; nothing else reads it until Task 8.
class WeekPlanScreen extends StatefulWidget {
  const WeekPlanScreen({super.key});

  @override
  State<WeekPlanScreen> createState() => _WeekPlanScreenState();
}

class _WeekPlanScreenState extends State<WeekPlanScreen> {
  late TemplateRepo _repo;
  List<Template> _templates = [];
  Map<int, int?> _plan = {};
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
    // A first-launch user may open the plan before the templates screen,
    // which is the only other place that seeds; `seedPresets` is idempotent
    // (see templates_screen.dart), so seeding here is cheap.
    await _repo.seedPresets();
    final templates = await _repo.all();
    final plan = await _repo.weekPlan();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _plan = plan;
      _loading = false;
    });
  }

  /// Publishes the plan to the notification labels. Best effort: a failed
  /// channel call (no plugin in widget tests) must not break the UI.
  Future<void> _publishLabels() async {
    try {
      await ReminderService.publishWeekLabels(await weekLabels(_repo));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: const Text('Weekly plan'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: VisorTheme.primary))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                for (var d = 1; d <= 7; d++) _row(d),
              ]),
            ),
    );
  }

  Widget _row(int weekday) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
            width: 108,
            child: Text(_weekdayName(weekday),
                style: const TextStyle(
                    color: VisorTheme.text, fontSize: 14)),
          ),
          Expanded(
            child: DropdownButton<int?>(
              isExpanded: true,
              dropdownColor: VisorTheme.surfaceAlt,
              value: _plan[weekday],
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('Rest day')),
                for (final t in _templates)
                  DropdownMenuItem<int?>(value: t.id, child: Text(t.name)),
              ],
              onChanged: (id) async {
                await _repo.setWeekday(weekday, id);
                await _publishLabels(); // Task 8
                await _load();
              },
            ),
          ),
        ]),
      );
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
