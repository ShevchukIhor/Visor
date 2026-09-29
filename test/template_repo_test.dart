import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:visor/core/db/vision_db.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
import 'package:visor/core/training/template_repo.dart';
import 'package:visor/core/training/training_step.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late TemplateRepo repo;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, v) => VisionDb.createV4ForTest(d),
      ),
    );
    repo = TemplateRepo(db);
  });

  tearDown(() async => db.close());

  Template t(String name, List<TrainingStep> steps) =>
      Template(id: 0, name: name, builtin: false, steps: steps);

  test('a saved template round-trips with its steps in order', () async {
    final id = await repo.save(t('Morning', [
      ExerciseStep(type: ExerciseType.convergence, seconds: 60),
      RestStep(cue: 'blink', seconds: 15),
      ExerciseStep(type: ExerciseType.nearFar, seconds: 90, gaborTarget: true),
    ]));

    final all = await repo.all();
    expect(all, hasLength(1));
    final got = all.single;
    expect(got.id, id);
    expect(got.name, 'Morning');
    expect(got.steps.map((s) => s.seconds), [60, 15, 90]);
    expect(got.steps[2], isA<ExerciseStep>());
    expect((got.steps[2] as ExerciseStep).gaborTarget, isTrue);
  });

  test('saving over a template replaces its steps rather than appending',
      () async {
    final id = await repo.save(t('X', [
      ExerciseStep(type: ExerciseType.orbs, seconds: 60),
      ExerciseStep(type: ExerciseType.orbs, seconds: 60),
    ]));
    await repo.save(Template(
      id: id,
      name: 'X',
      builtin: false,
      steps: [ExerciseStep(type: ExerciseType.orbs, seconds: 30)],
    ));
    final got = (await repo.all()).single;
    expect(got.steps, hasLength(1));
  });

  test('deleting a template frees the weekday it was assigned to', () async {
    final id = await repo.save(t('Mon', [
      ExerciseStep(type: ExerciseType.pursuit, seconds: 60),
    ]));
    await repo.setWeekday(DateTime.monday, id);
    expect((await repo.weekPlan())[DateTime.monday], id);

    await repo.delete(id);

    // ON DELETE SET NULL only fires with foreign keys on, which sqflite
    // leaves off by default.
    expect((await repo.weekPlan())[DateTime.monday], isNull);
    expect(await repo.forWeekday(DateTime.monday), isNull);
  });

  test('deleting a template removes its steps', () async {
    final id = await repo.save(t('X', [
      ExerciseStep(type: ExerciseType.orbs, seconds: 60),
    ]));
    await repo.delete(id);
    expect(await db.query('template_steps'), isEmpty);
  });

  test('presets seed once and are marked builtin', () async {
    await repo.seedPresets();
    await repo.seedPresets();
    final all = await repo.all();
    expect(all, hasLength(4));
    expect(all.every((t) => t.builtin), isTrue);
    expect(all.map((t) => t.name), contains('Screen break'));
  });

  test('forWeekday returns the assigned template with its steps', () async {
    await repo.seedPresets();
    final first = (await repo.all()).first;
    await repo.setWeekday(DateTime.wednesday, first.id);
    final got = await repo.forWeekday(DateTime.wednesday);
    expect(got!.name, first.name);
    expect(got.steps, isNotEmpty);
  });
}
