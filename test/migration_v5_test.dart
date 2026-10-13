import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:visor/core/db/vision_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openV4({required bool withBuiltin}) async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, v) => VisionDb.createV4ForTest(d),
      ),
    );
    if (withBuiltin) {
      await db.insert('templates',
          {'name': 'Screen break', 'builtin': 1, 'position': 0, 'created_at': 0});
    }
    return db;
  }

  test('v5 creates meta and marks presets seeded when a builtin exists',
      () async {
    final db = await openV4(withBuiltin: true);
    await VisionDb.migrate(db, 4, 5);
    final flag = Sqflite.firstIntValue(
        await db.rawQuery("SELECT value FROM meta WHERE key = 'presets_seeded'"));
    expect(flag, 1);
    await db.close();
  });

  test('v5 leaves the flag unset when no builtin exists', () async {
    final db = await openV4(withBuiltin: false);
    await VisionDb.migrate(db, 4, 5);
    final flag = Sqflite.firstIntValue(
        await db.rawQuery("SELECT value FROM meta WHERE key = 'presets_seeded'"));
    expect(flag, isNull);
    await db.close();
  });
}
