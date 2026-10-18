import 'package:flutter/material.dart';

/// Visor dark theme. Low-light palette tuned for a vision-training app so the
/// screen doesn't glare during exercises.
class VisorTheme {
  VisorTheme._();

  // Palette — dark, calm, high contrast for the Gabor patches to pop.
  static const Color bg = Color(0xFF0B0B0F);
  static const Color surface = Color(0xFF16161C);
  static const Color surfaceAlt = Color(0xFF1F1F27);
  static const Color primary = Color(0xFF4D9FFF);
  static const Color primaryDim = Color(0xFF2B6CB8);
  static const Color text = Color(0xFFE8E8EE);
  static const Color textDim = Color(0xFF8A8A96);
  static const Color accent = Color(0xFFFF9B3D); // streak/today accent
  static const Color success = Color(0xFF3DDC84);
  static const Color danger = Color(0xFFFF5A5F);

  /// Secondary text on a filled [primary] chip. 5.3:1 on [primary]; the old
  /// #123A66 measured 4.2:1, under the 4.5:1 WCAG floor for 14px text.
  static const Color onPrimaryDim = Color(0xFF0A2A4D);

  // Type scale — the only font sizes the app uses. Off-scale values (12.5,
  // 15) were normalised into this set so the hierarchy reads consistently.
  static const double fsCaption = 11;
  static const double fsSmall = 12;
  static const double fsNote = 13;
  static const double fsBody = 14;
  static const double fsTitle = 16;
  static const double fsTitleLg = 18;
  static const double fsDisplay = 24;
  static const double fsDisplayLg = 28;

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: primaryDim,
          surface: surface,
          onSurface: text,
          onPrimary: Color(0xFF001428),
        ),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: text),
          bodyMedium: TextStyle(color: text),
        ),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      );
}