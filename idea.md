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

6. ✅ **Done (PR #77).** **Variable-frame-rate (VFR) handling** — screen recorders
   (the core use case!) often output VFR, and the trim→`setpts`→concat path can drift
   A/V on VFR sources. Detect VFR (ffprobe) and normalize to CFR / handle timestamps
   explicitly. **Top stability pick — latent correctness bug for the exact videos
   Crisp targets.** Shipped: `crisp/framerate.py` policy + `tools.probe_video_fps` +
   `render` `-r`; Settings → Output → Frame rate (Automatic / Keep source timing /
   Constant rate).
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

## 🌍 Reach (more audience, same engine)

10. **Multi-language support** — the app is English-only today (whisper `en` model,
    `is_filler` vocab, retake matching tuned on English). Offer multilingual whisper
    models in the catalog and a language setting; pauses are already language-agnostic,
    so the work is fillers/captions/retakes + the model catalog. Biggest pure-reach
    expansion — opens Crisp to the global creator audience.
11. **Audio-first / podcast mode** — accept an audio file (or "export audio only"),
    run the same pauses + fillers + retakes pipeline, write a cleaned audio file. Same
    engine, a whole new use case (podcasters) — mostly skipping the video render path.

## 💎 Pro (justifies the paid tier)

12. **Export to your editor (FCPXML / EDL / DaVinci XML)** — instead of rendering,
    export the detected cuts as a *non-destructive timeline* the user opens in
    DaVinci / Final Cut / Premiere. Crisp does the tedious detection; they finish in
    their NLE. **Zero re-encode** — perfectly on-brand ("honest quality, never touch
    the footage") and the killer feature for serious creators (the kind who pay).
    Reuses the keep/cut span list the engine already produces. **Top pro pick.**
13. **Chapter detection + export** — auto-generate YouTube / podcast chapter markers
    from long pauses + transcript topic shifts; export as chapter metadata or a
    timestamp list. Reuses the existing transcript; concrete, visible creator value.

## 🤝 Trust (build on what just shipped — retakes)

14. **"Why was this cut?" inspector** — the engine already logs a reason per cut
    (pause / filler / retake / long-run). Surface it in the review timeline with a
    one-click *keep this one*, so the engine's decisions become something the user
    understands and controls. Turns the retake/cut logic from a black box into trust;
    pairs with #1/#2 and feeds #9.
15. **Pause "tighten" vs. "remove"** — option to *shorten* long pauses to a target
    (e.g. 0.3s) instead of cutting them entirely. Some creators find full removal too
    staccato; a tighten mode keeps natural rhythm. A new keep-segment strategy in
    `edit`, not a new detector.

---

## Suggested sequence
1. ✅ **VFR handling** (stability — protects screen recordings) — done, PR #77
2. **Result preview + keyboard review** (polish — low risk)
3. **Export to your editor / FCPXML** (pro — no re-encode, high value, low engine risk)
4. **Multi-language** (reach — biggest audience expansion)
5. **Smart-cut** (speed — big project)
6. **Feedback loop** (the flywheel)
