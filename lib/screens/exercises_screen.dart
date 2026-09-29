import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/db/drill.dart';
import '../core/db/vision_db.dart';
import '../core/exercises/exercise_painter.dart';
import '../core/gabor/gabor_patch.dart';
import '../core/reminder/reminder_service.dart';
import '../core/theme/visor_theme.dart';
import '../core/training/training_step.dart';

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

  /// Set when this exercise runs as one step of a saved template, so the
  /// recorded drill can be attributed to it. Null for a standalone exercise
  /// launched from the exercises list.
  final int? templateId;

  /// Fixed duration supplied by a routine step. When null the runner shows its
  /// own picker, which is the standalone path.
  final int? seconds;
  final bool autoStart;

  /// Called instead of showing the terminal card, so a session can advance.
  /// Also the signal that a session — not this widget — owns the screen's
  /// chrome: the top bar and the system-bar immersive mode.
  final VoidCallback? onDone;

  /// Near-Far target choice, fixed by a routine step.
  final bool gaborTarget;

  /// Reports the remaining seconds every time it changes, so a session that
  /// owns the chrome (see [onDone]) can show its own countdown instead of
  /// this widget's suppressed top bar.
  final ValueChanged<int>? onSecondsLeft;

  /// Called with the exact [Drill] whose write failed, in addition to
  /// setting the retry flag. Needed because when [onDone] is set, the
  /// finish overlay that would otherwise carry the retry affordance never
  /// renders — a session still needs the failed row so it can retry it.
  final void Function(Drill failed)? onRecordFailed;

  const ExerciseRunner({
    super.key,
    required this.type,
    this.templateId,
    this.seconds,
    this.autoStart = false,
    this.onDone,
    this.gaborTarget = false,
    this.onSecondsLeft,
    this.onRecordFailed,
  });

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

  /// When this run actually started — set in [_start], not back-computed
  /// from the end time, so a backgrounded app doesn't shift the recorded
  /// interval or file the drill under the wrong calendar day.
  DateTime? _startedAt;

  /// Set when writing the drill failed; drives the retry affordance in the
  /// finish overlay. Mirrors `game_screen.dart`'s `_saveError`.
  bool _saveError = false;

  /// Guards against a double write: `_record` has two call sites (natural
  /// completion in `_finish` and the Retry button), and a fast double tap on
  /// Retry would otherwise start two concurrent inserts. Mirrors
  /// `game_screen.dart`'s `_saved` flag, including resetting it on failure
  /// so a genuine error stays retryable.
  bool _saved = false;

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
    if (widget.onDone == null) {
      // Immersive for this screen only — the dashboard and settings need
      // their system bars back. In session mode `SessionRunner` owns this
      // for the whole routine instead, so the bars don't flash back on
      // between steps.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _loopMs),
    );
    if (widget.seconds != null) {
      _duration = widget.seconds!;
      _secondsLeft = _duration;
    }
    _nearFarGabor = widget.gaborTarget;
    // Gated on the type, not just the flag: `gaborTarget` only means
    // anything for Near-Far, and decoding six unused 192×192 patches for
    // any other exercise would be pure waste.
    if (widget.gaborTarget && widget.type == ExerciseType.nearFar) {
      _loadGaborImages(count: 6);
    }
    if (widget.type == ExerciseType.orbs) {
      _loadGaborImages(count: 1);
    }
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
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
    if (widget.onDone == null) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _start() {
    setState(() {
      _running = true;
      _finished = false;
      _secondsLeft = _duration;
    });
    widget.onSecondsLeft?.call(_secondsLeft);
    _startedAt = DateTime.now();
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
      widget.onSecondsLeft?.call(_secondsLeft);
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
    // A completed exercise is training: record it here, at natural
    // completion, and nowhere else (see _exit below).
    _record();
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
      return;
    }
  }

  /// A completed exercise is training: it belongs in `drills` so the streak,
  /// the today-counter and the history see it. Exiting early records nothing.
  Future<void> _record() async {
    if (_saved) return;
    final drill = drillForExercise(
      type: widget.type,
      seconds: _duration,
      // Not a literal: from the exit path this is false and the builder
      // refuses, which is what makes the guard real rather than a habit.
      completed: _finished,
      // The `??` fallback is unreachable: `_record` only runs from
      // `_finish` (called from the ticker started in `_start`, which sets
      // `_startedAt` first) or from the Retry button, which only exists
      // once `_finished` is true — i.e. after `_finish` already ran. It is
      // kept only as a type-safe default, never as a real end-time stamp.
      startedAt: _startedAt ?? DateTime.now(),
      templateId: widget.templateId,
    );
    // The guard is taken only once there is something to guard: taking it
    // before this null check would make a refused (not-completed) call
    // permanently block a real one from ever running.
    if (drill == null) return;
    _saved = true;
    try {
      await VisionDb.instance.insertDrill(drill);
      await ReminderService.markTrainedToday();
      if (!mounted) return;
      setState(() => _saveError = false);
    } catch (e) {
      // Losing a session silently while the screen says "complete" is worse
      // than an ugly message: the streak and history would disagree with
      // what the user just did.
      debugPrint('Failed to record exercise: $e');
      _saved = false;
      // Fires regardless of `mounted`: a session step routes around this
      // widget's own finish overlay via `onDone`, so this may be the only
      // place a session ever learns the write failed. Carries the exact
      // `Drill` that failed to insert, so a retry does not have to
      // reconstruct it from step configuration.
      widget.onRecordFailed?.call(drill);
      if (!mounted) return;
      setState(() => _saveError = true);
    }
  }

  /// Exit immediately — works at any point, including mid-exercise. Must
  /// never call [_record]: an exercise closed early is not training.
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
          // Suppressed in session mode — SessionRunner owns all chrome then
          // (see [onSecondsLeft]), so this doesn't paint a second bar over
          // its close button and step label.
          if (widget.onDone == null) SafeArea(child: _topBar()),
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
    if (widget.seconds != null && !_finished) {
      // A routine step supplies its own duration; the picker belongs only
      // to the standalone path.
      return const SizedBox.shrink();
    }
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
            if (_saveError) ...[
              const SizedBox(height: 16),
              const Text(
                'Could not save this exercise — your streak and history may '
                'not include it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: VisorTheme.danger, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() => _saveError = false);
                  _record();
                },
                child: const Text('Retry save'),
              ),
            ],
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
