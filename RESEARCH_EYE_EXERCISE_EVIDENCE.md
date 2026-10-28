# RESEARCH: Evidence, Correct Protocols, and Safety for the Eight Existing Eye Exercises

Date: 2026-10-28
Question: For the 8 exercises already in Visor (convergence, near-far cycles, focus shifting, saccadic jumps, smooth pursuit, figure-8 tracking, peripheral awareness, floating orbs) — what does each actually train, does the vision-science literature support it and for whom, what is the correct execution protocol (posture, distance, head position, eye/hand rules, rates, stop criteria), is it safe — and where does the current implementation contradict the correct protocol?
Scope note: covers only the 8 existing animated exercises. The six proposed game exercises are covered by `RESEARCH_EXERCISE_INTERACTIONS.md` and `RESEARCH_EXERCISE_MECHANICS.md` (same date). Code line numbers refer to the working tree as read 2026-10-28 (`git status`: `exercise_painter.dart` and `exercises_screen.dart` modified).

---

## 0. Executive summary

Angular figures below assume a ~6.5-inch phone (screen ≈ 7 cm wide × 15 cm tall) held ~40 cm from the eyes; at that distance the whole screen subtends only ~10° × 21°, so *nothing on the screen can ever be farther than ~10° from the fovea*. All angles are estimates from code geometry (§1–8).

| # | Exercise | Function the code names | What the screen actually delivers | Evidence for the named function | Verdict as implemented |
|---|----------|------------------------|-----------------------------------|--------------------------------|------------------------|
| 1 | Convergence Training (`exercise_painter.dart:9-10`) | Vergence amplitudes (convergence/divergence) | Vertical smooth-pursuit sweep, ±5°, ~5°/s | **Strong for CI** (CITT RCTs) — but vergence demand never changes on a flat screen | **Does not work** as a vergence exercise; it is a mislabeled pursuit drill |
| 2 | Near-Far Cycles (`:11-12`, "trains accommodation") | Accommodative amplitude/facility | Disc that changes *size and softness* at a fixed distance | Weak-mixed (small studies: flippers, Hart chart) | **Does not work** — accommodation demand at a fixed screen distance is constant |
| 3 | Focus Shifting (`:13-14`) | "Focus" between targets | Large saccades + fixation, 1 jump/s, ~10–16° apart | Weak/none for "focus"; saccade-adjacent | **Partially works** as a large-amplitude saccade drill; mislabeled |
| 4 | Saccadic Jumps (`:15-16`) | Saccadic accuracy/speed | Real saccades, ≤15°, one jump per 0.8 s | Mixed (positive hemianopia RCT; small mTBI trials; one industry-funded RCT) | **Partially works** — genuine saccade task; ghost trail and missing head-still rule undermine it |
| 5 | Smooth Pursuit (`:17-18`) | Pursuit gain | True pursuit, ≤~10°/s, fully predictable path | Weak (n=10 lab study; small mTBI series) | **Works as a stimulus**; transfer outside the lab is unproven |
| 6 | Figure-8 Tracking (`:19`) | "Tracking" | Pursuit variant on a lemniscate | None specific | **Harmless**; no unique training target — keep only as a pursuit variant |
| 7 | Peripheral Awareness (`:20-21`) | Peripheral attention / UFOV | Passive 1-Hz flash detection at ~4° eccentricity, no response, no adaptation | **Strong for UFOV-style adaptive training** (ACTIVE trial) — task mismatch | **Partially works** (fixation + attentional engagement); not the protocol that works |
| 8 | Floating Orbs (`:22-23`) | "Relax" | Slow drifting Gabor patches | None | **Not a training exercise** — fine as relaxation if labeled honestly |

Two structural findings apply to all eight (details in §9):

1. **A screen at a fixed distance cannot train vergence or accommodation.** Vergence demand (60 mm PD at 40 cm ≈ 15 prism diopters) and accommodative demand (40 cm = 2.5 D) are set by physical distance. Changing a target's *size, softness, or position on the screen plane* changes neither. Every home protocol that actually works in the literature uses either a real depth change (pencil push-ups, Brock string, near/far charts at 3–6 m) or binocular disparity (anaglyph/stereo targets). Exercises 1–3 as coded are pursuit/fixation drills wearing vergence/accommodation labels.
2. **The protocol layer is missing and the safety layer is partial.** The runner states no viewing distance, no head position ("eyes only, head still"), no stop criteria, and offers doses (30/60/120 s) far below any home-therapy dose in the literature (10–15 min/day, weeks). One real safety issue — photosensitive-epilepsy flash limits — is *passed* by the current code (§9.2), and should be locked in with a test.

---

## 1. Convergence Training

### 1.1 What it targets

Vergence — the disjunctive eye movements that rotate the two eyes inward (convergence) and outward (divergence) to keep a single image at different depths. The clinical target is convergence insufficiency (CI): exodeviation greater at near, reduced positive fusional vergence, remote near point of convergence (NPC), and asthenopic symptoms with near work (Iowa EyeRounds [7]). CI is common in children and young adults; NEI lists blurry/double vision at near, tired eyes, headaches, loss of concentration as core symptoms [4].

### 1.2 Evidence

Grade: **strong** — for office-based vergence/accommodative therapy (OBVAT) in diagnosed CI, delivered by a therapist. Not transferable to a flat screen.

- **CITT 2008 RCT** (n=221 children 9–17; Arch Ophthalmol 126(10):1336–49): successful/improved outcome in **73%** (OBVAT) vs **43%** (home pencil push-ups, HBPP), 33% (home computer vergence + push-ups), 35% (office placebo). OBVAT beat every other arm on CISS symptoms, NPC, and PFV [1].
- **2005 pilot RCT** (n=47, JAMA Ophthalmol/AJO series): symptom score fell 32.1→9.5 with office vision therapy vs 29.3→25.9 with pencil push-ups and 30.7→24.2 with placebo — pencil push-ups alone did not beat placebo [2].
- **Cochrane network meta-analysis** (Scheiman et al. 2020, 12 trials, 1289 participants): office-based therapy ranks first with high certainty; "there was little evidence that pencil or target push-ups … are an effective treatment for convergence insufficiency and in fact, may be no more effective than placebo" [3].
- **CITT-ART** (n=310, 9–14 y): office VT improved NPC (+10.2 cm) and PFV (+14.4 Δ) vs placebo [5], but **did not improve reading or attention** vs placebo, and the CISS symptom difference vs placebo was not significant in the ART sample (OVS 2019/2021 papers [6]) — symptom benefit beyond vergence mechanics is not established.
- **Adults:** CINAPS double-masked RCT (n=50, age 18–32): NPC improved 6.0 vs 3.1 cm (VT vs placebo) [8]. CONCUSS RCT (Br J Sports Med 2026;60(5):340–354): immediate office-based vergence therapy with movement improved concussion-related CI — 79% vs 13% symptom improvement at 6 weeks [9].
- **AAO position** (Esotropia/Exotropia PPP 2022): orthoptic/convergence exercises "may improve fusional control in children or adults with convergence insufficiency and with small- to moderate-angle exodeviations (≤20 PD)" [10]. AAO public guidance names convergence insufficiency as the one condition eye exercises can help [11].
- **Boundary:** eye exercises do **not** change refractive error — no evidence they reduce or eliminate glasses for myopia, hyperopia, astigmatism, or presbyopia (AAO 2017; joint statement 2014) [11].

### 1.3 Correct execution protocol

- **Diagnosis first.** NPC and PFV are clinical measures; the app cannot measure them (§9.5). Therapy targets people with diagnosed CI.
- **Pencil push-ups (canonical home protocol, CITT spec):** pencil with 20/60-size letters at arm's length; keep the letter single and clear; move slowly toward the nose until the target doubles; hold there, refocus until single again; goal is to converge to within 2–3 cm of the brow. Dose in the CITT: **15 min/day, 5 days/week, 12 weeks**, with a log of the closest fused distance [1,12]. Common clinic variants: 3 sets of 20 push-ups daily [13].
- **Suppression check:** a white index card behind the pencil (physiological diplopia awareness) so the user notices if one eye drops out [12].
- **Brock string:** 3 beads on ~20 cm of string, one end at the nose, other end fixed; watch the nearest bead — it must appear single with two strings forming an "X"/"A" behind and in front; work bead by bead toward the nose [7].
- **Dot cards (UK orthoptic practice):** card held at the nose, dots at 6–24 cm; jump fixation dot to dot while keeping single vision; practice hardest near the doubling point [14].
- **Stop criteria:** stop when the image stays double, the effort gives headache/nausea, or one eye suppresses the target; persistent diplopia = see a professional (§9.1).
- Key mechanism note: all of these use *physical* depth. Nothing in the literature supports a flat-screen dot as a convergence stimulus.

### 1.4 How the app's implementation differs

- `exercise_painter.dart:34-37`: the "convergence" path is `y = 0.5 + 0.25(1 − cos 2πt)·sin 2πt` — a **vertical oscillation through screen center**, ±25% of screen height (±~5°), peaking at ~5°/s. The comment on :35 ("toward/away from the nose") is stale: the target never leaves the screen plane and sweeps *above* center half the time.
- The subtitle "Train your eyes to converge and diverge together" (`:10`) and hint "Follow the dot toward the centre and back" (`exercises_screen.dart:32-33`) promise vergence; the drawn stimulus is slow vertical pursuit. No distance, no head rule, no stop rule anywhere in the runner.
- The 8 s loop (`exercises_screen.dart:216`) gives 7.5 sweeps/min — a plausible pursuit pacing, irrelevant for vergence.

### 1.5 Verdict and minimal fix

**Does not work as implemented** (as vergence training). Minimal honest options, cheapest first:

1. **Re-label:** rename to "Vertical Tracking" (a slow, large-amplitude pursuit drill) — zero vergence claims. ~2 string edits.
2. **Metronome mode:** keep the screen as a *timing aid* for a real pencil/Brock-string push-up (e.g., a dot that breathes 4 s out / 4 s in, with instructions to move the physical pencil in sync). This converts the exercise into a home-protocol pacing tool [12].
3. **Anaglyph mode** (larger change): red/cyan stereo targets with true disparity ramping — the mechanism the CITT computer arm approximates [1]. Worth it only with the game's existing asset pipeline.

---

## 2. Near-Far Cycles (accommodation)

### 2.1 What it targets

Accommodation — ciliary-muscle-driven lens power change that keeps near objects sharp. Named targets: accommodative amplitude, facility (cycles/min of ±lens blur recovery), accuracy.

### 2.2 Evidence

Grade: **weak-mixed** — training changes measured accommodative dynamics in small studies, mostly in people with accommodative dysfunction; the effect is lens-based, not display-based.

- Vasudevan, Ciuffreda & Ludlam (Optom Vis Sci 2009, doi 10.1097/OPX.0b013e3181bb44cf): 6 weeks home accommodative training in asymptomatic myopes improved lens-flipper rates (OD 11→16 cpm, OU 8→11 cpm) and **Hart-chart rates 22→33 cpm** [15].
- Accommodative-facility training changed facility rates and the time constants/peak velocity of accommodation in myopes and emmetropes after 3 days (Vision Research 2010, doi 10.1016/j.visres.2010.03.007; n=18) [16].
- Sterner et al. (Doc Ophthalmol 1999, doi 10.1023/a:1002623107251; OPO 2001, PMID 11727875): ±2.00 D flipper training (vs plano sham) increased relative accommodation in children with accommodative dysfunction [17].
- CITT accommodation analysis (Ophthalmology 2011): children with CI + accommodative dysfunction gained +9.9 D amplitude with OBVAT vs +2.2 D placebo [18].
- Cooper 1987 (Am J Optom Physiol Opt, small crossover, n=5): automated facility training reduced asthenopia [19].
- Honest adjacent: for screen fatigue the defensible, evidence-backed behavior is **breaks, not displays** — the 20-20-20 rule (AOA; AAO 2023) [20,21].

### 2.3 Correct execution protocol

- **Real near/far targets.** Near: reading card or screen at **40 cm**. Far: a chart or letter on a wall at **3–6 m** (the AOA 20-20-20 target is 20 ft ≈ 6 m) [20]. Demand change ≈ 2.5 D − 0.17 D ≈ 2.3 D.
- **Rhythm:** shift fixation on a steady beat, clearing the blur at each end before shifting back; clinical Hart-chart work runs at ~20–30 cpm [15]; school-age protocols commonly use holds of ~1–2 s per end (NHS/orthoptic leaflets [14]).
- **Head still, eyes only; screen/room lighting normal; both eyes open** (many sessions are monocular with occlusion in clinic — a phone cannot replicate lens flippers ±2 D).
- **Dose:** minutes per day, integrated into reading time; not a 30 s one-off.
- **Stop:** if blur does not clear within a few seconds, or headache/strain builds (§9.1).

### 2.4 How the app's implementation differs

- `exercise_painter.dart:38-40`: target stays centered; `nearFarPhase` (:89-104) ramps a phase value over a **16 s** loop (`exercises_screen.dart:216`): far hold 4.8 s → approach 3.2 s → near hold 2.4 s → retreat 4.8 s → 0.8 s rest (≈ 3.75 cycles/min vs the ~20–30 cpm Hart-chart pace [15]).
- Radius 1.8% → 30% of the shortest screen side (:221-223) — 0.36°→6°; alpha drops and blur is *simulated* by softening as it "near"s (:233, :242). Size and softness are perceptual cues, not accommodative load: at a fixed 40 cm the ciliary system sits at ~2.5 D the entire session.
- Subtitle "trains accommodation" (`:12`) and hint "small sharp dot is FAR, large soft disc is NEAR" (`exercises_screen.dart:33-35`) describe a distance shift that never happens. Gabor-sphere option (`:229-239`) adds texture, same physics.

### 2.5 Verdict and minimal fix

**Does not work as implemented** — no accommodative demand change. Minimal fix: convert to a **distance-shift driver** — screen target at 40 cm, then an interstitial instruction ("now find the smallest detail in the far room") with a beat timed by the loop; keep the Gabor sphere as the near anchor; drop the "trains accommodation" mechanism claim or keep it *only* with the real-distance protocol (defensible via [15,17]). Alternative honest relabel: "voluntary blur-tolerance practice" with no accommodation claim.

---

## 3. Focus Shifting

### 3.1 What it targets

By name: "jump your focus between widely spaced targets" (`:14`). At a single screen distance, "focus" is accommodation (§2 — unchanged) — what the stimulus actually delivers is **large-amplitude saccades plus fixation stability**. Fixation stability between saccades is a real, trainable component in rehabilitation contexts (e.g., OMT reduced fixation error in mTBI [22]).

### 3.2 Evidence

Grade: **weak** for the named function; saccade/fixation evidence is §4. No trial targets this exact task. Large-amplitude voluntary shifts between near and far (Hart chart) have small-study support [15]; on-screen-only shifts do not test that.

### 3.3 Correct execution protocol

- Two **real** targets at different distances (near 40 cm, far 3–6 m), head still, alternate fixation on a beat, clear each target before jumping.
- If screen-only: treat as saccadic work — two fixed anchor points, head still, jump on the beat; ~1 jump/s is fine; rest if eyes feel strained.
- Stop criteria: as §9.1.

### 3.4 How the app's implementation differs

- `focusShiftPoint` (`exercise_painter.dart:73-83`): 4 diagonal pairs, 8 legs per 8 s loop → **one 1-s jump per second**, alternating endpoints of each diagonal (~0.76 W × 0.68 H apart → up to ~16° chord). Amplitude and cadence are reasonable for a saccade drill.
- Mislabel: "Focus" (`:14`) implies accommodation; hint "Jump your gaze between the far-apart targets" (`exercises_screen.dart:35-36`) is accurate for what is drawn.
- Same teleporting-dot and ghost-trail issues as §4.4 (trail draws up to 1.3 s of prior positions — during 1-s legs, ghosts of the *other* endpoint linger).

### 3.5 Verdict and minimal fix

**Partially works** — as a large-amplitude saccade/fixation drill, not as "focus" training. Minimal fix: rename "Wide Gaze Shifts" and add the head-still line to the hint; optionally offer the distance variant with a far target instruction.

---

## 4. Saccadic Jumps

### 4.1 What it targets

Saccades — fast ballistic gaze shifts; the trainable variables are accuracy (gain), latency, velocity, and the fixation interval between them.

### 4.2 Evidence

Grade: **mixed**. Real effect sizes exist in rehabilitation niches; general training claims are industry-tinged.

- **Hemianopia:** explorative saccade training RCT (Brain 2009, PMID 19171828, n=28, 6 weeks): digit-search RT on the blind side fell 47%, improved search and scene exploration [23]. The 2025 **SEARCH** RCT (161 stroke patients, scanning training vs sham, 30 min × 7 d × 6 weeks, Int J Stroke; PMID 40083185) is the largest recent test; its outcome direction [not re-verified this session] [24]. Cochrane reviews underpin scanning training as a *compensatory* intervention for field loss [24].
- **mTBI:** Thiagarajan & Ciuffreda (Brain Inj 2014;28(7):930-43, n=12 crossover vs placebo): 6 weeks oculomotor training reduced fixational error and raised saccadic gain (p<0.05) [22]; a 2015 pilot showed persistence [25]. DHA TBI consensus statement (2017): "vision therapy is effective for convergence and accommodative dysfunctions. Visual scanning exercises also benefit these patients" [26].
- **General/saccadic dysfunction:** Murray, Hunfalvay et al. (Arch Rehabil Res Transl 2021, doi 10.1016/j.arrct.2021.100126; n=92 RCT): 10 min/day × 5 days of standardized oculomotor training improved saccadic metrics and Neurobehavioral Symptom Inventory scores vs control — **industry-affiliated authors (RightEye)**; treat effect size with caution [27].
- **Honest ceiling:** Barton & Ranalli (Ann Neurol 2020, doi 10.1002/ana.25820): for primary CI the benefit is "plausible and supported by data", but "there is not yet strong evidence of benefit for the post-traumatic variant" [28].

### 4.3 Correct execution protocol

- **Head absolutely still** — the sine qua non of saccade drills; the eyes, not the head, do the work.
- **Targets:** clinically, two fixed targets ~15–30° apart (e.g., two fingers or dots at arm's length, or a wall chart); computerized programs randomize positions. The app's range (0.15–0.85 of the screen = ≤7° horizontal, ≤15° vertical at 40 cm) is inside clinical norms.
- **Cadence:** ~0.5–1.5 jumps/s; **75 jumps/min (one per 0.8 s, `exercise_painter.dart:45-48`)** sits inside that band. Doses in trials: 10–45 min/day, days-to-weeks [22,27]; the app's 30–120 s is a warm-up dose.
- **Feedback:** clinical programs measure gain/latency; the app scores nothing (§9.5) — the user self-judges whether the eye lands on the dot.
- **Stop:** dizziness, headache, blur that does not clear (§9.1).

### 4.4 How the app's implementation differs

- `exercise_painter.dart:43-48`: 10 slots per 8 s loop, pseudo-random x/y — the dot **teleports** (position constant within a slot), which is correct for saccades.
- **Ghost trail contradicts the task:** `paint()` draws 8 trail dots at `progress − i·0.02` (:191-201) — for a teleporting target this smears faded ghosts over the previous jump position(s) for up to ~1.3 s. A faint second "target" invites a corrective saccade back — the opposite of clean fixation. `trailLength` should be 0 for saccadic (and focusShift).
- No head-still instruction: hint "Flick your eyes to each new position" (`exercises_screen.dart:37-38`) never says *keep the head still* — with a phone in hand, users drift their head, converting a saccade drill into head movement.
- No stop rule; no measurement (taps are unused in this exercise type — tap handling exists in the runner but nothing here depends on it).

### 4.5 Verdict and minimal fix

**Partially works.** Genuine saccade stimulus at a sane cadence; undermined by the ghost trail, absent head-still instruction, and no measurement. Minimal fix: `trailLength: 0` for saccadic/focusShift, add "keep your head still" to the hint, and add a simple per-jump self-check beat (e.g., confirm-flash at the target). Optional upgrade: measured two-target mode with score = fraction of on-beat responses.

---

## 5. Smooth Pursuit

### 5.1 What it targets

Smooth-pursuit gain (eye velocity / target velocity) and pursuit maintenance. Normal observers track near-perfectly below ~20–30°/s; gain degrades with age, fatigue, alcohol, and after brain injury (review of clinical interpretation [29]).

### 5.2 Evidence

Grade: **weak** — a small, real lab effect; no clinical-outcome RCT in healthy users.

- Eibenberger, Ring & Haslwanter (Exp Brain Res 2012;218(1):81-9, doi 10.1007/s00221-012-3009-8; n=10): **two 6-min sessions on 3 days** tracking a quasi-randomly moving target produced lasting closed-loop pursuit improvements (re-checked 5 days later) — the only direct "pursuit training" trial identified [30]. Training worked when the "pursuit system … is challenged sufficiently".
- Pursuit deficits after mTBI are common and small-series rehab studies (OMT, n=12) report improvement [22,26]; Barton & Ranalli's review caps the strength of that evidence [28].
- Sports-vision reviews report heterogeneous, mostly small studies of oculomotor training; "moderate support", methodological heterogeneity (Buscemi et al. 2024, doi 10.3390/jfmk9020092) [31].

### 5.3 Correct execution protocol

- **Head still, eyes follow the dot** (a pursuit drill done with head movement trains the neck, not pursuit).
- Target ~0.5° (the app's dot ≈ 0.6°, `exercise_painter.dart:206` — appropriate); speeds under ~20°/s keep gain near 1; **unpredictable or at least non-repeating paths prevent anticipatory pursuit** (predictive tracking deflates the training load; Eibenberger used quasi-random motion [30]).
- Duration: lab sessions of 6–18 min [30]; the app's 30–120 s is short but harmless.
- Stop: if the dot "slips" persistently with diplopia or dizziness (§9.1).

### 5.4 How the app's implementation differs

- `exercise_painter.dart:49-54`: Lissajous x = 0.5 + 0.35 sin(2πt), y = 0.5 + 0.3 sin(4πt) — amplitudes ±3.5° (x) / ±6.4° (y) at 40 cm; peak speeds ~2.8°/s (x) / ~10°/s (y). Speeds are inside pursuit capability — the stimulus is valid but light.
- **Fully periodic:** every 8 s the path repeats identically (`_ctrl.repeat()`, `exercises_screen.dart:346`), so within a minute the user is predicting the path — exactly what pursuit training avoids [30].
- Hint "Keep the dot locked in your gaze as it glides" (`exercises_screen.dart:38-39`) is correct; no head-still line.

### 5.5 Verdict and minimal fix

**Works as a stimulus; benefit unproven.** Minimal fix: add a per-session seed to the path (two or three alternate Lissajous phase sets chosen per launch, or slow phase drift across loops) and add "keep your head still" to the hint.

---

## 6. Figure-8 Tracking

### 6.1 What it targets

By implication: combined tracking + fixation along a large lemniscate — a pursuit variant popular in lay "eye exercise" routines. No vision-science trial targets a figure-8 specifically; no unique ocular mechanism is claimed beyond pursuit.

### 6.2 Evidence

Grade: **none specific**. It inherits whatever pursuit evidence exists (§5.2); figure-8 as such appears only in self-care/Vestibular-community material [not re-verified this session].

### 6.3 Correct execution protocol

Same as pursuit: head still, eyes trace, speeds low (~≤10–15°/s), rest if strained. If used for comfort, pair it with a blink break (§9.1).

### 6.4 How the app's implementation differs

- `exercise_painter.dart:55-62`: lemniscate amplitude 0.35 (same size class as pursuit), one loop per 8 s (7.5 loops/min), fully periodic, ghost trail present (:191-201), no head-still instruction.

### 6.5 Verdict and minimal fix

**Harmless; no unique target.** Minimal fix: keep as a pursuit variant with the §5 fixes (seed variation, head-still hint), or fold into pursuit and drop the menu entry.

---

## 7. Peripheral Awareness

### 7.1 What it targets

Detection/localization of stimuli outside fixation — the everyday "useful field of view" (UFOV). The named mechanism (detect flashes "at the edges without moving your eyes", `:21`) is peripheral attention under fixation.

### 7.2 Evidence

Grade: **strong for the UFOV-style task, weak for this task**.

- **ACTIVE trial** (Ball et al., JAMA 2002;288(18):2271-2281, doi 10.1001/jama.288.18.2271; n=2802 RCT): 10 one-hour sessions of **speed-of-processing training** (identify central object + localize a peripheral target simultaneously, adaptive to 75% accuracy) improved UFOV with durable effects (speed booster 92% at 2 y) [32]; gains persisted at 10 years (Rebok et al. 2014) [33]; speed-of-processing training reduced 10-year dementia risk 29% (Edwards et al. 2017) [34] and was linked to lower 20-year claims-based ADRD diagnosis (Coe et al. 2026, doi 10.1002/trc2.70197) [35].
- The active ingredient is **speeded identification with a response and adaptive timing** — center task + peripheral localization, feedback, difficulty tracking 75% accuracy [32].
- The app's task (passive fixation while a 1-Hz dot blinks at random angles) has no response, no timing pressure, no adaptation — by the ACTIVE logic it exercises fixation, not the trainable UFOV component.
- Eccentricity mismatch: flashes sit at `ringR = 0.42 × width` (`exercise_painter.dart:258`) ≈ **4°** at 40 cm (parafoveal ring); true peripheral awareness (>10°) is physically unreachable on a phone screen held at 40 cm — only by holding the phone very close (≤20 cm, ~7°) or turning to a wall display.

### 7.3 Correct execution protocol

- **UFOV-style (the protocol with evidence):** central judgment ("is the car/triangle pointing left or right?") **simultaneously** with localizing a briefly flashed peripheral target; exposure duration staircases to ~75% correct; ~10 sessions of ~1 h produced durable effects in older adults [32,33]. A mobile mini-version: 30–60 trials of 200–500 ms flashes with a tap on the flashed sector, adaptive duration.
- **Fixation discipline:** eyes never leave the central dot (the app's hint `exercises_screen.dart:40-41` says exactly this — correct).
- **Stop:** dizziness, eye strain, or (rarely) visual discomfort from flashing → stop (§9.2).

### 7.4 How the app's implementation differs

- `_paintPeripheral` (`exercise_painter.dart:254-267`): central dot r=6 (:255); **8 flash slots per 8 s loop** (:256) → one flash per second, **ON for 0.5 s, OFF for 0.5 s** (:263-266); ring radius 0.42×width (:258); flash dot r=8 (:265); random angle per slot (:108-110). No tap is scored; the runner's hint is the only instruction.
- It is a *passive* stimulus: the user can comply perfectly by blinking at the right moments. Nothing is measured (§9.5).

### 7.5 Verdict and minimal fix

**Partially works** (fixation + attentional vigilance practice). Minimal fix that unlocks the literature's mechanism: **response + adaptation** — flash a sector, ask the user to tap one of 8 sectors (or swipe the direction), adapt flash duration/salience to hold ~75% correct, write trials/correct into the existing `Drill` fields. This also fixes the claims problem: then "trains useful-field-of-view-style peripheral processing" is defensible [32]. Eccentricity can never exceed ~10° on a phone — say "near-peripheral", not "edges", in the hint.

---

## 8. Floating Orbs

### 8.1 What it targets

Nothing named in the literature. The subtitle ("relax and follow them", `:23`) and hint ("Relax and let your focus drift", `exercises_screen.dart:42-43`) frame it as relaxation/awareness of slow motion — closest to a motility-relaxation activity.

### 8.2 Evidence

Grade: **none**. No trial of drifting-patch viewing exists. The Gabor patches match the game's stimuli (`maxR = 15% shortest side`, `:273-274`), which supports visual continuity, not ocular training.

### 8.3 Correct execution protocol

Relaxation protocol: comfortable distance (~40 cm), normal blink rate, no fixation demand; follow-or-ignore both acceptable; stop on any discomfort (§9.1).

### 8.4 How the app's implementation differs

- `exercise_painter.dart:271-318`: two antiphase orbs, 24 s cycles (`kOrbCycleSeconds`, `:113`), random waypoints (:117-121), slow rotation, 12% fade in/out. Speeds are far below any pursuit load — by design.
- The only mismatch: the hint's "let your focus drift" implies the eyes gain something — they do not, and the app's own About screen does not claim otherwise.

### 8.5 Verdict and minimal fix

**Not a training exercise; fine as relaxation.** Minimal fix: label it "Relaxation" in the subtitle ("Gabor patches drift and slowly grow — a quiet cool-down") so the list view stops implying training parity with the others.

---

## 9. Safety and honesty

### 9.1 Contraindications and stop rules (should ship as a pre-session screen or in-app text)

**Do not use eye exercises — see an eye-care professional first — if any of these apply:**

- Undiagnosed or untreated **strabismus** or **amblyopia** (lazy eye): self-directed exercises without professional supervision risk suppression and wasted critical-period time (AAO PPP framing [10]; AAPOS guidance [not re-verified this session]).
- **Recent eye surgery or eye injury**, acute red/painful eye, or active retinal disease history — exercise has no place in acute care.
- **Untreated, significant refractive error** (blurry at any distance — the drills will be practiced on a blurry world).
- **Vestibular disorder or vertigo**: eye-drills can provoke dizziness; formal gaze-stabilization (VOR×1/×2) rehab requires head movement and professional titration — the app must not improvise it.
- **Photosensitive epilepsy / seizure disorder**: see §9.2; the current content passes the standards, but users deserve the warning.
- **Acute post-concussion phase**: oculomotor work belongs in return-to-learn protocols guided by a clinician; self-dosing during symptom peaks is not supported [28].

**Stop immediately and rest (and see a professional if it persists):**

- Double vision that does not clear when the exercise ends.
- Headache, nausea, or vertigo during or within hours after a session.
- Eye pain, persistent blur, or one eye "shutting out" of the task.
- Symptoms that keep worsening across sessions.

**Dose honesty:** every home-therapy dose in the literature is minutes per day over weeks (15 min/day × 5 d/wk for push-ups [1,12]; 10 min/day × 5 d for oculomotor training [27]; 10 × 1 h for UFOV [32]). The app's 30/60/120 s single sessions are practice/comfort doses, not therapy doses — say so.

### 9.2 Photosensitive epilepsy — the Peripheral Awareness flash, audited against the standards

**The standards** (they agree):

- **ITU-R BT.1702-3 (2023)** [36]: a "potentially harmful flash" = a pair of opposing luminance changes ≥20 cd/m² (only when the darker state is <160 cd/m²) — and independently, **any transition to/from saturated red** regardless of luminance. A flash *sequence* is impermissible only when **both**: (a) concurrent flash area >25% of screen, **and** (b) **more than 3 flashes per second** (6 luminance changes/s). Successive flashes with leading edges ≥360 ms apart (9 frames at 50 Hz) are acceptable *irrespective of brightness or area*.
- **Epilepsy Foundation consensus** (Epilepsia 2005;46:1423-41, PMID 16146438): hazard = luminance ≥20 cd/m², rate ≥3 Hz, solid angle ≥0.006 sr (~25% of screen); saturated-red rule; pattern rule: >5 light-dark stripe pairs is risky [37].
- **Ofcom/ITC guidance** (2002) [38] and **WCAG 2.3.1** [39] carry the same 3-flashes/s and 20 cd/m² numbers; WCAG's stricter cousin (2.3.3) simply bans >3 flashes/s [40]. The 2024 gap analysis (ACM TACCESS, doi 10.1145/3694790) confirms the family agreement [41].

**The app's parameters** (`_paintPeripheral`, `exercise_painter.dart:254-267`):

- Flash rate: **1 Hz** — leading edges 1000 ms apart. Limit: ≥360 ms separation acceptable, ≤3 flashes/s. **Pass with ~3× margin.**
- Flash area: 16-logical-px dot ≈ 2.4 mm ≈ **0.05% of a 7×15 cm screen** — limit 25% (0.006 sr). **Pass with ~500× margin.**
- Luminance change: a bright dot over near-black bg averages far below 20 cd/m² screen-wide (0.05% area × ~80 cd/m² ≈ 0.04 cd/m² screen-average). **Pass.**
- Red rule: color `0xFF4D9FFF` (R77 G159 B255) — blue; **not** saturated red. **Pass.**

**Verdict: compliant, with a wide margin — keep it that way in code.** Guard rails worth a test/assertion:

1. flash period ≥ 333 ms (never >3 flashes/s) — currently 1000 ms;
2. flash element area < 5% of screen (never full-screen flashes);
3. never use saturated red for flashes (keep the blue family);
4. never add moving stripe/chequerboard patterns with >5 light-dark pairs [37];
5. print a photosensitivity note in the disclaimer (§9.3).

### 9.3 Claims audit (file:line → judgment → replacement)

| File:line | Current claim | Judgment | Defensible replacement |
|-----------|--------------|----------|------------------------|
| `about_screen.dart:95-99` | "Regular short sessions can ease screen fatigue, sharpen focus, and loosen eye strain from long near-work." | **Overstated.** "Sharpen focus" implies visual-acuity/attention gains with no evidence for these drills (AAO 2017 [11]); the fatigue/strain verbs state a therapeutic effect the literature does not support for on-screen exercises. FTC has sanctioned a vision app for exactly this class of claim (Ultimeyes, $150,000, 2015-16 [42]). | "Short sessions of guided eye-movement drills and Gabor-patch games. The drills train eye coordination and tracking; the games practice fine visual discrimination. They are part of a comfortable screen routine — compare the 20-20-20 break rule — and are not a medical treatment." |
| `about_screen.dart:103-105` | "so your brain learns to tell real visual detail apart, not just guess at noise" | **Acceptable with hedge** — perceptual-learning-style claims need an adaptive staircase to be true in the strong sense (companion doc); as written it overstates a "learns" mechanism. | "…so each session practices telling real visual detail apart rather than guessing at noise." |
| `about_screen.dart:113-118` | Disclaimer (training tool, not medical device; symptoms → professional) | **Good — keep.** Add two lines: photosensitivity note (§9.2) and "eye exercises are not a substitute for diagnosis or therapy of convergence insufficiency or any binocular disorder". | — |
| `README.md:3-5` | "Vision training … Visor trains your visual cortex, not just your eyes." | **Overstated** as mechanism ("visual cortex" training is a research claim, not an established outcome of these drills). | "Gabor-patch games and guided eye exercises — stimuli used in vision research, in a game with controlled difficulty." |
| `README.md:11` | Exercise list bullet | **Neutral/factual — keep.** Add one clause: "Eye exercises train eye coordination and comfort routines; they do not change refractive error." | — |
| `LISTING.md` (Description/Long Description) | Describes stimuli, tasks, timers; explicitly avoids efficacy verbs (see the Ukrainian rationale comment at top) | **Model wording — keep.** This is the FTC/Play-safe register [11,42]. | — |
| `TERMS.md:13` | "…does not diagnose, treat, cure, or prevent any eye condition…" | **Good — keep.** | — |

Also worth adding to the About screen: "Exercises are practice sessions, not therapy: published home-therapy programs for diagnosed conditions run 10–15 minutes a day for weeks under professional supervision [1,12,27]."

### 9.4 Special populations

- **Children (9–17):** the population with the best evidence (CITT [1,5,18]) — but only under diagnosis; a school-age user with symptoms should get an exam, not silent exercises. Younger children (<9) have no trial base for self-directed practice.
- **Older adults:** UFOV training has real long-term outcomes [32-34] — but only the adaptive, speeded, response-based version; the app's passive flashes are not that protocol (§7). Presbyopia: exercises do not remove reading glasses (AAO [11]). Avoid any dementia-adjacent marketing; the ACTIVE results are intervention-dose (10 × 1 h) and population-specific [34].
- **mTBI/concussion:** vergence and pursuit dysfunction after mTBI is well documented [26,43]; office-based vergence therapy has RCT support for concussion-related CI [9], while review evidence for post-traumatic oculomotor training remains weak [28]. The app may serve as home reinforcement **if a clinician prescribes it**; add symptom-triggered stop rules (§9.1) and do not market "concussion recovery".
- **Strabismus/amblyopia:** professional care only; suppression checks (Brock string, red/green) are part of clinical protocols precisely because unsupervised binocular drills can entrench suppression [7,10].
- **Not a diagnostic device:** the app measures none of the clinical endpoints (NPC, PFV, facility cpm, UFOV threshold). It must never imply screening or diagnosis — this is also the FTC line Ultimeyes crossed [42].

### 9.5 The measurement gap that makes honesty hard

`drillForExercise` (`training_step.dart:150-166`) records only duration; `Drill.trials/correct/threshold/reversals/score` stay zero (shared finding A3 of the mechanics doc). Consequence: the app *cannot* honestly claim progress on any exercise, because it stores no evidence of it. Two of the three most valuable upgrades (§4.5, §7.5) are therefore also honesty upgrades: give saccadic and peripheral a measured task and persist trials/correct. The other exercises (pursuit, figure-8, orbs) have no natural scoring — label them practice/relaxation rather than pretending a metric exists.

---

## Map to current code (consolidated)

| Concern | Where | State |
|---|---|---|
| Titles/subtitles (mechanism claims) | `exercise_painter.dart:9-27` | convergence/nearFar subtitles name functions the stimulus cannot deliver (§1.4, §2.4) |
| Convergence path | `exercise_painter.dart:34-37` | vertical oscillation ±25% H; stale "nose" comment |
| Near-Far phase & radius | `:89-104`, `:221-223` | 16 s loop, 3.75 cycles/min, size/softness at fixed distance |
| Focus-shift legs | `:73-83` | 1 jump/s over ≤16° diagonals — valid saccade task, wrong name |
| Saccadic slots | `:43-48` | 0.8 s cadence, teleporting dot — valid; range ≤15° |
| Pursuit Lissajous | `:49-54` | ±3.5°/±6.4°, ≤~10°/s, periodic |
| Figure-8 lemniscate | `:55-62` | same class as pursuit |
| Peripheral flashes | `:254-267` | 1 Hz, 0.5 s on/off, ~4° ring, no response — photosafety PASS (§9.2) |
| Ghost trail | `:191-201` (`trailLength` 8) | contradicts saccadic/focusShift; harmless for pursuit |
| Loop timing | `exercises_screen.dart:216` | 8000/16000 ms; all exercises periodic |
| Durations | `exercises_screen.dart:174` | 30/60/120 s — practice dose, below therapy doses |
| Hints | `exercises_screen.dart:31-45` | no head-still rule, no stop criteria, "edges" overstates periphery |
| Wakelock / immersive | `exercises_screen.dart:250,332` | fine; no visual-discomfort issue |
| Records | `training_step.dart:150-166` | duration only; no trials/correct persisted |

## References

1. Convergence Insufficiency Treatment Trial Investigator Group. *Randomized clinical trial of treatments for symptomatic convergence insufficiency in children.* Arch Ophthalmol 2008;126(10):1336-49. doi 10.1001/archopht.126.10.1336. https://pubmed.ncbi.nlm.nih.gov/18852411/ (protocol detail: https://pmc.ncbi.nlm.nih.gov/articles/PMC2782898)
2. Pediatric Eye Disease Investigator Group / CITT pilot. *A randomized clinical trial of treatments for convergence insufficiency in children.* (47 children; VT vs pencil push-ups vs placebo.) https://pubmed.ncbi.nlm.nih.gov/15642806
3. Scheiman M, et al. *Interventions for convergence insufficiency: a network meta-analysis.* Cochrane Database Syst Rev 2020, CD006768. doi 10.1002/14651858.CD006768.pub3. https://pubmed.ncbi.nlm.nih.gov/33263359
4. National Eye Institute. *Convergence Insufficiency.* Updated 2024-12-04. https://www.nei.nih.gov/eye-health-information/eye-conditions-and-diseases/convergence-insufficiency
5. CITT-ART Investigator Group. *Treatment of symptomatic convergence insufficiency in children enrolled in the CITT-ART (secondary clinical outcomes).* Optom Vis Sci 2019;96(11):825-35. doi 10.1097/OPX.0000000000001443. https://pubmed.ncbi.nlm.nih.gov/31651593 (reading: doi 10.1097/OPX.0000000000001442, PMID 31651592; attention: doi 10.1097/OPX.0000000000001659, PMID 33771952; NIH release: https://www.nih.gov/news-events/news-releases/treatment-common-vision-disorder-does-not-improve-childrens-reading-skills)
6. NIH. *Treatment for common vision disorder does not improve children's reading skills.* 2019-10-23. (See [5].)
7. University of Iowa, EyeRounds. *Convergence Insufficiency* (pencil push-ups & Brock string protocols). 2020. https://webeye.ophth.uiowa.edu/eyeforum/cases/198-convergence-insuffic.pdf
8. Thiagarajan P, et al. *Convergence Insufficiency Neuro-mechanism in Adult Population Study RCT: clinical outcome results.* Optom Vis Sci 2020. doi 10.1097/OPX.0000000000001606. https://pubmed.ncbi.nlm.nih.gov/33186192
9. Alvarez TL, Scheiman M, et al. *CONCUSS randomised clinical trial of vergence/accommodative therapy for concussion-related symptomatic convergence insufficiency.* Br J Sports Med 2026;60(5):340-354. doi 10.1136/bjsports-2025-109807. https://pubmed.ncbi.nlm.nih.gov/41033748 (secondary: doi 10.1136/bjsports-2025-111200)
10. American Academy of Ophthalmology. *Esotropia and Exotropia Preferred Practice Pattern®.* Ophthalmology 2022/2023. https://www.aaojournal.org/article/S0161-6420(22)00864-8/fulltext (see "Convergence Exercises for Convergence Insufficiency")
11. American Academy of Ophthalmology. *Vision Training Not Proven to Make Vision Sharper.* 2017-07-26. https://www.aao.org/eye-health/tips-prevention/vision-training-not-proven-to-make-vision-sharper (joint statement: https://www.aao.org/clinical-statement/joint-statement-learning-disabilities-dyslexia-vis)
12. CITT. *Home-based pencil push-ups procedure* (in [1], Methods; 15 min/day, 5 days/week, 2–3 cm of brow, suppression check).
13. Cho YA, et al. *Comparison of alternate part-time patching and pencil push-up training for intermittent exotropia* (3 sets × 20 push-ups/day protocol). 2022. https://pmc.ncbi.nlm.nih.gov/articles/PMC9706999
14. Wrightington, Wigan and Leigh NHS Trust. *Home Exercises to Improve Convergence Insufficiency* (pen/dot-card protocol). Orth 013, 2019. https://www.wwl.nhs.uk/media/.leaflets/5fdb426abc4b08.13496553.pdf
15. Vasudevan B, Ciuffreda KJ, Ludlam DP. *Accommodative training to reduce nearwork-induced transient myopia.* Optom Vis Sci 2009. doi 10.1097/OPX.0b013e3181bb44cf. https://pubmed.ncbi.nlm.nih.gov/19786929
16. [Authors not re-verified this session.] *Changes in dynamics of accommodation after accommodative facility training in myopes and emmetropes.* Vision Research 2010;50(10):947-55. doi 10.1016/j.visres.2010.03.007. https://pubmed.ncbi.nlm.nih.gov/20304003
17. Sterner B, Abrahamsson M, Sjöstrand J. *Accommodative facility training with a long term follow up…* Doc Ophthalmol 1999;99(1):93-101. doi 10.1023/a:1002623107251 (https://pubmed.ncbi.nlm.nih.gov/10947012); flipper-vs-sham comparison: Ophthalmic Physiol Opt 2001, PMID 11727875 (https://pubmed.ncbi.nlm.nih.gov/11727875/)
18. CITT Investigator Group. *Treatment of accommodative dysfunction in children: results from a randomized clinical trial.* Ophthalmology 2011. https://pubmed.ncbi.nlm.nih.gov/21873922
19. Cooper J, et al. *Reduction of Asthenopia after Accommodative Facility Training.* Am J Optom Physiol Opt 1987;64(6). doi 10.1002/j.2330-9512.1987.tb01338.x
20. American Optometric Association. *Computer vision syndrome / 20-20-20 rule.* https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome
21. American Academy of Ophthalmology. *Eye Strain and Sleepy Eyes.* 2023-05-05. https://www.aao.org/eye-health/diseases/what-is-eye-strain
22. Thiagarajan P, Ciuffreda KJ. *Versional eye tracking in mild traumatic brain injury (mTBI): effects of oculomotor training (OMT).* Brain Inj 2014;28(7):930-43. https://pubmed.ncbi.nlm.nih.gov/24826956 (vergence OMT: doi 10.1097/OPX.0000000000000015? — see https://pubmed.ncbi.nlm.nih.gov/24458963)
23. [Authors not re-verified this session.] *Comparing explorative saccade and flicker training in hemianopia: a randomized controlled study.* Brain 2009. https://pubmed.ncbi.nlm.nih.gov/19171828 [DOI not re-verified this session]
24. *A randomized controlled trial of Scanning Eye trAining as a Rehabilitation Choice for Hemianopia after stroke (SEARCH).* Int J Stroke 2025;20(8):968-976. https://pubmed.ncbi.nlm.nih.gov/40083185 [result direction not re-verified this session]
25. Thiagarajan P, et al. *Short-term persistence of oculomotor rehabilitative changes in mTBI.* Brain Inj 2015;29(12):1475-9. doi 10.3109/02699052.2015.1070905. https://pubmed.ncbi.nlm.nih.gov/26308101
26. Defense Health Agency. *Vision Rehabilitation Following Traumatic Brain Injury: TBI Consensus Statement Project 2017.* 2018. https://blastinjuryresearch.health.mil/assets/docs/reset/fy17/vision_rehab/Vision_Rehabilitation_Following_TBI.pdf
27. Hunfalvay G, Murray N, et al. *Oculomotor Training for Poor Saccades Improves Functional Vision Scores and Neurobehavioral Symptoms.* Arch Rehabil Res Transl 2021. doi 10.1016/j.arrct.2021.100126. https://pmc.ncbi.nlm.nih.gov/articles/PMC8212010 [author affiliations include RightEye LLC — industry-funded]
28. Barton JJS, Ranalli PJ. *Vision Therapy: Ocular Motor Training in Mild Traumatic Brain Injury.* Ann Neurol 2020;88(3):453-461. doi 10.1002/ana.25820. https://pubmed.ncbi.nlm.nih.gov/32542907/
29. *Recording and interpretation of ocular movements: saccades, smooth pursuit, and optokinetic nystagmus.* Clinical review, 2023. https://www.e-acn.org/journal/view.php?number=642 [not re-verified this session]
30. Eibenberger K, Ring M, Haslwanter T. *Sustained effects for training of smooth pursuit plasticity.* Exp Brain Res 2012;218(1):81-9. doi 10.1007/s00221-012-3009-8. https://pubmed.ncbi.nlm.nih.gov/22349496
31. Buscemi A, et al. *Role of Sport Vision in Performance: Systematic Review.* J Funct Morphol Kinesiol 2024;9(2):92. doi 10.3390/jfmk9020092. https://pmc.ncbi.nlm.nih.gov/articles/PMC11204951
32. Ball K, Berch DB, Helmers KF, et al. *Effects of cognitive training interventions with older adults: a randomized controlled trial (ACTIVE).* JAMA 2002;288(18):2271-2281. doi 10.1001/jama.288.18.2271
33. Rebok GW, et al. *Ten-year effects of the ACTIVE cognitive training trial.* Psychol Sci 2014. https://sls.psychiatry.uw.edu/wp-content/uploads/2020/03/Rebok-Ten-year-effects-of-ACTIVE.pdf
34. Edwards JD, et al. *Speed of processing training results in lower risk of dementia (ACTIVE 10-year).* Alzheimer's & Dementia (TRCI) 2017. https://pmc.ncbi.nlm.nih.gov/articles/PMC5700828
35. Coe NB, et al. *Impact of cognitive training on claims-based diagnosed dementia over 20 years: evidence from the ACTIVE study.* Alzheimers Dement (TRCI) 2026. doi 10.1002/trc2.70197. https://pubmed.ncbi.nlm.nih.gov/41669119
36. ITU-R. *Recommendation BT.1702-3: Guidance for the reduction of photosensitive epileptic seizures caused by television.* 2023-11. https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.1702-3-202311-I!!PDF-E.pdf
37. Epilepsy Foundation of America Working Group. *Photic- and pattern-induced seizures: expert consensus.* Epilepsia 2005;46(9):1423-41. https://pubmed.ncbi.nlm.nih.gov/16146438
38. Ofcom/ITC. *Guidance Note for Licensees on Flashing Images and Regular Patterns in Television.* 2002. https://www.ofcom.org.uk/__data/assets/pdf_file/0021/16248/gn_flash.pdf
39. W3C. *Understanding Success Criterion 2.3.1: Three Flashes or Below Threshold (WCAG 2.2).* https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html
40. W3C. *Understanding Success Criterion 2.3.3: Animation from Interactions (stricter, optional SC).* https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html
41. *International Guidelines for Photosensitive Epilepsy: Gap Analysis and Recommendations.* ACM Trans Access Comput 2024. doi 10.1145/3694790. https://dl.acm.org/doi/full/10.1145/3694790
42. Federal Trade Commission. *FTC Charges Marketers of 'Vision Improvement' App (Ultimeyes) With Deceptive Claims.* 2015-09-17 (final order 2016-02-23, $150,000). https://www.ftc.gov/news-events/news/press-releases/2015/09/ftc-charges-marketers-vision-improvement-app-deceptive-claims
43. Thiagarajan P, Ciuffreda KJ, Ludlam DP. *Vergence dysfunction in mild traumatic brain injury (mTBI): a review.* Ophthalmic Physiol Opt 2011;31(5):456-468. doi 10.1111/j.1475-1313.2011.00831.x
44. EyeWiki (AAO). *Convergence Insufficiency.* Updated 2026-10-01. https://eyewiki.org/Convergence_Insufficiency

Items marked "[not re-verified this session]" come from search-result snippets only; verify the DOI/abstract before quoting them verbatim in marketing copy.
