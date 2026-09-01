import 'dart:async';

import 'package:flutter/material.dart';

import '../core/exercises/exercise_painter.dart';
import '../core/theme/visor_theme.dart';

/// List of eye exercises, plus a full-screen runner for each.
class ExercisesScreen extends StatelessWidget {
  const ExercisesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: const Text('Eye Exercises'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: ExerciseType.values.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final e = ExerciseType.values[i];
          return Material(
            color: VisorTheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ExerciseRunner(type: e)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.remove_red_eye,
                        color: VisorTheme.primary, size: 26),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title,
                              style: const TextStyle(
                                  color: VisorTheme.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(e.subtitle,
                              style: const TextStyle(
                                  color: VisorTheme.textDim, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.play_circle_outline,
                        color: VisorTheme.textDim, size: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen, immersive runner for a single exercise.
///
/// The animation drives the moving target; a separate countdown timer runs
/// in the background and ends the exercise after the chosen duration, so
/// exercises no longer play indefinitely.
class ExerciseRunner extends StatefulWidget {
  final ExerciseType type;
  const ExerciseRunner({super.key, required this.type});

  @override
  State<ExerciseRunner> createState() => _ExerciseRunnerState();
}

const List<int> _kExerciseDurations = [30, 60, 120]; // seconds

class _ExerciseRunnerState extends State<ExerciseRunner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Chosen duration (before start) and remaining time (during run).
  int _duration = 60;
  int _secondsLeft = 60;
  bool _running = false;
  bool _finished = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _running = true;
      _finished = false;
      _secondsLeft = _duration;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          _secondsLeft = 0;
          _finish();
        }
      });
    });
  }

  void _finish() {
    _ticker?.cancel();
    setState(() {
      _running = false;
      _finished = true;
    });
  }

  String _mmss(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      body: GestureDetector(
        onTap: _running ? null : () => Navigator.pop(context),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (ctx, _) => CustomPaint(
                  painter: ExercisePainter(widget.type, _ctrl.value),
                ),
              ),
            ),
            // Top-left: title + close.
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.close,
                          color: VisorTheme.textDim, size: 28),
                      const SizedBox(height: 4),
                      Text(
                        widget.type.title,
                        style: const TextStyle(
                            color: VisorTheme.textDim, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Center overlay: duration picker (before start) or countdown + finish.
            Center(child: _overlay()),
          ],
        ),
      ),
    );
  }

  Widget _overlay() {
    if (!_running && !_finished) {
      // Duration picker.
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: VisorTheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Duration',
                style: TextStyle(color: VisorTheme.textDim, fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: _kExerciseDurations.map((d) {
                final active = _duration == d;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _duration = d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: active
                            ? VisorTheme.primary
                            : VisorTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active
                              ? VisorTheme.primary
                              : VisorTheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        '${d}s',
                        style: TextStyle(
                          color: active
                              ? const Color(0xFF001428)
                              : VisorTheme.text,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: VisorTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _start,
                child: const Text('Start'),
              ),
            ),
          ],
        ),
      );
    }

    if (_finished) {
      // Finish screen.
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: VisorTheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Exercise complete',
                style: TextStyle(color: VisorTheme.text, fontSize: 20)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: VisorTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      );
    }

    // Running: show countdown in the top-right corner.
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: VisorTheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _mmss(_secondsLeft),
            style: const TextStyle(
              color: VisorTheme.text,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}