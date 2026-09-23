import 'package:flutter/services.dart';

/// App metadata read from the platform, so no screen hardcodes a version
/// string that can fall out of step with `pubspec.yaml`.
class AppInfo {
  static const MethodChannel _channel = MethodChannel('visor/app');

  static String? _cached;

  /// `versionName` from the Android package, or null when unavailable.
  static Future<String?> version() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final v = await _channel.invokeMethod<String>('appVersion');
      if (v == null || v.isEmpty) return null;
      _cached = v;
      return v;
    } catch (_) {
      return null;
    }
  }
}
