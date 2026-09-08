# Visor — Development Plan

This document is the working plan for Visor: an on-device, free, no-ads
vision-training application for Solana Seeker. It maps what exists today,
what is planned, and the order in which we intend to close the gaps.

> Companion docs: `ROADMAP.md` (public feature roadmap), `README.md`
> (landing + user-facing overview).

---

## 1. Architecture

Clean, modular Flutter structure. The Gabor core is deliberately decoupled
from the UI so it can be unit-tested independently.

```
lib/
  main.dart                     entry point — fullscreen immersive, MaterialApp
  screens/
    dashboard_screen.dart       home: streak / today / best + navigation menu
    setup_screen.dart           duration (1/2/3/5 min), difficulty (4 levels), stripe mode
    game_screen.dart            the "find the matching patch" game
    exercises_screen.dart       list of 8 exercises + full-screen runner
    analytics_screen.dart       score trend + session history
    reminder_screen.dart        daily reminder time
    about_screen.dart           about + optional tipping
  widgets/
    gabor_view.dart             renders a GaborPatch as an image (cached)
  core/
    gabor/gabor_patch.dart      patch model + generator + difficulty rules (core)
    models/session_setup.dart   session configuration DTO
    db/vision_db.dart           SQLite: sessions + reminder + account
    exercises/exercise_painter.dart  exercise trajectories (Canvas)
    reminder/reminder_service.dart   native notification layer
    wallet/wallet_auth.dart     Seed Vault (Solana Mobile) auth
    theme/visor_theme.dart      dark theme
```

The generator core (`gabor_patch.dart`) imports only `dart:math` and
`dart:typed_data` — no Flutter — so it is trivially testable in isolation.

---

## 2. Core logic

### 2.1 Gabor patch

A Gabor patch is a sinusoidal grating multiplied by a Gaussian envelope —
the canonical stimulus for orientation/contrast discrimination in primary
visual cortex (V1).

```
G(x,y) = exp( -(x'² + γ²·y'²) / (2σ²) ) · cos(2π·f·x' + φ)
```

Parameters:

| Param    | Meaning                              |
|----------|--------------------------------------|
| `theta`  | grating orientation (primary discrim axis) |
| `frequency` | spatial frequency (stripe count)  |
| `sigma`  | Gaussian envelope width             |
| `phase`  | stripe phase offset (hard+)         |
| `aspect` | envelope elongation                 |
| `contrast` | amplitude multiplier (1.0 → 0.6 on expert) |
| `curvature` | stripe bend (0 = straight, >0 = curved) |

### 2.2 Trial generation

`TrialGenerator.generate(difficulty)`:

1. Generate a random **target** patch.
2. Pick a random answer index in the N×N grid.
3. Fill remaining cells with **distractors** bounded by a controlled
   orientation delta (plus frequency/phase drift on higher levels).

The brain is asked to discriminate *orientation* (and later frequency/phase),
never random noise.

### 2.3 Difficulty map

| Level  | Grid | Angle delta | Extra axes     | Contrast | Score weight |
|--------|------|-------------|----------------|----------|--------------|
| Easy   | 3×3  | 30–60°      | —              | 1.0      | 1.0          |
| Medium | 4×4  | 15–30°      | frequency      | 1.0      | 1.5          |
| Hard   | 5×5  | 5–15°       | freq + phase   | 1.0      | 2.0          |
| Expert | 6×6  | 5–10°       | freq + phase   | 0.6      | 2.5          |

---

## 3. User flow

```
Dashboard → Start Training → Setup (duration / difficulty / stripe mode)
  → GameScreen:
      countdown timer (1/2/3/5 min), decrements every second → finish at 0
      top patch = target, N×N grid = options
      tap → check → ✓/✗ (650 ms) → next trial
      on finish → persist session to SQLite + markTrainedToday
  → ResultScreen → Done → Dashboard (refresh streak / today / best)
```

**Scoring** (`vision_db.dart`): `score = (correct / total) × 100 × weight`.
Difficulty is weighted, so an 80% Hard session outranks a 100% Easy one.

**Streak**: consecutive days (today, or yesterday if today is not yet closed)
with at least one session.

**Exercises**: 8 types, each a point trajectory in [0,1]×[0,1] via
`exercisePath()`, animated with `AnimationController` + a duration ticker
(30/60/120 s).

---

## 4. Gaps to close (priority order)

### Done — do not touch
- Gabor generator + difficulty map (scientifically sound).
- Weighted scoring, streak, best, SQLite persistence.
- 8 exercises with trajectories.
- Seed Vault wallet (optional SOL/SKR tipping).

### 4.1 Unit tests for the generator core
The generator is clean and dependency-free but has zero tests. Add `test/`
coverage: distractor deltas fall within the declared range, the target is
always present in the grid, and `render` never emits NaN.

### 4.2 Ambient Training
Passive Gabor grid over other windows (Android overlay). Not yet started;
technically a separate window/overlay layer, more involved than the rest.
Candidate for post-v1.

### 4.3 3D exercises (vergence-accommodation coupling)
Screen references "Bouncing Ball 3D", "Starfield 3D", "Floating Orbs 3D".
Current exercises are 2D trajectories only. Requires a 3D render layer.
Candidate for v2.

### 4.4 Monetization decision
ClearSight gates features behind PRO. Visor's philosophy is free core +
optional tips (SOL/SKR) via "Support Visor" — no nagging. Keep this;

### 4.5 Analytics filters
Analytics exists (trend + history) but lacks a per-difficulty / per-mode
breakdown. Low priority polish.

---

## 5. Recommended order

1. Unit tests for the generator (cheapest, catches regressions).
2. Ambient Training (flagship feature missing from the current build).
3. 3D exercises (vergence-accommodation).
4. Monetization final call + PRO-badge cosmetics if any.
5. Analytics filters (polish).