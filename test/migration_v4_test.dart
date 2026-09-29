import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:visor/core/db/vision_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// A v3 database with two sessions, one of them carrying a difficulty string
  /// that is not a known Difficulty name.
  Future<Database> openV3() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 3, onCreate: (d, v) async {
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
        await d.execute('''
          CREATE TABLE reminder (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            enabled INTEGER NOT NULL, hour INTEGER NOT NULL,
            minute INTEGER NOT NULL
          )
        ''');
        await d.insert('reminder',
            {'id': 1, 'enabled': 0, 'hour': 21, 'minute': 0});
      }),
    );
    await db.insert('vision_sessions', {
      'started_at': DateTime(2026, 3, 10).millisecondsSinceEpoch,
      'duration_s': 120, 'difficulty': 'hard', 'grid': 5,
      'pattern': 'straight', 'correct': 8, 'total': 10, 'score': 160.0,
    });
    await db.insert('vision_sessions', {
      'started_at': DateTime(2026, 3, 11).millisecondsSinceEpoch,
      'duration_s': 60, 'difficulty': 'insane', 'grid': 7,
      'pattern': 'curved', 'correct': 3, 'total': 9, 'score': 99.0,
    });
    return db;
  }

  test('v4 carries every v3 session into drills', () async {
    final db = await openV3();
    await VisionDb.migrate(db, 3, 4);

    final rows = await db.query('drills', orderBy: 'started_at');
    expect(rows, hasLength(2),
        reason: 'an unknown difficulty string must not drop a row');
    expect(rows.first['task'], 'gabor_grid');
    expect(rows.first['score'], 160.0);
    expect(rows.first['completed'], 1);
    expect(rows.first['threshold'], isNull);
    expect(rows.first['template_id'], isNull);
    expect(rows.last['params'], contains('insane'));
    await db.close();
  });

  test('v4 drops the old table so nothing reads it by accident', () async {
    final db = await openV3();
    await VisionDb.migrate(db, 3, 4);
    final t = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['vision_sessions']);
    expect(t, isEmpty);
    await db.close();
  });

  test('v4 creates the template tables and viewing_geometry', () async {
    final db = await openV3();
    await VisionDb.migrate(db, 3, 4);
    final names = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'])
        .toSet();
    expect(names,
        containsAll(['drills', 'templates', 'template_steps',
                     'week_plan', 'viewing_geometry']));
    await db.close();
  });
}
