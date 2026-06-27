# Notes — Retake feature: state, problems, plan (living handoff)

Living doc for the "remove repeated takes" feature's next arc. Started while Abdul
tested PR #73 (calibration) on his real YouTube footage. Read this first if you're a
fresh session picking this up. See also: `retake-calibration.md`, `analytics-dashboard.md`,
and the `retake-removal` memory.

## Where it stands
- **PR #72** (transcript-matching retake removal) — merged to nightly (`cd4426a`).
- **PR #73** (pause-anchoring + gentle/balanced/aggressive sensitivity + UX) — merged to
  nightly (`753f84d`). This is the **solid baseline**.
- Engine: `crisp/retake.py` (`detect_retakes`), `crisp/pipeline.py` wires it; sensitivity
  in `crisp/config.py` (`RETAKE_SENSITIVITY_MIN_RUN = {gentle:5, balanced:4, aggressive:3}`).
- App: Settings ▸ Cutting ▸ Repeated takes (sensitivity picker); bottom-bar on/off toggle;
  disabled + clear warning when the Wren fast-filler model is on (retakes need whisper).
- Progress shows: Detecting pauses → Transcribing → Finding repeated takes → Planning cuts.
- Estimate shows pause count (retakes/fillers counted while cleaning — need whisper).

## How it works (the baseline that IS good)
whisper transcript → find a repeated run of words (≥ `min_run`) → cut the first take.
**Pause-anchoring**: the corrected take must begin right after a detected silence (found
at a short 0.3s threshold). That anchor is what gives precision. On conversational
footage (8-min "Deploying" clip), **balanced = 1 cut = the one real retake, 0 false
positives.** That part works well.

## Abdul's experience & feedback (his words, paraphrased)
- Verdict: **"the retake functionality is kind of mid."** Fair — it nails clean retakes,
  misses messy real-world ones.
- He **does a lot of retakes** when recording; his footage is the real test (the polished
  test clips have ~none, so they only prove we don't over-cut, not that we catch his).
- Concrete miss he flagged ("open source" correction): he said something like *"it'll be
  open… and it is open… no, I said it'll be open source."* → not caught.
- He wants it to handle **chained / merging retakes**: *"this is a retake, this is another
  retake, and this retake is merging into another sentence — cut these so the audio and
  the cut are completely seamless."* I.e. multiple stacked restarts, cut cleanly.
- He was testing on: **balanced** sensitivity, **whisper** model, **remove fillers on**,
  **repeated takes enabled**. (Note: the dev build force-enables Wren, which disables
  retakes — he had to turn Wren off to test, which he did.)
- Cut **seamlessness** matters to him a lot — non-editors must trust it; janky cuts kill it.

## The core problems (NOT threshold bugs — the ceiling of transcript-only detection)

### Problem 1 — pause-less stumbling restarts (MISSED)
"Idea→Code→App" clip @ ~801s:
> "I'm using this notepad to, **you can see**, I was using this notepad to work…"

He fumbled and restarted **without pausing**. The repeat IS in the transcript; run/gap are
fine. Rejected purely by **pause-anchoring** — no silence before the corrected take.

| config | total cuts (idea clip) | catches 801s retake? |
|---|---|---|
| balanced (anchored) | 3 (clean) | ❌ |
| anchoring OFF | 23 (noisy) | ✅ but +20 false cuts |

**The tension:** the pause anchor is what makes balanced clean AND what makes it miss
continuous stumbles. Can't fix with a knob.

### Problem 2 — semantic "no, I said X" corrections with NO verbatim repeat (INVISIBLE)
whisper **smooths disfluencies away** — transcribes the intended sentence, drops the false
start. At Abdul's "open source" timestamps the repeat isn't in the transcript at all. **No
text repeat → matching has nothing to catch.** Only a semantic model can touch this.

### Problem 3 — parallel structure looks identical to a redo (the false-positive class)
"at the startup level, at the enterprise level" / "how it's gonna run, how it's gonna come
together" — intentional, textually identical to a retake. Pause-anchoring filters most
(they're continuous), which is WHY we need the anchor. On list-heavy technical footage
even balanced over-cuts a little (gentle safer there).

### Problem 4 — seamless cuts on chained/merging retakes (cut-quality)
When several restarts stack ("A… A… A-and-then"), the cut boundaries must land so the kept
take flows naturally. `detect_retakes` already resumes at the kept take (`i = best_j`) so
chained restarts cut in sequence — but only if each is *detected* (Problem 1 blocks that).
Need to confirm boundaries are clean when multiple cut spans merge (build_keep_segments
merges overlapping removals; zero-cross snap + fade smooth the splice).

## Decision — next step (agreed direction)
**#1: discourse-stumble markers as an ADDITIONAL catch-path on top of pause-anchoring.**
Highest value, lowest risk. Idea: a retake is valid if the corrected take begins after a
pause **OR** the gap between takes contains a stumble marker — "um", "uh", "I mean",
"sorry", "you know", "you can see" (Abdul's notepad case has "you can see"). Parallel
structure never has these, so it should catch more (Problem 1) without reintroducing the
Problem 3 false positives.

**Hard prerequisite — don't overfit:** build a small **test set from Abdul's own footage**
before tuning. Each entry = `(clip, timestamp, what he actually said, should-cut?)`. One
example (notepad) shows the problem; **need ~5–6 flagged misses** to design a signal that
generalizes and guard against regressions. Ask Abdul to flag misses as he tests:
timestamp + roughly what he said + should-it-have-cut.

Other candidates (later): repeat-bursts (same phrase 3×); the **"retake-judge" model** (a
small semantic/text classifier or tiny local LLM — the only thing that can touch Problem
2; NOT Wren, which is an audio→filler classifier and can't read words → `ml-custom-models`).

## For a fresh session
1. Read this + the `retake-removal` memory.
2. Get Abdul's flagged misses (the test set) before changing detection.
3. Prototype #1 (stumble-marker catch-path) against the test set; verify precision doesn't
   regress on the "Deploying" (8-min) clip (should stay ~1 clean cut).
4. Keep cuts seamless (Problem 4) and the sensitivity presets meaningful.
