import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:visor/core/db/vision_db.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
import 'package:visor/core/gabor/gabor_patch.dart';
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

  test('an exercise step round-trips its type and its Gabor target',
      () async {
    await repo.save(t('X', [
      ExerciseStep(
          type: ExerciseType.nearFar, seconds: 90, gaborTarget: true),
    ]));
    final s = (await repo.all()).single.steps.single as ExerciseStep;
    // nearFar, not the orElse fallback of orbs: a dropped 'type' would show.
    expect(s.type, ExerciseType.nearFar);
    expect(s.gaborTarget, isTrue);
    expect(s.seconds, 90);
  });

  test('a gabor step round-trips its difficulty and stripe mode', () async {
    await repo.save(t('X', [
      GaborGameStep(
          difficulty: Difficulty.hard, seconds: 180, curved: true),
    ]));
    final s = (await repo.all()).single.steps.single as GaborGameStep;
    expect(s.difficulty, Difficulty.hard); // not the easy fallback
    expect(s.curved, isTrue);
    expect(s.seconds, 180);
  });

  test('a rest step round-trips its cue', () async {
    await repo.save(t('X', [RestStep(cue: 'Blink slowly', seconds: 30)]));
    final s = (await repo.all()).single.steps.single as RestStep;
    expect(s.cue, 'Blink slowly');
    expect(s.seconds, 30);
  });

  test('a drill step round-trips its task id', () async {
    await repo.save(t('X', [DrillStep(task: 'vernier', seconds: 120)]));
    final s = (await repo.all()).single.steps.single as DrillStep;
    expect(s.task, 'vernier');
    expect(s.seconds, 120);
  });

  test("no shipped preset trips the app's own warnings", () async {
    await repo.seedPresets();
    for (final preset in await repo.all()) {
      expect(templateWarnings(preset.steps), isEmpty,
          reason: 'preset "${preset.name}" warns about itself');
    }
  });

  test(
      'deleting a builtin template is refused, but a user template deletes '
      'normally', () async {
    await repo.seedPresets();
    final builtin = (await repo.all()).first;
    await repo.delete(builtin.id);
    expect((await repo.all()).map((tpl) => tpl.id), contains(builtin.id));

    final userId = await repo.save(t('Mine', [
      ExerciseStep(type: ExerciseType.orbs, seconds: 30),
    ]));
    await repo.delete(userId);
    expect((await repo.all()).map((tpl) => tpl.id), isNot(contains(userId)));
  });
}
