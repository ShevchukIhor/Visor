# Training Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user run several exercises back to back from one tap as a saved routine, and assign routines to weekdays as a suggestion.

**Architecture:** A `TrainingStep` sealed hierarchy describes a routine's steps; templates and the weekly plan live in SQLite behind a repository. A `SessionRunner` walks the steps, rebuilding the existing `ExerciseRunner` per step via `ValueKey`, so the runner's internals are untouched and a single exercise becomes a one-step session. Every completed step writes a row to a new generic `drills` table, which finally makes eye exercises count toward the streak.

**Tech Stack:** Flutter, sqflite, `sqflite_common_ffi` (new, tests only), Kotlin (`ReminderReceiver`, `ReminderStore`).

**Spec:** `dev-docs/specs/2026-09-29-training-templates-design.md`

## Global Constraints

- The weekly plan is a **suggestion**, never a prescription: any training counts toward the streak regardless of which routine ran.
- Editor warnings **warn, never block**. Nothing in this feature prevents the user from saving or running a template.
- Templates with `builtin = 1` can be run, copied and edited, but not deleted.
- `RestStep` writes nothing to the database — it is not training.
- Weekday numbering is ISO: Monday = 1 … Sunday = 7. `DateTime.weekday` already uses this.
- The reminder stores **all seven** weekday labels; `ReminderReceiver` picks by the weekday at fire time, never by a stored "today".
- There is **no session row**. A routine is a group of `drills` rows sharing `template_id` and a date; "incomplete" is computed where displayed.
- Streak rule, unchanged in shape: a day is closed by any `drills` row with `completed = 1 AND duration_s >= 30`.
- All code comments, commit messages and user-facing strings are English.
- **Deliberately not built here:** spec §7.3's cap on total session length. The
  spec ties it to the per-category vergence cap "once that lands", and that cap
  belongs to the psychophysical-engine spec. Routines ship without it; the
  editor warnings (§2) are the only load guidance in this plan.

## Review Focus

Five conditions the spec implies but does not spell out as tests. Each is pinned to a task below.

1. **A template with no runnable steps** (empty, or nothing but `RestStep`) must not launch a session — Start is disabled and says why. *(Task 2)*
2. **Deleting a template assigned to a weekday** must leave that day as "no plan" rather than a dangling id or a crash — which only holds if `PRAGMA foreign_keys` is actually on. *(Task 3)*
3. **The v4 backfill must not lose rows**, including a session whose `difficulty` string is not a known `Difficulty` name. *(Task 1)*
4. **Quitting during the first step** must write no `drills` rows and leave the streak untouched — a routine opened and abandoned is not training. *(Task 4, via `drillForExercise`)*
5. **The reminder firing days after the app last ran** must name the current weekday's routine, not the one stored when it was scheduled. *(Task 8)*

---

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `lib/core/training/training_step.dart` | `TrainingStep` hierarchy, `Template`, load categories, validation warnings. Pure Dart. |
| `lib/core/training/template_repo.dart` | CRUD for templates, steps and the weekly plan; preset seeding. |
| `lib/core/db/drill.dart` | `Drill` row model and its mapping. |
| `lib/screens/session_runner.dart` | Walks a step list; owns session chrome and the finish card. |
| `lib/screens/templates_screen.dart` | Template list. |
| `lib/screens/template_editor_screen.dart` | Reorderable step editor. |
| `lib/screens/week_plan_screen.dart` | Seven weekday rows. |
| `lib/widgets/today_card.dart` | Dashboard "Today" card. |
| `test/training_step_test.dart` | Model, categories, warnings, runnability. |
| `test/migration_v4_test.dart` | Schema creation, backfill, foreign keys. |
| `test/template_repo_test.dart` | Repository round-trips, seeding, deletion behaviour. |

**Modified**

| File | Change |
|---|---|
| `lib/core/db/vision_db.dart` | v4 migration; `drills` CRUD; streak and best-score read `drills`. |
| `lib/screens/exercises_screen.dart` | `ExerciseRunner` loses its picker, gains `autoStart`/`onDone`; records a drill. |
| `lib/screens/dashboard_screen.dart` | Today card; Routines menu entry. |
| `lib/screens/analytics_screen.dart` | Reads `drills` instead of `vision_sessions`. |
| `lib/widgets/accuracy_chart.dart` | `toSample` takes a `Drill`. |
| `lib/core/reminder/reminder_service.dart` | Writes seven weekday labels. |
| `android/.../ReminderStore.kt` | Stores and reads the seven labels. |
| `android/.../ReminderReceiver.kt` | Picks the label by current weekday. |
| `pubspec.yaml` | `sqflite_common_ffi` dev dependency. |

---

## Task 1: Schema v4 — the `drills` table and the backfill

The `drills` table is shared with the psychophysical-engine spec; this task creates the whole of it, including the columns that spec will fill later. `viewing_geometry` is created here too, because `drills.geometry_id` references it and, with foreign keys on, an insert would fail against a missing table. Rebuilding a table later to add an FK is far worse than six lines now.

**Files:**
- Modify: `lib/core/db/vision_db.dart`
- Create: `lib/core/db/drill.dart`
- Create: `test/migration_v4_test.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: nothing.
- Produces: `class Drill` with fields `id, startedAt, task, durationS, completed, trials, correct, threshold, thresholdUnit, reversals, geometryId, score, templateId, params` and `Drill.fromMap` / `toMap`; `VisionDb.insertDrill(Drill) → Future<int>`, `VisionDb.allDrills() → Future<List<Drill>>`.

- [ ] **Step 1: Add the test-only sqflite backend**

In `pubspec.yaml`, under `dev_dependencies`:

```yaml
  sqflite_common_ffi: ^2.3.3
```

Run: `flutter pub get`

- [ ] **Step 2: Write the failing migration test**

Create `test/migration_v4_test.dart`:

```dart
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
```

- [ ] **Step 3: Run the test and watch it fail**

Run: `flutter test test/migration_v4_test.dart`
Expected: FAIL — `Method not found: 'VisionDb.migrate'`.

- [ ] **Step 4: Create the `Drill` model**

Create `lib/core/db/drill.dart`:

```dart
/// One recorded unit of training: a Gabor game, an eye exercise, or — once the
/// psychophysical engine lands — a measured drill. Replaces VisionSession.
class Drill {
  final int id;
  final DateTime startedAt;
  final String task;
  final int durationS;
  final bool completed;
  final int trials;
  final int correct;
  final double? threshold;
  final String? thresholdUnit;
  final String? reversals;
  final int? geometryId;
  final double? score;
  final int? templateId;
  final String? params;

  const Drill({
    this.id = 0,
    required this.startedAt,
    required this.task,
    required this.durationS,
    this.completed = true,
    this.trials = 0,
    this.correct = 0,
    this.threshold,
    this.thresholdUnit,
    this.reversals,
    this.geometryId,
    this.score,
    this.templateId,
    this.params,
  });

  Map<String, Object?> toMap() => {
        'started_at': startedAt.millisecondsSinceEpoch,
        'task': task,
        'duration_s': durationS,
        'completed': completed ? 1 : 0,
        'trials': trials,
        'correct': correct,
        'threshold': threshold,
        'threshold_unit': thresholdUnit,
        'reversals': reversals,
        'geometry_id': geometryId,
        'score': score,
        'template_id': templateId,
        'params': params,
      };

  factory Drill.fromMap(Map<String, Object?> m) => Drill(
        id: m['id'] as int,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        task: m['task'] as String,
        durationS: m['duration_s'] as int,
        completed: (m['completed'] as int) == 1,
        trials: m['trials'] as int,
        correct: m['correct'] as int,
        threshold: (m['threshold'] as num?)?.toDouble(),
        thresholdUnit: m['threshold_unit'] as String?,
        reversals: m['reversals'] as String?,
        geometryId: m['geometry_id'] as int?,
        score: (m['score'] as num?)?.toDouble(),
        templateId: m['template_id'] as int?,
        params: m['params'] as String?,
      );
}
```

- [ ] **Step 5: Write the migration**

In `lib/core/db/vision_db.dart`, add a static `migrate` so the SQL is reachable from a test without opening the app's real database file:

```dart
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
        'task': 'gabor_grid',
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
```

Add `import 'dart:convert';` at the top of the file, bump `version: 3` to `version: 4` in `_open`, route both callbacks through `migrate`, and turn foreign keys on — sqflite leaves them off, which would make every `ON DELETE` clause in this schema decoration:

```dart
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
```

- [ ] **Step 6: Run the migration test**

Run: `flutter test test/migration_v4_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 7: Move the existing queries onto `drills`**

Replace `insertSession` / `allSessions` / `sessionsOnDay` / `bestScore` / `streak` in `vision_db.dart`:

```dart
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

  /// Best weighted score, still a Gabor-game notion: an exercise has no score.
  Future<double> bestScore() async {
    final d = await db;
    final rows = await d.rawQuery(
        "SELECT MAX(score) AS m FROM drills WHERE task = 'gabor_grid'");
    return ((rows.first['m'] as num?) ?? 0).toDouble();
  }

  /// Days closed by training. A drill counts only if it ran to the end and
  /// lasted at least 30 s, otherwise opening and closing a screen would farm
  /// the streak.
  Future<int> streak() async {
    final d = await db;
    final rows = await d.rawQuery(
      "SELECT DISTINCT date(started_at/1000, 'unixepoch', 'localtime') AS day "
      'FROM drills WHERE completed = 1 AND duration_s >= 30',
    );
    final days = rows.map((r) => r['day'] as String).toSet();
    return computeStreak(days, DateTime.now());
  }
```

Delete `class VisionSession` and its `toMap`/`fromMap`. Update `game_screen.dart:82-92` to insert a `Drill` instead:

```dart
      await VisionDb.instance.insertDrill(Drill(
        startedAt: _startedAt ?? DateTime.now(),
        task: 'gabor_grid',
        durationS: widget.setup.durationS,
        completed: true,
        trials: _total,
        correct: _correct,
        score: score,
        templateId: widget.templateId,
        params: jsonEncode({
          'difficulty': widget.setup.difficulty.name,
          'grid': _grid,
          'pattern': widget.setup.curved ? 'curved' : 'straight',
        }),
      ));
```

Add `final int? templateId;` to `GameScreen` with a default of `null` so the standalone path is unchanged.

- [ ] **Step 8: Point the chart at `Drill`**

In `lib/widgets/accuracy_chart.dart`, change `toSample` and the widget's field type:

```dart
SessionSample toSample(Drill d) => SessionSample.fromCounts(
      at: d.startedAt,
      correct: d.correct,
      total: d.trials,
      difficulty: difficultyByName(_difficultyOf(d)),
    );

/// The difficulty moved into the params JSON in schema v4.
String _difficultyOf(Drill d) {
  if (d.params == null) return '';
  final m = jsonDecode(d.params!) as Map<String, Object?>;
  return (m['difficulty'] as String?) ?? '';
}
```

Change `AccuracyChart.sessions` to `List<Drill> drills`, and filter to the Gabor game where it is built — an exercise has no accuracy to plot:

```dart
    final points = aggregateByDay([
      for (final d in drills)
        if (d.task == 'gabor_grid' && d.trials > 0) toSample(d),
    ]);
```

Update `analytics_screen.dart` to call `allDrills()` and to render the history rows from `Drill`.

- [ ] **Step 9: Update the golden fixture**

`test/accuracy_chart_golden_test.dart` builds `VisionSession` objects, which no
longer exist. Change its `session()` helper to build a `Drill`:

```dart
  int id = 0;
  Drill session(
    DateTime at, {
    int correct = 8,
    int total = 10,
    Difficulty difficulty = Difficulty.easy,
  }) =>
      Drill(
        id: ++id,
        startedAt: at,
        task: 'gabor_grid',
        durationS: 60,
        completed: true,
        trials: total,
        correct: correct,
        score: VisionDb.computeScore(
            correct: correct, total: total, d: difficulty),
        params: jsonEncode({
          'difficulty': difficulty.name,
          'grid': difficulty.grid,
          'pattern': 'straight',
        }),
      );
```

and `AccuracyChart(sessions: sessions, now: now)` to `AccuracyChart(drills: sessions, now: now)`.

- [ ] **Step 10: Run the whole suite**

Run: `flutter test && dart analyze`
Expected: all tests pass, analyzer clean. `chart_math_test.dart` is untouched —
`SessionSample` did not change shape. The golden image must still match without
`--update-goldens`: the chart's pixels do not depend on where the rows came
from. If it does not match, something in the data mapping changed meaning —
find out what before regenerating.

- [ ] **Step 11: Commit**

```bash
git add pubspec.yaml lib/core/db lib/screens/game_screen.dart \
        lib/screens/analytics_screen.dart lib/widgets/accuracy_chart.dart \
        test/migration_v4_test.dart test/accuracy_chart_golden_test.dart
git commit -m "feat(db): schema v4 — generic drills table replaces vision_sessions"
```

---

## Task 2: The step model, categories and warnings

**Files:**
- Create: `lib/core/training/training_step.dart`
- Create: `test/training_step_test.dart`

**Interfaces:**
- Consumes: `ExerciseType` and `Difficulty`.
- Produces: `sealed class TrainingStep`, `ExerciseStep`, `GaborGameStep`, `RestStep`, `DrillStep`, `Template`, `ExerciseLoad` enum with `ExerciseType.load`, `List<String> templateWarnings(List<TrainingStep>)`, `bool isRunnable(List<TrainingStep>)`.

- [ ] **Step 1: Write the failing test**

Create `test/training_step_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/exercises/exercise_painter.dart';
import 'package:visor/core/gabor/gabor_patch.dart';
import 'package:visor/core/training/training_step.dart';

void main() {
  group('Template', () {
    test('total time is the sum of its steps', () {
      final t = Template(id: 1, name: 'x', builtin: false, steps: [
        ExerciseStep(type: ExerciseType.pursuit, seconds: 60),
        RestStep(cue: 'blink', seconds: 15),
        GaborGameStep(difficulty: Difficulty.medium, seconds: 180),
      ]);
      expect(t.totalSeconds, 255);
    });
  });

  group('isRunnable', () {
    test('a template with no steps cannot start a session', () {
      expect(isRunnable([]), isFalse);
    });

    test('a template of nothing but rest cannot start a session', () {
      expect(
        isRunnable([
          RestStep(cue: 'blink', seconds: 30),
          RestStep(cue: 'relax', seconds: 30),
        ]),
        isFalse,
      );
    });

    test('one real step is enough', () {
      expect(
        isRunnable([
          RestStep(cue: 'blink', seconds: 30),
          ExerciseStep(type: ExerciseType.orbs, seconds: 60),
        ]),
        isTrue,
      );
    });
  });

  group('load categories', () {
    test('every exercise type has a load', () {
      for (final t in ExerciseType.values) {
        expect(t.load, isNotNull, reason: '$t');
      }
    });

    test('the two tracking drills share a category', () {
      expect(ExerciseType.pursuit.load, ExerciseType.figure8.load);
      expect(ExerciseType.pursuit.load, ExerciseLoad.pursuit);
    });
  });

  group('templateWarnings', () {
    test('a well-formed routine warns about nothing', () {
      final w = templateWarnings([
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
        RestStep(cue: 'blink', seconds: 15),
        ExerciseStep(type: ExerciseType.pursuit, seconds: 60),
        ExerciseStep(type: ExerciseType.saccadic, seconds: 45),
      ]);
      expect(w, isEmpty);
    });

    test('two steps of the same load in a row are flagged', () {
      final w = templateWarnings([
        ExerciseStep(type: ExerciseType.pursuit, seconds: 60),
        ExerciseStep(type: ExerciseType.figure8, seconds: 60),
      ]);
      expect(w, hasLength(1));
      expect(w.single, contains('Smooth Pursuit'));
      expect(w.single, contains('Figure-8'));
    });

    test('vergence work without a rest after it is flagged', () {
      final w = templateWarnings([
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
        ExerciseStep(type: ExerciseType.saccadic, seconds: 45),
      ]);
      expect(w, hasLength(1));
      expect(w.single.toLowerCase(), contains('rest'));
    });

    test('vergence as the last step needs no rest after it', () {
      final w = templateWarnings([
        ExerciseStep(type: ExerciseType.saccadic, seconds: 45),
        ExerciseStep(type: ExerciseType.convergence, seconds: 60),
      ]);
      expect(w, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `flutter test test/training_step_test.dart`
Expected: FAIL — `Error: Not found: 'package:visor/core/training/training_step.dart'`.

- [ ] **Step 3: Write the model**

Create `lib/core/training/training_step.dart`:

```dart
/// Routine building blocks. Pure Dart: no Flutter, so the rules below are
/// directly testable.
library;

import '../exercises/exercise_painter.dart';
import '../gabor/gabor_patch.dart';

/// What a step loads. Used to warn about badly shaped routines; a chain of
/// arbitrary animations is just a longer animation.
enum ExerciseLoad {
  vergence,
  accommodation,
  saccadic,
  pursuit,
  peripheral,
  relax,
}

extension ExerciseLoadOf on ExerciseType {
  ExerciseLoad get load => switch (this) {
        ExerciseType.convergence => ExerciseLoad.vergence,
        ExerciseType.nearFar => ExerciseLoad.accommodation,
        ExerciseType.focusShift => ExerciseLoad.saccadic,
        ExerciseType.saccadic => ExerciseLoad.saccadic,
        ExerciseType.pursuit => ExerciseLoad.pursuit,
        ExerciseType.figure8 => ExerciseLoad.pursuit,
        ExerciseType.peripheral => ExerciseLoad.peripheral,
        ExerciseType.orbs => ExerciseLoad.relax,
      };
}

sealed class TrainingStep {
  const TrainingStep({required this.seconds});
  final int seconds;

  /// Label shown in the editor and in the session's top bar.
  String get title;
}

class ExerciseStep extends TrainingStep {
  const ExerciseStep({
    required this.type,
    required super.seconds,
    this.gaborTarget = false,
  });

  final ExerciseType type;

  /// Near-Far only: the sphere is a Gabor patch rather than a plain dot. The
  /// standalone runner exposes this as a chip; a template fixes it.
  final bool gaborTarget;

  @override
  String get title => type.title;
}

class GaborGameStep extends TrainingStep {
  const GaborGameStep({
    required this.difficulty,
    required super.seconds,
    this.curved = false,
  });

  final Difficulty difficulty;
  final bool curved;

  @override
  String get title => 'Gabor Game · ${difficulty.label}';
}

class RestStep extends TrainingStep {
  const RestStep({required this.cue, required super.seconds});
  final String cue;

  @override
  String get title => 'Rest';
}

/// Reserved for the psychophysical engine. Not rendered until that lands.
class DrillStep extends TrainingStep {
  const DrillStep({required this.task, required super.seconds});
  final String task;

  @override
  String get title => task;
}

class Template {
  const Template({
    required this.id,
    required this.name,
    required this.builtin,
    required this.steps,
  });

  final int id;
  final String name;
  final bool builtin;
  final List<TrainingStep> steps;

  int get totalSeconds =>
      steps.fold(0, (sum, s) => sum + s.seconds);
}

/// Whether a step list is worth starting. Rest is not training, so a routine
/// made only of rest has nothing to run.
bool isRunnable(List<TrainingStep> steps) =>
    steps.any((s) => s is! RestStep);

/// Advisory notes for the editor. These never block saving or running — they
/// describe load, and the user is allowed to disagree.
List<String> templateWarnings(List<TrainingStep> steps) {
  final out = <String>[];
  for (var i = 0; i < steps.length - 1; i++) {
    final a = steps[i];
    final b = steps[i + 1];
    if (a is! ExerciseStep) continue;
    if (b is ExerciseStep && a.type.load == b.type.load) {
      out.add('${a.type.title} and ${b.type.title} load the same system '
          'back to back — consider separating them.');
    }
    if (a.type.load == ExerciseLoad.vergence && b is! RestStep) {
      out.add('${a.type.title} is vergence work; a rest step after it '
          'reduces eye strain.');
    }
  }
  return out;
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/training_step_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/core/training/training_step.dart test/training_step_test.dart
git commit -m "feat(training): step model, load categories and routine warnings"
```

---

## Task 3: The template repository

**Files:**
- Create: `lib/core/training/template_repo.dart`
- Create: `test/template_repo_test.dart`
- Modify: `lib/core/db/vision_db.dart` (expose the `Database` handle — it already does, via `db`)

**Interfaces:**
- Consumes: `Template`, `TrainingStep` (Task 2); the v4 schema (Task 1).
- Produces: `TemplateRepo(Database)` with `Future<List<Template>> all()`, `Future<int> save(Template)`, `Future<void> delete(int id)`, `Future<void> seedPresets()`, `Future<Map<int, int?>> weekPlan()`, `Future<void> setWeekday(int weekday, int? templateId)`, `Future<Template?> forWeekday(int weekday)`.

- [ ] **Step 1: Write the failing test**

Create `test/template_repo_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `flutter test test/template_repo_test.dart`
Expected: FAIL — `Not found: 'package:visor/core/training/template_repo.dart'`.

- [ ] **Step 3: Expose the v4 DDL for tests**

In `vision_db.dart`, add a thin alias next to `migrate` so a test can build the schema without the app's file path:

```dart
  /// The v4 DDL, for tests that need the schema without the app's database
  /// file. Production goes through [_open].
  static Future<void> createV4ForTest(Database d) => _createV4(d);
```

- [ ] **Step 4: Write the repository**

Create `lib/core/training/template_repo.dart`:

```dart
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

  Future<void> delete(int id) async {
    await _db.delete('templates', where: 'id = ?', whereArgs: [id]);
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
  /// does nothing once any template exists.
  Future<void> seedPresets() async {
    final n = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM templates')) ??
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
      ExerciseStep(type: ExerciseType.figure8, seconds: 60),
      ExerciseStep(type: ExerciseType.saccadic, seconds: 45),
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
      default:
        return RestStep(cue: (p['cue'] as String?) ?? '', seconds: seconds);
    }
  }
}
```

- [ ] **Step 5: Run the test**

Run: `flutter test test/template_repo_test.dart`
Expected: PASS, 6 tests. If `deleting a template frees the weekday` fails with the id still present, `PRAGMA foreign_keys = ON` is not being applied — check `onConfigure`, not `onOpen`.

- [ ] **Step 6: Commit**

```bash
git add lib/core/training/template_repo.dart lib/core/db/vision_db.dart \
        test/template_repo_test.dart
git commit -m "feat(training): template and weekly-plan repository with seeded presets"
```

---

## Task 4: Exercises record a drill

Independent value, and a prerequisite for routines: until an exercise writes a row, a routine of exercises records nothing.

**Files:**
- Modify: `lib/screens/exercises_screen.dart` (`_ExerciseRunnerState._finish`, around line 250)

**Interfaces:**
- Consumes: `VisionDb.insertDrill`, `Drill` (Task 1).
- Produces: `Drill? drillForExercise({required ExerciseType type, required int seconds, required bool completed, required DateTime endedAt, int? templateId})` in `lib/core/training/training_step.dart`.

- [ ] **Step 1: Write the failing test for the drill builder**

The rule "an abandoned exercise is not training" must live somewhere a test can
reach. Putting it in a pure builder makes it a guard rather than a convention:
even if a future edit calls the recorder from the exit path, the builder
refuses. Add to `test/training_step_test.dart`:

```dart
  group('drillForExercise', () {
    final ended = DateTime(2026, 3, 15, 9, 30);

    test('a completed exercise becomes a drill row', () {
      final d = drillForExercise(
        type: ExerciseType.pursuit,
        seconds: 60,
        completed: true,
        endedAt: ended,
        templateId: 7,
      );
      expect(d, isNotNull);
      expect(d!.task, 'exercise');
      expect(d.durationS, 60);
      expect(d.completed, isTrue);
      expect(d.templateId, 7);
      expect(d.params, contains('pursuit'));
      // Backdated by its own length: the drill occupies the time it ran.
      expect(d.startedAt, ended.subtract(const Duration(seconds: 60)));
    });

    test('an abandoned exercise produces nothing to record', () {
      final d = drillForExercise(
        type: ExerciseType.pursuit,
        seconds: 60,
        completed: false,
        endedAt: ended,
      );
      expect(d, isNull);
    });
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/training_step_test.dart`
Expected: FAIL — `Method not found: 'drillForExercise'`.

- [ ] **Step 3: Write the builder**

Append to `lib/core/training/training_step.dart` (add `dart:convert` and the
`Drill` import):

```dart
/// The `drills` row for a finished exercise, or null when it did not finish.
///
/// Returning null rather than writing an "incomplete" row is the guard: an
/// exercise the user walked out of is not training, and the streak must not
/// see it.
Drill? drillForExercise({
  required ExerciseType type,
  required int seconds,
  required bool completed,
  required DateTime endedAt,
  int? templateId,
}) {
  if (!completed) return null;
  return Drill(
    startedAt: endedAt.subtract(Duration(seconds: seconds)),
    task: 'exercise',
    durationS: seconds,
    completed: true,
    templateId: templateId,
    params: jsonEncode({'type': type.name}),
  );
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/training_step_test.dart`
Expected: PASS.

- [ ] **Step 5: Record on completion**

In `_ExerciseRunnerState`, replace `_finish()`:

```dart
  void _finish() {
    _ticker?.cancel();
    _ctrl.stop();
    _clock.stop();
    setState(() {
      _running = false;
      _finished = true;
    });
    _record();
  }

  /// A completed exercise is training: it belongs in `drills` so the streak,
  /// the today-counter and the history see it. Exiting early records nothing.
  Future<void> _record() async {
    try {
      final drill = drillForExercise(
        type: widget.type,
        seconds: _duration,
        completed: true,
        endedAt: DateTime.now(),
        templateId: widget.templateId,
      );
      if (drill == null) return;
      await VisionDb.instance.insertDrill(drill);
      await ReminderService.markTrainedToday();
    } catch (e) {
      debugPrint('Failed to record exercise: $e');
    }
  }
```

Add `final int? templateId;` to `ExerciseRunner` (default `null`) and the imports for `drillForExercise`, `VisionDb` and `ReminderService`. `_exit()` stays as it is — it must not call `_record`.

- [ ] **Step 6: Verify by hand**

Ask before installing on the device. On an emulator, or with the user's
go-ahead: run an exercise to completion, return to the dashboard, confirm the
today-counter and streak moved. Then start an exercise and close it early, and
confirm neither moved.

- [ ] **Step 7: Run the suite and commit**

```bash
flutter test && dart analyze
git add lib/screens/exercises_screen.dart lib/core/training/training_step.dart \
        test/training_step_test.dart
git commit -m "feat(exercises): record a completed exercise so it counts toward the streak"
```

---

## Task 5: `SessionRunner`

**Files:**
- Create: `lib/screens/session_runner.dart`
- Modify: `lib/screens/exercises_screen.dart`

**Interfaces:**
- Consumes: `Template`, `TrainingStep`, `isRunnable` (Task 2); `ExerciseRunner`.
- Produces: `SessionRunner({required Template template})`; `ExerciseRunner({required ExerciseType type, int? seconds, bool autoStart = false, bool gaborTarget = false, VoidCallback? onDone, int? templateId})`.

- [ ] **Step 1: Change `ExerciseRunner`'s edges**

Add to `ExerciseRunner`:

```dart
  /// Fixed duration supplied by a routine step. When null the runner shows its
  /// own picker, which is the standalone path.
  final int? seconds;
  final bool autoStart;

  /// Called instead of showing the terminal card, so a session can advance.
  final VoidCallback? onDone;

  /// Near-Far target choice, fixed by a routine step.
  final bool gaborTarget;
```

In `initState`, honour them:

```dart
    if (widget.seconds != null) {
      _duration = widget.seconds!;
      _secondsLeft = _duration;
    }
    _nearFarGabor = widget.gaborTarget;
    if (widget.gaborTarget) _loadGaborImages(count: 6);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
```

In `_finish`, hand control up when a session owns it:

```dart
    _record();
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
      return;
    }
```

In `_overlay()`, return `const SizedBox.shrink()` when `widget.seconds != null` and the runner is not finished — the picker belongs to the standalone path only.

- [ ] **Step 2: Write `SessionRunner`**

Create `lib/screens/session_runner.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/visor_theme.dart';
import '../core/training/training_step.dart';
import 'exercises_screen.dart';
import 'game_screen.dart';
import '../core/models/session_setup.dart';

/// Walks a routine's steps without returning to any list.
///
/// Each step gets a fresh child keyed by its index: ExerciseRunner builds its
/// AnimationController in initState from a per-type loop length, so switching
/// type inside one State is not possible. A new key is the idiomatic way to
/// get a new State, a new controller and a clean dispose.
class SessionRunner extends StatefulWidget {
  const SessionRunner({super.key, required this.template});
  final Template template;

  @override
  State<SessionRunner> createState() => _SessionRunnerState();
}

class _SessionRunnerState extends State<SessionRunner> {
  int _index = 0;
  bool _done = false;

  List<TrainingStep> get _steps => widget.template.steps;

  void _next() {
    if (_index + 1 >= _steps.length) {
      setState(() => _done = true);
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _finishCard();
    final step = _steps[_index];
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      body: Stack(children: [
        Positioned.fill(child: _stage(step)),
        SafeArea(child: _progressBar(step)),
      ]),
    );
  }

  Widget _stage(TrainingStep step) {
    final key = ValueKey('step-$_index');
    return switch (step) {
      ExerciseStep(:final type, :final seconds, :final gaborTarget) =>
        ExerciseRunner(
          key: key,
          type: type,
          seconds: seconds,
          gaborTarget: gaborTarget,
          autoStart: true,
          onDone: _next,
          templateId: widget.template.id,
        ),
      GaborGameStep(:final difficulty, :final seconds, :final curved) =>
        GameScreen(
          key: key,
          setup: SessionSetup(
              durationS: seconds, difficulty: difficulty, curved: curved),
          templateId: widget.template.id,
          onDone: _next,
        ),
      // Patterns must BIND: in a switch expression the scrutinee is not
      // promoted, so `RestStep()` alone would leave `step` typed TrainingStep.
      final RestStep rest => _RestCard(
          key: key,
          step: rest,
          next: _index + 1 < _steps.length ? _steps[_index + 1].title : null,
          onDone: _next,
        ),
      DrillStep(:final seconds) => _RestCard(
          key: key,
          step: RestStep(cue: 'Not available yet', seconds: seconds),
          next: null,
          onDone: _next,
        ),
    };
  }

  Widget _progressBar(TrainingStep step) {
    final total = _steps.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close, color: VisorTheme.text, size: 20),
          tooltip: 'Quit routine',
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_index + 1}/$total · ${step.title}',
                style: const TextStyle(color: VisorTheme.text, fontSize: 14)),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (_index) / total,
              backgroundColor: VisorTheme.surfaceAlt,
              color: VisorTheme.primary,
              minHeight: 3,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _finishCard() {
    final mins = (widget.template.totalSeconds / 60).round();
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle,
                color: VisorTheme.success, size: 56),
            const SizedBox(height: 16),
            Text(widget.template.name,
                style: const TextStyle(
                    color: VisorTheme.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('${_steps.length} steps · ~$mins min',
                style: const TextStyle(
                    color: VisorTheme.textDim, fontSize: 14)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Countdown between drills. It is interface — knowing what is next — and
/// safety: two vergence drills stitched together with no gap is how
/// asthenopia is earned.
class _RestCard extends StatefulWidget {
  const _RestCard({
    super.key,
    required this.step,
    required this.next,
    required this.onDone,
  });

  final RestStep step;
  final String? next;
  final VoidCallback onDone;

  @override
  State<_RestCard> createState() => _RestCardState();
}

class _RestCardState extends State<_RestCard> {
  late int _left = widget.step.seconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _ticker?.cancel();
        widget.onDone();
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$_left',
              style: const TextStyle(
                  color: VisorTheme.text,
                  fontSize: 56,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(widget.step.cue,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: VisorTheme.text, fontSize: 16, height: 1.4)),
          if (widget.next != null) ...[
            const SizedBox(height: 18),
            Text('Next: ${widget.next}',
                style: const TextStyle(
                    color: VisorTheme.textDim, fontSize: 13)),
          ],
        ]),
      ),
    );
  }
}
```

`GameScreen` gains `onDone` and `templateId` with `null` defaults. In its
`_finish`, after `_save()` completes, call `onDone` when it is set instead of
showing its own terminal card — otherwise the routine stalls on the Gabor step.

- [ ] **Step 3: Re-express a single exercise as a one-step session**

In `ExercisesScreen`'s `onTap`, keep pushing `ExerciseRunner` with no `seconds` — the standalone picker path is unchanged. Nothing else to do; this step is a check, not an edit.

- [ ] **Step 4: Run the suite and commit**

```bash
flutter test && dart analyze
git add lib/screens/session_runner.dart lib/screens/exercises_screen.dart \
        lib/screens/game_screen.dart
git commit -m "feat(training): run a routine's steps back to back"
```

---

## Task 6: Template list and editor

**Files:**
- Create: `lib/screens/templates_screen.dart`
- Create: `lib/screens/template_editor_screen.dart`

**Interfaces:**
- Consumes: `TemplateRepo`, `Template`, `templateWarnings`, `isRunnable`, `SessionRunner`.
- Produces: `TemplatesScreen()`, `TemplateEditorScreen({Template? template})`.

- [ ] **Step 1: Build the list screen**

Follow the card style already used in `ExercisesScreen`: `Material` +
`InkWell` + `VisorTheme.surface`, radius 14. The row body:

```dart
  Widget _row(Template t) {
    final runnable = isRunnable(t.steps);
    final mins = (t.totalSeconds / 60).round();
    return Material(
      color: VisorTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // Review Focus 1: a routine with nothing but rest has nothing to run.
        onTap: runnable
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SessionRunner(template: t)),
                ).then((_) => _load())
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.name,
                      style: const TextStyle(
                          color: VisorTheme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    runnable
                        ? '${t.steps.length} steps · ~$mins min'
                        : 'Add an exercise to run this routine',
                    style: TextStyle(
                        color: runnable
                            ? VisorTheme.textDim
                            : VisorTheme.accent,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: VisorTheme.textDim, size: 20),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TemplateEditorScreen(template: t)),
              ).then((_) => _load()),
            ),
            Icon(Icons.play_circle_outline,
                color: runnable
                    ? VisorTheme.primary
                    : VisorTheme.textDim.withValues(alpha: 0.4),
                size: 26),
          ]),
        ),
      ),
    );
  }
```

`_load()` calls `repo.seedPresets()` then `repo.all()`. A `FloatingActionButton`
opens `TemplateEditorScreen(template: null)` for a new routine. A `builtin`
template offers Duplicate in place of Delete — long-press opens that menu.

- [ ] **Step 2: Build the editor**

State is a mutable working copy, `List<TrainingStep> _steps`, plus a name
controller. The body:

```dart
  static const _durations = [15, 30, 45, 60, 90, 120, 180];

  void _bumpDuration(int i, int delta) {
    final cur = _durations.indexOf(_steps[i].seconds);
    final next = (cur < 0 ? 3 : cur + delta).clamp(0, _durations.length - 1);
    setState(() => _steps[i] = _withSeconds(_steps[i], _durations[next]));
  }

  TrainingStep _withSeconds(TrainingStep s, int seconds) => switch (s) {
        ExerciseStep(:final type, :final gaborTarget) => ExerciseStep(
            type: type, seconds: seconds, gaborTarget: gaborTarget),
        GaborGameStep(:final difficulty, :final curved) => GaborGameStep(
            difficulty: difficulty, seconds: seconds, curved: curved),
        RestStep(:final cue) => RestStep(cue: cue, seconds: seconds),
        DrillStep(:final task) => DrillStep(task: task, seconds: seconds),
      };

  @override
  Widget build(BuildContext context) {
    final warnings = templateWarnings(_steps);
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: TextField(controller: _name, decoration: null),
        actions: [
          // Never disabled by warnings: they describe load, and the user is
          // allowed to disagree.
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _steps.length,
            onReorder: (from, to) => setState(() {
              if (to > from) to -= 1;
              _steps.insert(to, _steps.removeAt(from));
            }),
            itemBuilder: (ctx, i) => _stepTile(i, key: ValueKey(i)),
          ),
        ),
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(children: [
              const Icon(Icons.info_outline,
                  color: VisorTheme.accent, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(w,
                    style: const TextStyle(
                        color: VisorTheme.accent, fontSize: 11, height: 1.3)),
              ),
            ]),
          ),
        const SizedBox(height: 8),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: _addStepSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
```

`_stepTile(i)` shows `_steps[i].title`, a `-` / `m:ss` / `+` stepper wired to
`_bumpDuration`, and a remove button. `_addStepSheet` is a bottom sheet listing
the eight `ExerciseType` values, "Gabor Game" and "Rest", each appending a step
with a 60 s default (15 s for rest). `_save` builds a `Template` from
`_name.text` and `_steps`, calls `repo.save`, then pops.

- [ ] **Step 3: Wire the menu entry**

In `dashboard_screen.dart`, add above "Eye Exercises":

```dart
              _menuButton(
                icon: Icons.checklist,
                title: 'Routines',
                subtitle: 'Run several exercises back to back',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TemplatesScreen()),
                ).then((_) => _load()),
              ),
```

- [ ] **Step 4: Verify and commit**

Run: `flutter test && dart analyze`, then exercise the flow in the app: create a routine, reorder it, save, run it end to end.

```bash
git add lib/screens/templates_screen.dart \
        lib/screens/template_editor_screen.dart lib/screens/dashboard_screen.dart
git commit -m "feat(training): routine list and step editor"
```

---

## Task 7: Today card and the week screen

**Files:**
- Create: `lib/widgets/today_card.dart`
- Create: `lib/screens/week_plan_screen.dart`
- Modify: `lib/screens/dashboard_screen.dart`

**Interfaces:**
- Consumes: `TemplateRepo.forWeekday`, `SessionRunner`.
- Produces: `TodayCard({required VoidCallback onChanged})`, `WeekPlanScreen()`.

- [ ] **Step 1: Build the Today card**

Sits directly under `_statsRow()` in the dashboard. It loads
`repo.forWeekday(DateTime.now().weekday)` in `initState`:

```dart
  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 92);
    final t = _today;
    final weekday = _weekdayName(DateTime.now().weekday);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VisorTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: VisorTheme.primary.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(weekday.toUpperCase(),
                  style: const TextStyle(
                      color: VisorTheme.textDim,
                      fontSize: 11,
                      letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Text(t?.name ?? 'No routine for $weekday',
                  style: const TextStyle(
                      color: VisorTheme.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              if (t != null) ...[
                const SizedBox(height: 3),
                Text('${t.steps.length} steps · ~${(t.totalSeconds / 60).round()} min',
                    style: const TextStyle(
                        color: VisorTheme.textDim, fontSize: 12)),
              ],
            ],
          ),
        ),
        if (t != null && isRunnable(t.steps))
          FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SessionRunner(template: t)),
            ).then((_) => widget.onChanged()),
            child: const Text('Start'),
          )
        else
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WeekPlanScreen()),
            ).then((_) => _load()),
            child: const Text('Plan week'),
          ),
      ]),
    );
  }
```

Everything else on the dashboard stays exactly as it is. That is what keeps the
plan a suggestion: any training is still one tap away, and the streak does not
care which routine ran.

- [ ] **Step 2: Build the week screen**

```dart
  Widget _row(int weekday) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
            width: 108,
            child: Text(_weekdayName(weekday),
                style: const TextStyle(
                    color: VisorTheme.text, fontSize: 14)),
          ),
          Expanded(
            child: DropdownButton<int?>(
              isExpanded: true,
              dropdownColor: VisorTheme.surfaceAlt,
              value: _plan[weekday],
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('Rest day')),
                for (final t in _templates)
                  DropdownMenuItem<int?>(value: t.id, child: Text(t.name)),
              ],
              onChanged: (id) async {
                await _repo.setWeekday(weekday, id);
                await _publishLabels();   // Task 8
                await _load();
              },
            ),
          ),
        ]),
      );
```

The body is `for (var d = 1; d <= 7; d++) _row(d)` — Monday first, ISO order,
matching `DateTime.weekday`. `_publishLabels` is a no-op until Task 8; wire the
call now so the two tasks do not have to touch this file twice.

- [ ] **Step 3: Verify and commit**

```bash
flutter test && dart analyze
git add lib/widgets/today_card.dart lib/screens/week_plan_screen.dart \
        lib/screens/dashboard_screen.dart
git commit -m "feat(training): today card and weekly plan"
```

---

## Task 8: The reminder names the day's routine

**Files:**
- Modify: `lib/core/reminder/reminder_service.dart`
- Modify: `android/app/src/main/kotlin/com/visor/app/ReminderStore.kt`
- Modify: `android/app/src/main/kotlin/com/visor/app/ReminderReceiver.kt:44-51`

**Interfaces:**
- Consumes: `TemplateRepo.weekPlan`, `TemplateRepo.all`.
- Produces: `Future<List<String?>> weekLabels(TemplateRepo)` in `template_repo.dart`; `ReminderService.publishWeekLabels(List<String?> sevenLabels)`.

- [ ] **Step 1: Write the failing test for the label list**

Half the bug surface is Dart-side: seven entries, Monday first, gaps preserved.
The other half is the Kotlin weekday arithmetic, checked by hand in Step 5.
Add to `test/template_repo_test.dart`:

```dart
  test('week labels are seven entries, Monday first, with gaps kept', () async {
    await repo.seedPresets();
    final all = await repo.all();
    await repo.setWeekday(DateTime.monday, all[0].id);
    await repo.setWeekday(DateTime.friday, all[1].id);

    final labels = await weekLabels(repo);

    expect(labels, hasLength(7));
    expect(labels[0], contains(all[0].name));   // Monday
    expect(labels[4], contains(all[1].name));   // Friday
    expect(labels[1], isNull);                  // Tuesday: rest day
    expect(labels[6], isNull);                  // Sunday
    expect(labels[0], contains('min'));
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/template_repo_test.dart`
Expected: FAIL — `Method not found: 'weekLabels'`.

- [ ] **Step 3: Build the label list**

Append to `lib/core/training/template_repo.dart`:

```dart
/// One label per ISO weekday, index 0 = Monday, null where the day has no
/// routine. Always seven entries: the native side indexes into it directly.
Future<List<String?>> weekLabels(TemplateRepo repo) async {
  final plan = await repo.weekPlan();
  final byId = {for (final t in await repo.all()) t.id: t};
  return [
    for (var d = 1; d <= 7; d++)
      switch (byId[plan[d]]) {
        null => null,
        final t => '${t.name}, ${(t.totalSeconds / 60).round()} min',
      },
  ];
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/template_repo_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Publish seven labels from Dart**

In `reminder_service.dart`:

```dart
  /// Push one label per ISO weekday (index 0 = Monday) to the native side.
  ///
  /// Seven labels, not one: the alarm can fire days after the app last ran, so
  /// a single stored "today" string would name the wrong routine. The receiver
  /// picks by the weekday at fire time.
  static Future<void> publishWeekLabels(List<String?> labels) async {
    assert(labels.length == 7);
    await _channel.invokeMethod<void>('setWeekLabels', {
      'labels': labels.map((l) => l ?? '').toList(),
    });
  }
```

Fill in `_publishLabels` in `WeekPlanScreen` (stubbed in Task 7) and call the
same helper from `TemplateEditorScreen` after a save — renaming a routine or
changing its length must update the notification text too:

```dart
  Future<void> _publishLabels() async =>
      ReminderService.publishWeekLabels(await weekLabels(_repo));
```

- [ ] **Step 6: Store them natively**

In `ReminderStore.kt`:

```kotlin
  private const val KEY_WEEK_LABELS = "week_labels"

  /** Seven labels, Monday first, joined by \n. Empty entry = no routine. */
  fun setWeekLabels(context: Context, labels: List<String>) {
    prefs(context).edit()
      .putString(KEY_WEEK_LABELS, labels.joinToString("\n"))
      .apply()
  }

  /** Label for [isoWeekday] (1 = Monday), or null when none is set. */
  fun labelFor(context: Context, isoWeekday: Int): String? {
    val raw = prefs(context).getString(KEY_WEEK_LABELS, null) ?: return null
    val parts = raw.split("\n")
    if (parts.size != 7) return null
    return parts[isoWeekday - 1].ifBlank { null }
  }
```

- [ ] **Step 7: Use the current weekday at fire time**

Replace `handleReminder` in `ReminderReceiver.kt`:

```kotlin
  private fun handleReminder(context: Context) {
    if (ReminderStore.trainedToday(context)) return
    // Resolved now, not when the alarm was scheduled: the app may not have run
    // for days, so anything stored as "today's routine" would be stale.
    val cal = Calendar.getInstance()
    val iso = ((cal.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1  // Sun=1 → Mon=1
    val label = ReminderStore.labelFor(context, iso)
    showNotification(
      context,
      "Keep your streak alive",
      if (label != null) "Today: $label"
      else "You haven't trained today — 1 minute keeps your streak going.",
    )
  }
```

Add `setWeekLabels` to the `visor/reminder` method channel in `MainActivity.kt`, forwarding to `ReminderStore.setWeekLabels`.

- [ ] **Step 8: Verify the weekday mapping by hand**

`Calendar.DAY_OF_WEEK` is `Sunday = 1 … Saturday = 7`; `((dow + 5) % 7) + 1` maps that to ISO `Monday = 1 … Sunday = 7`. Check both ends: Sunday `((1+5)%7)+1 = 7`; Monday `((2+5)%7)+1 = 1`. Then set a routine for today, use the in-app test notification, and confirm the text names it.

- [ ] **Step 9: Build and commit**

```bash
flutter test && dart analyze && flutter build apk --debug
git add lib/core/reminder/reminder_service.dart lib/core/training/template_repo.dart \
        lib/screens/week_plan_screen.dart lib/screens/template_editor_screen.dart \
        test/template_repo_test.dart android/app/src/main/kotlin
git commit -m "feat(reminder): name the day's routine in the daily notification"
```

---

## Notes for the executor

- Do not install on the physical device without asking first. Building is fine.
- `flutter test` must be green and `dart analyze` clean before each commit.
- The golden at `test/goldens/accuracy_chart.png` is a real gate. If a change to
  `Drill` alters the chart, regenerate it with `--update-goldens` and **look at
  the image** before committing it.
