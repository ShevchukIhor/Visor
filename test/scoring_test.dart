import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/analytics/chart_math.dart';
import 'package:visor/core/db/vision_db.dart';
import 'package:visor/core/gabor/gabor_patch.dart';

void main() {
  group('computeScore', () {
    test('is zero when nothing was answered', () {
      expect(
        VisionDb.computeScore(correct: 0, total: 0, d: Difficulty.easy),
        0,
      );
    });

    test('a perfect easy run scores 100', () {
      expect(
        VisionDb.computeScore(correct: 10, total: 10, d: Difficulty.easy),
        100,
      );
    });

    test('difficulty weight scales the same accuracy', () {
      final easy =
          VisionDb.computeScore(correct: 8, total: 10, d: Difficulty.easy);
      final expert =
          VisionDb.computeScore(correct: 8, total: 10, d: Difficulty.expert);
      expect(expert, closeTo(easy * Difficulty.expert.weight, 1e-9));
      expect(expert, greaterThan(easy));
    });
  });

  group('computeStreak', () {
    // Fixed "today" so the tests never depend on when they run.
    final now = DateTime(2026, 3, 15, 10, 30);
    String key(int daysAgo) =>
        dateKey(DateTime(now.year, now.month, now.day - daysAgo));

    test('is zero with no sessions at all', () {
      expect(computeStreak({}, now), 0);
    });

    test('counts today plus the run before it', () {
      final days = {key(0), key(1), key(2)};
      expect(computeStreak(days, now), 3);
    });

    test('survives a day that has not happened yet', () {
      // Nothing today, but yesterday and before: the streak is still alive.
      final days = {key(1), key(2)};
      expect(computeStreak(days, now), 2);
    });

    test('is broken by a gap', () {
      // Today and 2 days ago, but nothing yesterday.
      final days = {key(0), key(2), key(3)};
      expect(computeStreak(days, now), 1);
    });

    test('is zero when the last session is older than yesterday', () {
      final days = {key(2), key(3)};
      expect(computeStreak(days, now), 0);
    });

    test('counts a single session today as one', () {
      expect(computeStreak({key(0)}, now), 1);
    });

    test('walks across a month boundary', () {
      final march1 = DateTime(2026, 3, 1, 9);
      final days = {
        dateKey(DateTime(2026, 3, 1)),
        dateKey(DateTime(2026, 2, 28)),
        dateKey(DateTime(2026, 2, 27)),
      };
      expect(computeStreak(days, march1), 3);
    });

    test('walks across a leap day', () {
      final mar1 = DateTime(2024, 3, 1, 9);
      final days = {
        dateKey(DateTime(2024, 3, 1)),
        dateKey(DateTime(2024, 2, 29)),
        dateKey(DateTime(2024, 2, 28)),
      };
      expect(computeStreak(days, mar1), 3);
    });

    test('ignores the time of day', () {
      final lateNight = DateTime(2026, 3, 15, 23, 59, 59);
      final earlyMorning = DateTime(2026, 3, 15, 0, 0, 1);
      final days = {dateKey(DateTime(2026, 3, 15))};
      expect(computeStreak(days, lateNight), 1);
      expect(computeStreak(days, earlyMorning), 1);
    });
  });

  group('dateKey', () {
    test('zero-pads to the SQLite date() format', () {
      expect(dateKey(DateTime(2026, 1, 2)), '2026-01-02');
      expect(dateKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('niceCeil', () {
    test('returns a floor of 10 for empty or negative maxima', () {
      expect(niceCeil(0), 10);
      expect(niceCeil(-5), 10);
      expect(niceCeil(double.nan), 10);
    });

    test('snaps to round ceilings', () {
      expect(niceCeil(100), 100);
      expect(niceCeil(95), 100);
      expect(niceCeil(101), 200);
      expect(niceCeil(230), 250);
      expect(niceCeil(7), 10);
      expect(niceCeil(1.5), 2);
    });

    test('never rounds below the value it must contain', () {
      for (var v = 0.5; v < 500; v += 0.5) {
        expect(niceCeil(v), greaterThanOrEqualTo(v), reason: 'v=$v');
      }
    });

    test('a perfect expert score fits under its ceiling', () {
      final best =
          VisionDb.computeScore(correct: 20, total: 20, d: Difficulty.expert);
      expect(niceCeil(best), greaterThanOrEqualTo(best));
    });
  });
}
