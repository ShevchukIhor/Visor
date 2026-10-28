# RESEARCH: Interaction Models for the Six "Game" Exercises

Date: 2026-10-28
Question: For each of Contrast Sensitivity, Color Vision, Depth Perception, Visual Search, Motion Detection, and Visual Memory — what should the user actually do, what makes the interaction an effective *training* exercise, and what does the vision-science literature support?

---

## 0. Executive summary

| # | Exercise | Current interaction | Verdict | Evidence-based interaction |
|---|----------|--------------------|---------|---------------------------|
| 1 | Contrast Sensitivity | "Tap when target becomes visible" | **Wrong** — yes/no detection is bias-prone and the app scores *every* tap as correct (`exercises_screen.dart:357-360`), so nothing is measured | Temporal or spatial **2AFC** ("which of these two intervals/locations contained the patch?") with an **adaptive staircase** on contrast |
| 2 | Color Vision | "Tap the unique color among similar hues" | **Half right** — odd-one-out is a valid paradigm (pseudoisochromatic-plate analog), but scoring is broken (`correct = tap near screen center`, line 361-366) and no luminance noise means the task is not really chromatic | **4AFC odd-one-out** with patches of *randomized luminance and size* (Stilling's principle), staircase on chromatic distance from a gray base |
| 3 | Depth Perception | "Tap which object is closer" | **Question right, stimulus wrong** — "which is closer" is exactly the clinical question (Howard-Dolman), but the correct answer sits at a *fixed screen position* every trial (line 367-372) and a flat screen carries no binocular disparity at all | **2AFC with randomized positions**; best: random-dot **anaglyph** (red-green glasses) stimulus; without glasses: monocular-cue discrimination with cues explicitly counter-balanced |
| 4 | Visual Search | "Tap the target among distractors" | **Mostly right** — tap-the-target is the standard; but the 5×5 grid and single-feature (square vs circle) pop-out make it near-effortless, and difficulty never adapts | Keep tap-the-target; make it **UFOV-style**: simultaneous center identification + peripheral localization, **adaptive timing/eccentricity/set size**, conjunction targets |
| 5 | Motion Detection | "Tap when motion appears" | **Wrong** — the target moves 100% of the time (no catch trials), so "tap when it appears" is an instruction to a task that never has a "when" | **Random-dot kinematogram (RDK)** with variable **coherence**, 2AFC direction judgment ("left or right?"), staircase on coherence % |
| 6 | Visual Memory | "Tap to recall pattern" | **Wrong** — dots are always on screen, tap is always scored correct (line 388-391); nothing is stored, nothing is recalled | **Change detection / change localization**: brief memory array → blank delay → test array; user taps **the changed cell** (localization beats yes/no: bias-free, reliability 0.77) |

Two structural findings that apply to all six:

1. **Forced choice, not detection taps.** The single most repeated finding in psychophysics: yes/no detection ("tap when you see it") conflates *sensitivity* with *response criterion*; a forced-choice task forces every observer onto the same criterion, so percentage correct is a bias-resistant sensitivity measure (Green & Swets, *Signal Detection Theory and Psychophysics*, 1966; see also the SDT chapter in *Vision Research: A Practical Guide to Laboratory Methods* — d′ from 2AFC = √2·Z(pc)). "Tap when it becomes visible" can be gamed or under-reported by the same person on different days; "left or right?" cannot.
2. **The training variable must be adaptive and it must be the stimulus dimension itself.** Every successful protocol in the literature holds the *task* fixed and staircases the *stimulus*: contrast (Zhou/Huang et al. PNAS 2004; Li, Levi et al.), chromatic distance (Regan, Reffin & Mollon 1994), disparity (IOVS 2014 stereo training), motion coherence (Law & Gold 2008), display duration (UFOV, Ball et al. 2002). Difficulty targeting **~75–80% correct** (the 3-down/1-up staircase converges to 79.4%; Levitt 1971) is the effective zone — too easy trains nothing, too hard causes guessing and dropout. The app's three "always correct" exercises cannot adapt difficulty at all, because they never measure.

---

## 1. Contrast Sensitivity

### 1.1 What the user should do

**Temporal 2AFC (the lab standard):** Fixation cross. Two brief stimulus intervals are marked, e.g., by four peripheral cross-hairs lighting up. A Gabor patch (or the app's existing patch) appears in *one* of the two intervals for a very short window (30 ms in Li et al. 2009; 200 ms in IOVS 2014 training). The user presses/taps **"first" or "second"** — a pure forced choice, no "I didn't see it" option.

**Spatial 2AFC (mobile-friendly variant):** Two candidate locations (e.g., left/right panel or two grid cells); exactly one contains a low-contrast patch; tap the one with the patch. The app's existing `game_screen.dart` ("find the matching patch" among distractors) is architecturally already this task — a single-interval detection-with-flankers forced choice — and is closer to the literature than the current Contrast exercise.

### 1.2 Why this is the right interaction

- **Bias resistance.** Yes/no detection lets the observer trade hits for false alarms by moving their criterion; percent-correct in 2AFC maps directly onto signal-detection d′ with no criterion term (Green & Swets 1966; Simpson & Fitter 1973). The SDT literature explicitly recommends 2AFC when you want sensitivity alone: "2AFC detection of 0.76 is often used to define threshold" and its measurement variability was *less than half* that of method-of-adjustment (Higgins et al. 1984, cited in the NCBI SDT appendix).
- **The staircase is the training engine.** 3-down/1-up with 0.05–0.1 log-unit steps converges at 79.4% correct and is the canonical rule (Levitt 1971; used in Zhou et al. PNAS 2004 with 0.1 log steps; Li et al. 2009 with 0.1 log steps; IOVS 2013 TPE protocol with QUEST). Each session's geometric-mean threshold of the final reversals *is* the progress metric — the app can chart log-contrast-threshold per session.
- **The task must be discriminating, not just detecting.** Zhou et al. (PNAS 2016, doi 10.1073/pnas.1524160113) trained direction *change* judgments; IOVS 2014 trained "which Gabor had higher contrast" judgments; several groups note contrast *discrimination* (two visible patches) trains where pure detection does not (Yu, Klein & Levi 2004 JOV found flanker-free learning, but contrast specificity/roving effects show the task structure matters).
- **Feedback.** Auditory feedback on errors is standard in these protocols (IOVS 2014: "Auditory feedback was given on incorrect responses").

### 1.3 Evidence that training works

- **Perceptual learning in amblyopia improves CSF and acuity.** Zhou, Huang et al. (PNAS 2004, doi 10.1073/pnas.0401200101, "Improving vision in adult amblyopia by perceptual learning"): Gabor contrast-detection training with 3-down/1-up staircase; "Contrast-detection thresholds were measured with a one-up/three-down staircase (with steps of 0.1 log units)". Companion group study (PubMed 16153674, "Perceptual learning improves contrast sensitivity and visual acuity in adults with anisometropic amblyopia"): 23 amblyopes, grating detection near cutoff SF, improvements generalized to fellow eye, **~90% retention at 1 year**.
- **Review:** Levi & Li, "Perceptual learning as a potential treatment for amblyopia" (Vision Research 2009, PMC2764839).
- **Even normal adults improve via game-based training.** Li, Polat, Makous & Bavelier, "Enhancing the contrast sensitivity function through action video game training," *Nature Neuroscience* 12(7):843–848 (2009), doi 10.1038/nn.2296: CSF measured with temporal 2AFC, 3-up/1-down staircase to 79%; 50 h of action-game training produced a **43–58% contrast-sensitivity improvement** at mid/high spatial frequencies vs. a non-action game control — a causal effect, retained months later.
- **Specificity/transfer caveat (design guidance):** learning is tuned to spatial frequency, orientation, retinal location, and contrast (Yu, Klein & Levi 2004 JOV); training-plus-exposure protocols recover broad transfer (IOVS 2014, doi 10.1167/iovs.13-13739 — 1.5–1.6 lines acuity gain, 53% stereoacuity gain). Practical consequence: **interleave multiple spatial frequencies/orientations per session** rather than fixing one, or rotate them across days.

### 1.4 Concrete spec for the app

```
Trial: fixation 400 ms → interval 1 (blank or patch) → ISI 500 ms → interval 2 →
       tap "Interval 1" / "Interval 2" (two large buttons at screen bottom)
Stimulus: one Gabor patch, orientation fixed per block, SF stepped per block
          (e.g., 1 / 2 / 4 / 8 cpd blocks interleaved)
Adaptive variable: Michelson contrast, 3-down/1-up, 0.1 log-unit steps
Session: ~40–60 trials (~8–10 min); threshold = geometric mean of last 4–6 reversals
Feedback: tone on error; correctness never affects contrast (staircase handles it)
Anti-cue: randomize which interval is 'signal' 50/50
```

---

## 2. Color Vision

### 2.1 What the user should do

**4AFC odd-one-out with pseudoisochromatic noise** is both the classic plate format and the validated computer format:

- The Cambridge Colour Test family (Mollon & Reffin 1989; Regan, Reffin & Mollon 1994) presents a **Landolt C** built from circles of *randomly varying size and luminance*; the C is defined by **chromaticity alone**; the subject presses one of **four buttons** for the gap's orientation. The handbook specifies a **3-second response window** and a staircase along the protan/deutan/tritan confusion lines in CIE u′v′ space.
- A validated mobile-analog task is the **4AFC "identify the differently colored circle"** task used in the color-discrimination training literature (Sci Rep 2024, doi 10.1038/s41598-024-60283-4): several circles share a base hue; one differs along the L-M or S axis; the observer taps the odd one; color difference is adjusted by PSI adaptive staircase.

So the current description ("tap the unique color among similar hues") names the right paradigm — **but only if luminance and size are randomized per patch**. Without luminance noise, the task is solvable by brightness/contrast differences, not color vision, and training gains measure contrast detection, not chromatic discrimination.

### 2.2 Why this is the right interaction

- **Pseudoisochromatic principle (Stilling, 1883 → Ishihara, 1917):** make the target and background differ in hue while *randomly varying luminance and patch size*, so luminance channels cannot solve the task. This is what makes the exercise *about color*.
- **Chibret's principle (dynamic thresholding):** the chromatic difference is adapted by staircase along defined axes of color space (protan / deutan / tritan confusion lines), giving a quantitative threshold rather than a pass/fail plate reading (Mollon & Reffin 1989; Regan et al. 1994, *Vision Research* 34(10):1279–1299).
- **Forced choice:** the Landolt-C orientation response or the "which circle differs" tap is a forced choice — no "not sure" escape hatch, hence criterion-stable.
- **Short response window** (3 s in the CCT) keeps trial count high and prevents unbounded deliberation strategies.

### 2.3 Evidence that training works (and its limits)

- **Chromatic perceptual learning is real but narrow.** Sowden et al. (2011, "Chromatic perceptual learning"): 10-day training on chromatic edge-orientation discrimination improved thresholds — **no transfer to other hues or retinal locations**. Frontiers in Psychology 2016 (doi 10.3389/fpsyg.2016.00731): thresholds reduced after training; improvements stayed within the trained hue.
- **Sci Rep 2024** (doi 10.1038/s41598-024-60283-4): five sessions of 200–300 trials, 4AFC odd-one-out, PSI staircase — thresholds decreased, but training *distorted* unique hues and category boundaries near the trained color. Training works; design for it (rotate trained hues across days rather than always training one hue).
- **Clinical arrangement tests confirm practice effects exist:** Farnsworth-Munsell 100-hue scores improve over repetitions, driven largely by *cognitive/test-taking strategy* rather than retina (Aspinall et al., *Appl. Opt.* 27:1038, 1988, "Influence of serial practice on Farnsworth-Munsell 100-hue scores: the learning effect"). Consequence: an arrangement-style task (drag-to-order, D-15/100-hue analog) is a legitimate alternative interaction, but a large part of its learning is task familiarity — the odd-one-out + staircase measures perception more cleanly.

### 2.4 Concrete spec for the app

```
Trial: grid of 4 large circles (2×2 or 4 in a row), identical base color.
       Every circle: random luminance jitter (±ΔL), random diameter jitter
       (Stilling's principle). Exactly one differs in hue along a confusion axis.
User: taps the odd circle (4AFC). 3 s response window.
Adaptive variable: chromatic distance from base in CIE u′v′ (or approximated in
       the app's color space); 3-down/1-up staircase; interleave protan/deutan/
       tritan axes; rotate base hues between sessions.
Score: threshold chromatic distance per axis.
```

Fallback if full u′v′ math is too heavy: odd-one-out where distractors differ from base by small random luminance and the target differs by hue only — and *validate* it by checking that a grayscale mode (target removed) yields near-chance performance.

---

## 3. Depth Perception

### 3.1 What the user should do

**"Which of the two is closer?" is the historically correct question** — the Howard-Dolman apparatus has the observer state which of two vertical needles is nearer, and stereoacuity is the smallest separation they can reliably resolve (measured in arc seconds; normal ≈ 20–40″). Modern psychophysics uses the identical 2AFC: two dots with opposite disparities, "was the left or right dot closer in depth?" answered with a button, disparity swept and thresholds fit by probit/cumulative-Gaussian (Deas & Wilcox, *PLOS ONE* 2016, doi 10.1371/journal.pone.0165932).

But on a **flat phone screen the stimulus carries no binocular disparity**, so what the current version trains is *monocular* cue use — and right now it doesn't even do that honestly, because the correct answer is a fixed screen coordinate (`closePos = Offset(0.35, 0.65)`) that any user learns within 5 trials. The interaction model needs three repairs:

1. **Randomize** which side holds the near object, every trial.
2. **Decide what depth signal you are training** and make everything else in the stimulus noise-free or cue-controlled:
   - **Without glasses (monocular cues):** the near object differs in *size*, *occlusion*, or *shading*; equalize all other cues (same position distance from center, same color); the judgment is about the cue, positions random.
   - **With red-green glasses (anaglyph, the practical mobile route):** render the two objects/panels as red-green anaglyphs with opposite disparities — this is literally the protocol used in the stereo-training literature on ordinary monitors (IOVS 2014 stereo training: red–green anaglyph glasses, 100 cm viewing distance; recovery-of-stereo studies used red/blue anaglyph, PMC2935377).
   - **Random-dot version (gold standard, both glasses modes):** a random-dot stereogram in which one textured square pops out in depth — no monocular shape cue exists by construction (Julesz, *Foundations of Cyclopean Perception*, 1971; TNO/Lang random-dot clinical tests are the clinical incarnation: "Lack monocular cues therefore this is the most favoured test").
3. **Keep the forced choice** ("left or right?" / "top or bottom?") and **staircase the disparity** (or the monocular cue magnitude) so the exercise has a threshold.

### 3.2 Why this trains anything

- **Stereo training has direct causal evidence.** "Perceptual Learning Improves Stereoacuity in Amblyopia" (*IOVS* 2014, doi 10.1167/iovs.13-12627): 11 adult amblyopes, 10–13 sessions of red-green anaglyph texture judgments, one texture at zero disparity vs. one with crossed/uncrossed disparity, respond "which texture is nearer" with up/down keys, tone on correct — **stereoacuity 200.3″ → 81.6″**, Titmus-measured, 59% improvement, partially retained at 5 months, and acuity also improved ~0.9 lines.
- **Home random-dot video game training works.** "A Random Dot Computer Video Game Improves Stereopsis" (*Optometry & Vision Science* 2018, doi 10.1097/opx.0000000000001222): 32 stereo-deficient children, home perceptual-learning program with RDS, stereoscopic demand increased adaptively until lowest detectable disparity — **median 50% stereoacuity improvement** on the Randot Preschool test vs. 0% in the constant-demand comparison group; stable at 6 months. This is the closest published analog to what a phone app should do.
- **Normal adults can be trained too:** Gabor-target stereo depth training in normal-vision observers improved thresholds 64%, with substantial transfer across carrier orientation and spatial frequency (IOVS ARVO 2013, "Enhancing stereoacuity through perceptual learning in normal vision").
- Astle, Blundell & McGraw ("Recovery of stereo acuity in adults with amblyopia", *Vision Research* 2013, PubMed 22707543): 9 days of random-dot depth detection restored normal stereoacuity in two adult amblyopes.

### 3.3 Concrete spec for the app

```
Mode A (no glasses — monocular-cue trainer, honest about what it trains):
  Two squares, random left/right (or upper/lower) placement, jittered distance
  from center. Exactly one carries the nearness cue: larger size, or occludes a
  background line, or has top-left shading. Staircase the cue magnitude
  (e.g., size ratio → 1.0). 2AFC: tap the nearer square. Fixed trials/level.

Mode B (red-green glasses — true stereopsis trainer; the evidence-backed one):
  Random-dot canvas, two textured panels, one at zero disparity, one shifted
  (crossed or uncrossed, randomized). Tap the panel that pops out. Staircase on
  disparity; report stereoacuity-like threshold in arc-equivalent units given
  the instructed viewing distance. Tone on correct.
```

Keep the instruction to fix viewing distance — disparity thresholds are meaningless without it (the CCT and stereo protocols both fix distance for exactly this reason).

---

## 4. Visual Search

### 4.1 What the user should do

**Keep tap-the-target.** That is the standard in both the cognitive literature (Treisman & Gelade, *Cognitive Psychology* 12:97–136, 1980 — feature-integration theory; conjunction search is the trained regime) and the *only* vision-training family with RCT evidence for real-world transfer:

**UFOV / speed-of-processing training (Ball et al.):** each trial shows a central target to identify *and* a peripheral target to localize; distractors may surround the peripheral target; display duration shrinks adaptively. The user **taps/touches the peripheral target's location** (the PC-touch version has test–retest reliability 0.74; Edwards et al. 2006).

### 4.2 What is wrong with the current version

- The 5×5 grid is fixed and the target slot is a deterministic function of progress (`targetSlot = progress * 25`), so the layout is predictable within seconds.
- Target = square vs. distractor = circle, one feature axis: this is **feature search**, which is parallel and near-zero effort (Treisman & Gelade 1980; Wolfe, *Guided Search 2.0*, Perception & Psychophysics 55:339–353, 1994). Training value lives in **conjunction search** (color × shape × orientation must be *bound*) and in divided attention, not in pop-out.
- No timing pressure and no adaptation: UFOV's entire effect is built on **decreasing display duration and increasing eccentricity/complexity** while keeping performance near 75% correct.

### 4.3 Evidence that training works (the strongest evidence of the six)

- **ACTIVE RCT** (Ball et al., *JAMA* 288(18):2271–2281, 2002): n=2,832 older adults; speed-of-processing training — "visual search skills and the ability to identify and locate visual information quickly in a divided-attention format... task difficulty was manipulated by decreasing the duration of the stimuli, adding distraction, increasing the number of concurrent tasks, or presenting targets over a wider spatial expanse" — largest and most durable effect of the three ACTIVE arms.
- **10-year durability and real-world transfer:** Willis et al. 2006 (JAMA) five-year follow-up; Ball et al. 2010 — training cut at-fault crash risk in half over 6 years; Roenker et al. 2003 — 277 ms faster sign responses on-road.
- **Meta-analysis** (*Neuroscience & Biobehavioral Reviews*, 2017, doi 10.1016/j.neubiorev.2017.11.004; companion report doi 10.1093/geroni/igy023.2532): UFOV-type training vs. control, **d = 0.71** on the trained outcome; **adaptive training d = 0.89 vs. non-adaptive d ≈ 0** — the adaptation mechanism is not optional, it is the active ingredient.
- **Underlying task taxonomy:** UFOV subtest structure — (1) central identification, (2) + peripheral localization, (3) + distractors, (4) simultaneous discrimination + localization; threshold = display duration at **75% correct**, double-staircase (Edwards & Madden descriptions in PMC3947605).

### 4.4 Concrete spec for the app

```
Trial: small task at center (e.g., "was the center letter/symbol X or Y?")
       simultaneously a peripheral target appears at radius r (8–12 radial slots)
       among distractor shapes. Timer shows it briefly (ms).
User: (1) taps the center-task answer button, then (2) taps the peripheral
       target's location.
Adaptive: display duration shrinks with success (staircase to ~75% correct);
       eccentricity and distractor count grow; targets advance from feature to
       conjunction definition.
Score: threshold duration per session (the UFOV metric), plus accuracy/RT.
```

---

## 5. Motion Detection

### 5.1 What the user should do

**Random-dot kinematogram (RDK) direction discrimination.** A field of dots flickers; a fraction (coherence c) moves in a common direction while the rest move randomly. The user answers a **forced-choice direction question** — typically "left or right?" (2AFC), "clockwise or counterclockwise?" (relative to a reference, the Lu et al. 2007 / PNAS 2016 format), or 4-way (Newsome's up/down). Coherence is staircased. This — not "tap when motion appears" — is the paradigm the entire MT/motion-perception literature is built on:

- Newsome & Paré, *J. Neuroscience* 8(6):2201–2211 (1988): "a dynamic random dot display that permitted us to vary the intensity of a motion signal in the midst of masking motion noise... The goal was to determine the threshold correlation for which the subject could reliably discriminate upward from downward motion." MT lesions selectively elevate these thresholds — i.e., the RDK coherence threshold is the accepted behavioral index of the motion system.
- Britten, Newsome, Shadlen et al. 1992 (J Neurosci, "The Analysis of Visual Motion: A Comparison of Neuronal and Psychophysical Performance") — the standard psychometric analysis of the same task.

### 5.2 Why the current "tap when motion appears" cannot train anything

- There is no "when": the app's motion target moves for the entire exercise (`exercisePath` returns a moving point on every frame; the trail confirms it). A detection task with 100% signal on every trial measures reaction time at best, and the tap is scored correct regardless (line 384-386).
- No signal manipulation → no staircase → no threshold → no progress curve.
- "Motion appears" tasks in the literature (simple visual motion onset detection) are used as *measures*, and even then with catch trials; they are not used as training, and they carry the same criterion bias problem as all yes/no tasks.

### 5.3 Evidence that training works

- **Motion direction-discrimination learning is real and has known limits.** Lu et al., "Motion perceptual learning: When only task-relevant information is learned" (*JOV* 7(10):14, 2007, doi 10.1167/7.10.14): 8 days of training; **direction-discrimination trainees improved both discrimination and detection**; detection-only trainees improved only detection. Design consequence: train the *direction judgment*, and detection gains come for free — the reverse is not true.
- **Large threshold gains with task-relevant training:** Law & Gold (J Neurosci 2008, PMC2424192, "Neural correlates of perceptual learning in a sensory-motor, but not a sensory, cortical area"): monkeys trained on RDK direction choice improved coherence thresholds from **~67% to ~15% coherence** over months of daily sessions.
- **QUEST-staircased direction-change training in humans:** PNAS 2016 (doi 10.1073/pnas.1524160113) — two sequential RDKs, 2AFC "clockwise or counterclockwise change?", QUEST staircase, five daily sessions at 9° eccentricity, with measurable cortical reorganization.
- **Broader visual gains:** action-video-game players show enhanced motion processing (Hutchinson & Stocks 2013; reviewed in Green, Gorman & Bavelier, "Action video-game training and its effects on perception and attentional control") — relevant context, but the RDK staircase is the protocol a phone app can implement faithfully.

### 5.4 Concrete spec for the app

```
Trial: fixation dot; aperture with ~50–100 dots, each dot lives a few frames and
       respawns randomly; coherence c of dots share a displacement vector
       (direction = one of 2 or 4); duration ~1 s.
User: taps "LEFT"/"RIGHT" (or taps one of 2/4 direction buttons).
Adaptive variable: coherence c, 3-down/1-up staircase.
Score: threshold coherence % per session (normal young adults ≈ 5–10%).
Optional harder arm: fixed high coherence, staircase on direction angle
       (clockwise/counterclockwise relative to reference) — the Lu et al. format.
```

---

## 6. Visual Memory

### 6.1 What the user should do

**Change detection / change localization** (Phillips 1974; Luck & Vogel, *Nature* 390:279–281, 1997):

1. **Memory array:** grid of colored/filled cells shown 100–500 ms.
2. **Blank retention interval:** ~900 ms (the display goes empty — this is the part the current app is missing entirely; its dots never disappear, so nothing is ever remembered).
3. **Test array:** identical, or one cell changed.
4. **Response — two validated formats:**
   - *Whole-display recognition:* "Did anything change? — same / different" (2AFC).
   - *Change localization:* a change is **always** present; the user **taps the cell that changed**. This is the better training response: it forces spatially-indexed memory, cannot be gamed by a "always say changed" strategy, and has excellent psychometrics — a 10-minute change-localization task had **test–retest reliability 0.77** over 1.5 years and predicts ~43% of fluid-intelligence individual differences (Adam, Vogel et al., "Visual Working Memory Capacity: From Psychophysics and Neurobiology to Individual Differences", PMC3729738).
5. **Score with Cowan's K:** K = set size × (hit rate − false alarm rate) — from the change-detection canon (Rouder et al., "How to measure working memory capacity in the change detection paradigm", *Psychonomic Bulletin & Review* 15(1):52–58, 2008, PMC3070885). Set size should adapt (3–6 items), because capacity is only ~3–4 items (Luck & Vogel 1997; Conway/Luck slot-model literature).

### 6.2 Why this is the right interaction

- The task forces the full memory loop the current version skips: *encode briefly → maintain over a blank → compare against a probe → decide*. Every element of that loop is load-bearing (Rouder et al. 2008; Luck's methodological reviews).
- Two-alternative or localization responses keep criterion bias out of the score; a raw "tap when pattern shows" tap carries no information at all (and is scored correct no matter what in `exercises_screen.dart:388-391`).
- **Adaptive set size and adaptive delay** are the staircase dimensions: more items → more load; longer delay → stronger maintenance demand. Adaptive difficulty is again the mechanism that separates effective from ineffective training (the n-back/WM-training literature is explicit that non-adaptive training produces little transfer; PMC5805159).

### 6.3 Evidence that training works (with honest limits)

- **Near transfer is solid:** adaptive working-memory training reliably improves the trained memory domain (review and dual n-back vs. complex span comparison, PMC5805159; Lovden et al. argument that training needs a sustained demand/supply mismatch).
- **Far transfer is contested:** Jaeggi et al., *PNAS* 105(19):6829–6836 (2008) reported fluid-intelligence gains from dual n-back; replications are mixed (Redick et al. 2013; Thompson et al. 2013), and the field's consensus position is stated by Simons et al., "Do 'brain-training' programs work?" (*Psychological Science in the Public Interest* 17(3):103–186, 2016): claims of far transfer require active controls and remain unproven. **Design consequence:** score and promote *visual working memory* gains (threshold K, delay tolerance) — do not promise life-wide memory benefits.
- For a *vision* app, change localization with visual features (color, orientation) is the right choice: it trains the visual system's own storage limit, is behaviorally simple, and is the standard paradigm in the vision science of working memory.

### 6.4 Concrete spec for the app

```
Trial:  show N filled cells (random subset of an 8×8 or 5×5 grid) for 500 ms
        → blank 900 ms → test array (same or one cell changed) for 2 s
User:   taps the changed cell (change localization; ~50% of trials have a change
        in the localization variant — or always-changed with a same-cell catch)
Adaptive: staircase on N (set size) and/or delay duration to ~75% correct
Score:  Cowan's K per session, plus threshold set size
```

---

## 7. Cross-cutting design principles (from the literature, for all six)

1. **Forced choice over detection taps.** Green & Swets (1966) established that forced choice makes the observer's criterion irrelevant; "tap when you see it" measures a mixture of sensitivity and willingness to respond. All six exercises should be expressible as a choice between ≥2 defined options.
2. **Staircase the stimulus, hold the task fixed.** 3-down/1-up → 79.4% (Levitt 1971); QUEST/ZEST variants (Watson & Pelli 1983) converge faster. Target performance ≈ 75% correct: UFOV training held participants there explicitly, and the meta-analytic gap between adaptive (d=0.89) and non-adaptive (≈0) training is the strongest single argument in this document.
3. **The threshold is the metric.** Record threshold (contrast, chromatic distance, disparity, coherence, display duration, set size) per session and chart it. Accuracy-at-fixed-difficulty hides learning because difficulty never moves.
4. **Feedback on errors.** Auditory (tone) feedback on incorrect responses appears in essentially every protocol cited above (IOVS 2014 contrast; IOVS 2014 stereo; Yu/Levi contrast).
5. **Interleave conditions to force transfer.** Learning is specific to orientation, spatial frequency, retinal location, hue, and (in motion) direction (Yu, Klein & Levi 2004; Sowden 2011; Frontiers 2016; Lu 2007). Interleaved staircases (as in the CCT Trivector test and the PNAS 2016 protocol) buy transfer that single-condition training does not.
6. **Short daily sessions.** Perceptual-learning regimens in the cited literature run 10–13 sessions of ~10–30 min (stereo: 10–13 sessions; color: 5 days × 200–300 trials; motion: 8 days; ACTIVE: 10 × 60–75 min group sessions).
7. **Phone-specific honesty.** A phone has uncontrolled ambient light and uncalibrated gamma; absolute thresholds are not clinical values. Instruct a fixed viewing distance, test binocularly (as Li et al. 2009 did for exactly this reason), and treat scores as *relative to the user's own baseline*, not as diagnostics.
8. **A red-green anaglyph "glasses mode"** would unlock the two exercises that a bare 2D screen fundamentally cannot do (true stereopsis for Depth; dichoptic contrast presentation for Amblyopia-style contrast training). The published home-training evidence for both uses exactly this hardware ($1 paper glasses; RDS video game study, OVS 2018).

---

## 8. Map to current code

- `lib/screens/exercises_screen.dart:356-391` — `_handleTap` scores: contrast→always true; color→"tap within 0.15 of screen center"; depth→"tap within 0.15 of Offset(0.35, 0.65)" (fixed!); search→grid-slot check (matches deterministic painter slot); motion→always true; memory→always true. **All six of these scoring paths need replacement by trial logic** (each trial must carry its own ground truth generated with the stimulus, never derived from the painter's progress value).
- `lib/core/exercises/exercise_painter.dart` — renderers. The deterministic `targetSlot = progress * 25` (search) and angle-derived dot pattern (memory) should move into a per-trial random generator shared with scoring.
- `lib/screens/game_screen.dart` — the existing Gabor "find the matching patch" game already has the right trial→tap→feedback→score architecture (`_tap(i)`, instant feedback, trial advance) and can host the 2AFC/odd-one-out/changed-cell variants with modest extension; a per-trial `_trial.answer` field plus a staircased difficulty parameter is the core change.

---

## 9. References

**Contrast sensitivity / perceptual learning**
- Zhou Y. et al. "Improving vision in adult amblyopia by perceptual learning." *PNAS* (2004). doi 10.1073/pnas.0401200101
- "Perceptual learning improves contrast sensitivity and visual acuity in adults with anisometropic amblyopia." *IOVS/PNAS-line* (PubMed 16153674). ~90% 1-year retention.
- Levi D.M. & Li R.W. "Perceptual learning as a potential treatment for amblyopia." *Vision Research* (2009). PMC2764839
- Yu C., Klein S.A., Levi D.M. "Perceptual learning in contrast discrimination and the (questionable) role of hand position." *JOV* (2004). doi 10.1167/jov... (JOV 4(9), articleid 2121635)
- Li R.W., Polat U., Makous W., Bavelier D. "Enhancing the contrast sensitivity function through action video game training." *Nature Neuroscience* 12(7):843–848 (2009). doi 10.1038/nn.2296
- "Perceptual Learning Improves Adult Amblyopic Vision Through Rule-Based Cognitive Compensation." *IOVS* (2014). doi 10.1167/iovs.13-13739
- "Perceptual learning modifies the functional specializations of visual cortical areas." *PNAS* (2016). doi 10.1073/pnas.1524160113
- Pelli D.G., Robson J.G., Wilkins A.J. "The design of a new letter-chart for measuring contrast sensitivity." *Clinical Vision Sciences* 2:187–199 (1988). [clinical reference standard; not re-verified this session]

**Color vision**
- Mollon J.D., Reffin J.P. "A computer-controlled colour vision test that combines the principles of Chibret and of Stilling." (1989, Cambridge; PDF: vision.psychol.cam.ac.uk/jdmollon/papers/MollonReffin1989.pdf)
- Regan B.C., Reffin J.P., Mollon J.D. "Luminance noise and the rapid determination of discrimination ellipses in colour deficiency." *Vision Research* 34(10):1279–1299 (1994). doi 10.1016/0042-6989(94)90203-8
- "Colour vision: A review of the Cambridge Colour Test and other colour testing methods." *African Vision and Eye Health* 74(1) (2015). doi 10.4102/aveh.v74i1.23
- "Color discrimination repetition distorts color representations." *Scientific Reports* (2024). doi 10.1038/s41598-024-60283-4
- "Chromatic Perceptual Learning but No Category Effects without Linguistic Input." *Frontiers in Psychology* (2016). doi 10.3389/fpsyg.2016.00731
- Sowden P. et al. "Chromatic perceptual learning." (2011). doi 10.1075/z.167.48sow
- Aspinall P.A. et al. "Influence of serial practice on Farnsworth-Munsell 100-hue scores: the learning effect." *Applied Optics* 27:1038 (1988). doi 10.1364/ao.27.001038
- Ishihara S. *Tests for Colour-Blindness* (1917). [plate-design canon; standard reference]

**Depth perception / stereopsis**
- Howard I.P., Rogers B.J. *Binocular Vision and Stereopsis.* Oxford University Press (1995). [textbook; Howard-Dolman, stereoacuity norms]
- Julesz B. *Foundations of Cyclopean Perception.* University of Chicago Press (1971). [random-dot stereograms; no monocular cues]
- Deas L.M. & Wilcox L.M. "Binocular Depth Judgments on Smoothly Curved Surfaces." *PLOS ONE* (2016). doi 10.1371/journal.pone.0165932 [2AFC left/right-dot-closer, probit fitting]
- "Perceptual Learning Improves Stereoacuity in Amblyopia." *IOVS* (2014). doi 10.1167/iovs.13-12627 [red-green anaglyph training, 200.3″→81.6″]
- "A Random Dot Computer Video Game Improves Stereopsis." *Optometry and Vision Science* (2018). doi 10.1097/opx.0000000000001222 [home RDS game training, median 50% gain]
- Astle A.T., Blundell G.G., McGraw P.V. "Recovery of stereo acuity in adults with amblyopia." *Vision Research* (2013). PubMed 22707543
- "Enhancing stereoacuity through perceptual learning in normal vision." *IOVS* (ARVO 2013). [64% threshold improvement, transfers across orientation/SF]
- "Stereoscopic Vision in the Absence of the Lateral Occipital Cortex." *PLOS ONE* (2010). doi 10.1371/journal.pone.0012608 [RDS methodology; anaglyph on flat monitor]

**Visual search / attention training**
- Treisman A.M. & Gelade G. "A feature-integration theory of attention." *Cognitive Psychology* 12(1):97–136 (1980).
- Wolfe J.M. "Guided Search 2.0." *Perception & Psychophysics* 55:339–353 (1994).
- Ball K. et al. "Effects of cognitive training interventions with older adults." *JAMA* 288(18):2271–2281 (2002). [ACTIVE RCT]
- Owsley C. et al. "Visual processing impairment and risk of motor vehicle crash among older adults." *JAMA* 279(14):1084 (1998).
- "Speed of Processing Training in the ACTIVE Study: Who Benefits?" PMC3947605 [UFOV protocol detail: 75% threshold, double staircase, reliability 0.74]
- "The ACTIVE Study: Study Overview and Major Findings." PMC3934012
- "Systematic review and meta-analyses of useful field of view cognitive training." *Neuroscience & Biobehavioral Reviews* (2017). doi 10.1016/j.neubiorev.2017.11.004
- "USEFUL FIELD OF VIEW COGNITIVE TRAINING IMPROVES OLDER ADULTS' EVERYDAY FUNCTION." *Innovation in Aging* (2018). doi 10.1093/geroni/igy023.2532 [d=0.71; adaptive d=0.89; driving OR=0.50]

**Motion perception**
- Newsome W.T. & Paré E.B. "A selective impairment of motion perception following lesions of the middle temporal visual area (MT)." *J. Neuroscience* 8(6):2201–2211 (1988). doi 10.1523/jneurosci.08-06-02201.1988
- Britten K.H. et al. "The analysis of visual motion: a comparison of neuronal and psychophysical performance." *J. Neuroscience* (1992).
- Law C.-T. & Gold J.I. "Neural correlates of perceptual learning in a sensory-motor, but not a sensory, cortical area." *J. Neuroscience* (2008). PMC2424192 [coherence thresholds 67%→15%]
- Lu Z.-L. et al. "Motion perceptual learning: When only task-relevant information is learned." *JOV* 7(10):14 (2007). doi 10.1167/7.10.14
- "Motion perceptual learning: Only task-relevant stimulus information is learned." *JOV* (2010). doi 10.1167/6.6.163
- Green C.S., Gorman J., Bavelier D. "Action video-game training and its effects on perception and attentional control." (Green Lab review PDF, U. Wisconsin). [motion-processing enhancements; unverified DOI]

**Visual working memory**
- Phillips W.A. "On the distinction between sensory storage and short-term visual memory." *Perception & Psychophysics* 16:283–290 (1974).
- Luck S.J. & Vogel E.K. "The capacity of visual working memory for features and their conjunctions." *Nature* 390:279–281 (1997).
- Rouder J.N. et al. "How to measure working memory capacity in the change detection paradigm." *Psychonomic Bulletin & Review* 15(1):52–58 (2008). PMC3070885
- Adam K.C.S., Vogel E.K. et al. "Visual Working Memory Capacity: From Psychophysics and Neurobiology to Individual Differences." PMC3729738 [change-localization reliability 0.77; K limits]
- Jaeggi S.M. et al. "Improving fluid intelligence with training on working memory." *PNAS* 105(19):6829–6836 (2008).
- Simons D.J. et al. "Do 'brain-training' programs work?" *Psychological Science in the Public Interest* 17(3):103–186 (2016).
- "N-back versus Complex Span Working Memory Training." PMC5805159 [adaptive difficulty as prerequisite; near vs far transfer]

**Psychophysical method (cross-cutting)**
- Green D.M. & Swets J.A. *Signal Detection Theory and Psychophysics.* Wiley (1966). [forced choice ≈ criterion-free; NCBI NBK219045 appendix restates d′ = √2·Z(pc) and the 2AFC-vs-adjustment reliability result of Higgins et al. 1984]
- Levitt H. "Transformed up-down methods in psychoacoustics." *J. Acoust. Soc. Am.* 49:467 (1971). [3-down/1-up → 79.4%]
- Watson A.B. & Pelli D.G. "QUEST: a Bayesian adaptive psychometric method." *Perception & Psychophysics* 33:113–120 (1983).
- "Bias and Sensitivity in Two-Interval Forced Choice Procedures: Tests of the Difference Model." PMC5839130. [honest caveat: check interval bias; recorded per-interval]

*References marked "not re-verified this session" are canonical standards included for completeness; all other citations were pulled directly from the sources listed above during this research session.*
