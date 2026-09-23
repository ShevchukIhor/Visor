import 'package:flutter/material.dart';

import '../core/app_info.dart';
import '../core/db/vision_db.dart';
import '../core/theme/visor_theme.dart';
import 'analytics_screen.dart';
import 'exercises_screen.dart';
import 'reminder_screen.dart';
import 'setup_screen.dart';
import 'about_screen.dart';

/// Home dashboard: streak, today, best, and navigation to training modes.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _streak = 0;
  int _today = 0;
  double _best = 0;
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final streak = await VisionDb.instance.streak();
    final today = await VisionDb.instance.sessionsOnDay(DateTime.now());
    final best = await VisionDb.instance.bestScore();
    final version = await AppInfo.version();
    if (!mounted) return;
    setState(() {
      _streak = streak;
      _today = today;
      _best = best;
      _version = version;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Text(
                    'VISOR',
                    style: TextStyle(
                      color: VisorTheme.primary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'vision training',
                    style:
                        TextStyle(color: VisorTheme.textDim, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _statsRow(),
              const SizedBox(height: 24),
              _menuButton(
                icon: Icons.play_arrow,
                title: 'Start Training',
                subtitle: 'Gabor patch game — trains your visual cortex',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SetupScreen()),
                ).then((_) => _load()),
              ),
              _menuButton(
                icon: Icons.visibility,
                title: 'Eye Exercises',
                subtitle: 'Guided movements — reduces strain & coordination',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ExercisesScreen()),
                ),
              ),
              _menuButton(
                icon: Icons.alarm,
                title: 'Reminder',
                subtitle: 'Daily nudge to keep your streak alive',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReminderScreen()),
                ),
              ),
              _menuButton(
                icon: Icons.insights,
                title: 'Analytics',
                subtitle: 'Score trends, session history & progress',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
                ),
              ),
              _menuButton(
                icon: Icons.info_outline,
                title: 'Support Visor',
                subtitle: 'About this app and tipping',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                ),
              ),
              const Spacer(),
              Center(
                child: Text(
                  'Next break: train daily to build your streak',
                  style: TextStyle(
                      color: VisorTheme.textDim.withValues(alpha: 0.7),
                      fontSize: 12),
                ),
              ),
              const SizedBox(height: 6),
              if (_version != null)
                Center(
                  child: Text(
                    'Version $_version',
                    style: TextStyle(
                        color: VisorTheme.textDim.withValues(alpha: 0.5),
                        fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsRow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VisorTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('Streak', '$_streak-day', VisorTheme.accent),
          _stat('Today', '$_today sessions', VisorTheme.text),
          _stat('Best', _best.toStringAsFixed(0), VisorTheme.success),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style:
                const TextStyle(color: VisorTheme.textDim, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _menuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: VisorTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: VisorTheme.primary, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: VisorTheme.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              color: VisorTheme.textDim, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: VisorTheme.textDim, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}