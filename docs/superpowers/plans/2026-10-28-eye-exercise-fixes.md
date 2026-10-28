# Plan: Fix Existing 8 Eye Exercises (Evidence-Based)

Date: 2026-10-28. Source: `RESEARCH_EYE_EXERCISE_EVIDENCE.md` (429 lines, do i's / line refs verified).

## Constraint
- No medical/clinical claims that the literature doesn't support.
- No false "vergence/accommodation" on flat-screen exercises.
- Photosafety audit passes with locked-in assertions.
- All 8 exercises remain usable; no feature removals.

## P0 — Truth / Safety (must ship first)

1. **Re-label Convergence** (ex 1) in `exercise_painter.dart:9`, subtitle + `exercises_screen.dart:32` hint → "Vertical Tracking" or "Smooth Tracking". No vergence claim remains.
2. **Re-label Near-Far** (ex 2) subtitle + hint → "Near-Far Pace" (not accommodation); document distance-shift is a future feature.
3. **Re-label Focus Shifting** (ex 3) → "Large Saccadic Jumps".
4. **Head-still rule** added to hints of saccadic (4), pursuit (5), figure-8 (6): `exercises_screen.dart:31-45`, one line per.
5. **Ghost trail fix** saccadic: `exercise_painter.dart` `trailLength` set to 0 for type == saccadic/focusShift (avoid second-faint-target problem).
6. **Photosafety lock-in**: assert `flashPeriodMs >= 333`, `maxFlashAreaRatio < 0.05`, `redFlashForbidden = true`. Add to `exercise_painter.dart` `_paintPeripheral`.
7. **Stop rules / contraindications**: new screen/section in `about_screen.dart` (`exercises_screen.dart` exit or About) — list 8 stop conditions from §9.1 of research doc.
8. **Claims fix** `about_screen.dart:95-99`: replace with honest wording (cite `LISTING.md` model).

## P1 — Interaction Fixes

9. **Saccadic Jumps scoring** (`exercises_screen.dart:384-387`): replace `correct = true` with 2AFC — user taps one of two target regions per trial; trial spec generated per loop rather than progress-derived.
10. **Peripheral Awareness scoring** (`:384-387` area): add a brief tap-to-detect window (≤3 s, matches CCT window); adaptive timing shrinks when >75 % correct (UFOV-style, from ACTIVE trial evidence).
11. **Smooth Pursuit path** (`exercise_painter.dart`: Lissajous): add random-phase offset so not fully periodic; reduce speed to realistic ~10°/s.
12. **Figure-8**: keep; minor head-still hint only.

## P2 — Content / Transparency

13. **Floating Orbs (8)** subtitle + hint → "Relaxation"; no training claim.
14. **Near-Far distance-shift driver**: implement as a future-mode flag (real screen + remote target toggle), not default — requires user to have a far target in room.
15. **New measurement fields** in `drillForExercise` (`training_step.dart`): `trials`, `correct`, `threshold`, `reversals` — seed next session from previous threshold.
16. **All changes commit together** with message referencing `RESEARCH_EYE_EXERCISE_EVIDENCE.md`.

## Testing
- `flutter test` passes.
- Device verification at all 8 (screenshot capture per exercise after tap).
- Photo-flash audit: run `_paintPeripheral` with assertions and confirm no crash / no red flash.
- Build release APK (53 MB pattern) — install `adb -s 100.68.25.102:46495`.

## Anti-goals (not building)
- No clinical diagnostic functionality.
- No anaglyph/stereo module (requires hardware/glasses, out of scope).
- No 10+ min adaptive protocols (scope is exercise fixes, not full protocol rebuild).
