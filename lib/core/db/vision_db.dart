/// Session model + database.
library;

import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../gabor/gabor_patch.dart';
import 'drill.dart';

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

/// Database access for drills and the reminder settings row.
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
      version: 4,
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (d, v) async {
        await _createV4(d);
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
      onUpgrade: migrate,
    );
  }

  /// Schema steps, extracted from [_open] so a test can drive them against an
  /// in-memory database.
  static Future<void> migrate(Database d, int oldV, int newV) async {
    if (oldV < 3) {
      await d.execute('DROP TABLE IF EXISTS account');
    }
    if (oldV < 4) {
      await _createV4(d);
      await _backfillSessionsIntoDrills(d);
      await d.execute('DROP TABLE IF EXISTS vision_sessions');
    }
  }

  static Future<void> _createV4(Database d) async {
    await d.execute('''
      CREATE TABLE viewing_geometry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at INTEGER NOT NULL,
        px_per_mm REAL NOT NULL,
        distance_mm REAL NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE drills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at INTEGER NOT NULL,
        task TEXT NOT NULL,
        duration_s INTEGER NOT NULL,
        completed INTEGER NOT NULL,
        trials INTEGER NOT NULL,
        correct INTEGER NOT NULL,
        threshold REAL,
        threshold_unit TEXT,
        reversals TEXT,
        geometry_id INTEGER REFERENCES viewing_geometry(id),
        score REAL,
        template_id INTEGER,
        params TEXT
      )
    ''');
    await d.execute(
        'CREATE INDEX idx_drills_started ON drills(started_at)');
    await d.execute('''
      CREATE TABLE templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        builtin INTEGER NOT NULL,
        position INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE template_steps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        template_id INTEGER NOT NULL
            REFERENCES templates(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        kind TEXT NOT NULL,
        seconds INTEGER NOT NULL,
        params TEXT
      )
    ''');
    await d.execute(
        'CREATE INDEX idx_steps_template ON template_steps(template_id, position)');
    await d.execute('''
      CREATE TABLE week_plan (
        weekday INTEGER PRIMARY KEY CHECK (weekday BETWEEN 1 AND 7),
        template_id INTEGER REFERENCES templates(id) ON DELETE SET NULL
      )
    ''');
  }

  /// Copy v3 sessions across. The difficulty string is carried verbatim into
  /// `params` rather than parsed: a row written by a build we do not know about
  /// is still the user's training history and must survive the upgrade.
  static Future<void> _backfillSessionsIntoDrills(Database d) async {
    final rows = await d.query('vision_sessions');
    final batch = d.batch();
    for (final r in rows) {
      final params = jsonEncode({
        'difficulty': r['difficulty'],
        'grid': r['grid'],
        'pattern': r['pattern'],
      });
      batch.insert('drills', {
        'started_at': r['started_at'],
        'task': taskGaborGrid,
        'duration_s': r['duration_s'],
        'completed': 1,
        'trials': r['total'],
        'correct': r['correct'],
        'score': r['score'],
        'params': params,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<int> insertDrill(Drill drill) async {
    final d = await db;
    return d.insert('drills', drill.toMap());
  }

  Future<List<Drill>> allDrills() async {
    final d = await db;
    final rows = await d.query('drills', orderBy: 'started_at DESC');
    return rows.map(Drill.fromMap).toList();
  }

  Future<int> drillsOnDay(DateTime day) async {
    final d = await db;
    final start =
        DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end = start + 24 * 60 * 60 * 1000;
    final rows = await d.rawQuery(
      'SELECT COUNT(*) AS c FROM drills WHERE started_at >= ? AND started_at < ?',
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

  /// Best weighted score, still a Gabor-game notion: an exercise has no score.
  Future<double> bestScore() async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT MAX(score) AS m FROM drills WHERE task = ?', [taskGaborGrid]);
    return ((rows.first['m'] as num?) ?? 0).toDouble();
  }

  /// Days closed by training. A drill counts only if it ran to the end and
  /// lasted at least 30 s, otherwise opening and closing a screen would farm
  /// the streak.
  Future<int> streak() async {
    final d = await db;
    return streakFrom(d, DateTime.now());
  }

  /// Extracted from [streak] so a test can drive the closing-day SQL against
  /// an in-memory database, the same way [migrate] is tested.
  static Future<int> streakFrom(Database d, DateTime now) async {
    final rows = await d.rawQuery(
      "SELECT DISTINCT date(started_at/1000, 'unixepoch', 'localtime') AS day "
      'FROM drills WHERE completed = 1 AND duration_s >= 30',
    );
    final days = rows.map((r) => r['day'] as String).toSet();
    return computeStreak(days, now);
  }

  /// Composite score for a finished session.
  static double computeScore(
          {required int correct, required int total, required Difficulty d}) =>
      total == 0 ? 0 : (correct / total) * 100 * d.weight;
}
