import 'package:flutter/material.dart';

import '../core/db/vision_db.dart';
import '../core/reminder/reminder_service.dart';
import '../core/theme/visor_theme.dart';

/// Reminder settings: daily time + on/off + a live test button.
class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  bool _enabled = false;
  int _hour = 21;
  int _minute = 0;
  bool _loaded = false;
  bool _scheduled = false;
  bool _testing = false;
  bool _hasPermission = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await VisionDb.instance.getReminder();
      final hasPerm = await ReminderService.hasNotificationPermission();
      final scheduled = await ReminderService.hasSchedule();
      if (!mounted) return;
      setState(() {
        _enabled = (r['enabled'] as int?) == 1;
        _hour = (r['hour'] as int?) ?? 21;
        _minute = (r['minute'] as int?) ?? 0;
        _hasPermission = hasPerm;
        _scheduled = scheduled;
        _loaded = true;
      });
    } catch (_) {
      // Never leave the screen stuck on the loading spinner.
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _hasPermission = true;
        _scheduled = false;
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (t == null) return;
    setState(() {
      _hour = t.hour;
      _minute = t.minute;
    });
    if (_enabled) await _save();
  }

  Future<void> _toggle(bool v) async {
    setState(() => _enabled = v);
    // Ask for notification permission when enabling (API 33+).
    if (v && !_hasPermission) {
      await ReminderService.requestNotificationPermission();
      _hasPermission = await ReminderService.hasNotificationPermission();
    }
    await _save();
  }

  Future<void> _save() async {
    final ok = await ReminderService.schedule(
        enabled: _enabled, hour: _hour, minute: _minute);
    if (!mounted) return;
    setState(() => _scheduled = ok);
    if (ok) {
      _snack('Reminder scheduled for ${_fmt(_hour, _minute)}');
    } else {
      _snack('Could not schedule (exact-alarm permission missing)');
    }
  }

  Future<void> _testNow() async {
    setState(() => _testing = true);
    final ok = await ReminderService.testNotify();
    if (!mounted) return;
    setState(() => _testing = false);
    _snack(ok ? 'Test notification will fire in ~5s' : 'Test failed');
  }

  String _fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: const Text('Reminder'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Train daily to keep your streak. We remind you once a day — only if you haven\'t trained yet.',
                    style:
                        TextStyle(color: VisorTheme.textDim, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: VisorTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Text('Enable daily reminder',
                            style: TextStyle(
                                color: VisorTheme.text, fontSize: 16)),
                        const Spacer(),
                        Switch(
                          value: _enabled,
                          activeColor: VisorTheme.primary,
                          onChanged: _toggle,
                        ),
                      ],
                    ),
                  ),
                  if (!_hasPermission) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Notifications are disabled for Visor. Enable them in Android settings to receive reminders.',
                      style: TextStyle(color: VisorTheme.danger, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Material(
                    color: VisorTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickTime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time,
                                color: VisorTheme.primary),
                            const SizedBox(width: 14),
                            Text(
                              _fmt(_hour, _minute),
                              style: const TextStyle(
                                  color: VisorTheme.text, fontSize: 20),
                            ),
                            const Spacer(),
                            Icon(
                              _scheduled
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              color: _scheduled
                                  ? VisorTheme.success
                                  : VisorTheme.textDim,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right,
                                color: VisorTheme.textDim),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: VisorTheme.primary,
                        side: const BorderSide(color: VisorTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _testing ? null : _testNow,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.notifications_active),
                      label: const Text('Send test notification'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}