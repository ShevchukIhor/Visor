/// Scale helpers for the score-trend chart, kept free of Flutter types so the
/// axis arithmetic can be tested directly.
library;

import 'dart:math' as math;

import '../gabor/gabor_patch.dart';

/// Round a raw max up to a clean ceiling.
///
/// The scale is 0-based on purpose: line height then reads as a share of the
/// real value rather than a position inside a min..max window.
double niceCeil(double v) {
  if (!v.isFinite || v <= 0) return 10;
  final exp = (math.log(v) / math.log(10)).floorToDouble();
  final mag = math.pow(10.0, exp).toDouble();
  final n = v / mag;
  final nice = const [1.0, 2.0, 2.5, 5.0, 10.0]
      .firstWhere((c) => n <= c, orElse: () => 10.0);
  return nice * mag;
}

/// One finished session, reduced to what the trend chart needs.
class SessionSample {
  /// When the session started, in local time.
  final DateTime at;

  /// Share of correct answers, 0..100. Deliberately *not* the weighted score:
  /// the weight folds difficulty into the number, so a weighted series cannot
  /// be compared with itself once the user changes level. Difficulty is
  /// carried separately and shown as colour instead.
  final double accuracy;

  final Difficulty difficulty;

  const SessionSample({
    required this.at,
    required this.accuracy,
    required this.difficulty,
  });

  factory SessionSample.fromCounts({
    required DateTime at,
    required int correct,
    required int total,
    required Difficulty difficulty,
  }) =>
      SessionSample(
        at: at,
        accuracy: total == 0 ? 0 : correct / total * 100,
        difficulty: difficulty,
      );
}

/// One calendar day of sessions, collapsed into a single plotted point.
class DayPoint {
  /// Local calendar date, time-of-day stripped.
  final DateTime day;

  /// Mean, highest and lowest accuracy recorded that day.
  final double mean;
  final double best;
  final double worst;

  /// How many sessions the day holds — plotted as the dot's radius, so a day
  /// of twelve sessions is visibly not a day of one.
  final int sessions;

  /// Hardest difficulty trained that day, which drives the dot's colour.
  /// Hardest rather than most frequent: the colour then reads as "how far the
  /// user pushed", and it moves monotonically as they level up.
  final Difficulty difficulty;

  const DayPoint({
    required this.day,
    required this.mean,
    required this.best,
    required this.worst,
    required this.sessions,
    required this.difficulty,
  });

  // Value equality: the chart rebuilds a fresh list on every setState, so
  // identity would always differ and the painter would repaint on every frame.
  @override
  bool operator ==(Object other) =>
      other is DayPoint &&
      other.day == day &&
      other.mean == mean &&
      other.best == best &&
      other.worst == worst &&
      other.sessions == sessions &&
      other.difficulty == difficulty;

  @override
  int get hashCode =>
      Object.hash(day, mean, best, worst, sessions, difficulty);
}

/// Days since the Unix epoch for the local calendar date of [dt].
///
/// Normalized through UTC on purpose: `difference().inDays` counts 24-hour
/// spans, so a local day that is 23 or 25 hours long across a DST boundary
/// would report a one-day gap as zero or two — which would collapse or
/// duplicate a column on the chart.
int dayOrdinal(DateTime dt) =>
    DateTime.utc(dt.year, dt.month, dt.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;

/// Collapse sessions into one point per calendar day, oldest first.
///
/// Plotting raw sessions is what makes a short history unreadable: a one-minute
/// run holds only a handful of trials, so two taps move its accuracy by twenty
/// points, and consecutive sessions zig-zag the full height of the plot. A day
/// is the smallest bucket that averages that noise away while still matching
/// how the streak counts.
List<DayPoint> aggregateByDay(List<SessionSample> samples) {
  final byDay = <int, List<SessionSample>>{};
  for (final s in samples) {
    byDay.putIfAbsent(dayOrdinal(s.at), () => <SessionSample>[]).add(s);
  }
  final ordinals = byDay.keys.toList()..sort();
  return [
    for (final o in ordinals) _collapse(byDay[o]!),
  ];
}

DayPoint _collapse(List<SessionSample> day) {
  var sum = 0.0;
  var best = day.first.accuracy;
  var worst = day.first.accuracy;
  var hardest = day.first.difficulty;
  for (final s in day) {
    sum += s.accuracy;
    if (s.accuracy > best) best = s.accuracy;
    if (s.accuracy < worst) worst = s.accuracy;
    if (s.difficulty.index > hardest.index) hardest = s.difficulty;
  }
  final at = day.first.at;
  return DayPoint(
    day: DateTime(at.year, at.month, at.day),
    mean: sum / day.length,
    best: best,
    worst: worst,
    sessions: day.length,
    difficulty: hardest,
  );
}

/// Inclusive span of calendar days the X axis covers.
class ChartWindow {
  final DateTime firstDay;
  final DateTime lastDay;

  const ChartWindow({required this.firstDay, required this.lastDay});

  @override
  bool operator ==(Object other) =>
      other is ChartWindow &&
      other.firstDay == firstDay &&
      other.lastDay == lastDay;

  @override
  int get hashCode => Object.hash(firstDay, lastDay);

  /// Number of days on the axis, both ends included.
  int get days => dayOrdinal(lastDay) - dayOrdinal(firstDay) + 1;

  bool covers(DateTime day) {
    final o = dayOrdinal(day);
    return o >= dayOrdinal(firstDay) && o <= dayOrdinal(lastDay);
  }

  /// Horizontal position of [day] inside a plot of width [plotW] starting at
  /// [padL]. A single-day window has no span to divide, so its point is
  /// centred rather than pinned to an edge.
  double xFor(DateTime day, double padL, double plotW) {
    final n = days;
    if (n <= 1) return padL + plotW / 2;
    final i = dayOrdinal(day) - dayOrdinal(firstDay);
    return padL + plotW * (i / (n - 1));
  }
}

/// Day span for the trend chart: always ending today, never narrower than
/// [minDays].
///
/// The floor is what makes a young history honest. Four days stretched across
/// the full width read as a long trend; four days in the right-hand four
/// sevenths read as "you are four days in", with the empty left side saying
/// so. The right edge is today even when the last session is older, so a gap
/// in training shows up as a gap.
///
/// [points] must be ordered oldest-first, as [aggregateByDay] returns them.
ChartWindow chartWindow(
  List<DayPoint> points,
  DateTime now, {
  int minDays = 7,
}) {
  final today = DateTime(now.year, now.month, now.day);
  var last = today;
  // A session dated ahead of the clock (skew, or a timezone change) would
  // otherwise land off-canvas.
  if (points.isNotEmpty && dayOrdinal(points.last.day) > dayOrdinal(last)) {
    last = points.last.day;
  }
  final span = math.max(minDays, 1);
  var first = DateTime(last.year, last.month, last.day - (span - 1));
  if (points.isNotEmpty && dayOrdinal(points.first.day) < dayOrdinal(first)) {
    first = points.first.day;
  }
  return ChartWindow(firstDay: first, lastDay: last);
}

/// Resolve the `Difficulty.name` string stored on a session row.
///
/// Unknown values degrade to [Difficulty.easy]: a row written by a newer build
/// should not take the whole chart down.
Difficulty difficultyByName(String name) => Difficulty.values
    .firstWhere((d) => d.name == name, orElse: () => Difficulty.easy);
