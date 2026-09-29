import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

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
  const SessionRunner({super.key, required this.template});
  final Template template;

  @override
  State<SessionRunner> createState() => _SessionRunnerState();
}

/// A step whose `drills` write failed. Kept as a lazily-rebuildable [Drill]
/// rather than a reference to the (by then likely disposed) step widget, so
/// retry works from data the session already owns and does not depend on any
/// child's internal state surviving.
class _FailedStep {
  _FailedStep({required this.index, required this.rebuild});
  final int index;
  final Drill Function() rebuild;
}

class _SessionRunnerState extends State<SessionRunner> {
  int _index = 0;
  bool _done = false;

  /// Steps that failed to save, in case any is retried from the finish card.
  final List<_FailedStep> _failedSteps = [];
  bool _retrying = false;

  /// Wall-clock time each step began, captured the first time it is built.
  /// Used only to file a retried write under roughly the right moment —
  /// good enough since it only affects the retry, not the original attempt.
  final Map<int, DateTime> _stepStartedAt = {};

  List<TrainingStep> get _steps => widget.template.steps;

  void _next() {
    if (_index + 1 >= _steps.length) {
      setState(() => _done = true);
    } else {
      setState(() => _index++);
    }
  }

  /// Records a step's write failure. Called from a step widget's
  /// `onRecordFailed`, which may fire after that widget has already been
  /// replaced by the next step — so it must not touch the widget, only the
  /// data captured when the step started.
  void _recordFailure(int index, Drill Function() rebuild) {
    if (!mounted) return;
    setState(() => _failedSteps.add(_FailedStep(index: index, rebuild: rebuild)));
  }

  Future<void> _retryFailed() async {
    if (_failedSteps.isEmpty || _retrying) return;
    setState(() => _retrying = true);
    final stillFailed = <_FailedStep>[];
    for (final failed in _failedSteps) {
      try {
        await VisionDb.instance.insertDrill(failed.rebuild());
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
    _stepStartedAt.putIfAbsent(index, () => DateTime.now());
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
      DrillStep(:final seconds) => _RestCard(
          key: key,
          step: RestStep(cue: 'Not available yet', seconds: seconds),
          next: null,
          onDone: _next,
        ),
    };
  }

  Widget _exerciseStage(
    Key key,
    int index,
    ExerciseType type,
    int seconds,
    bool gaborTarget,
  ) {
    final startedAt = _stepStartedAt[index]!;
    return ExerciseRunner(
      key: key,
      type: type,
      seconds: seconds,
      gaborTarget: gaborTarget,
      autoStart: true,
      onDone: _next,
      templateId: widget.template.id,
      onRecordFailed: () => _recordFailure(
        index,
        () => drillForExercise(
          type: type,
          seconds: seconds,
          completed: true,
          startedAt: startedAt,
          templateId: widget.template.id,
        )!,
      ),
    );
  }

  Widget _gameStage(
    Key key,
    int index,
    Difficulty difficulty,
    int seconds,
    bool curved,
  ) {
    final startedAt = _stepStartedAt[index]!;
    return GameScreen(
      key: key,
      setup: SessionSetup(
          durationS: seconds, difficulty: difficulty, curved: curved),
      templateId: widget.template.id,
      onDone: _next,
      // The retry can't recover the trials actually played (that state lived
      // only in the disposed GameScreen), so it re-files the step as
      // completed with no trial detail — enough to close the streak and show
      // up in history, which is what was actually lost.
      onRecordFailed: () => _recordFailure(
        index,
        () => Drill(
          startedAt: startedAt,
          task: taskGaborGrid,
          durationS: seconds,
          completed: true,
          templateId: widget.template.id,
          params: jsonEncode({
            'difficulty': difficulty.name,
            'grid': difficulty.grid,
            'pattern': curved ? 'curved' : 'straight',
          }),
        ),
      ),
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
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_index + 1}/$total · ${step.title}',
                style: const TextStyle(color: VisorTheme.text, fontSize: 14)),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (_index) / total,
              backgroundColor: VisorTheme.surfaceAlt,
              color: VisorTheme.primary,
              minHeight: 3,
            ),
          ]),
        ),
      ]),
    );
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ]),
        ),
      ),
    );
  }
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
