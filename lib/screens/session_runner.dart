import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/db/drill.dart';
import '../core/db/vision_db.dart';
import '../core/exercises/exercise_painter.dart';
import '../core/gabor/gabor_patch.dart';
import '../core/reminder/reminder_service.dart';
import '../core/theme/visor_theme.dart';
import '../core/training/training_step.dart';
import 'exercises_screen.dart';
import 'game_screen.dart';
import '../core/models/session_setup.dart';

/// Walks a routine's steps without returning to any list.
///
/// Each step gets a fresh child keyed by its index: ExerciseRunner builds its
/// AnimationController in initState from a per-type loop length, so switching
/// type inside one State is not possible. A new key is the idiomatic way to
/// get a new State, a new controller and a clean dispose.
class SessionRunner extends StatefulWidget {
  // Not `const`: the assert calls `isRunnable`, which isn't a constant
  // expression, and a `Template` is always loaded at runtime anyway.
  SessionRunner({super.key, required this.template})
      : assert(
          isRunnable(template.steps),
          'SessionRunner requires at least one non-rest step; check '
          'isRunnable(template.steps) before pushing this route.',
        );
  final Template template;

  @override
  State<SessionRunner> createState() => _SessionRunnerState();
}

/// A step whose `drills` write failed, carrying the exact [Drill] the failing
/// widget already built and tried to insert — not a reconstruction from step
/// configuration, which cannot recover runtime fields like a Gabor game's
/// trial count and score.
class _FailedStep {
  _FailedStep({required this.index, required this.drill});
  final int index;
  final Drill drill;
}

class _SessionRunnerState extends State<SessionRunner> {
  int _index = 0;
  bool _done = false;

  /// Steps that failed to save, in case any is retried from the finish card.
  final List<_FailedStep> _failedSteps = [];
  bool _retrying = false;

  /// Live progress for the current step, fed by its `onSecondsLeft`/
  /// `onProgress` callback since that step's own top bar is hidden — this is
  /// what the session's bar shows in its place. Reset to nothing every time
  /// the step changes, so a new step never briefly shows the last one's
  /// numbers.
  int? _stepSecondsLeft;
  int _stepCorrect = 0;
  int _stepTotal = 0;

  List<TrainingStep> get _steps => widget.template.steps;

  @override
  void initState() {
    super.initState();
    // Immersive for the whole routine, owned here rather than by each step:
    // Flutter builds the incoming step's State before disposing the
    // outgoing one, so if both children set this themselves, the outgoing
    // step's dispose puts the system bars back right after the incoming step
    // hid them — from the second step onward the bars just stay visible.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _next() {
    if (_index + 1 >= _steps.length) {
      setState(() => _done = true);
    } else {
      setState(() {
        _index++;
        _stepSecondsLeft = null;
        _stepCorrect = 0;
        _stepTotal = 0;
      });
    }
  }

  void _onExerciseTick(int secondsLeft) {
    if (!mounted) return;
    setState(() => _stepSecondsLeft = secondsLeft);
  }

  void _onGameProgress(int secondsLeft, int correct, int total) {
    if (!mounted) return;
    setState(() {
      _stepSecondsLeft = secondsLeft;
      _stepCorrect = correct;
      _stepTotal = total;
    });
  }

  /// Records a step's write failure. Called from a step widget's
  /// `onRecordFailed`, which may fire after that widget has already been
  /// replaced by the next step — so it must not touch the widget, only the
  /// `Drill` it handed up.
  void _recordFailure(int index, Drill drill) {
    if (!mounted) return;
    setState(() => _failedSteps.add(_FailedStep(index: index, drill: drill)));
  }

  Future<void> _retryFailed() async {
    if (_failedSteps.isEmpty || _retrying) return;
    setState(() => _retrying = true);
    final stillFailed = <_FailedStep>[];
    for (final failed in _failedSteps) {
      try {
        await VisionDb.instance.insertDrill(failed.drill);
        await ReminderService.markTrainedToday();
      } catch (e) {
        debugPrint('Retry failed for routine step ${failed.index}: $e');
        stillFailed.add(failed);
      }
    }
    if (!mounted) return;
    setState(() {
      _failedSteps
        ..clear()
        ..addAll(stillFailed);
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // `isRunnable` is asserted in the constructor, which only fires in
    // debug/test builds — this is the release-mode guard against the same
    // condition: an empty step list would otherwise crash on `_steps[0]`,
    // and a rest-only one would run a chain of countdowns, record nothing,
    // and still show the "complete" card below as if training had happened.
    if (_steps.isEmpty || !isRunnable(_steps)) return _nothingToRunCard();
    if (_done) return _finishCard();
    final step = _steps[_index];
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      body: Stack(children: [
        Positioned.fill(child: _stage(step)),
        SafeArea(child: _progressBar(step)),
      ]),
    );
  }

  Widget _stage(TrainingStep step) {
    final key = ValueKey('step-$_index');
    final index = _index;
    return switch (step) {
      ExerciseStep(:final type, :final seconds, :final gaborTarget) =>
        _exerciseStage(key, index, type, seconds, gaborTarget),
      GaborGameStep(:final difficulty, :final seconds, :final curved) =>
        _gameStage(key, index, difficulty, seconds, curved),
      // Patterns must BIND: in a switch expression the scrutinee is not
      // promoted, so `RestStep()` alone would leave `step` typed TrainingStep.
      final RestStep rest => _RestCard(
          key: key,
          step: rest,
          next: index + 1 < _steps.length ? _steps[index + 1].title : null,
          onDone: _next,
        ),
      // Reserved for the psychophysical engine, not rendered until that
      // lands — advance past it immediately rather than making the user
      // watch a full-duration countdown for a step that does nothing.
      DrillStep() => _AutoSkip(key: key, onDone: _next),
    };
  }

  Widget _exerciseStage(
    Key key,
    int index,
    ExerciseType type,
    int seconds,
    bool gaborTarget,
  ) {
    return ExerciseRunner(
      key: key,
      type: type,
      seconds: seconds,
      gaborTarget: gaborTarget,
      autoStart: true,
      onDone: _next,
      onSecondsLeft: _onExerciseTick,
      templateId: widget.template.id,
      onRecordFailed: (drill) => _recordFailure(index, drill),
    );
  }

  Widget _gameStage(
    Key key,
    int index,
    Difficulty difficulty,
    int seconds,
    bool curved,
  ) {
    return GameScreen(
      key: key,
      setup: SessionSetup(
          durationS: seconds, difficulty: difficulty, curved: curved),
      templateId: widget.template.id,
      onDone: _next,
      onProgress: _onGameProgress,
      onRecordFailed: (drill) => _recordFailure(index, drill),
    );
  }

  Widget _progressBar(TrainingStep step) {
    final total = _steps.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close, color: VisorTheme.text, size: 20),
          tooltip: 'Quit routine',
          // A quit is not a finish — pop `false` so a launcher can tell the
          // two apart (and knows whether to refresh, e.g., the dashboard).
          onPressed: () => Navigator.pop(context, false),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${_index + 1}/$total · ${step.title}',
                    style:
                        const TextStyle(color: VisorTheme.text, fontSize: 14)),
              ),
              // The current step's own top bar is hidden in session mode
              // (see ExerciseRunner.onSecondsLeft / GameScreen.onProgress);
              // this is where its countdown and score reappear instead.
              if (_stepSecondsLeft != null) ...[
                const SizedBox(width: 8),
                Text(_mmss(_stepSecondsLeft!),
                    style: const TextStyle(
                        color: VisorTheme.text,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ],
              if (_stepTotal > 0) ...[
                const SizedBox(width: 10),
                Text('✓ $_stepCorrect ✗ ${_stepTotal - _stepCorrect}',
                    style:
                        const TextStyle(color: VisorTheme.text, fontSize: 13)),
              ],
            ]),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (_index + 1) / total,
              backgroundColor: VisorTheme.surfaceAlt,
              color: VisorTheme.primary,
              minHeight: 3,
            ),
          ]),
        ),
      ]),
    );
  }

  String _mmss(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  Widget _finishCard() {
    final mins = (widget.template.totalSeconds / 60).round();
    final failed = _failedSteps.length;
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              failed > 0 ? Icons.warning_amber_rounded : Icons.check_circle,
              color: failed > 0 ? VisorTheme.danger : VisorTheme.success,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(widget.template.name,
                style: const TextStyle(
                    color: VisorTheme.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('${_steps.length} steps · ~$mins min',
                style: const TextStyle(
                    color: VisorTheme.textDim, fontSize: 14)),
            if (failed > 0) ...[
              const SizedBox(height: 16),
              Text(
                'Could not save $failed step${failed == 1 ? '' : 's'} — your '
                'streak and history may not include ${failed == 1 ? 'it' : 'them'}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: VisorTheme.danger, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _retrying ? null : _retryFailed,
                child: Text(_retrying ? 'Retrying…' : 'Retry save'),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Done'),
            ),
          ]),
        ),
      ),
    );
  }

  /// Shown instead of crashing on an empty step list, or of running a chain
  /// of countdowns and then claiming training happened for a routine made
  /// only of rest — see [isRunnable].
  Widget _nothingToRunCard() {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.info_outline,
                color: VisorTheme.textDim, size: 56),
            const SizedBox(height: 16),
            Text(widget.template.name,
                style: const TextStyle(
                    color: VisorTheme.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Nothing to run — this routine has no training steps.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VisorTheme.textDim, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Advances past a step with nothing to render, on the next frame. Used for
/// `DrillStep`, which is reserved for a psychophysical engine that doesn't
/// exist yet — there is nothing to show, so the routine should not make the
/// user wait out its duration for a placeholder.
class _AutoSkip extends StatefulWidget {
  const _AutoSkip({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<_AutoSkip> createState() => _AutoSkipState();
}

class _AutoSkipState extends State<_AutoSkip> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Countdown between drills. It is interface — knowing what is next — and
/// safety: two vergence drills stitched together with no gap is how
/// asthenopia is earned.
class _RestCard extends StatefulWidget {
  const _RestCard({
    super.key,
    required this.step,
    required this.next,
    required this.onDone,
  });

  final RestStep step;
  final String? next;
  final VoidCallback onDone;

  @override
  State<_RestCard> createState() => _RestCardState();
}

class _RestCardState extends State<_RestCard> {
  late int _left = widget.step.seconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _ticker?.cancel();
        widget.onDone();
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$_left',
              style: const TextStyle(
                  color: VisorTheme.text,
                  fontSize: 56,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(widget.step.cue,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: VisorTheme.text, fontSize: 16, height: 1.4)),
          if (widget.next != null) ...[
            const SizedBox(height: 18),
            Text('Next: ${widget.next}',
                style: const TextStyle(
                    color: VisorTheme.textDim, fontSize: 13)),
          ],
        ]),
      ),
    );
  }
}
