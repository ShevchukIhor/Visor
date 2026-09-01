import 'dart:async';

import 'package:flutter/material.dart';

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

  const GameScreen({super.key, required this.setup});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final TrialGenerator _gen;
  late GaborTrial _trial;
  late int _secondsLeft;
  int _correct = 0;
  int _total = 0;
  int? _selected; // tapped index (null until answered)
  bool _answered = false;
  bool _finished = false;
  Timer? _timer;
  DateTime? _startedAt;
  bool _saved = false;

  int get _grid => widget.setup.difficulty.grid;

  @override
  void initState() {
    super.initState();
    _gen = TrialGenerator(curved: widget.setup.curved);
    _trial = _gen.generate(widget.setup.difficulty);
    _secondsLeft = widget.setup.durationS;
    _startedAt = DateTime.now();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
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
    _timer?.cancel();
    setState(() => _finished = true);
    _save();
  }

  Future<void> _save() async {
    if (_saved) return;
    _saved = true;
    final score = VisionDb.computeScore(
      correct: _correct,
      total: _total,
      d: widget.setup.difficulty,
    );
    await VisionDb.instance.insertSession(VisionSession(
      id: 0,
      startedAt: _startedAt ?? DateTime.now(),
      durationS: widget.setup.durationS,
      difficulty: widget.setup.difficulty.name,
      grid: _grid,
      pattern: widget.setup.curved ? 'curved' : 'straight',
      correct: _correct,
      total: _total,
      score: score,
    ));
    // Tell the native reminder layer we trained today.
    await ReminderService.markTrainedToday();
  }

  void _tap(int index) {
    if (_answered || _finished) return;
    setState(() {
      _answered = true;
      _selected = index;
      _total++;
      if (index == _trial.answerIndex) {
        _correct++;
      }
    });
    // Show result briefly, then advance.
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted || _finished) return;
      setState(() {
        _trial = _gen.generate(widget.setup.difficulty);
        _answered = false;
        _selected = null;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      body: SafeArea(
        child: _finished ? _resultView() : _gameView(),
      ),
    );
  }

  Widget _gameView() {
    return Column(
      children: [
        _topBar(),
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
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.close, color: VisorTheme.textDim),
          ),
          const SizedBox(width: 12),
          Text(
            '${mmss(_secondsLeft)}',
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
    return Column(
      children: [
        const Text(
          'Find the matching patch',
          style: TextStyle(color: VisorTheme.textDim, fontSize: 15),
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
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
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
    return Center(
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
              style:
                  const TextStyle(color: VisorTheme.textDim, fontSize: 16),
            ),
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
    );
  }
}