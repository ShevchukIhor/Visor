import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/db/drill.dart';
import '../core/db/vision_db.dart';
import '../core/gabor/gabor_patch.dart';
import '../core/models/session_setup.dart';
import '../core/reminder/reminder_service.dart';
import '../core/theme/visor_theme.dart';
import '../widgets/gabor_view.dart';

/// The "find the matching patch" game screen.
///
/// Shows a target patch above an N×N grid. One grid cell matches the target;
/// the rest are distractors. Tapping a cell scores it, gives instant feedback,
/// and shows the next trial until the timer runs out.
class GameScreen extends StatefulWidget {
  final SessionSetup setup;
  final int? templateId;

  /// Called instead of showing the terminal card, so a routine can advance
  /// to its next step. Also the signal that a routine — not this widget —
  /// owns the screen's chrome: the top bar and the system-bar immersive mode.
  final VoidCallback? onDone;

  /// Called with the exact [Drill] whose write failed, in addition to
  /// setting the retry flag. When [onDone] is set the result view that
  /// would otherwise carry the retry affordance never renders, so a routine
  /// needs this to learn a step's write failed and retry that same row.
  final void Function(Drill failed)? onRecordFailed;

  /// Reports the seconds remaining and the running score whenever either
  /// changes, so a routine that owns the chrome (see [onDone]) can show
  /// equivalent progress instead of this widget's hidden top bar.
  final void Function(int secondsLeft, int correct, int total)? onProgress;

  const GameScreen({
    super.key,
    required this.setup,
    this.templateId,
    this.onDone,
    this.onRecordFailed,
    this.onProgress,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  late final TrialGenerator _gen;
  late GaborTrial _trial;
  late int _secondsLeft;

  /// Fades and settles the result card in. The mixin's vsync was already
  /// reserved for this; the game itself runs on a Timer, not an animation.
  late final AnimationController _reveal;

  /// Animates trial transitions: new patches scale in and fade in.
  late final AnimationController _trialAnim;
  int _correct = 0;
  int _total = 0;
  int? _selected; // tapped index (null until answered)
  bool _answered = false;
  bool _finished = false;
  Timer? _timer;
  DateTime? _startedAt;
  bool _saved = false;
  bool _saveError = false;

  int get _grid => widget.setup.difficulty.grid;

  @override
  void initState() {
    super.initState();
    if (widget.onDone == null) {
      // Hide the system bars for the duration of the session only — a
      // bright status bar next to a Gabor grid is exactly the distraction
      // the drill is trying to remove. In routine mode `SessionRunner` owns
      // this for the whole routine instead, so the bars don't flash back on
      // between steps.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      // Keep the screen on while the session runs: studying a 5×5 grid can
      // take longer than the device's screen timeout, and a locked screen
      // kills a running drill. In routine mode `SessionRunner` owns this
      // for the whole routine instead (see its initState).
      WakelockPlus.enable();
    }
    _gen = TrialGenerator(curved: widget.setup.curved);
    _trial = _gen.generate(widget.setup.difficulty);
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _trialAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _secondsLeft = widget.setup.durationS;
    _startedAt = DateTime.now();
    // Defer the initial progress report to after the first frame, so the
    // callback (which calls setState on the parent) does not fire during
    // the parent's build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportProgress();
    });
    _startTimer();
  }

  void _reportProgress() =>
      widget.onProgress?.call(_secondsLeft, _correct, _total);

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final done = _secondsLeft <= 1;
      setState(() => _secondsLeft = done ? 0 : _secondsLeft - 1);
      _reportProgress();
      if (done) _finish();
    });
  }

  void _finish() {
    _timer?.cancel();
    // The timer is done; the result card is static, so the screen can
    // time out normally. In routine mode the session owns the wakelock.
    if (widget.onDone == null) WakelockPlus.disable();
    setState(() => _finished = true);
    _reveal.forward(from: 0);
    _save();
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
      return;
    }
  }

  Future<void> _save() async {
    if (_saved) return;
    _saved = true;
    final score = VisionDb.computeScore(
      correct: _correct,
      total: _total,
      d: widget.setup.difficulty,
    );
    final drill = Drill(
      startedAt: _startedAt ?? DateTime.now(),
      task: taskGaborGrid,
      durationS: widget.setup.durationS,
      completed: true,
      trials: _total,
      correct: _correct,
      score: score,
      templateId: widget.templateId,
      params: jsonEncode({
        'difficulty': widget.setup.difficulty.name,
        'grid': _grid,
        'pattern': widget.setup.curved ? 'curved' : 'straight',
      }),
    );
    try {
      await VisionDb.instance.insertDrill(drill);
      // Tell the native reminder layer we trained today.
      await ReminderService.markTrainedToday();
    } catch (e) {
      // Losing a session silently while the screen says "complete" is worse
      // than an ugly message: the streak and the chart would disagree with
      // what the user just did.
      debugPrint('Failed to save session: $e');
      _saved = false;
      // Fires regardless of `mounted`: a routine step routes around this
      // widget's own result view via `onDone`, so this may be the only place
      // a routine ever learns the write failed. Carries the exact `Drill`
      // that failed to insert, so a retry does not have to guess at trial
      // stats it can no longer observe.
      widget.onRecordFailed?.call(drill);
      if (!mounted) return;
      setState(() => _saveError = true);
    }
  }

  void _tap(int index) {
    if (_answered || _finished) return;
    final correct = index == _trial.answerIndex;
    setState(() {
      _answered = true;
      _selected = index;
      _total++;
      if (correct) {
        _correct++;
      }
    });
    // The game is a rapid-tap drill: the thumb needs the answer the instant
    // the finger lifts, and the two strengths keep correct/wrong distinct
    // without sound.
    if (correct) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
    _reportProgress();
    // Generate the next trial now and prewarm its images during the feedback
    // delay, so the grid swap lands on decoded patches instead of flashing
    // up to 36 spinners.
    final next = _gen.generate(widget.setup.difficulty);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _finished) return;
      GaborView.prewarm(next.target, size: 128);
      for (final patch in next.distractors) {
        GaborView.prewarm(patch, size: 96);
      }
    });
    // Show result briefly, then advance with animation.
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted || _finished) return;
      setState(() {
        _trial = next;
        _answered = false;
        _selected = null;
      });
      // Animate the new trial into view.
      _trialAnim.forward(from: 0);
    });
  }

  /// Exit guard: a session with answered trials has earned nothing yet —
  /// `_save` only runs on natural completion — so confirm before throwing it
  /// away. A fresh session (no taps) just goes back.
  Future<void> _confirmExit() async {
    if (_total == 0) {
      Navigator.pop(context);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VisorTheme.surface,
        title: const Text('End session?',
            style: TextStyle(color: VisorTheme.text)),
        content: Text('Your progress will not be saved.',
            style: const TextStyle(color: VisorTheme.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End',
                style: TextStyle(color: VisorTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reveal.dispose();
    _trialAnim.dispose();
    if (widget.onDone == null) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // Safety net for the exit path: `_finish` already released the
      // wakelock for a completed session, but an early exit disposes
      // without going through `_finish`.
      WakelockPlus.disable();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // In routine mode the SessionRunner owns exit (its bottom bar), so the
    // system back gesture must pop the whole routine, not confirm a step.
    final scaffold = Scaffold(
      backgroundColor: VisorTheme.bg,
      body: SafeArea(
        child: _finished ? _resultView() : _gameView(),
      ),
    );
    if (widget.onDone != null) return scaffold;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: scaffold,
    );
  }

  Widget _gameView() {
    return Column(
      children: [
        // Hidden (but space-preserving) in routine mode — SessionRunner
        // owns all chrome then (see [onProgress]), so this doesn't paint a
        // second close button, countdown and score over its own bar.
        Visibility(
          visible: widget.onDone == null,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: _topBar(),
        ),
        const SizedBox(height: 8),
        Expanded(child: _targetAndGrid()),
      ],
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: VisorTheme.textDim),
            tooltip: 'End session',
            onPressed: _confirmExit,
            // The old bare GestureDetector gave a 24 dp target; a finger
            // exits mid-drill, so it gets the same 48 dp floor as the
            // SessionRunner's quit/skip controls.
            constraints: const BoxConstraints(
                minWidth: 48, minHeight: 48),
          ),
          const SizedBox(width: 12),
          Text(
            mmss(_secondsLeft),
            style: const TextStyle(
              color: VisorTheme.text,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            '✓ $_correct   ✗ ${_total - _correct}',
            style: const TextStyle(
              color: VisorTheme.text,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  String mmss(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  Widget _targetAndGrid() {
    final scaleAnim = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _trialAnim, curve: Curves.easeOut),
    );
    final fadeAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _trialAnim, curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: _trialAnim,
      builder: (ctx, child) {
        return Transform.scale(
          scale: scaleAnim.value,
          child: Opacity(
            opacity: fadeAnim.value,
            child: child,
          ),
        );
      },
      child: Column(
        children: [
          const Text(
            'Find the matching patch',
            style: TextStyle(color: VisorTheme.textDim, fontSize: 14),
          ),
          const SizedBox(height: 10),
          // Target patch
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              border: Border.all(color: VisorTheme.primary, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: GaborView(patch: _trial.target, size: 128),
          ),
          const SizedBox(height: 16),
          Expanded(child: _gridView()),
        ],
      ),
    );
  }

  Widget _gridView() {
    final n = _grid;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: false,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: n,
          // 8 dp keeps a fast tap from landing on a neighbour's edge — the
          // old 6 dp gap was under the minimum touch spacing.
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: n * n,
        itemBuilder: (ctx, i) {
          final isAnswer = _answered && i == _trial.answerIndex;
          final isPicked = _answered && i == _selected;
          final isWrong = isPicked && i != _trial.answerIndex;
          return GestureDetector(
            onTap: () => _tap(i),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isAnswer
                      ? VisorTheme.success
                      : isWrong
                          ? VisorTheme.danger
                          : VisorTheme.surfaceAlt,
                  width: isAnswer || isWrong ? 3 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: GaborView(patch: _trial.distractors[i], size: 96),
            ),
          );
        },
      ),
    );
  }

  Widget _resultView() {
    final acc = _total == 0 ? 0 : _correct / _total;
    // A short settle-in marks the transition from drill to result; the
    // game's own motion stays instant, this is the one place it eases.
    return FadeTransition(
      opacity: CurvedAnimation(parent: _reveal, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(
          CurvedAnimation(parent: _reveal, curve: Curves.easeOut),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Session complete',
                    style: TextStyle(color: VisorTheme.text, fontSize: 24)),
                const SizedBox(height: 16),
                Text(
                  '$_correct / $_total',
                  style: const TextStyle(
                    color: VisorTheme.primary,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'accuracy ${(acc * 100).round()}%',
                  style: const TextStyle(
                      color: VisorTheme.textDim, fontSize: 16),
                ),
                if (_saveError) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Could not save this session — your streak and history '
                    'may not include it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VisorTheme.danger, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() => _saveError = false);
                      _save();
                    },
                    child: const Text('Retry save'),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: VisorTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}