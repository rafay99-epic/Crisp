# Retake removal — calibration plan (do after PR #72 merges to nightly)

## The idea (why it matters)
Retake removal automatically cuts a line you flubbed and immediately said again
("the app is *slow*… the app is **fast**"), keeping the good take. It's the most
time-saving feature in Crisp — it removes the most tedious manual editing step.

## The problem to fix
On **real footage** it over-fires: ~81–86 "retakes" detected on one talking-head
video, when only a handful were real do-overs. The rest are false positives.

**Why:** natural speech constantly repeats short 2-word phrases that were never
re-recorded — "you know", "so the", "going to", "this is", "I think". The current
default (`RETAKE_MIN_RUN = 2`, 3-second window) flags all of them.

Synthetic test clips (one clean do-over) don't expose this — only real speech does.

## What's already done (PR #72)
- Single-word stutter trimming is **off by default** (`RETAKE_STUTTER = False`) —
  it can't tell "the the the" (stumble) from "very very" (emphasis).
- So only ≥2-word phrase retakes run by default. But 2 words is still too loose.

## The calibration (the actual work)
Make detection **pickier** so it only fires on real do-overs. Three knobs in
`packages/engine/crisp/config.py` + `retake.py`:

1. **Longer minimum match** — raise `RETAKE_MIN_RUN` 2 → 3 (a 3-word run repeating
   back-to-back is far rarer in natural speech than a 2-word one).
2. **Tighter time window** — shrink `RETAKE_MAX_GAP` (a real do-over is immediate).
3. **Pause-anchoring** — only count a match if there's a real silence/stumble
   between the bad take and the good one, like the filler silence-gate already does
   (`gate_fillers_by_silence` in `edit.py`). This is the strongest signal.

## How to tune it (must use real footage — it's the answer key)
1. Run a real recording with verbose logging; log **which phrases** get flagged.
2. Eyeball the list: how many are real do-overs vs. false positives?
3. Tighten a knob, re-run, repeat — until the count matches the do-overs actually made.
4. Validate on 2–3 different real videos (different speaking styles) so it's not
   overfit to one.

Guessing the numbers blind risks too-strict (misses real retakes) or still-too-loose
(cuts good speech). Tune against Abdul's own recordings.

## Sequence
1. Resolve cubic AI review feedback on PR #72.
2. Merge PR #72 → nightly.
3. Then do this calibration as a follow-up branch.
