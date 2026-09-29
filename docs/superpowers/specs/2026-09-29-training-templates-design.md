# Training templates and the weekly plan — design

**Date:** 2026-09-29
**Status:** proposed, awaiting review
**Scope:** running several exercises back to back as a saved routine, and
assigning routines to weekdays.

**Relationship to other specs:** independent of
`2026-09-29-psychophysical-engine-design.md` and shippable before it. The two
share one schema migration (v4) so users upgrade once, and the step model has a
branch reserved for that spec's measured drills.

---

## 1. Intent

Starting one exercise today costs six actions: dashboard → Eye Exercises →
scroll → tap → duration picker → Start. Doing a five-exercise routine costs it
five times over, with a return to the list between each. The list is a menu, not
a programme: it answers "what exists", never "what should I do now".

This design adds a **template** — an ordered list of steps with durations, run
back to back from one tap — and a **weekly plan** that says which template
belongs to which weekday.

### Success criteria

1. Running a saved routine is one tap from the dashboard.
2. A routine runs end to end without returning to any list.
3. Every completed step is recorded and counts toward the streak exactly as a
   single session does today.
4. Adding a measured drill (per the psychophysical engine spec) as a routine
   step requires no schema migration.

### Non-goals

- Prescriptive scheduling. The weekly plan is a **suggestion**: the dashboard
  and the reminder name the day's routine, but any training counts and the
  streak is indifferent to which routine ran. Missing Monday's plan while still
  training must never be punished.
- Auto-generated periodization from measured thresholds. That belongs with the
  psychophysical engine once thresholds exist; the model here does not block it.
- Sharing or importing routines.

---

## 2. Model

A step is deliberately **not** `(ExerciseType, seconds)`. That shape cannot hold
the Gabor game — which is the app's core and has no reason to be excluded from a
routine — and it cannot hold a measured drill later.

```dart
sealed class TrainingStep {
  int get seconds;
}

class ExerciseStep extends TrainingStep {
  final ExerciseType type;
}

class GaborGameStep extends TrainingStep {
  final Difficulty difficulty;
  final bool curved;
}

class RestStep extends TrainingStep {
  final String cue; // "blink and relax — saccades next"
}

class DrillStep extends TrainingStep {
  final String task; // psychophysical engine; not rendered until it exists
}

class Template {
  final int id;
  final String name;
  final bool builtin;
  final List<TrainingStep> steps;

  int get totalSeconds => steps.fold(0, (a, s) => a + s.seconds);
}
```

### Load categories

`ExerciseType` gains a category. It costs one getter and gives the editor
something to reason about:

| Category | Exercises |
|---|---|
| vergence | `convergence` |
| accommodation | `nearFar` |
| saccadic | `saccadic`, `focusShift` |
| pursuit | `pursuit`, `figure8` |
| peripheral | `peripheral` |
| relax | `orbs` |

The editor **warns, never blocks**, on two consecutive steps of the same
category, and on vergence work with no rest after it. A chain of five arbitrary
animations is just a longer animation; real vision-therapy protocols have a
shape — warm-up, main work, relax — and the category is the cheapest way to give
a template one without pretending to prescribe.

### Seeded presets

A template list that opens empty teaches nothing. Four presets ship as
`builtin = 1`: they can be run, copied and edited, but not deleted.

| Name | Steps |
|---|---|
| Screen break · 3 min | nearFar 60 → focusShift 45 → peripheral 45 → rest 30 |
| Morning · 6 min | convergence 60 → rest 15 → pursuit 60 → figure8 60 → saccadic 45 → orbs 60 |
| Wind down · 4 min | orbs 90 → nearFar 90 → rest 60 |
| Sharpen · 8 min | gabor(medium, 180) → saccadic 60 → focusShift 60 → orbs 60 |

---

## 3. The sequential runner

### What exists

`ExerciseRunner` (`lib/screens/exercises_screen.dart`) is a three-state machine
— duration picker → running → finished — pushed onto the navigator per
exercise. Its `AnimationController` is built in `initState` from `_loopMs`,
which depends on the type (`nearFar` runs a 16 s accommodation loop, everything
else 8 s). A single instance therefore cannot switch types: the controller's
duration is fixed at construction, and the decoded Gabor images belong to the
type that requested them.

### Structure

```
SessionRunner(steps)                       // holds the index and the totals
  └─ ExerciseStage(step, key: ValueKey(i), onDone: _next)
```

`ValueKey(stepIndex)` makes Flutter discard the old `State` and build a fresh
one at every step — new controller, freshly decoded patches, `dispose` called on
the way out. This is the idiomatic answer and it means the runner's internals
are not rewritten, only its edges.

### Changes to `ExerciseRunner`

- The internal duration picker is removed; the step supplies the duration.
- It gains `autoStart` and `onDone`.
- The terminal finish card moves up into `SessionRunner`.
- **A single exercise becomes a one-step session.** No duplicated path; the
  duration picker returns as "quick run" — a one-step template built in memory
  from the existing `[30, 60, 120]` choices and never written to `templates`.

### Session chrome

Top bar during a session: `3/6 · Smooth Pursuit`, the step's remaining time and
the session's remaining time, plus skip and quit.

Quitting mid-session records only the steps that completed. There is **no
session row**: a routine is a grouping of `drills` rows sharing a `template_id`
and a date, so "incomplete" is implicit — fewer step rows than the template has
steps — and computed where it is displayed rather than stored. That keeps the
streak query untouched and means a partly-finished routine still counts as
training, which is the intent.

A `RestStep` renders a countdown card naming what comes next. It is both
interface — knowing what is coming — and safety: two vergence drills stitched
together with no gap is how asthenopia is earned.

---

## 4. Data

Folded into the **same v4 migration** as the psychophysical engine's `drills`
table, so the user upgrades once.

```sql
CREATE TABLE templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  builtin INTEGER NOT NULL,      -- seeded preset: copyable, not deletable
  position INTEGER NOT NULL,     -- user ordering
  created_at INTEGER NOT NULL
);

CREATE TABLE template_steps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  template_id INTEGER NOT NULL REFERENCES templates(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  kind TEXT NOT NULL,            -- 'exercise' | 'gabor' | 'rest' | 'drill'
  seconds INTEGER NOT NULL,
  params TEXT                    -- JSON: {"type":"pursuit"} | {"difficulty":"hard","curved":false} | {"cue":"blink"}
);

CREATE INDEX idx_steps_template ON template_steps(template_id, position);

CREATE TABLE week_plan (
  weekday INTEGER PRIMARY KEY CHECK (weekday BETWEEN 1 AND 7),  -- ISO, Mon = 1
  template_id INTEGER REFERENCES templates(id) ON DELETE SET NULL
);
```

Three details that are easy to miss:

- **`ON DELETE SET NULL` on `week_plan`.** Deleting a template must not silently
  erase the weekday; the day becomes "no plan" and says so.
- **sqflite does not enable foreign keys.** `PRAGMA foreign_keys = ON` has to be
  issued in `onConfigure`; the current `VisionDb._open()` has no `onConfigure` at
  all, so without it both `ON DELETE` clauses are decoration.
- **Results are recorded per step, not per session.** Each completed step writes
  one `drills` row, and `drills` gains a nullable `template_id` column in the
  same migration. The Gabor step then keeps its weighted `score`, a future
  measured drill keeps its `threshold`, the streak query is unchanged, and
  analytics can count completions of a named routine. `RestStep` writes nothing
  — it is not training.

---

## 5. Interface

- **Dashboard "Today" card, above the existing menu.** The day's routine name,
  its total time, one Start button. With no plan for that weekday the card says
  so and links to the week screen. Everything else on the dashboard stays: any
  training can still be started directly, and the streak counts it. That is what
  makes the plan a suggestion rather than a prescription.
- **Routines** — a new menu entry: the template list, run on tap, edit on long
  press or a trailing button.
- **Editor** — a `ReorderableListView` of steps, a duration stepper per step, an
  add-step bottom sheet. Category warnings appear as a line under the list, not
  as a modal.
- **Week** — seven rows, each a dropdown over the templates plus "rest day".

`ExercisesScreen` is untouched and remains the way to run a single exercise
without a template.

---

## 6. Reminders

The notification text is hardcoded natively at `ReminderReceiver.kt:49`
("You haven't trained today — 1 minute keeps your streak going."), and
`ReminderStore` already carries values from Dart into `SharedPreferences` — the
`mark_trained` marker the receiver reads at fire time. The path is established.

**The trap:** writing "today's plan" as a single string is wrong. The alarm
fires while the app may have been dead for days, so that string would be stale
and the notification would name the wrong routine. Dart must write **all seven
weekday labels**, and `ReminderReceiver` picks by the current weekday at the
moment it fires.

The reminder then says "Monday: Morning, 6 min" instead of "train today" — the
cheapest worthwhile upgrade available to the reminder in this app. When the
weekday has no plan, the existing generic copy is used unchanged.

---

## 7. Safety

1. Category warnings in the editor (§2) — advisory, never blocking.
2. A rest step between heavy steps, surfaced by the same warnings.
3. A cap on total session length, consistent with the per-category vergence cap
   in the psychophysical engine spec once that lands.
4. Quitting mid-session is always available and never penalised: each completed
   step is its own `drills` row, so the streak closes the day on the first step
   that ran to the end and lasted at least 30 s — the same rule as any other
   drill.

---

## 8. Order of work

1. Model + category getter, with the editor's warning rules as pure tested
   functions.
2. Schema v4 (templates, steps, week plan, `drills.template_id`,
   `PRAGMA foreign_keys`), plus preset seeding.
3. `SessionRunner` and the `ExerciseRunner` edge changes; single exercise
   re-expressed as a one-step session.
4. Template list and editor.
5. Dashboard "Today" card and the week screen.
6. Reminder labels through `SharedPreferences` and the receiver's weekday
   lookup.
