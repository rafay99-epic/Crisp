# Crisp — feature ideas / roadmap

Polish, speed, and stability ideas for the app. Grounded in the current
architecture (SwiftUI app driving the stdlib Python engine). Sequenced by
impact-per-effort. Living doc — add/reorder freely.

---

## 🎨 Polish (premium feel)

1. **Before/after preview of the *result*** — scrub/play the cleaned result (or A/B
   against the original) *before* writing the file. The "hear it before you commit"
   step. Reuses the review timeline + preview sheet + waveform. **Top polish pick.**
2. **Keyboard-driven cut review** — in the review timeline: `J/K/L` to move between
   cuts, `space` to toggle keep/remove, and a **"play across this cut"** button to
   hear whether a join is clean. Pairs with the smooth-cuts work.
3. **Re-weight the progress bar** — fix the "rockets to ~60% then crawls": give the
   encode phase a bigger share so the bar tracks wall-clock. Small (stage labels
   already exist).

## ⚡ Speed (the cost is the re-encode, not the model)

4. **Smart-cut / stream-copy hybrid** — *the* speed lever. Copy the video stream
   losslessly for the interior of each kept segment and only re-encode the few frames
   at each cut boundary (GOP edges). Most of a video is copied, not encoded — often
   5–10× faster on long videos. **Big effort** (GOP analysis, mixing copied +
   re-encoded segments, muxing), highest speed payoff.
5. **Cache the analysis between re-cleans** — re-cleaning the same file with only
   encoder/quality changed re-extracts audio + re-detects every time. Cache that
   (keyed by file + detection params) so encoder tweaks are instant. Cheap, safe.

## 🛟 Stability (what will actually bite real users)

6. **Variable-frame-rate (VFR) handling** — screen recorders (the core use case!)
   often output VFR, and the trim→`setpts`→concat path can drift A/V on VFR sources.
   Detect VFR (ffprobe) and normalize to CFR / handle timestamps explicitly. **Top
   stability pick — latent correctness bug for the exact videos Crisp targets.**
7. **Preflight checks** — before a long render: enough disk space for the output, a
   valid video+audio stream, a decodable codec. Fail fast with a clear message
   instead of dying mid-encode.
8. **Graceful odd-input handling** — no-audio videos, corrupt/partial files, exotic
   codecs → a clean error, never a crash or a half-written file.

## 🔁 Cross-cutting (polish + the model flywheel)

9. **Review-timeline feedback loop** — capture which predicted cuts the user keeps vs
   removes → labeled data from real usage → feeds the next model. The "reward/treat"
   idea done right (active learning, not RL). Both a UX win (the app learns your
   taste) and the highest-leverage long-term data source. Already noted in
   `research/NOTES.md` §6 as "data collection — later".

---

## Suggested sequence
1. **VFR handling** (stability — protects screen recordings)
2. **Result preview + keyboard review** (polish — low risk)
3. **Smart-cut** (speed — big project)
4. **Feedback loop** (the flywheel)
