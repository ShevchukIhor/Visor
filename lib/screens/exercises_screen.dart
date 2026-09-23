import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/exercises/exercise_painter.dart';
import '../core/gabor/gabor_patch.dart';
import '../core/theme/visor_theme.dart';

/// Per-exercise icon for the list view.
extension ExerciseIcon on ExerciseType {
  IconData get icon => switch (this) {
        ExerciseType.convergence => Icons.all_inclusive,
        ExerciseType.nearFar => Icons.zoom_out_map,
        ExerciseType.focusShift => Icons.swap_horiz,
        ExerciseType.saccadic => Icons.bolt,
        ExerciseType.pursuit => Icons.airline_stops,
        ExerciseType.figure8 => Icons.loop,
        ExerciseType.peripheral => Icons.blur_on,
        ExerciseType.orbs => Icons.bubble_chart,
      };

  /// One-line guidance shown while the exercise runs.
  String get hint => switch (this) {
        ExerciseType.convergence =>
          'Follow the dot toward the centre and back',
        ExerciseType.nearFar =>
          'Shift focus: small sharp dot is FAR, large soft disc is NEAR',
        ExerciseType.focusShift =>
          'Jump your gaze between the far-apart targets',
        ExerciseType.saccadic => 'Flick your eyes to each new position',
        ExerciseType.pursuit => 'Keep the dot locked in your gaze as it glides',
        ExerciseType.figure8 => 'Trace the loop smoothly with your eyes',
        ExerciseType.peripheral =>
          'Fixate on the centre dot; catch the flashes at the edges',
        ExerciseType.orbs =>
          'Relax and let your focus drift with the growing patches',
      };
}

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
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final e = ExerciseType.values[i];
          return Material(
            color: VisorTheme.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ExerciseRunner(type: e)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: VisorTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(e.icon, color: VisorTheme.primary, size: 24),
                    ),
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
                          const SizedBox(height: 3),
                          Text(e.subtitle,
                              style: const TextStyle(
                                  color: VisorTheme.textDim,
                                  fontSize: 12,
                                  height: 1.3)),
                        ],
                      ),
                    ),
                    const Icon(Icons.play_circle_outline,
                        color: VisorTheme.textDim, size: 26),
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
/// in the background and ends the exercise after the chosen duration. The
/// close button in the top bar exits early at any time.
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

  // Session-level randomness + clock/resources for the Gabor exercises.
  late final int _seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
  /// Drives the orbs' slow cycles. Started by [_start] so the orbs begin
  /// their first cycle when the drill does, not while the picker is up.
  final Stopwatch _clock = Stopwatch();

  /// Animation loop length: Near-Far runs a slower accommodation cycle.
  int get _loopMs => widget.type == ExerciseType.nearFar ? 16000 : 8000;

  // Decoded circular Gabor patches. Near-Far steps through them — a fresh
  // patch every accommodation cycle; Orbs just use the first one. A new
  // random set is generated for every launch of the exercise.
  final List<ui.Image> _gaborImages = [];

  /// Patch for the current accommodation cycle: the index advances exactly
  /// at each loop wrap, i.e. while the sphere sits at its minimum (FAR)
  /// hold — so the swap is imperceptible.
  ui.Image? get _gaborImage {
    if (_gaborImages.isEmpty) return null;
    if (widget.type == ExerciseType.nearFar) {
      final loop = _clock.elapsedMilliseconds ~/ _loopMs;
      return _gaborImages[loop % _gaborImages.length];
    }
    return _gaborImages.first;
  }

  // Near-Far: whether the target is a Gabor sphere or a plain dot.
  bool _nearFarGabor = false;

  /// Set as soon as decoding starts. `_gaborImages` stays empty until the
  /// first callback fires, so it cannot guard against a second request.
  bool _gaborRequested = false;

  @override
  void initState() {
    super.initState();
    // Immersive for this screen only — the dashboard and settings need their
    // system bars back.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _loopMs),
    );
    if (widget.type == ExerciseType.orbs) {
      _loadGaborImages(count: 1);
    }
  }

  void _loadGaborImages({int count = 6}) {
    if (_gaborRequested) return;
    _gaborRequested = true;
    final rng = math.Random(); // a fresh variety of patches per launch
    for (var k = 0; k < count; k++) {
      final patch = GaborPatch(
        theta: rng.nextDouble() * math.pi,
        frequency: 5 + rng.nextDouble() * 2,
        sigma: 0.45 + rng.nextDouble() * 0.2,
        phase: rng.nextDouble() * 2 * math.pi,
      );
      final rgba = renderRgbaCircular(patch, 192);
      ui.decodeImageFromPixels(
        rgba,
        192,
        192,
        ui.PixelFormat.rgba8888,
        (img) {
          if (!mounted) {
            img.dispose();
            return;
          }
          setState(() => _gaborImages.add(img));
        },
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl.dispose();
    for (final img in _gaborImages) {
      img.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _start() {
    setState(() {
      _running = true;
      _finished = false;
      _secondsLeft = _duration;
    });
    // The animation only needs to run while the drill does; repeating it
    // behind the duration picker and the finish card just burns battery.
    _clock
      ..reset()
      ..start();
    _ctrl.repeat();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final done = _secondsLeft <= 1;
      setState(() => _secondsLeft = done ? 0 : _secondsLeft - 1);
      if (done) _finish();
    });
  }

  void _finish() {
    _ticker?.cancel();
    _ctrl.stop();
    _clock.stop();
    setState(() {
      _running = false;
      _finished = true;
    });
  }

  /// Exit immediately — works at any point, including mid-exercise.
  void _exit() {
    _ticker?.cancel();
    _ctrl.stop();
    Navigator.pop(context);
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
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (ctx, _) => CustomPaint(
                painter: ExercisePainter(
                  widget.type,
                  _ctrl.value,
                  seed: _seed,
                  orbsTime: _clock.elapsedMilliseconds / 1000.0,
                  gaborImage: _gaborImage,
                  nearFarGabor: _nearFarGabor,
                ),
              ),
            ),
          ),
          // Top bar: close button + title + countdown (when running).
          SafeArea(child: _topBar()),
          // Bottom hint while running.
          if (_running)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _glassPill(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Text(
                      widget.type.hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: VisorTheme.textDim, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          // Center overlay: duration picker (before start) or finish card.
          Center(child: _overlay()),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          _glassPill(
            padding: EdgeInsets.zero,
            child: IconButton(
              icon: const Icon(Icons.close, color: VisorTheme.text, size: 20),
              tooltip: 'Exit exercise',
              onPressed: _exit,
            ),
          ),
          const SizedBox(width: 10),
          _glassPill(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              widget.type.title,
              style: const TextStyle(color: VisorTheme.text, fontSize: 14),
            ),
          ),
          const Spacer(),
          if (_running)
            _glassPill(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                _mmss(_secondsLeft),
                style: const TextStyle(
                  color: VisorTheme.text,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _targetChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? VisorTheme.primary : VisorTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? VisorTheme.primary : VisorTheme.surface,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF001428) : VisorTheme.text,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  /// Frosted-glass container used for all floating UI chrome.
  Widget _glassPill({required EdgeInsets padding, required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: VisorTheme.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
      ),
    );
  }

  /// Frosted-glass card for center overlays.
  Widget _glassCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: VisorTheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(18),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _overlay() {
    if (!_running && !_finished) {
      // Duration picker.
      return _glassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.type.title,
                style: const TextStyle(
                    color: VisorTheme.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              widget.type.hint,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: VisorTheme.textDim, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (widget.type == ExerciseType.nearFar) ...[
              const Text('Target',
                  style:
                      TextStyle(color: VisorTheme.textDim, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _targetChip('Round dot', !_nearFarGabor, () {
                    setState(() => _nearFarGabor = false);
                  }),
                  const SizedBox(width: 8),
                  _targetChip('Gabor sphere', _nearFarGabor, () {
                    setState(() => _nearFarGabor = true);
                    _loadGaborImages(count: 6);
                  }),
                ],
              ),
              const SizedBox(height: 12),
            ],
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
      return _glassCard(
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

    // Running: no center overlay (countdown lives in the top bar).
    return const SizedBox.shrink();
  }
}
