import 'package:flutter/services.dart';

import '../db/vision_db.dart';

/// Bridges to the native reminder scheduler (AlarmManager + Receiver).
///
/// The native side checks the training marker at fire time and only notifies
/// when the user has not trained today — so reminders never nag after a
/// workout. Alarms are exact, one-shot, self-rescheduling, and survive reboot.
class ReminderService {
  static const MethodChannel _channel = MethodChannel('visor/reminder');
  static const MethodChannel _notify = MethodChannel('visor/notify');

  /// Schedule (or reschedule) the daily reminder. [hour]/[minute] are local.
  static Future<bool> schedule({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    await VisionDb.instance.setReminder(
        enabled: enabled, hour: hour, minute: minute);
    final ok = await _channel.invokeMethod<bool>('scheduleReminder', {
      'enabled': enabled,
      'hour': hour,
      'minute': minute,
    });
    return ok ?? false;
  }

  /// Whether an alarm is currently armed.
  static Future<bool> hasSchedule() async {
    try {
      final v = await _channel.invokeMethod<bool>('hasSchedule');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Fire a test notification in ~5 seconds (for verifying the pipeline).
  static Future<bool> testNotify() async {
    try {
      final v = await _notify.invokeMethod<bool>('testNotify');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// True if POST_NOTIFICATIONS is granted (API 33+). Always true below 33.
  static Future<bool> hasNotificationPermission() async {
    try {
      final v = await _notify.invokeMethod<bool>('hasNotificationPermission');
      return v ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Ask the OS for POST_NOTIFICATIONS permission (API 33+).
  ///
  /// Resolves only once the user has answered the system dialog, so the
  /// returned value is the real outcome — not the state from before it was
  /// shown.
  static Future<bool> requestNotificationPermission() async {
    try {
      final v = await _notify.invokeMethod<bool>('requestNotificationPermission');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether Android will honour exact alarms (Android 12+ gates them behind
  /// a special permission). False means reminders fall back to inexact timing.
  static Future<bool> canScheduleExactAlarms() async {
    try {
      final v = await _notify.invokeMethod<bool>('canScheduleExactAlarms');
      return v ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Open the system screen where the user can grant exact alarms.
  static Future<void> openExactAlarmSettings() async {
    try {
      await _notify.invokeMethod('openExactAlarmSettings');
    } catch (_) {}
  }

  /// Record that the user trained today (so the reminder won't nag).
  static Future<void> markTrainedToday() async {
    try {
      await _channel.invokeMethod('markTrained', {
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }
}