# RESEARCH: Mechanics of the Six New Vision Exercises

Date: 2026-10-28
Scope: what the code in `lib/core/exercises/exercise_painter.dart` and `lib/screens/exercises_screen.dart` *actually does* for Contrast Sensitivity, Color Vision, Depth Perception, Visual Search, Motion Detection, Visual Memory — why each fails its intended training effect, and concrete code fixes.
Note: these six exercises are uncommitted working-tree changes (`git status`), so all line numbers refer to the current files as read today.
Companion doc: `RESEARCH_EXERCISE_INTERACTIONS.md` covers the evidence-based *interaction design* (what the user should do and why, with literature). This doc covers the implementation mechanics and the gaps between code and intent.

---

## 0. Executive summary

| # | Exercise | What it does now | Root cause of failure | Severity |
|---|----------|------------------|----------------------|----------|
| 1 | Contrast Sensitivity | One centered disc whose contrast *rises* 10%→100% every 8 s, forever | Ramp inverted vs. "decreasing contrast"; no staircase; any tap anywhere = correct | High |
| 2 | Color Vision | 9 circles in a fixed ring with 3.6° hue steps; target = center circle | No odd-one-out exists (all hues differ); target identified by *size/position*, not color; 2 of 8 distractors score as correct taps | High |
| 3 | Depth Perception | A static two-circle scene, identical for the whole run | Zero trials, zero variation; correct answer never changes; tap check hardcoded to a position the painter doesn't exactly draw | High |
| 4 | Visual Search | Target square *teleports to a new grid cell every 320 ms* in deterministic reading order | Target moves faster than a saccade; tap check uses a different grid and a different slot count (×10 vs ×25) — correct taps score wrong | Critical |
| 5 | Motion Detection | One dot gliding between random waypoints — i.e. Smooth Pursuit with a polyline | No detection/discrimination task at all; duplicates the existing pursuit exercise; taps always correct | High |
| 6 | Visual Memory | A regular dot-polygon that rotates every second, forever | No memorize → delay → probe cycle; nothing is ever recalled; taps always correct | High |

Three structural defects shared by all six (details in §1):

- **A1. No trial engine.** Everything is derived from one 8 s repeating `AnimationController` (`_ctrl.repeat()`, `exercises_screen.dart:436`), so "trials" are phases of an animation loop that repeats identically forever.
- **A2. Hit-testing is duplicated magic numbers that disagree with the painter.** Three of six checks are provably misaligned (Visual Search, Depth, Color Vision); two more validate nothing.
- **A3. Performance is never recorded.** `drillForExercise` (`training_step.dart:150-166`) writes only duration; `Drill.trials/correct/threshold/reversals/score` (`drill.dart:18-24`) stay at their zero defaults, so no cross-session progression is even possible.

---

## 1. Shared architecture findings

### A1. Everything is a phase of an 8 s loop — there are no trials

`ExerciseRunner` runs a single `AnimationController` with `duration: _loopMs` (8000 ms for all six new exercises; `exercises_screen.dart:239`) and `_ctrl.repeat()` (`:436`). Each painter branches into its own method using `progress = _ctrl.value` to derive its stimulus:

- Contrast: one sweep per 8 s loop (`exercise_painter.dart:397`)
- Color vision: hue drifts across the loop (`:423`)
- Visual search: 25 target slots per loop (`:484`)
- Motion: 4 linear legs per loop (`:95-106`)
- Memory: 8 pattern slots per loop (`:546`)

**Why this fails training.** A trial-based exercise needs the cycle show → respond → feedback → new randomized trial, where each trial's stimulus is *new* and difficulty adapts to responses. Here the cycle is show → (loop repeats) — the user can learn the exact schedule; difficulty is a fixed function of loop time; nothing the user does changes what happens next. The five different "slot counts" (1, 25, 4, 8…) derived from one loop are evidence the loop is standing in for a trial engine it can't express.

**Fix.** Introduce a per-type trial state machine. Suggested shape (new file `lib/core/exercises/trial_engine.dart`):

```dart
class TrialEngine {
  TrialSpec spec;            // current trial's stimulus parameters
  final Staircase staircase; // adaptive difficulty (see A4)
  int trials = 0, correct = 0;
  final List<double> reversals = [];

  /// Called by the runner on a tap, or on a phase timeout.
  void respond(Response r) { ... update staircase, score, spec ... }
}
```

The runner drives phases with `Timer`s (or one `Stopwatch` + periodic tick, like `_clock` at `exercises_screen.dart:236`), not the repeating `_ctrl`. Keep `_ctrl` only for the eight purely-animated exercises.

### A2. Hit-testing duplicates painter geometry — and disagrees with it

`_handleTap` (`exercises_screen.dart:351-401`) re-derives stimulus positions with hardcoded normalized magic numbers instead of sharing a layout with the painter. Every check is in *normalized screen units* while the painter draws in *pixels scaled by `shortestSide`*; on a portrait phone (e.g. 1080×2400) a drawn circle maps to an ellipse in normalized space, so thresholds don't match the drawing. Concrete mismatches:

| Exercise | Painter draws | Tap check expects | Result |
|---|---|---|---|
| Visual Search | cell centers at `(c+0.5)/5` = 0.1…0.9, slot = `(progress*25)` (0…24) (`exercise_painter.dart:486-491`) | `0.15 + col*0.175` = 0.15…0.85, slot = `(_ctrl.value*10)` (0…9 → rows 0-1 only) (`exercises_screen.dart:375-380`) | Slots can agree only in the first 320 ms of each loop (both slot 0); expected point is off-center by up to 0.07 — inside the 0.08 radius by coincidence only for cell (0,0) |
| Depth | object 1 at normalized y = `(0.5h + 0.15s)/h` = 0.5675 on 1080×2400 (`exercise_painter.dart:457-459`) | fixed `(0.35, 0.65)` (`exercises_screen.dart:369`) | Passes within ±0.15 tolerance on common aspects by coincidence; fragile |
| Color Vision | distractor ring radius = `0.10 * shortestSide * 2.5` px (`exercise_painter.dart:430`) | `dist < 0.15` from center in normalized units (`exercises_screen.dart:363-365`) | On 1080×2400 the top/bottom distractors sit at normalized distance 270/2400 = 0.1125 < 0.15 → **tapping those wrong circles scores correct**; side ones (0.25) score wrong |

**Fix.** One source of truth: the trial spec carries positions already in pixel space, computed from the same `Size` the painter gets. Hit-test against the spec:

```dart
// In the painter's CustomPaint subtree, capture the box size once per layout:
final box = context.findRenderObject() as RenderBox;
// _handleTap receives details.localPosition — already in painter coordinates.
// Compare against spec.targetRect (px), not normalized magic numbers.
final correct = spec.hitTest(details.localPosition);
```

Drop `MediaQuery.of(context).size` (`exercises_screen.dart:352`) in favor of the paint surface's own `RenderBox.size`, so insets/orientation can never desynchronize the two coordinate systems.

### A3. Nothing is measured, so nothing can progress

`drillForExercise` (`training_step.dart:150-166`) writes `task: taskExercise, durationS, completed, templateId, params: {'type': name}` — that is all. `Drill` already has `trials`, `correct`, `threshold`, `thresholdUnit`, `reversals`, `score` columns (`drill.dart:18-24`) — the psychophysical schema exists but the exercise path never populates it. Consequences:

- No session summary ("14/20 correct, threshold 4.2%").
- No seeding of the next session's difficulty (staircase always restarts at its default).
- The streak/history see a "training" row for a drill in which the user made zero meaningful responses.

**Fix.** Add the engine's tallies to `drillForExercise`:

```dart
Drill? drillForExercise({
  required ExerciseType type,
  required int seconds,
  required bool completed,
  required DateTime startedAt,
  int? templateId,
  TrialResult? result, // NEW: trials, correct, threshold, reversals
}) {
  ...
  return Drill(
    ...
    trials: result?.trials ?? 0,
    correct: result?.correct ?? 0,
    threshold: result?.threshold,
    thresholdUnit: result?.thresholdUnit,
    reversals: result?.reversalList,
    params: jsonEncode({'type': type.name, ...?result?.levelInfo}),
  );
}
```

For seeding, add a DB helper next to `bestScore()` (`vision_db.dart:266-274`):

```dart
Future<double?> lastThreshold(String task, String type) async =>
  // SELECT threshold FROM drills WHERE params LIKE '%"type": "contrast"%'
  //   AND threshold IS NOT NULL ORDER BY started_at DESC LIMIT 1
```

and seed each staircase at `lastThreshold * 1.25` (one step easier).

### A4. No adaptive staircase exists

Difficulty in all six is a fixed function of loop progress. The training variable (contrast, chromatic difference, cue magnitude, set size, coherence, delay) must instead be per-trial state adjusted by responses. A single shared utility suffices for all six:

```dart
/// 3-down/1-up staircase, converges at 79.4% correct (Levitt 1971).
class Staircase {
  Staircase({required this.start, required this.stepDown, this.min, this.max});
  double level = start; // the stimulus variable, in exercise-specific units
  final double stepDown; // e.g. * 0.8 for contrast, -2° for hue
  ...
  void record(bool correct) {
    // 3 correct in a row → harder; 1 wrong → easier; log reversal points.
  }
}
```

### A5. Misc runner issues

- **Feedback occludes the stimulus.** The 60×60 badge is centered on screen (`exercises_screen.dart:610-627`) — exactly where Contrast/Color/Depth/Memory draw their stimuli. Move it to the tap point or the top bar.
- **Tap spam is costless.** Contrast/Motion/Memory score every tap correct and taps are unlimited; a user can hold a finger down (rapid tap) for a strobe of green checks. Trials need a response window with timeouts counted as misses.
- **`ExerciseLoad` taxonomy is wrong for the six perceptual drills** (`training_step.dart:35-41`): contrast→`accommodation`, colorVision→`pursuit`, depthPerception→`vergence`, motionDetection→`pursuit`, visualMemory→`relax`. These are discrimination tasks, not oculomotor loads; the mapping makes `templateWarnings` (`training_step.dart:127-143`) emit false "loads the same system back to back" advisories (e.g. Near-Far followed by Contrast Sensitivity). Add a `discrimination` load.
- **Dead code:** the `exercisePath` branches for contrast/colorVision/depthPerception/visualMemory (`exercise_painter.dart:80-88, 107-109`) are unreachable — each painter returns early (`:229-252`) and only Motion Detection's branch is consumed (`:512, 522`).

---

## 2. Per-exercise analysis

### 2.1 Contrast Sensitivity

**Intended effect** (enum subtitle `exercise_painter.dart:24-25`, hint `exercises_screen.dart:51-52`): detect the target *as contrast decreases* — i.e. find the user's contrast threshold, and train at it.

**What the code actually does** (`_paintContrast`, `exercise_painter.dart:386-410`):

- Fills the screen with mid-gray `0xFF808080` and draws one disc, radius `0.08 * shortestSide`, dead center.
- `contrastLevel = 0.1 + 0.9 * progress` (`:397`) — contrast *rises* from 10% to 100% over the 8 s loop, then snaps back to 10%. The comment on `:396` ("higher = harder") is backwards: higher `contrastLevel` = whiter disc = *more* contrast = easier to see.
- The hint says "as contrast decreases"; the code does the opposite. What actually happens visually: a near-invisible disc fades *in* over 8 s, then resets. There is no detection judgment — the sweep is a pure function of loop time.

**Interaction** (`exercises_screen.dart:357-360`):

```dart
case ExerciseType.contrast:
  // User tapped - always correct for now (simplified)
  correct = true;
```

Any tap, anywhere, at any time = green check. The disc is never validated as a hit target, misses don't exist, and nothing about the response feeds back into the stimulus. The label `CONTRAST {n}%` (`:409`) displays the current level, which at least reveals the sweep — but the user's behavior has zero effect on it.

**Verdict.** The exercise as shipped is a passive 8-second fading-disc animation with a green-check strobe. It trains nothing: no threshold is probed, no adaptive difficulty, no feedback signal, no score.

**What must change:**

1. Per-trial state, not a ramp: hold a `Staircase` over Michelson contrast (start ~50%, step ×0.8 down / ×1.25 up, log-unit-ish).
2. Trial structure (mobile-friendly spatial 2AFC, per the companion doc §1.4): fixation beat → show patch at a *random* position in one of two side-by-side panels at the staircase contrast for ~600 ms → blank → user taps the panel that contained it. Misses/timeout = wrong.
3. Painter contract change: `ExercisePainter` needs the contrast level and target position as *fields of the current trial spec*, not derived from `progress`. Draw the two panels and highlight the response window.
4. Hit-test: tap inside the chosen panel's rect (pixel space, A2).
5. Record: `trials`, `correct`, `threshold` = staircase level, `thresholdUnit: '%'`.
6. Fix the hint text once the ramp is per-trial ("Which panel showed the faint patch?").

### 2.2 Color Vision

**Intended effect** (`exercise_painter.dart:26-27`, hint `exercises_screen.dart:53-54`): "Identify the unique color among similar hues."

**What the code actually does** (`_paintColorVision`, `exercise_painter.dart:412-443`):

- `hue = 0.1 + 0.02 * progress` (`:423`) — a 0.02 hue drift (36°→43.2°) across the loop. All nine circles stay inside a 36°–72° hue band forever.
- The center circle (the "target") uses that hue; the 8 distractors use `hue + 0.01*(i+1)` (`:432`) — offsets of +3.6°…+28.8° *from the target*. Every circle has a different hue; adjacent circles differ by a constant 3.6°. **There is no unique color and no odd-one-out** — no circle is perceptually distinct; the field is a smooth hue gradient. The task as hinted is unsolvable as posed.
- The only reliable cues for "the target" are *non-color* cues: it is the only circle of radius `r` (distractors are `0.6r`) and it is always exactly centered. The exercise reduces to "tap the big circle in the middle" — a size/position task, not color vision.
- Positions are a fixed ring (`:427-431`), identical every run.

**Interaction** (`exercises_screen.dart:361-366`): `dist < 0.15` from `(0.5, 0.5)` in normalized units. On a 1080×2400 screen the vertical distractors sit at normalized distance 0.1125 — *inside* the acceptance radius — so tapping those wrong circles scores correct, while tapping side distractors (0.25) scores wrong (see A2 table). Aspect-ratio-dependent scoring.

**Verdict.** No chromatic discrimination is ever demanded; difficulty never varies; 2 of 8 wrong answers score as right.

**What must change:**

1. Real odd-one-out: N circles (start 4, grow to 8) at **randomized** positions, all identical *size*, all sharing one base hue **with per-circle luminance jitter** (Stilling/pseudoisochromatic principle — prevents solving by brightness), one circle offset by ΔC along a fixed axis.
2. ΔC staircased: start ~15° hue offset, step down toward ~2°; that offset is the training variable.
3. Painter takes the trial spec (base hue, ΔC, positions, jitter) as fields.
4. Hit-test: nearest circle within its pixel radius; correct iff it is the odd one.
5. Record `trials/correct/threshold (Δhue in degrees)`.

### 2.3 Depth Perception

**Intended effect** (`exercise_painter.dart:28-29`, hint `exercises_screen.dart:55-56`): "Judge relative depth of objects."

**What the code actually does** (`_paintDepthPerception`, `exercise_painter.dart:445-468`):

- A completely static scene: object 1 (larger `r=0.12s`, lower `cy+0.15s`, brighter `alpha 0.9`, left) and object 2 (smaller, higher, dimmer, right). **Nothing is a function of `progress`** — the display is identical for the entire 30/60/120 s run.
- All three pictorial depth cues (size, height-in-field, brightness) are confounded and all point at object 1; the answer never changes; there is one "trial" lasting the whole run.

**Interaction** (`exercises_screen.dart:367-372`): the close object's position is hardcoded as `Offset(0.35, 0.65)` in normalized units. The painter actually draws it at normalized y = `(0.5h + 0.15s)/h` — 0.5675 on 1080×2400, 0.65 only on a square surface. It passes only because the 0.15 tolerance happens to cover the gap (A2 table). Taps on object 2 correctly score wrong — but since the scene is static, the correct strategy is to tap the same pixel forever and collect a green check every second.

**Verdict.** A still image with a fixed answer. No depth judgment, no trials, no progression. (A flat screen also carries no binocular disparity — true stereopsis requires anaglyph/random-dot stimuli; see companion doc §3.)

**What must change:**

1. Trial engine: each trial randomly picks which side holds the closer object; randomize x-positions; keep a 2AFC response ("tap the closer one", hit-tested against the two actual circles).
2. Staircase the *cue magnitude*: size ratio from 1.6 → 1.05, height offset from 0.15 → 0.02 of shortest side, alpha equalized (or randomized independently so cues can conflict — a genuine inference task rather than three redundant cues).
3. Painter takes the trial spec (positions, radii, alphas) as fields; remove the progress-free static scene.
4. Optional future: red-cyan anaglyph random-dot stimulus for real disparity (needs glasses — flag it in UI).
5. Record `trials/correct/threshold` (e.g. size ratio at threshold).

### 2.4 Visual Search

**Intended effect** (`exercise_painter.dart:30-31`, hint `exercises_screen.dart:57-58`): "Find the square among circles."

**What the code actually does** (`_paintVisualSearch`, `exercise_painter.dart:470-508`):

- 5×5 grid; `targetSlot = (progress * 25).floor()` (`:484`). The target cell **changes every 8 s / 25 = 320 ms**, and not randomly — `slot ~/ 5`, `slot % 5` scans the grid in *reading order*, left-to-right, top-to-bottom, wrapping each loop. The square teleports to the next cell ~3× per second, faster than a saccade-plus-verification cycle (~400-500 ms). The user cannot find and fixate a target before it relocates.
- The search itself is a single-feature pop-out (square vs. circle, same color; distractors additionally at `alpha 0.5` vs the target's full alpha, `:496-503` — a second unintended pop-out cue). Pop-out is pre-attentive: zero training load even if the target stood still.

**Interaction** (`exercises_screen.dart:373-383`):

```dart
final searchSlot = (_ctrl.value * 10).floor();   // ×10, painter uses ×25
final targetRow = searchSlot ~/ 5;               // rows 0..1 only
final targetCol = searchSlot % 5;
final targetX = 0.15 + targetCol * 0.175;        // painter centers: (c+0.5)/5
final targetY = 0.15 + targetRow * 0.175;
```

Four independent bugs: (a) ×10 instead of ×25; (b) slot range 0…9 means the expected row is only ever 0 or 1 regardless of where the drawn target is; (c) the grid origin/step (0.15/0.175) does not match the painter's cell centers (0.1…0.9); (d) threshold 0.08 in normalized units. Net effect: the check point and the drawn target can coincide only when both slots are 0 — the first 320 ms of each loop, top-left cell. **Tapping the actually-drawn square scores wrong ~100% of the time**, and the user is shown a red X for correct behavior. The most broken of the six.

**Verdict.** Unsolvable stimulus (320 ms teleport) + a hit-test that rejects correct answers.

**What must change:**

1. Target fixed per trial: choose one random cell at trial start; it stays until tapped or until a timeout (counts as miss). Next trial re-randomizes.
2. Shared layout function used by painter and hit-test (A2): `Offset cellCenter(int row, int col, Size size)`.
3. Real progression: conjunction search — target defined by color AND shape (e.g. red square among red circles and green squares), set size 3×3 → 5×5, more similar shapes; optionally staircase display duration (UFOV-style).
4. Track response time; record `trials/correct/score` (mean RT or set-size level).

### 2.5 Motion Detection

**Intended effect** (`exercise_painter.dart:32-33`, hint `exercises_screen.dart:59-60`): "Detect moving objects."

**What the code actually does** (`_paintMotionDetection`, `exercise_painter.dart:510-534` + path `:95-106`):

- One dot moves linearly between hash-derived waypoints, 4 legs per 8 s loop (2 s per leg), with a 5-sample trail. It is *always* visibly moving.
- There is nothing to *detect* — the task decomposes into "watch the dot", i.e. smooth pursuit. It is functionally a duplicate of the existing `pursuit` exercise with a polyline path instead of a Lissajous curve. The hint ("Follow the moving object") agrees with the code but contradicts the exercise's name and training intent.

**Interaction** (`exercises_screen.dart:384-387`): `correct = true` — every tap anywhere is green. No task, no validation.

**Verdict.** Duplicate pursuit animation; no detection or discrimination component.

**What must change** — pick one paradigm (companion doc §5 recommends the RDK):

- **RDK-lite (recommended):** ~80-120 small dots drifting with coherence *c*% in one of two directions (left/right); the rest jitter randomly. Two response buttons (LEFT / RIGHT). Staircase on coherence 100% → ~5%. This trains direction-integration, the actual motion-detection faculty.
- **Minimum viable alternative:** N≈6 dots; on each trial exactly one moves smoothly while the others jitter in place; user taps the moving one; staircase on speed (px/s) and/or dot contrast.
- Painter takes trial spec (dot count, coherence, direction, speed) as fields; the current `exercisePath` motion branch becomes a trial-internal trajectory generator, not a loop function.
- Record `trials/correct/threshold` (coherence %).

### 2.6 Visual Memory

**Intended effect** (`exercise_painter.dart:34-35`, hint `exercises_screen.dart:61-62`): "Recall visual patterns."

**What the code actually does** (`_paintVisualMemory`, `exercise_painter.dart:536-563`):

- `patternSlot = (progress * 8).floor()` (`:546`) — the "pattern" changes every 1 s, forever. `numDots = 3 + (patternSlot % 4)` cycles 3→4→5→6→3…, and dots sit at evenly spaced angles on a *fixed-radius ring* (`:549-553`), rotated by `patternSlot * 0.5` rad per slot. So every "pattern" is just a regular polygon (triangle/square/pentagon/hexagon) rotated by ~29°/s. It is not a memorable spatial pattern; it is a rotating shape, continuously changing.
- There is **no memorize phase, no blank delay, no probe, no recall response** — the entire construct of a memory task is absent. A 1-second slot gives no time to encode, and there is nothing to compare against afterward.

**Interaction** (`exercises_screen.dart:388-391`): `correct = true` — all taps green.

**Verdict.** No memory is exercised at all; the animation is decorative.

**What must change (change-localization, per companion doc §6):**

1. Phase machine per trial: **sample** (k dots at random grid cells, shown ~1500 ms) → **blank delay** (staircased, start ~1000 ms) → **test** (same array, or one dot displaced to a new cell) → user taps the changed dot → feedback → next trial.
2. Progression: k from 3 up, delay up to 3 s, displacement magnitude down.
3. Painter takes `phase` + `sampleDots` + `testDots` from the trial spec; the ring/polygon code is deleted.
4. Record `trials/correct/score`.

---

## 3. Prioritized fix plan

1. **P0 — Fix the three broken hit-tests** (Visual Search ×10-vs-×25 + grid mismatch; Depth's hardcoded position; Color Vision's aspect-dependent radius). Minimal change: compute positions in pixel space from one shared layout helper per exercise; delete the normalized magic numbers. This stops *punishing correct behavior* even before the tasks are redesigned.
2. **P0 — Stop the Visual Search target from teleporting** (target fixed per trial; 320 ms slot removed). One-line-ish change to the painter once a trial state exists.
3. **P1 — Trial engine + staircase utility** (`trial_engine.dart` with `Staircase`), driven by per-phase `Timer`s; runner keeps `_ctrl` only for the eight animated exercises. This unblocks all six.
4. **P1 — Record results**: extend `drillForExercise` with a `TrialResult`; add `VisionDb.lastThreshold` for seeding next sessions.
5. **P2 — Rebuild each stimulus on trial specs** in the order of training value: Contrast (2AFC panels), Color (luminance-jittered odd-one-out), Motion (RDK or moving-among-static), Memory (change localization), Depth (randomized cue magnitude), Search (conjunction search + set size).
6. **P2 — UI polish**: feedback badge at tap point (not center); response-window timeouts counted as misses; fix `ExerciseLoad` mapping (add `discrimination`); delete dead `exercisePath` branches; update hints to describe the real tasks.
7. **P3 — Tests**: golden/logic tests for each trial spec's `hitTest` and the staircase (3-down/1-up behavior, reversal logging) — none exist today for any of the six (`test/` has no reference to these types).
