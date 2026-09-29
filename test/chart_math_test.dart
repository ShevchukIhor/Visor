import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/analytics/chart_math.dart';
import 'package:visor/core/gabor/gabor_patch.dart';

/// Shorthand for a session sample on a given local date/time.
SessionSample sample(
  DateTime at, {
  int correct = 8,
  int total = 10,
  Difficulty difficulty = Difficulty.easy,
}) =>
    SessionSample.fromCounts(
      at: at,
      correct: correct,
      total: total,
      difficulty: difficulty,
    );

void main() {
  group('SessionSample.fromCounts', () {
    test('accuracy is the percentage of correct answers', () {
      final s = sample(DateTime(2026, 3, 15), correct: 8, total: 10);
      expect(s.accuracy, 80);
    });

    test('an unanswered session scores zero instead of dividing by zero', () {
      final s = sample(DateTime(2026, 3, 15), correct: 0, total: 0);
      expect(s.accuracy, 0);
    });
  });

  group('dayOrdinal', () {
    test('adjacent calendar days differ by exactly one', () {
      final a = dayOrdinal(DateTime(2026, 3, 15));
      final b = dayOrdinal(DateTime(2026, 3, 16));
      expect(b - a, 1);
    });

    test('a spring-forward DST boundary is still one day wide', () {
      // Europe/Kyiv springs forward on 2026-03-29: that local day is 23h long,
      // so DateTime.difference().inDays would report 0 for this pair.
      final a = dayOrdinal(DateTime(2026, 3, 29));
      final b = dayOrdinal(DateTime(2026, 3, 30));
      expect(b - a, 1);
    });

    test('an autumn fall-back boundary is still one day wide', () {
      // 2026-10-25 is 25h long locally.
      final a = dayOrdinal(DateTime(2026, 10, 25));
      final b = dayOrdinal(DateTime(2026, 10, 26));
      expect(b - a, 1);
    });

    test('ignores the time of day', () {
      expect(
        dayOrdinal(DateTime(2026, 3, 15, 23, 59, 59)),
        dayOrdinal(DateTime(2026, 3, 15, 0, 0, 1)),
      );
    });

    test('walks across a month and a leap day', () {
      expect(dayOrdinal(DateTime(2026, 3, 1)) - dayOrdinal(DateTime(2026, 2, 28)),
          1);
      expect(dayOrdinal(DateTime(2024, 3, 1)) - dayOrdinal(DateTime(2024, 2, 28)),
          2); // 29 Feb exists in 2024
    });
  });

  group('aggregateByDay', () {
    test('no sessions produce no points', () {
      expect(aggregateByDay([]), isEmpty);
    });

    test('a single session becomes one point with flat spread', () {
      final pts = aggregateByDay([
        sample(DateTime(2026, 3, 15, 10), correct: 7, total: 10),
      ]);
      expect(pts, hasLength(1));
      expect(pts.single.day, DateTime(2026, 3, 15));
      expect(pts.single.mean, 70);
      expect(pts.single.best, 70);
      expect(pts.single.worst, 70);
      expect(pts.single.sessions, 1);
    });

    test('sessions on the same day collapse into their mean and extremes', () {
      final pts = aggregateByDay([
        sample(DateTime(2026, 3, 15, 9), correct: 4, total: 10), // 40
        sample(DateTime(2026, 3, 15, 14), correct: 10, total: 10), // 100
        sample(DateTime(2026, 3, 15, 21), correct: 7, total: 10), // 70
      ]);
      expect(pts, hasLength(1));
      expect(pts.single.mean, closeTo(70, 1e-9));
      expect(pts.single.best, 100);
      expect(pts.single.worst, 40);
      expect(pts.single.sessions, 3);
    });

    test('midnight edges stay on their own calendar day', () {
      final pts = aggregateByDay([
        sample(DateTime(2026, 3, 15, 23, 59, 59)),
        sample(DateTime(2026, 3, 16, 0, 0, 1)),
      ]);
      expect(pts, hasLength(2));
      expect(pts.first.day, DateTime(2026, 3, 15));
      expect(pts.last.day, DateTime(2026, 3, 16));
    });

    test('points come out chronologically whatever the input order', () {
      final pts = aggregateByDay([
        sample(DateTime(2026, 3, 17)),
        sample(DateTime(2026, 3, 15)),
        sample(DateTime(2026, 3, 16)),
      ]);
      expect(
        pts.map((p) => p.day),
        [DateTime(2026, 3, 15), DateTime(2026, 3, 16), DateTime(2026, 3, 17)],
      );
    });

    test('a day is coloured by the hardest difficulty trained on it', () {
      final pts = aggregateByDay([
        sample(DateTime(2026, 3, 15, 9), difficulty: Difficulty.easy),
        sample(DateTime(2026, 3, 15, 10), difficulty: Difficulty.hard),
        sample(DateTime(2026, 3, 15, 11), difficulty: Difficulty.medium),
      ]);
      expect(pts.single.difficulty, Difficulty.hard);
    });

    test('each day keeps its own hardest difficulty', () {
      final pts = aggregateByDay([
        sample(DateTime(2026, 3, 15), difficulty: Difficulty.expert),
        sample(DateTime(2026, 3, 16), difficulty: Difficulty.easy),
      ]);
      expect(pts.first.difficulty, Difficulty.expert);
      expect(pts.last.difficulty, Difficulty.easy);
    });
  });

  group('chartWindow', () {
    final today = DateTime(2026, 3, 15, 18, 30);
    DateTime day(int daysAgo) =>
        DateTime(today.year, today.month, today.day - daysAgo);

    test('with no data it still spans the minimum window ending today', () {
      final w = chartWindow([], today);
      expect(w.days, 7);
      expect(w.lastDay, DateTime(2026, 3, 15));
      expect(w.firstDay, DateTime(2026, 3, 9));
    });

    test('four days of history keep the full seven-day window', () {
      final pts = aggregateByDay([
        for (var d = 3; d >= 0; d--) sample(day(d)),
      ]);
      final w = chartWindow(pts, today);
      expect(w.days, 7);
      expect(w.firstDay, DateTime(2026, 3, 9));
      expect(w.lastDay, DateTime(2026, 3, 15));
    });

    test('a history longer than the minimum widens the window', () {
      final pts = aggregateByDay([sample(day(29)), sample(day(0))]);
      final w = chartWindow(pts, today);
      expect(w.days, 30);
      expect(w.firstDay, day(29));
      expect(w.lastDay, DateTime(2026, 3, 15));
    });

    test('the window ends today even after days without training', () {
      final pts = aggregateByDay([sample(day(5)), sample(day(3))]);
      final w = chartWindow(pts, today);
      expect(w.lastDay, DateTime(2026, 3, 15));
      expect(w.firstDay, DateTime(2026, 3, 9)); // still 7 days wide
    });

    test('a session dated in the future extends the window past today', () {
      // Clock skew or a device timezone change must not put a point off-canvas.
      final pts = aggregateByDay([sample(DateTime(2026, 3, 18))]);
      final w = chartWindow(pts, today);
      expect(w.lastDay, DateTime(2026, 3, 18));
      expect(w.covers(DateTime(2026, 3, 18)), isTrue);
    });

    test('minDays is configurable', () {
      final w = chartWindow([], today, minDays: 14);
      expect(w.days, 14);
      expect(w.firstDay, DateTime(2026, 3, 2));
    });
  });

  group('ChartWindow.xFor', () {
    const padL = 34.0;
    const plotW = 300.0;
    final today = DateTime(2026, 3, 15);

    test('the first day sits on the left edge of the plot', () {
      final w = chartWindow([], today);
      expect(w.xFor(w.firstDay, padL, plotW), closeTo(padL, 1e-9));
    });

    test('the last day sits on the right edge of the plot', () {
      final w = chartWindow([], today);
      expect(w.xFor(w.lastDay, padL, plotW), closeTo(padL + plotW, 1e-9));
    });

    test('days are evenly spaced across the window', () {
      final w = chartWindow([], today); // 7 days → 6 gaps
      final step = plotW / 6;
      for (var i = 0; i < 7; i++) {
        final d = DateTime(2026, 3, 9 + i);
        expect(w.xFor(d, padL, plotW), closeTo(padL + step * i, 1e-9),
            reason: 'day $d');
      }
    });

    test('spacing stays even across a DST boundary', () {
      // Window 2026-03-26 … 2026-04-01 contains the spring-forward day.
      final pts =
          aggregateByDay([sample(DateTime(2026, 3, 26))]);
      final w = chartWindow(pts, DateTime(2026, 4, 1));
      expect(w.days, 7);
      final step = plotW / 6;
      expect(w.xFor(DateTime(2026, 3, 29), padL, plotW),
          closeTo(padL + step * 3, 1e-9));
      expect(w.xFor(DateTime(2026, 3, 30), padL, plotW),
          closeTo(padL + step * 4, 1e-9));
    });

    test('a one-day window centres its only point', () {
      final w = chartWindow([], today, minDays: 1);
      expect(w.days, 1);
      expect(w.xFor(today, padL, plotW), closeTo(padL + plotW / 2, 1e-9));
    });

    test('covers reports whether a day is inside the window', () {
      final w = chartWindow([], today);
      expect(w.covers(DateTime(2026, 3, 9)), isTrue);
      expect(w.covers(DateTime(2026, 3, 15)), isTrue);
      expect(w.covers(DateTime(2026, 3, 8)), isFalse);
      expect(w.covers(DateTime(2026, 3, 16)), isFalse);
    });
  });

  group('value equality', () {
    test('identical days compare equal so the painter can skip a repaint', () {
      final a = aggregateByDay([sample(DateTime(2026, 3, 15, 9))]);
      final b = aggregateByDay([sample(DateTime(2026, 3, 15, 9))]);
      expect(a.single, b.single);
      expect(a.single.hashCode, b.single.hashCode);
    });

    test('a day that gained a session is not equal to the old one', () {
      final before = aggregateByDay([sample(DateTime(2026, 3, 15, 9))]);
      final after = aggregateByDay([
        sample(DateTime(2026, 3, 15, 9)),
        sample(DateTime(2026, 3, 15, 10)),
      ]);
      expect(after.single, isNot(before.single));
    });

    test('windows over the same span compare equal', () {
      final now = DateTime(2026, 3, 15, 8);
      final later = DateTime(2026, 3, 15, 20);
      expect(chartWindow([], now), chartWindow([], later));
      expect(chartWindow([], now).hashCode, chartWindow([], later).hashCode);
    });

    test('windows over different spans do not', () {
      final now = DateTime(2026, 3, 15);
      expect(chartWindow([], now), isNot(chartWindow([], now, minDays: 14)));
    });
  });

  group('difficultyByName', () {
    test('round-trips the name the game stores', () {
      for (final d in Difficulty.values) {
        expect(difficultyByName(d.name), d);
      }
    });

    test('an unknown level degrades to easy instead of throwing', () {
      // A row written by a future build must not crash the whole chart.
      expect(difficultyByName('insane'), Difficulty.easy);
      expect(difficultyByName(''), Difficulty.easy);
    });
  });
}
