/// Session model + database.
library;

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../gabor/gabor_patch.dart';

/// One completed training session.
class VisionSession {
  final int id;
  final DateTime startedAt;
  final int durationS;
  final String difficulty;
  final int grid;
  final String pattern; // 'straight' | 'curved'
  final int correct;
  final int total;
  final double score;

  const VisionSession({
    required this.id,
    required this.startedAt,
    required this.durationS,
    required this.difficulty,
    required this.grid,
    required this.pattern,
    required this.correct,
    required this.total,
    required this.score,
  });

  Map<String, Object?> toMap() => {
        'started_at': startedAt.millisecondsSinceEpoch,
        'duration_s': durationS,
        'difficulty': difficulty,
        'grid': grid,
        'pattern': pattern,
        'correct': correct,
        'total': total,
        'score': score,
      };

  factory VisionSession.fromMap(Map<String, Object?> m) => VisionSession(
        id: m['id'] as int,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        durationS: m['duration_s'] as int,
        difficulty: m['difficulty'] as String,
        grid: m['grid'] as int,
        pattern: m['pattern'] as String,
        correct: m['correct'] as int,
        total: m['total'] as int,
        score: (m['score'] as num).toDouble(),
      );
}

/// Local-date key (`YYYY-MM-DD`), matching SQLite's
/// `date(started_at/1000, 'unixepoch', 'localtime')`.
String dateKey(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';

/// Consecutive days ending at [now] (or at yesterday, if today has no session
/// yet) that appear in [days].
///
/// Pure so the calendar edge cases — an empty history, a gap, a streak that is
/// still alive because today simply has not happened yet — are testable
/// without a database.
int computeStreak(Set<String> days, DateTime now) {
  // Calendar arithmetic, not `subtract(Duration(days: 1))`: on a DST boundary
  // a 24-hour step lands on the same local date (or skips one), which would
  // silently break or double-count a streak.
  DateTime previousDay(DateTime d) => DateTime(d.year, d.month, d.day - 1);

  var cursor = DateTime(now.year, now.month, now.day);
  if (!days.contains(dateKey(cursor))) {
    cursor = previousDay(cursor);
  }
  var streak = 0;
  while (days.contains(dateKey(cursor))) {
    streak++;
    cursor = previousDay(cursor);
  }
  return streak;
}

/// Database access for vision sessions and the reminder settings row.
class VisionDb {
  VisionDb._();
  static final VisionDb instance = VisionDb._();

  /// The *future* is cached, not the resolved handle: two callers racing on
  /// the first access would otherwise both get past a `_db == null` check and
  /// open the database twice.
  Future<Database>? _dbFuture;

  Future<Database> get db => _dbFuture ??= _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'visor.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE vision_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started_at INTEGER NOT NULL,
            duration_s INTEGER NOT NULL,
            difficulty TEXT NOT NULL,
            grid INTEGER NOT NULL,
            pattern TEXT NOT NULL,
            correct INTEGER NOT NULL,
            total INTEGER NOT NULL,
            score REAL NOT NULL
          )
        ''');
        await d.execute(
          'CREATE INDEX idx_sessions_started ON vision_sessions(started_at)',
        );
        await d.execute('''
          CREATE TABLE reminder (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            enabled INTEGER NOT NULL,
            hour INTEGER NOT NULL,
            minute INTEGER NOT NULL
          )
        ''');
        await d.insert('reminder',
            {'id': 1, 'enabled': 0, 'hour': 21, 'minute': 0});
      },
      onUpgrade: (d, oldV, newV) async {
        // v2 added an `account` table for a Seed Vault wallet card that was
        // removed from the UI; v3 drops it so no wallet address lingers on
        // disk. Tipping needs no stored account.
        if (oldV < 3) {
          await d.execute('DROP TABLE IF EXISTS account');
        }
      },
    );
  }

  Future<int> insertSession(VisionSession s) async {
    final d = await db;
    final id = await d.insert('vision_sessions', s.toMap());
    return id;
  }

  Future<List<VisionSession>> allSessions() async {
    final d = await db;
    final rows = await d.query('vision_sessions',
        orderBy: 'started_at DESC');
    return rows.map(VisionSession.fromMap).toList();
  }

  Future<int> sessionsOnDay(DateTime day) async {
    final d = await db;
    final start =
        DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end = start + 24 * 60 * 60 * 1000;
    final rows = await d.rawQuery(
      'SELECT COUNT(*) AS c FROM vision_sessions WHERE started_at >= ? AND started_at < ?',
      [start, end],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  // --- Reminder settings ---
  Future<Map<String, Object?>> getReminder() async {
    final d = await db;
    final rows = await d.query('reminder', where: 'id = 1');
    if (rows.isEmpty) return {'enabled': 0, 'hour': 21, 'minute': 0};
    return rows.first;
  }

  Future<void> setReminder(
      {required bool enabled, required int hour, required int minute}) async {
    final d = await db;
    await d.update(
      'reminder',
      {'enabled': enabled ? 1 : 0, 'hour': hour, 'minute': minute},
      where: 'id = 1',
    );
  }

  /// Best score across all sessions, weighted by difficulty (already baked
  /// into the stored `score`).
  Future<double> bestScore() async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT MAX(score) AS m FROM vision_sessions');
    return ((rows.first['m'] as num?) ?? 0).toDouble();
  }

  /// Current streak = consecutive days ending at today (or yesterday, if
  /// today is not yet closed) that have at least one session.
  Future<int> streak() async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT DISTINCT date(started_at/1000, \'unixepoch\', \'localtime\') AS day '
      'FROM vision_sessions',
    );
    final days = rows.map((r) => r['day'] as String).toSet();
    return computeStreak(days, DateTime.now());
  }

  /// Composite score for a finished session.
  static double computeScore(
          {required int correct, required int total, required Difficulty d}) =>
      total == 0 ? 0 : (correct / total) * 100 * d.weight;
}
