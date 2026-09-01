import '../gabor/gabor_patch.dart';

/// User selections for a training session.
class SessionSetup {
  final int durationS;
  final Difficulty difficulty;
  final bool curved; // true = curved stripes, false = straight

  const SessionSetup({
    required this.durationS,
    required this.difficulty,
    required this.curved,
  });
}

/// Available durations in seconds.
const List<int> kDurations = [60, 120, 180, 300];

String durationLabel(int seconds) {
  final m = seconds ~/ 60;
  return '$m min';
}