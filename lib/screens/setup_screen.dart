import 'package:flutter/material.dart';

import '../core/gabor/gabor_patch.dart';
import '../core/models/session_setup.dart';
import '../core/theme/visor_theme.dart';
import 'game_screen.dart';

/// Setup screen: choose duration, difficulty, and stripe mode, then start.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _duration = 60;
  Difficulty _difficulty = Difficulty.easy;
  bool _curved = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: const Text('Start Training'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('Duration'),
              const SizedBox(height: 8),
              _durationRow(),
              const SizedBox(height: 24),
              const _SectionLabel('Difficulty'),
              const SizedBox(height: 8),
              ...Difficulty.values.map(_difficultyCard),
              const SizedBox(height: 24),
              const _SectionLabel('Stripe mode'),
              const SizedBox(height: 8),
              _stripeSwitch(),
              const SizedBox(height: 12),
              const Text(
                'Tip: for best results set brightness so the bright and dark '
                'stripes are clearly distinct \u2014 no higher than comfortable.',
                style: TextStyle(color: VisorTheme.textDim, fontSize: 12.5, height: 1.4),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: VisorTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _start,
                  child: const Text('Start Training',
                      style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _durationRow() {
    return Row(
      children: kDurations.map((d) {
        final active = _duration == d;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => setState(() => _duration = d),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: active ? VisorTheme.primary : VisorTheme.surface,
                  border: Border.all(
                    color: active ? VisorTheme.primary : VisorTheme.surfaceAlt,
                    width: 2,
                  ),
                ),
                child: Text(
                  durationLabel(d),
                  style: TextStyle(
                    color: active
                        ? const Color(0xFF001428)
                        : VisorTheme.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _difficultyCard(Difficulty d) {
    final active = _difficulty == d;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _difficulty = d),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: active ? VisorTheme.primary : VisorTheme.surface,
            border: Border.all(
              color: active ? VisorTheme.primary : VisorTheme.surfaceAlt,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Text(
                d.label,
                style: TextStyle(
                  color: active ? const Color(0xFF001428) : VisorTheme.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text(
                '${d.grid}×${d.grid} grid',
                style: TextStyle(
                  color: active ? const Color(0xFF123A66) : VisorTheme.textDim,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stripeSwitch() {
    return Row(
      children: [
        const Text('Straight',
            style: TextStyle(color: VisorTheme.text, fontSize: 15)),
        Switch(
          value: _curved,
          activeColor: VisorTheme.primary,
          onChanged: (v) => setState(() => _curved = v),
        ),
        const Text('Curved',
            style: TextStyle(color: VisorTheme.text, fontSize: 15)),
      ],
    );
  }

  void _start() {
    final setup = SessionSetup(
      durationS: _duration,
      difficulty: _difficulty,
      curved: _curved,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GameScreen(setup: setup)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: VisorTheme.textDim,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}