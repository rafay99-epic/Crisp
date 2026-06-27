# Notes — retake detection: the hard problems (don't forget)

Captured while testing PR #73 (retake calibration) on Abdul's real YouTube footage.
The feature works well on *clean* retakes but has two real limits. These are NOT
threshold bugs — they're the ceiling of transcript-only detection.

## How it works today (baseline that's solid)
- whisper transcript → find a repeated run of words (≥ `min_run`) → cut the first take.
- **Pause-anchoring**: the corrected take must begin right after a detected silence
  (found at a short 0.3s threshold). This is what gives precision — it kills the big
  false-positive class (see #2). Sensitivity = gentle(5)/balanced(4)/aggressive(3).
- On conversational footage (the 8-min "Deploying" clip), **balanced = 1 cut, the one
  real retake, 0 false positives.** This part is good.

## Problem 1 — pause-less stumbling restarts (MISSED)
Real example, "Idea→Code→App" clip @ ~801s:
> "I'm using this notepad to, **you can see**, I was using this notepad to work…"

Abdul fumbled and restarted **without pausing**. The repeat ("using this notepad to")
IS in the transcript, run length is fine, gap is fine. The ONLY reason it's rejected:
**pause-anchoring** — there's no silence before the corrected take, because he never
stopped, he just barreled through with "you can see" wedged in.

Data (idea clip):
| config | total cuts | catches the 801s retake? |
|---|---|---|
| balanced (anchored) | 3 (clean) | ❌ |
| anchoring OFF | 23 (noisy) | ✅ but +20 false cuts |

**The tension in one line:** the pause anchor is what makes balanced clean AND what
makes it miss continuous stumbles. Can't fix with a knob — loosening brings back the
false positives.

## Problem 2 — semantic corrections with NO verbatim repeat (INVISIBLE)
Abdul described saying (paraphrase): "it will be open… and it is open… no, I said it
will be open source." Whisper **smooths disfluencies away** — it transcribes the
*intended* sentence and drops the false start. At his timestamps the verbatim repeat
isn't in the transcript at all. **If the repeat isn't in the text, matching can't see
it.** This is the "no, I said X" correction class.

## Problem 3 — parallel structure looks identical to a redo (the false-positive class)
"at the startup level, at the enterprise level" / "how it's gonna run, how it's gonna
come together" — intentional, but textually identical to a retake. Pause-anchoring
filters most (they're usually continuous), which is why we need it. On list-heavy
technical footage even balanced over-cuts a bit (gentle is safer there).

## Candidate fixes (need a real test set before building — don't overfit to one clip)
1. **Discourse-stumble markers between the takes** — Abdul's notepad case has "you can
   see"; real restarts often have "um", "uh", "I mean", "sorry", "you know". Parallel
   structure never does. Use as an ADDITIONAL catch path on top of pause-anchoring
   (catch more without losing precision). Best near-term bet.
2. **Repeat bursts** — same phrase 3× in a row ("using this" ×3) = stumble. Genuine
   parallel structure repeats exactly twice.
3. **"Retake-judge" model** — a small semantic/text classifier (or tiny local LLM)
   that reads the two phrases and decides "correction vs. intentional repeat." The only
   thing that can touch Problem 2. Research project ([[ml-custom-models]] territory),
   NOT Wren (Wren is an audio→filler classifier, can't read words).

## Process note
Build a small test set from Abdul's OWN footage: each entry = (clip, timestamp, what he
actually said, should-cut?). One example shows the problem; 5–6 show the fix and guard
against overfitting/regressions. Ask him to flag misses (timestamp + rough words) as he
tests.

## Status
PR #73 ships the solid baseline (clean retakes + sensitivity + honest UX). Problems
1–3 are the next research arc, tracked here. See also retake-calibration.md.
