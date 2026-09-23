import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/visor_theme.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the system bars but keep them reachable. The training and
  // exercise screens opt into immersive mode for their own duration; hiding
  // the bars app-wide also hid them behind time pickers and snackbars.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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