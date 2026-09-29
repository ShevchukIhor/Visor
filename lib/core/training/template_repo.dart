import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../exercises/exercise_painter.dart';
import '../gabor/gabor_patch.dart';
import 'training_step.dart';

/// Storage for routines and the weekly plan.
class TemplateRepo {
  TemplateRepo(this._db);
  final Database _db;

  Future<List<Template>> all() async {
    final rows = await _db.query('templates', orderBy: 'position, id');
    final steps = await _db.query('template_steps',
        orderBy: 'template_id, position');
    final byTemplate = <int, List<TrainingStep>>{};
    for (final r in steps) {
      byTemplate
          .putIfAbsent(r['template_id'] as int, () => <TrainingStep>[])
          .add(_stepFromRow(r));
    }
    return [
      for (final r in rows)
        Template(
          id: r['id'] as int,
          name: r['name'] as String,
          builtin: (r['builtin'] as int) == 1,
          steps: byTemplate[r['id'] as int] ?? const [],
        ),
    ];
  }

  /// Insert when [t.id] is 0, otherwise replace in place. Steps are always
  /// rewritten wholesale: reordering and deletion make an incremental diff
  /// more code than it is worth at this size.
  Future<int> save(Template t) async {
    return _db.transaction((txn) async {
      var id = t.id;
      if (id == 0) {
        final maxPos = Sqflite.firstIntValue(await txn
                .rawQuery('SELECT MAX(position) FROM templates')) ??
            0;
        id = await txn.insert('templates', {
          'name': t.name,
          'builtin': t.builtin ? 1 : 0,
          'position': maxPos + 1,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        await txn.update('templates', {'name': t.name},
            where: 'id = ?', whereArgs: [id]);
        await txn.delete('template_steps',
            where: 'template_id = ?', whereArgs: [id]);
      }
      for (var i = 0; i < t.steps.length; i++) {
        await txn.insert('template_steps', _stepToRow(id, i, t.steps[i]));
      }
      return id;
    });
  }

  /// Builtins can be run, copied and edited, but never deleted.
  Future<void> delete(int id) async {
    await _db.delete('templates',
        where: 'id = ? AND builtin = 0', whereArgs: [id]);
  }

  Future<Map<int, int?>> weekPlan() async {
    final rows = await _db.query('week_plan');
    return {
      for (var d = 1; d <= 7; d++) d: null,
      for (final r in rows)
        r['weekday'] as int: r['template_id'] as int?,
    };
  }

  Future<void> setWeekday(int weekday, int? templateId) async {
    await _db.insert(
      'week_plan',
      {'weekday': weekday, 'template_id': templateId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Template?> forWeekday(int weekday) async {
    final id = (await weekPlan())[weekday];
    if (id == null) return null;
    final list = await all();
    for (final t in list) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Ship four routines so the list is never an empty page. Idempotent: it
  /// does nothing once any builtin template exists. Guarding on builtins
  /// specifically (rather than any template) is safe only because [delete]
  /// refuses to remove a builtin — otherwise deleting all four would
  /// resurrect them on the next app start.
  Future<void> seedPresets() async {
    final n = Sqflite.firstIntValue(await _db
            .rawQuery('SELECT COUNT(*) FROM templates WHERE builtin = 1')) ??
        0;
    if (n > 0) return;
    for (final t in _presets) {
      await save(t);
    }
  }

  static final List<Template> _presets = [
    Template(id: 0, name: 'Screen break', builtin: true, steps: const [
      ExerciseStep(type: ExerciseType.nearFar, seconds: 60),
      ExerciseStep(type: ExerciseType.focusShift, seconds: 45),
      ExerciseStep(type: ExerciseType.peripheral, seconds: 45),
      RestStep(cue: 'Blink slowly and let your eyes soften', seconds: 30),
    ]),
    Template(id: 0, name: 'Morning', builtin: true, steps: const [
      ExerciseStep(type: ExerciseType.convergence, seconds: 60),
      RestStep(cue: 'Blink — smooth pursuit next', seconds: 15),
      ExerciseStep(type: ExerciseType.pursuit, seconds: 60),
      ExerciseStep(type: ExerciseType.saccadic, seconds: 45),
      ExerciseStep(type: ExerciseType.figure8, seconds: 60),
      ExerciseStep(type: ExerciseType.orbs, seconds: 60),
    ]),
    Template(id: 0, name: 'Wind down', builtin: true, steps: const [
      ExerciseStep(type: ExerciseType.orbs, seconds: 90),
      ExerciseStep(type: ExerciseType.nearFar, seconds: 90),
      RestStep(cue: 'Close your eyes until the timer ends', seconds: 60),
    ]),
    Template(id: 0, name: 'Sharpen', builtin: true, steps: const [
      GaborGameStep(difficulty: Difficulty.medium, seconds: 180),
      ExerciseStep(type: ExerciseType.saccadic, seconds: 60),
      RestStep(cue: 'Blink — focus shifting next', seconds: 15),
      ExerciseStep(type: ExerciseType.focusShift, seconds: 60),
      ExerciseStep(type: ExerciseType.orbs, seconds: 60),
    ]),
  ];

  Map<String, Object?> _stepToRow(int templateId, int position,
      TrainingStep s) {
    final (kind, params) = switch (s) {
      ExerciseStep(:final type, :final gaborTarget) => (
          'exercise',
          {'type': type.name, 'gaborTarget': gaborTarget}
        ),
      GaborGameStep(:final difficulty, :final curved) => (
          'gabor',
          {'difficulty': difficulty.name, 'curved': curved}
        ),
      RestStep(:final cue) => ('rest', {'cue': cue}),
      DrillStep(:final task) => ('drill', {'task': task}),
    };
    return {
      'template_id': templateId,
      'position': position,
      'kind': kind,
      'seconds': s.seconds,
      'params': jsonEncode(params),
    };
  }

  TrainingStep _stepFromRow(Map<String, Object?> r) {
    final seconds = r['seconds'] as int;
    final p = jsonDecode((r['params'] as String?) ?? '{}')
        as Map<String, Object?>;
    switch (r['kind'] as String) {
      case 'exercise':
        return ExerciseStep(
          type: ExerciseType.values.firstWhere(
              (t) => t.name == p['type'],
              orElse: () => ExerciseType.orbs),
          seconds: seconds,
          gaborTarget: p['gaborTarget'] == true,
        );
      case 'gabor':
        return GaborGameStep(
          difficulty: Difficulty.values.firstWhere(
              (d) => d.name == p['difficulty'],
              orElse: () => Difficulty.easy),
          seconds: seconds,
          curved: p['curved'] == true,
        );
      case 'drill':
        return DrillStep(task: (p['task'] as String?) ?? '', seconds: seconds);
      case 'rest':
        return RestStep(cue: (p['cue'] as String?) ?? '', seconds: seconds);
      default:
        // Rest is explicitly not training, so a corrupt or future-version
        // row must never be silently treated as a rest step — that would
        // stop it from counting toward a streak without anyone noticing.
        throw StateError('Unknown training step kind: ${r['kind']}');
    }
  }
}
