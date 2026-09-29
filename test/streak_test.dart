import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:visor/core/db/vision_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// A bare `drills` table — enough columns for [VisionDb.streakFrom]'s query,
  /// without going through the full v4 migration.
  Future<Database> openDrillsDb() async {
    return databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: (d, v) async {
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
            geometry_id INTEGER,
            score REAL,
            template_id INTEGER,
            params TEXT
          )
        ''');
      }),
    );
  }

  test('streakFrom closes a day only for a completed drill of at least 30s',
      () async {
    final db = await openDrillsDb();

    // Three drills, each on its own day, far enough apart that one day's
    // qualification cannot spill into another's streak count.
    final closes = DateTime(2026, 3, 10, 9); // 30s, completed — should count
    final tooShort = DateTime(2026, 3, 5, 9); // 29s, completed — should not
    final notFinished =
        DateTime(2026, 2, 25, 9); // 60s, not completed — should not

    await db.insert('drills', {
      'started_at': closes.millisecondsSinceEpoch,
      'task': 'gabor_grid',
      'duration_s': 30,
      'completed': 1,
      'trials': 10,
      'correct': 8,
    });
    await db.insert('drills', {
      'started_at': tooShort.millisecondsSinceEpoch,
      'task': 'gabor_grid',
      'duration_s': 29,
      'completed': 1,
      'trials': 10,
      'correct': 8,
    });
    await db.insert('drills', {
      'started_at': notFinished.millisecondsSinceEpoch,
      'task': 'gabor_grid',
      'duration_s': 60,
      'completed': 0,
      'trials': 10,
      'correct': 8,
    });

    // Asking "what is the streak as of this drill's own day" isolates each
    // row: if a filter were dropped, that row's day would wrongly qualify and
    // this call would see it as closing "today".
    expect(await VisionDb.streakFrom(db, closes), 1,
        reason: 'a completed 30s drill closes its day');
    expect(await VisionDb.streakFrom(db, tooShort), 0,
        reason: 'a completed drill under 30s must not close its day');
    expect(await VisionDb.streakFrom(db, notFinished), 0,
        reason: 'an incomplete drill must not close its day, however long');

    await db.close();
  });
}
