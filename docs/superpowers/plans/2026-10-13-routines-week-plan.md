# Routines & Weekly Plan Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the unreachable weekly plan and add generate / delete-defaults / reorder / new-at-top / session-timer improvements to routines.

**Architecture:** Repository-level logic in `TemplateRepo` and `VisionDb` (a backward-compatible v4→v5 migration adds a `meta` table), screen-level UI in `dashboard_screen.dart`, `week_plan_screen.dart`, `templates_screen.dart`, and `session_runner.dart`. Pure helpers (`generatedWeekPlan`, `sessionProgress`) are extracted so the cycling and progress math are unit-testable without a widget or a database.

**Tech Stack:** Flutter `^3.13.0`, `sqflite ^2.3.3+1`, `sqflite_common_ffi ^2.3.3` (tests), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-13-routines-week-plan-design.md`

## Global Constraints

- Flutter `^3.13.0`; `sqflite ^2.3.3+1`; tests use `sqflite_common_ffi`.
- The database is version 4; the only schema change is a backward-compatible `v4 → v5` migration that adds a `meta` table. Existing user data must survive.
- Screens use the real `VisionDb.instance` singleton. Widget tests set `databaseFactory = databaseFactoryFfi` and run every disk-I/O interaction inside `tester.runAsync`, polling (bounded) for the `CircularProgressIndicator` to clear instead of `pumpAndSettle` (the indeterminate spinner never settles).
- `TemplateRepo.all()` orders by `position, id`; positions are 0-based and contiguous.
- `week_plan.template_id` is `ON DELETE SET NULL` (foreign keys are ON).

## Review Focus

1. **Deleted-default resurrection** — deleting all four builtins then re-running `seedPresets` must leave zero builtins. Pinned in Task 2.
2. **Generate with zero routines** — `applyGeneratedWeekPlan` with an empty routine list returns `false` and leaves the existing plan untouched. Pinned in Task 5.
3. **Plan row referencing a deleted routine** — deleting a routine assigned to a weekday nulls that weekday (FK) and `WeekPlanScreen` still renders (its dropdown `value` is always one of its items). Pinned in Task 2.
4. **New-at-top + reorder stay contiguous** — after reordering, a newly created routine lands at `position 0` and the rest keep their relative order. Pinned in Task 3 and Task 4.
5. **Big number before the first tick** — at session start (before the first `onSecondsLeft`), the focal number shows the current step's full duration, never blank. Pinned in Task 6.

---

### Task 1: Persistent entry to the Weekly plan (bug fix)

**Files:**
- Modify: `lib/screens/dashboard_screen.dart`
- Test: `test/dashboard_screen_test.dart` (create)

**Interfaces:**
- Consumes: `WeekPlanScreen` (`lib/screens/week_plan_screen.dart`), `VisionDb.instance`.
- Produces: a "Weekly plan" menu button in the dashboard that pushes `WeekPlanScreen`.

- [ ] **Step 1: Write the failing test**

Create `test/dashboard_screen_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:visor/core/db/vision_db.dart';
import 'package:visor/screens/dashboard_screen.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = p.join(await databaseFactoryFfi.getDatabasesPath(), 'visor.db');
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  });

  testWidgets('the dashboard offers a Weekly plan entry that opens the plan',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
      for (var i = 0;
          i < 40 &&
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    expect(find.text('Weekly plan'), findsOneWidget);

    await tester.tap(find.text('Weekly plan'));
    await tester.runAsync(() async {
      await tester.pumpAndSettle();
      for (var i = 0;
          i < 40 &&
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    // 'Monday' only exists on the plan screen, so it proves the push happened.
    expect(find.text('Monday'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/dashboard_screen_test.dart`
Expected: FAIL — `find.text('Weekly plan')` finds nothing (no such button yet).

- [ ] **Step 3: Add the "Weekly plan" menu button**

In `dashboard_screen.dart`, after the "Routines" `_menuButton(...)` block (the one that pushes `TemplatesScreen`), add a sibling `_menuButton` that pushes `WeekPlanScreen`. Import `week_plan_screen.dart`. The button:

```dart
_menuButton(
  icon: Icons.calendar_month,
  title: 'Weekly plan',
  subtitle: 'Assign a routine to each weekday',
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const WeekPlanScreen()),
  ).then((_) => _load()),
),
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/dashboard_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/dashboard_screen.dart test/dashboard_screen_test.dart
git commit -m "fix: add a persistent Weekly plan entry to the dashboard"
```

---

### Task 2: Delete default routines + re-seed flag (v5 migration)

**Files:**
- Modify: `lib/core/db/vision_db.dart`
- Modify: `lib/core/training/template_repo.dart`
- Modify: `lib/screens/templates_screen.dart`
- Test: `test/template_repo_test.dart`
- Test: `test/migration_v5_test.dart` (create)
- Test: `test/templates_and_editor_screen_test.dart`

**Interfaces:**
- Produces: a `meta(key TEXT PRIMARY KEY, value INTEGER NOT NULL)` table; `VisionDb.createV5ForTest(Database)`; `TemplateRepo.delete` that deletes builtins; `TemplateRepo.seedPresets` that seeds once via the `presets_seeded` flag.

- [ ] **Step 1: Write the failing tests**

(a) In `test/template_repo_test.dart`, change the database setup from `version: 4` / `createV4ForTest` to `version: 5` / `VisionDb.createV5ForTest`. Replace the existing test `deleting a builtin template is refused, but a user template deletes normally` with two tests:

```dart
test('deleting a builtin template now removes it', () async {
  await repo.seedPresets();
  final builtin = (await repo.all()).firstWhere((t) => t.builtin);
  await repo.delete(builtin.id);
  expect((await repo.all()).map((t) => t.id), isNot(contains(builtin.id)));
});

test('deleting all builtins keeps them deleted across a re-seed', () async {
  await repo.seedPresets();
  for (final b in (await repo.all()).where((t) => t.builtin).toList()) {
    await repo.delete(b.id);
  }
  expect((await repo.all()).where((t) => t.builtin), isEmpty);
  await repo.seedPresets(); // must not resurrect the deleted defaults
  expect((await repo.all()).where((t) => t.builtin), isEmpty);
});
```

(b) Create `test/migration_v5_test.dart`:

```dart
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
```

(c) In `test/templates_and_editor_screen_test.dart`, add `await db.delete('meta');` to the `setUp` body (so each test starts with no seed flag). Add a test that a builtin's action sheet offers Delete:

```dart
testWidgets('a builtin routine offers Delete in its action sheet',
    (tester) async {
  await tester.runAsync(() async {
    await TemplateRepo(await VisionDb.instance.db).seedPresets();
    await tester.pumpWidget(const MaterialApp(home: TemplatesScreen()));
    for (var i = 0;
        i < 40 &&
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  });
  await tester.longPress(find.text('Screen break'));
  await tester.pumpAndSettle();
  expect(find.text('Delete'), findsOneWidget);
  expect(find.text('Duplicate'), findsOneWidget);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/template_repo_test.dart test/migration_v5_test.dart test/templates_and_editor_screen_test.dart`
Expected: FAIL — `createV5ForTest` undefined; `delete` still refuses builtins; no `meta` table; action sheet has no Delete for a builtin.

- [ ] **Step 3: Implement the v5 schema in `vision_db.dart`**

- Bump the `openDatabase` `version:` from `4` to `5`.
- Add a `_createV5(Database d)` that calls `_createV4(d)` then creates the `meta` table:
  ```dart
  static Future<void> _createV5(Database d) async {
    await _createV4(d);
    await d.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value INTEGER NOT NULL
      )
    ''');
  }
  ```
- Change `onCreate` to call `_createV5(d)` (instead of `_createV4(d)`) before the `reminder` table.
- Add a `createV5ForTest` static that returns `_createV5(d)` (keep `createV4ForTest` for the v3→v4 migration test).
- In `migrate`, add:
  ```dart
  if (oldV < 5) {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value INTEGER NOT NULL
      )
    ''');
    final hasBuiltin = Sqflite.firstIntValue(
            await d.rawQuery('SELECT COUNT(*) FROM templates WHERE builtin = 1')) ??
        0;
    if (hasBuiltin > 0) {
      await d.insert('meta', {'key': 'presets_seeded', 'value': 1},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
  ```

- [ ] **Step 4: Implement the repo changes in `template_repo.dart`**

- `delete`: remove the `AND builtin = 0` guard so it is `where: 'id = ?', whereArgs: [id]`.
- `seedPresets`: replace the count-of-builtins guard with the flag:
  ```dart
  Future<void> seedPresets() async {
    final seeded = Sqflite.firstIntValue(await _db
            .rawQuery("SELECT value FROM meta WHERE key = 'presets_seeded'")) ??
        0;
    if (seeded == 1) return;
    for (final t in _presets) {
      await save(t);
    }
    await _db.insert('meta', {'key': 'presets_seeded', 'value': 1},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  ```

- [ ] **Step 5: Offer Delete for builtins in `templates_screen.dart`**

In `_showActionSheet`, replace the `if (t.builtin) Duplicate else Delete` branch so a builtin offers **both** "Duplicate" and "Delete" (keep the existing Duplicate tile, and add the existing Delete tile after it). User routines keep "Delete" only.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/template_repo_test.dart test/migration_v5_test.dart test/templates_and_editor_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/core/db/vision_db.dart lib/core/training/template_repo.dart lib/screens/templates_screen.dart test/template_repo_test.dart test/migration_v5_test.dart test/templates_and_editor_screen_test.dart
git commit -m "feat: allow deleting default routines without re-seeding (v5 meta flag)"
```

---

### Task 3: New routines at the top

**Files:**
- Modify: `lib/core/training/template_repo.dart`
- Test: `test/template_repo_test.dart`

**Interfaces:**
- Consumes: `TemplateRepo.save` (existing).
- Produces: `Future<int> TemplateRepo.save(Template t, {bool newAtTop = true})`.

- [ ] **Step 1: Write the failing tests**

Add to `test/template_repo_test.dart`:

```dart
test('a new routine is inserted at the top of the list', () async {
  await repo.save(t('A', [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  await repo.save(t('B', [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  expect((await repo.all()).map((x) => x.name), ['B', 'A']);
});

test('presets keep their intended top-to-bottom order', () async {
  await repo.seedPresets();
  expect((await repo.all()).map((x) => x.name),
      ['Screen break', 'Morning', 'Wind down', 'Sharpen']);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/template_repo_test.dart --plain-name "a new routine is inserted at the top of the list"`
Expected: FAIL — the new routine is at the bottom (`['A', 'B']`).

- [ ] **Step 3: Implement `newAtTop` in `save`**

Change `save`'s signature to `Future<int> save(Template t, {bool newAtTop = true})`. In the `id == 0` branch:

```dart
if (id == 0) {
  if (newAtTop) {
    await txn.rawUpdate('UPDATE templates SET position = position + 1');
    id = await txn.insert('templates', {
      'name': t.name,
      'builtin': t.builtin ? 1 : 0,
      'position': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  } else {
    final maxPos = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT MAX(position) FROM templates')) ??
        0;
    id = await txn.insert('templates', {
      'name': t.name,
      'builtin': t.builtin ? 1 : 0,
      'position': maxPos + 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
```

Update `seedPresets` to call `await save(t, newAtTop: false);` so the four presets append in their intended order.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/template_repo_test.dart`
Expected: PASS (including the two new tests and the existing round-trip/seed tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/training/template_repo.dart test/template_repo_test.dart
git commit -m "feat: insert new routines at the top of the list"
```

---

### Task 4: Reorder routines

**Files:**
- Modify: `lib/core/training/template_repo.dart`
- Modify: `lib/screens/templates_screen.dart`
- Test: `test/template_repo_test.dart`
- Test: `test/templates_and_editor_screen_test.dart`

**Interfaces:**
- Consumes: `TemplateRepo.all()` (ordered by position).
- Produces: `Future<void> TemplateRepo.reorder(List<int> orderedIds)`.

- [ ] **Step 1: Write the failing tests**

(a) Unit, in `test/template_repo_test.dart`:

```dart
test('reorder rewrites positions in the given order', () async {
  final a = await repo.save(t('A', [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  final b = await repo.save(t('B', [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  final c = await repo.save(t('C', [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  // After three new-at-top saves the list is C, B, A.
  await repo.reorder([a, c, b]);
  expect((await repo.all()).map((x) => x.id), [a, c, b]);
});
```

(b) Widget, in `test/templates_and_editor_screen_test.dart`:

```dart
testWidgets('dragging a routine reorders the list and persists it',
    (tester) async {
  await tester.runAsync(() async {
    final repo = TemplateRepo(await VisionDb.instance.db);
    await repo.save(Template(id: 0, name: 'First', builtin: false,
        steps: [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
    await repo.save(Template(id: 0, name: 'Second', builtin: false,
        steps: [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  });
  await tester.runAsync(() async {
    await tester.pumpWidget(const MaterialApp(home: TemplatesScreen()));
    for (var i = 0;
        i < 40 &&
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  });
  // The list is Second (top), First. Drag the top row's handle below First.
  final start = tester.getCenter(find.byType(ReorderableDragStartListener).first);
  final target = tester.getCenter(find.text('First'));
  final drag = await tester.startGesture(start);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  await drag.moveTo(target + (target - start));
  await tester.pump();
  await drag.up();
  await tester.runAsync(() async {
    await tester.pumpAndSettle();
    for (var i = 0;
        i < 40 &&
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
    final all = await TemplateRepo(await VisionDb.instance.db).all();
    expect(all.map((x) => x.name), ['First', 'Second']);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/template_repo_test.dart --plain-name "reorder rewrites positions"`
Expected: FAIL — `reorder` is not a method on `TemplateRepo`.

- [ ] **Step 3: Implement `reorder` in `template_repo.dart`**

```dart
Future<void> reorder(List<int> orderedIds) async {
  await _db.transaction((txn) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await txn.update('templates', {'position': i},
          where: 'id = ?', whereArgs: [orderedIds[i]]);
    }
  });
}
```

- [ ] **Step 4: Make the list reorderable in `templates_screen.dart`**

- Replace the `ListView.separated(...)` body with a `ReorderableListView.builder` keyed by template id:
  ```dart
  ReorderableListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: _templates.length,
    onReorderItem: (from, to) => _reorder(from, to),
    itemBuilder: (ctx, i) => Padding(
      key: ValueKey(_templates[i].id),
      padding: const EdgeInsets.only(bottom: 10),
      child: _row(_templates[i], i),
    ),
  )
  ```
- Add the handler:
  ```dart
  Future<void> _reorder(int from, int to) async {
    final next = List.of(_templates);
    next.insert(to, next.removeAt(from));
    setState(() => _templates = next);
    final repo = _repo;
    if (repo == null) return;
    await repo.reorder(next.map((t) => t.id).toList());
    await _load();
  }
  ```
- Change `_row(Template t)` to `_row(Template t, int index)` and add a drag handle as the first child of the row, wrapped so only it starts the drag:
  ```dart
  ReorderableDragStartListener(
    itemIndex: index,
    child: const Padding(
      padding: EdgeInsets.all(4),
      child: Icon(Icons.drag_handle, color: VisorTheme.textDim, size: 20),
    ),
  ),
  ```
  Keep the row's `onTap` (start) and `onLongPress` (action sheet) as they are.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/template_repo_test.dart test/templates_and_editor_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/training/template_repo.dart lib/screens/templates_screen.dart test/template_repo_test.dart test/templates_and_editor_screen_test.dart
git commit -m "feat: reorder routines by dragging"
```

---

### Task 5: "Generate plan" button

**Files:**
- Modify: `lib/core/training/template_repo.dart`
- Modify: `lib/screens/week_plan_screen.dart`
- Test: `test/template_repo_test.dart`
- Test: `test/templates_and_editor_screen_test.dart`

**Interfaces:**
- Consumes: `TemplateRepo.all()`, `TemplateRepo.setWeekday`.
- Produces: top-level `Map<int, int?> generatedWeekPlan(List<Template> templates)`; `Future<bool> TemplateRepo.applyGeneratedWeekPlan()`.

- [ ] **Step 1: Write the failing tests**

(a) Unit, in `test/template_repo_test.dart`:

```dart
test('generatedWeekPlan cycles routines across all seven days', () async {
  final a = await repo.save(t('A', [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  final b = await repo.save(t('B', [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  final c = await repo.save(t('C', [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  final plan = generatedWeekPlan([
    Template(id: a, name: 'A', builtin: false, steps: const []),
    Template(id: b, name: 'B', builtin: false, steps: const []),
    Template(id: c, name: 'C', builtin: false, steps: const []),
  ]);
  expect(plan, {1: a, 2: b, 3: c, 4: a, 5: b, 6: c, 7: a});
});

test('generatedWeekPlan with no routines is all rest days', () {
  expect(generatedWeekPlan(const []),
      {1: null, 2: null, 3: null, 4: null, 5: null, 6: null, 7: null});
});

test('applyGeneratedWeekPlan fills every day from the existing routines',
    () async {
  await repo.save(t('A', [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  await repo.save(t('B', [ExerciseStep(type: ExerciseType.orbs, seconds: 30)]));
  expect(await repo.applyGeneratedWeekPlan(), isTrue);
  final plan = await repo.weekPlan();
  expect(plan.values.where((v) => v != null).length, 7);
});

test('applyGeneratedWeekPlan with no routines returns false and changes nothing',
    () async {
  await repo.setWeekday(1, 999);
  expect(await repo.applyGeneratedWeekPlan(), isFalse);
  expect((await repo.weekPlan())[1], 999);
});
```

(b) Widget, in `test/templates_and_editor_screen_test.dart`:

```dart
testWidgets('the Generate button fills all seven days', (tester) async {
  await tester.runAsync(() async {
    await TemplateRepo(await VisionDb.instance.db).seedPresets();
    await tester.pumpWidget(const MaterialApp(home: WeekPlanScreen()));
    for (var i = 0;
        i < 40 &&
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  });
  expect(find.text('Generate'), findsOneWidget);
  await tester.runAsync(() async {
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    for (var i = 0;
        i < 40 &&
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  });
  // Four presets cycle across seven days, so no day is left a rest day.
  expect(find.text('Rest day'), findsNothing);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/template_repo_test.dart --plain-name "generatedWeekPlan cycles"`
Expected: FAIL — `generatedWeekPlan` is not defined.

- [ ] **Step 3: Implement `generatedWeekPlan` and `applyGeneratedWeekPlan` in `template_repo.dart`**

Add a top-level pure function (next to `weekLabels`):

```dart
/// Assigns a routine to each of the seven weekdays, cycling through
/// [templates] in order. An empty list yields all rest days.
Map<int, int?> generatedWeekPlan(List<Template> templates) {
  if (templates.isEmpty) {
    return {for (var d = 1; d <= 7; d++) d: null};
  }
  return {
    for (var d = 1; d <= 7; d++)
      d: templates[(d - 1) % templates.length].id,
  };
}
```

Add a repo method:

```dart
/// Fills all seven weekdays from the existing routines (cycling). Returns
/// false and changes nothing when there is no routine to draw from.
Future<bool> applyGeneratedWeekPlan() async {
  final templates = await all();
  if (templates.isEmpty) return false;
  for (final e in generatedWeekPlan(templates).entries) {
    await setWeekday(e.key, e.value);
  }
  return true;
}
```

- [ ] **Step 4: Add the Generate button in `week_plan_screen.dart`**

Add it to the `AppBar` `actions`:

```dart
actions: [
  TextButton(
    onPressed: _loading ? null : _generate,
    child: const Text('Generate'),
  ),
],
```

Add the handler:

```dart
Future<void> _generate() async {
  final ok = await _repo.applyGeneratedWeekPlan();
  if (!mounted) return;
  if (ok) {
    await _publishLabels();
    await _load();
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No routines to generate from')),
    );
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/template_repo_test.dart test/templates_and_editor_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/training/template_repo.dart lib/screens/week_plan_screen.dart test/template_repo_test.dart test/templates_and_editor_screen_test.dart
git commit -m "feat: add a one-tap Generate button to the weekly plan"
```

---

### Task 6: Session timer — one big number + time progress bar

**Files:**
- Modify: `lib/screens/session_runner.dart`
- Test: `test/session_runner_test.dart`

**Interfaces:**
- Produces: top-level `double sessionProgress({required int sessionSecondsLeft, required int totalSeconds})`.

- [ ] **Step 1: Write the failing tests**

Add a unit test to `test/session_runner_test.dart` (it is a bare widget-test file; a plain `test` is fine):

```dart
test('sessionProgress is 0 at start, 1 at end, and clamped', () {
  expect(sessionProgress(sessionSecondsLeft: 12, totalSeconds: 12), 0.0);
  expect(sessionProgress(sessionSecondsLeft: 0, totalSeconds: 12), 1.0);
  expect(sessionProgress(sessionSecondsLeft: 6, totalSeconds: 12), 0.5);
  expect(sessionProgress(sessionSecondsLeft: -1, totalSeconds: 12), 1.0);
  expect(sessionProgress(sessionSecondsLeft: 0, totalSeconds: 0), 0.0);
});
```

Replace the existing test `the session remaining time counts down and recomputes on step change` with a test of the new single-number + time-bar layout:

```dart
testWidgets('the session shows one big step countdown and a time-based bar',
    (tester) async {
  final t = routine([
    ExerciseStep(type: ExerciseType.pursuit, seconds: 3),
    ExerciseStep(type: ExerciseType.saccadic, seconds: 4),
    ExerciseStep(type: ExerciseType.figure8, seconds: 5),
  ]);
  await tester.pumpWidget(MaterialApp(home: SessionRunner(template: t)));
  await tester.pump(); // autoStart: before the first tick the step shows full

  // The big focal number is the current step's full duration (3 s).
  expect(find.text('0:03'), findsOneWidget);
  // The dim session-remaining number is gone.
  expect(find.text('0:12'), findsNothing);
  // The bar is time-based: nothing elapsed yet.
  expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.0);

  // One second in: the step owes 2 s; the bar has done 1 of 12 s.
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
  expect(find.text('0:02'), findsOneWidget);
  expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
      closeTo(1 / 12, 0.001));

  // Drain the remaining steps so their tickers don't outlive the test.
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
  await tester.pump(const Duration(seconds: 5));
  await tester.pump();
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/session_runner_test.dart`
Expected: FAIL — `sessionProgress` is not defined; the big number is not `0:03`; the dim `0:12` is still shown.

- [ ] **Step 3: Implement the timer change in `session_runner.dart`**

- Add a top-level pure helper:
  ```dart
  /// Fraction of the session elapsed, from 0 (start) to 1 (done). Guards a
  /// zero-length session and clamps so a late tick can never overflow the bar.
  double sessionProgress({
    required int sessionSecondsLeft,
    required int totalSeconds,
  }) {
    if (totalSeconds <= 0) return 0;
    return (1 - sessionSecondsLeft / totalSeconds).clamp(0.0, 1.0);
  }
  ```
- Add a getter on the state: `int get _totalSessionSeconds => _steps.fold(0, (s, step) => s + step.seconds);`
- In `_progressBar`, replace the two numbers with one big number and a time-based bar:
  - The focal number (where the bold step countdown was) becomes:
    ```dart
    Text(_mmss(_stepSecondsLeft ?? _steps[_index].seconds),
        style: const TextStyle(
            color: VisorTheme.text, fontSize: 22, fontWeight: FontWeight.bold)),
    ```
  - Delete the dim session-remaining `Padding(... Text(_mmss(_sessionSecondsLeft()) ...))` block entirely.
  - Change the `LinearProgressIndicator` value from `(_index + 1) / total` to:
    ```dart
    sessionProgress(
        sessionSecondsLeft: _sessionSecondsLeft(),
        totalSeconds: _totalSessionSeconds),
    ```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/session_runner_test.dart`
Expected: PASS (all session tests, including the rewritten timer test and the new `sessionProgress` unit test).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/session_runner.dart test/session_runner_test.dart
git commit -m "feat: show one big step countdown and a time-based session bar"
```

---

## Final verification

- [ ] Run the whole suite: `flutter test`
  Expected: all tests pass.
- [ ] Run the analyzer: `flutter analyze`
  Expected: no new issues.
- [ ] Push the branch: `git push -u origin fix/routines-week-plan`.
