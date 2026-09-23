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

class _ReminderScreenState extends State<ReminderScreen>
    with WidgetsBindingObserver {
  bool _enabled = false;
  int _hour = 21;
  int _minute = 0;
  bool _loaded = false;
  bool _scheduled = false;
  bool _testing = false;
  bool _hasPermission = true;
  bool _canScheduleExact = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Both permissions can be changed from system settings while this screen
  /// sits in the background, so re-read them on the way back in.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final r = await VisionDb.instance.getReminder();
      final hasPerm = await ReminderService.hasNotificationPermission();
      final scheduled = await ReminderService.hasSchedule();
      final exact = await ReminderService.canScheduleExactAlarms();
      if (!mounted) return;
      setState(() {
        _enabled = (r['enabled'] as int?) == 1;
        _hour = (r['hour'] as int?) ?? 21;
        _minute = (r['minute'] as int?) ?? 0;
        _hasPermission = hasPerm;
        _scheduled = scheduled;
        _canScheduleExact = exact;
        _loaded = true;
      });
    } catch (_) {
      // Never leave the screen stuck on the loading spinner.
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _hasPermission = true;
        _scheduled = false;
        _canScheduleExact = true;
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
    // Ask for notification permission when enabling (API 33+). The call
    // resolves only after the user answers, so this is the real outcome.
    if (v && !_hasPermission) {
      final granted = await ReminderService.requestNotificationPermission();
      if (!mounted) return;
      setState(() => _hasPermission = granted);
    }
    await _save();
  }

  Future<void> _save() async {
    final ok = await ReminderService.schedule(
        enabled: _enabled, hour: _hour, minute: _minute);
    final exact = await ReminderService.canScheduleExactAlarms();
    if (!mounted) return;
    setState(() {
      _scheduled = ok && _enabled;
      _canScheduleExact = exact;
    });
    if (!_enabled) {
      _snack('Reminder turned off');
      return;
    }
    if (!ok) {
      _snack('Could not schedule the reminder');
      return;
    }
    if (exact) {
      _snack('Reminder scheduled for ${_fmt(_hour, _minute)}');
    } else {
      // The alarm is armed, just not exact — say so and offer the fix rather
      // than leaving the user to wonder why it drifts.
      _snack(
        'Scheduled for ${_fmt(_hour, _minute)}, but timing may drift',
        action: SnackBarAction(
          label: 'Fix',
          onPressed: ReminderService.openExactAlarmSettings,
        ),
      );
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

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        action: action,
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
                          activeThumbColor: VisorTheme.primary,
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
                  if (!_canScheduleExact) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: Text(
                            'Android is not allowing exact alarms, so the reminder may arrive late.',
                            style: TextStyle(
                                color: VisorTheme.accent, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: ReminderService.openExactAlarmSettings,
                          child: const Text('Allow'),
                        ),
                      ],
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