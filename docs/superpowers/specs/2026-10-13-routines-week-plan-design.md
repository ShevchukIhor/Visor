# Routines & Weekly Plan Improvements — Design

## Intent

The app is in active testing. The tester found one blocking bug — a weekly
plan, once set, cannot be edited again — plus a batch of quality-of-life
changes to routines and the weekly plan. This design covers all six, in one
feature area (routines + weekly plan + in-session timer).

## Goals

1. Always be able to open and edit the weekly plan.
2. One-tap "generate a week" that fills all seven days from existing routines (the lazy path).
3. Allow deleting the built-in (default) routines, and keep them deleted.
4. Reorder the routines list by dragging.
5. New routines appear at the top of the list.
6. The in-session timer shows one large, easy-to-read number (the current exercise) plus a thin time-based progress bar for the whole session.

## Non-goals

- No changes to the exercise logic, Gabor game, analytics, or reminder scheduling.
- No new routine-generation algorithm: "generate" only assigns existing routines to days; it does not invent steps.
- No cloud sync, no multi-week plans.

## Anti-goals (would make this a failure)

- A deleted default routine reappearing on next launch.
- The weekly plan still being unreachable after it has been set.
- The session timer showing two competing small numbers.

## Constraints

- Flutter `^3.13.0`, `sqflite ^2.3.3+1`, `sqflite_common_ffi ^2.3.3` for tests.
- The database is at version 4; any schema change requires a backward-compatible `v4 → v5` migration (existing users keep their data).
- Screens go through the real `VisionDb.instance` singleton (no repository injection); widget tests use `sqflite_common_ffi` + `tester.runAsync` for real disk I/O.
- `TemplateRepo.all()` orders by `position, id`; positions are 0-based and contiguous.
- The `week_plan.template_id` foreign key is `ON DELETE SET NULL` (with `PRAGMA foreign_keys = ON`).

## The six changes

### 1. Persistent entry to the Weekly plan (bug)

Root cause: the only route to `WeekPlanScreen` is the "Plan week" button on
`TodayCard` (`today_card.dart`), which is replaced by "Start" the moment today
has a runnable routine. There is no other entry point, so a set plan cannot be
edited.

Fix: add a "Weekly plan" menu button to the dashboard (`dashboard_screen.dart`),
always visible, navigating to `WeekPlanScreen`. The `TodayCard` is left
unchanged — it keeps showing today's routine + Start / Plan week.

### 2. "Generate plan" button on the Weekly plan screen

A "Generate" button on `WeekPlanScreen`. On tap it fills all seven weekdays by
cycling through the existing routines in list order (routine *i* goes to day
`(i mod n) + 1`); if there are fewer than 7 routines it wraps. It replaces the
current plan, then republishes the reminder week labels and reloads. If there
are no routines at all it shows a message and changes nothing. No
minimum-duration filter.

### 3. Delete default routines (and keep them deleted)

- `TemplateRepo.delete` currently refuses builtins (`WHERE id = ? AND builtin = 0`).
  Remove the `builtin = 0` guard so builtins delete like any other routine.
- The routines action sheet currently offers only "Duplicate" for a builtin and
  only "Delete" for a user routine. Offer "Duplicate" **and** "Delete" for a
  builtin (user routines keep "Delete").
- Re-seed guard: `seedPresets` today re-seeds whenever no builtin exists, so
  deleting all defaults would resurrect them on next launch. Replace that with
  a one-time `presets_seeded` flag in a new `meta` table (schema v5).
  `seedPresets` seeds only when the flag is unset, then sets it. The v4→v5
  migration creates `meta` and sets the flag to 1 when any builtin exists (true
  for every v4 install, since builtins could not be deleted before).

### 4. Reorder routines

The routines list (`templates_screen.dart`) becomes a `ReorderableListView`. A
drag handle on each row (wrapped in `ReorderableDragStartListener`) starts the
drag; the row keeps its tap (start) and long-press (action sheet). On drop, the
new order is persisted via a new `TemplateRepo.reorder(List<int> orderedIds)`
that sets each template's `position` to its index in the list.

### 5. New routines at the top

`TemplateRepo.save` for a new routine (id 0) inserts at `position 0` and shifts
every existing template's position up by 1, so the new routine is first.
`seedPresets` appends instead (so the four presets keep their intended
top-to-bottom order). `save` gains an optional `newAtTop` flag (default `true`);
`seedPresets` passes `newAtTop: false`.

### 6. Session timer: one big number + time progress bar

In `session_runner.dart`'s top progress bar: the current exercise's countdown
becomes the single large focal number (the step's full duration until its first
tick, then live). The dim session-remaining number is removed. The existing thin
progress bar becomes time-based: `(total − sessionLeft) / total`, where total is
the sum of all steps' durations. A pure `sessionProgress(sessionSecondsLeft,
totalSeconds)` helper is extracted and unit-tested.

## Builder's calls (decided here, not by the implementer)

- The dashboard menu button is the fix for the bug; no Today-card edit icon is added (kept minimal).
- "Generate" replaces the whole plan (all 7 days), not just empty days.
- The re-seed flag lives in a `meta(key TEXT PRIMARY KEY, value INTEGER NOT NULL)` table.
- The session progress bar is time-based, not step-count-based.
- The big number uses the step's full duration before its first tick, so there is never an empty focal number.
