import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/visor_theme.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fullscreen immersive mode: hide status + navigation bars.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const VisorApp());
}

class VisorApp extends StatelessWidget {
  const VisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visor',
      debugShowCheckedModeBanner: false,
      theme: VisorTheme.theme,
      home: const DashboardScreen(),
    );
  }
}