# Psychophysical engine — design

**Date:** 2026-09-29
**Status:** proposed, awaiting review
**Scope:** the measurement core Visor's exercises run on, and the tasks built on it.

---

## 1. Intent

Visor today has two halves that do not meet. The Gabor grid game measures
something — accuracy, weighted into a score — and writes it to SQLite. The
eight eye exercises measure nothing: `exercises_screen.dart` imports no
database, runs an animation against a timer, and ends. A user can spend ten
minutes on convergence drills and the streak still shows a missed day.

The exercises are also open-loop in the stricter sense: there is no response
channel, so there is no error signal, so there is no adaptation and no number
that improves. Adding more animations does not fix that; it multiplies it.

This design replaces "an exercise is an animation with a timer" with "an
exercise is a sequence of psychophysical trials". The unit of the app becomes a
**trial**: a stimulus at a controlled level, a response, a correctness
judgement, and a step along an adaptive staircase. The output is a **threshold**
in physical units — arcseconds of offset, arcminutes of disparity, percent
contrast — that a user can watch fall over weeks.

### Success criteria

1. Every drill writes a row that the streak and the analytics screen can see.
2. A vernier threshold measured on a calibrated device lands in the published
   human range (roughly 5–20 arcseconds). This is the engine's self-test: if it
   reports 300 arcseconds, either the calibration or the staircase is wrong.
3. Adding a new task is writing a `PsychTask` implementation and a config —
   not a new screen.
4. Nothing in the app reports a physical unit it has not earned. Uncalibrated
   drills show relative units and say so.

### Non-goals

- Spatial cognition tasks (mental rotation, Corsi span, spatial n-back). See
  §6.3 for why these are excluded rather than merely deferred.
- Camera-based gaze or distance tracking.
- Ambient training overlay (`PLAN.md` §4.2) — unrelated subsystem.

---

## 2. Units and calibration

### The problem

`GaborPatch.render` works in normalized coordinates: `frequency` is documented
as "cycles per unit length of the patch" and `sigma` is normalized to the patch
half-width. Nothing in the codebase knows how large a patch is on the retina.
Orientation deltas are honest — a 5° rotation of a grating is 5° regardless of
viewing distance — but disparity in arcminutes, spatial frequency in cycles per
degree, and eccentricity in degrees all depend on two unknowns: the physical
size of a pixel and the distance from eye to screen.

### `ViewingGeometry`

```
pxPerMm    ← device metrics (logicalPx × devicePixelRatio / physicalSize)
distanceMm ← calibrated once, stored
⇒ degPerPx = atan(1 / (pxPerMm × distanceMm)) in degrees
```

Flutter supplies `pxPerMm` nearly free, but Android OEMs misreport DPI by 5–15%.
One manual correction fixes it: the user scales an on-screen frame to match a
bank card (ISO/IEC 7810 ID-1, 85.60 mm — identical worldwide). This is the
standard trick from web psychophysics (the "virtual chinrest" method).

`distanceMm` defaults to 350 mm — typical phone-to-eye distance — and is
user-adjustable. Refining it with the camera is rejected: the app's promise is
that nothing leaves the device, a camera permission undermines that story in a
reviewer's eyes, and the gain is smaller than the staircase's own spread.

### Honesty rule

An uncalibrated user still trains. Thresholds are then reported in relative
units (pixels, percent contrast) with a visible prompt to calibrate for angular
units. The app never prints a fabricated arcsecond.

### Blast radius

None. The existing Gabor grid game stays in grating degrees and needs no
calibration.

---

## 3. The trial engine

Three abstractions, none of which import Flutter — matching the existing
convention that `gabor_patch.dart` and `chart_math.dart` are pure and directly
testable.

```dart
abstract class PsychTask<S> {
  /// Stimulus for the current staircase level.
  S stimulus(double level, Random rng);
  bool isCorrect(S stimulus, Response response);
  AxisSpec get axis; // name, unit, bounds, direction of "harder"
}

class Staircase {
  double level;
  double step;          // halved at each reversal
  void record(bool correct);
  double? threshold();  // mean of the last N reversals, null until converged
}

class DrillRunner {
  // stimulus → response → staircase step; ends on time or convergence
}
```

### Why a staircase instead of four fixed levels

A transformed up-down rule (1-up / 2-down) converges on the level where the
user is right 70.7% of the time, in roughly 40–60 trials. That yields *this
user's* threshold rather than a designer's guess at "Hard". It is both more
honest and a better motivational loop: the number is physical and it falls.

The four `Difficulty` levels survive as a shell — they set the staircase's
starting level and initial step, so a newcomer is not dropped straight onto
their threshold.

### Response channel

One sealed type, four shapes, because different tasks measure different things:

| Shape | Tasks | Yields |
|---|---|---|
| `Choice(index)` | Gabor grid, RDS, vernier, Landolt C | correct / incorrect → staircase step |
| `Localize(offset)` | peripheral, UFOV | localization error in degrees |
| `Timed(latency)` | saccades, trajectory extrapolation | reaction time distribution |
| `Track(samples)` | smooth pursuit, figure-8 | RMS tracking error |

**Deferred response for fixation tasks.** For peripheral and UFOV drills the
response is collected *after* the cycle, not during it. Tapping in real time
breaks fixation, which destroys the stimulus the task depends on. This is the
first thing to validate with a throwaway probe (§7).

### Blast radius

`game_screen.dart` is rewritten on top of `DrillRunner` — its loop is already a
trial loop, only without a staircase. `Difficulty.maxThetaDelta` /
`minThetaDelta` become staircase starting points.

### Two defects in the current generator that the engine forces us to fix

1. **`TrialGenerator._randomPatch` draws `theta` over `[0, 2π)`.** A grating is
   π-periodic: θ+π is the same grating with inverted phase. The orientation
   space is doubled, which is harmless for a game and wrong for a threshold.
   Reduce to `[0, π)`.
2. **`TrialGenerator._distractor` gives every distractor an independent delta**
   drawn from `[minThetaDelta, maxThetaDelta]`. The effective difficulty of a
   trial is therefore the *smallest* delta that happened to land in the grid —
   a random variable. A staircase needs one controlled Δθ applied to the whole
   grid, otherwise it measures the random draw and not the eye.

Fixing (2) changes the contract that `test/gabor_test.dart` asserts on
distractor deltas. Those tests get rewritten deliberately, not patched around.

---

## 4. Data

### The problem

`vision_sessions` is the schema of one game: `difficulty / grid / pattern /
correct / total / score`. A threshold does not fit in it, and vernier has no
grid. The streak and `bestScore()` read only this table, which is why exercises
are invisible by construction.

### Schema, migration v3 → v4

```sql
CREATE TABLE viewing_geometry (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at INTEGER NOT NULL,
  px_per_mm REAL NOT NULL,
  distance_mm REAL NOT NULL
);

CREATE TABLE drills (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at INTEGER NOT NULL,
  task TEXT NOT NULL,            -- 'gabor_grid' | 'vernier' | 'csf' | 'rds' | …
  duration_s INTEGER NOT NULL,
  completed INTEGER NOT NULL,    -- ran to the end, or was closed early
  trials INTEGER NOT NULL,
  correct INTEGER NOT NULL,
  threshold REAL,                -- NULL when the staircase did not converge
  threshold_unit TEXT,           -- 'arcsec' | 'arcmin' | 'cpd' | 'pct' | 'deg' | 'ms'
  reversals TEXT,                -- JSON array of levels at each reversal
  geometry_id INTEGER REFERENCES viewing_geometry(id),  -- NULL = uncalibrated
  score REAL,                    -- legacy weighted grid score; NULL otherwise
  template_id INTEGER,           -- routine this step belonged to; see the
                                 -- training-templates spec. NULL for a
                                 -- standalone drill.
  params TEXT                    -- JSON: grid, curved, eccentricity, frequency bin…
);

CREATE INDEX idx_drills_started ON drills(started_at);
```

Three non-obvious decisions:

- **`viewing_geometry` is a table, not a single row.** Re-calibrating, or
  changing device, means older thresholds were measured with a different ruler.
  `geometry_id` on each drill keeps history honest instead of retroactively
  rewriting old arcseconds. It costs a handful of rows over the app's lifetime
  and prevents a fake jump in the progress chart.
- **`reversals` is a JSON column, not a `trials` table.** A per-trial table
  would be 40–60 rows per drill and would allow refitting a psychometric
  function later. Neither is needed now: the reversals are the informative
  residue of the staircase, and a different estimator can be applied to them.
  One column instead of a table and its joins.
- **`template_id` is owned by the training-templates spec**, which shares this
  migration. It is listed here so the v4 DDL is complete in one place; neither
  spec creates the column twice.
- **`vision_sessions` is backfilled into `drills`, then dropped.** User history
  is real data. Each row becomes `task='gabor_grid'`, `threshold=NULL`, with
  `score` preserved and `params={difficulty,grid,pattern}`. One table
  afterwards, no unions. `bestScore()` filters
  `task='gabor_grid' AND score IS NOT NULL` and behaves as before.

### Streak

`computeStreak` is pure and tested; it does not change. Only its source of days
changes: `drills` instead of `vision_sessions`, filtered by
`completed = 1 AND duration_s >= 30`. Without that filter the streak can be
farmed by opening and closing an exercise.

**Product decision:** any completed drill closes the day. The streak measures
the habit, not the volume; volume is visible in the analytics. Weighting the
streak by minutes turns it into bookkeeping and punishes short days — and short
days are what keep a habit alive.

---

## 5. Analytics

The trend chart was rebuilt separately (see `lib/widgets/accuracy_chart.dart`
and `chart_math.dart`): the X axis is calendar time with a minimum seven-day
window, a point is one day, and the Y axis is accuracy 0–100 with difficulty
carried as colour. That work is done and this design builds on it.

Thresholds need a **second** axis type, not a reuse of the first:

| Series | Y axis | Why |
|---|---|---|
| Daily accuracy | fixed 0–100, zero-based | a percentage; zero-based is correct and `niceCeil` is unnecessary |
| Threshold over time | logarithmic, inverted, min..max window | thresholds are multiplicative (the staircase halves its step) and lower is better; a zero-based axis squashes the interesting range into the top few percent |
| CSF | sensitivity (1/threshold) vs spatial frequency, log–log, no time axis | the classic inverted-U; one drill is one curve |

Only the time axis is shared between them — `chartWindow` and `ChartWindow.xFor`
are reused as-is. Drills with and without `geometry_id` are never drawn on the
same axis: their units differ.

---

## 6. Tasks

Ordered by the cost of *validating the engine*, not by impact. Each task is a
configuration of `PsychTask`, not a new screen.

### 6.1 Wave 1 — validate the engine, no new rendering

1. **Vernier acuity.** Two line segments, offset by N pixels, response
   "left / right". Level = offset → arcseconds. It goes first because it is the
   only task with a hard published norm (5–20″ in a sighted adult) to check the
   whole chain against.
2. **Contrast sensitivity function.** The existing `GaborPatch`, untouched:
   vary `contrast` at four or five fixed spatial frequencies, take a contrast
   threshold at each. The output is a curve, not a number — the first genuinely
   new chart in the app, at almost no cost.

### 6.2 Wave 2 — stereo, closing `PLAN.md` §4.3 without a 3D renderer

3. **Random-dot stereogram**, free-fusion. New renderer, conceptually simple: a
   dot field with a shifted region. Level = disparity → arcminutes.
4. **Stereo-Gabor.** Two `renderRgbaCircular` copies with an x-offset; level is
   disparity. Nearly free once the RDS fusion onboarding exists.
5. **Digital Brock string / fusion targets.** This one measures a *vergence
   range*, not a threshold. The response is subjective ("still single / now
   double"), so the procedure is the method of ascending limits, not 1-up/2-down
   — the single place where the engine needs a second algorithm. Reported in
   prism dioptres: `Δ = 100 × displacement / distance`.

### 6.3 Wave 3 — attention and field, needs the deferred response channel

6. **Peripheral / UFOV.** Not a new exercise: a *conversion* of the existing
   `peripheral` drill onto `Localize`, adding localization error in degrees.
   The first of the original eight to measure anything.
7. **Multiple object tracking.** Track 3 of 10 identical dots. Level = target
   count or speed.
8. **Trajectory extrapolation.** `Timed`; a dot passes behind an occluder.

### 6.4 Excluded: spatial cognition

Mental rotation, Corsi span and spatial n-back are deliberately out of scope —
not on cost grounds. They exercise parietal cortex, not the visual system, and
including them shifts the app's claim from "we train vision, here is your
threshold in arcseconds" to "we train your brain". The latter is the claim the
FTC fined Lumosity $2M over. Vernier and CSF can be shown to a reviewer as
measurements; "spatial thinking" cannot. If that layer is wanted it deserves its
own product decision and its own spec.

---

## 7. Cheap validation before implementation

Three probes, each under an hour, each able to kill or reshape a wave:

1. **Calibration.** Bank-card scaling plus arm's-length default. Measure one's
   own vernier threshold: 5–20″ means the geometry is sane; 2′ means the
   distance model is lying.
2. **Free fusion.** A static page with two dots and an RDS, tried on two or
   three people: do they see a third dot, does the square pop out? If not,
   stereo tasks live behind an onboarding gate rather than in the main menu.
3. **Response channel.** Add a tap to the existing `peripheral` drill and check
   whether tapping breaks fixation. If it does, the response must be deferred to
   the end of the cycle rather than collected live.

---

## 8. Safety and correctness traps

1. **Fusion sign.** Cross-eyed fusion inverts depth. A cross-fuser answers an
   RDS mirror-reversed, so the staircase diverges instead of converging — which
   presents as inability rather than as inversion. Onboarding must detect and
   record *which* fusion the user performs, and the engine must flip the sign of
   disparity accordingly. This is a correctness bug waiting to happen, not a
   nicety.
2. **Screen luminance.** Contrast thresholds depend on display luminance and
   adaptation state, and absolute nits are not readable on Android. A CSF drill
   therefore requests a fixed brightness for its duration and records that it
   did so in `params`. Day-to-day comparability stays approximate, and the UI
   says so rather than implying a laboratory.
3. **Vergence load.** Free-fusion and Brock-string work are the drills that
   actually cause asthenopia. A daily cumulative cap on that category, a forced
   break, and copy that says to stop if doubling does not clear after a rest.
   The existing 30 / 60 / 120 s timers already work in our favour here.
4. **Colour coding.** The difficulty ramp (green → blue → orange → red) puts its
   two extremes at the ends of the red–green confusion axis. The legend names
   every level, and position and dot size carry information independently, but a
   shape or pattern channel should be considered if users report trouble.

---

## 9. Order of work

1. Trend chart rebuild — **done**, on branch `feat/analytics-chart-time-axis`.
   It also establishes the time axis the threshold charts reuse.
2. `ViewingGeometry` + calibration screen.
3. `PsychTask` / `Staircase` / `DrillRunner`, with `game_screen.dart` ported
   onto it and the two generator defects in §3 fixed.
4. Schema v4 and the streak source change.
5. Wave 1 (vernier, CSF) — validates the engine end to end.
6. Wave 2 (stereo), gated on probe 2.
7. Wave 3 (attention), gated on probe 3.
