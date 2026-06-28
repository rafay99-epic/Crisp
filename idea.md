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

12. ✅ **Shipped (PR #79) — "Send to a video editor" (FCPXML, DaVinci Resolve).**
    Instead of rendering, export the detected cuts as a *non-destructive timeline* the
    user opens in DaVinci Resolve (free edition works — File ▸ Import ▸ Timeline; no
    Studio scripting API needed). Crisp writes a `<name> (Crisp)/` folder = a copy of
    the original + an `.fcpxml`. **Zero re-encode for CFR sources** (VFR is normalized to
    CFR once, frame-accurately). Engine: `crisp/timeline.py` + `tools.probe_stream_meta`
    + `pipeline._export_editor_project`; app: `EditorDetector`, Settings → Output → "Send
    my cuts to a video editor", auto editor-picker sheet on finish. **Top pro pick.**
    - **Open follow-ups (deferred — not blockers):**
      - *Hard-cancel leftover:* a force-kill (SIGKILL) mid-copy can leave a partial
        `(Crisp)` folder; we clean up on caught errors but can't on SIGKILL. Low impact
        (original untouched; re-export overwrites). Could add a stale-partial sweep.
      - *History project path:* an editor handoff records the `.fcpxml` path but not the
        project folder, so History can't reveal the project after an app restart.
      - *Presets drop fields:* `Preset.parameters()` rebuilds from defaults and only
        carries cut/encode knobs — captions / frame-rate / smoothing / split fall back to
        defaults (pre-existing; this PR only threaded the new `exportToEditor`). Worth
        making presets capture the full recipe.
    - **NEXT (the big one the user is curious about) — auto-import spike.** Goal: skip the
      manual File ▸ Import step by auto-creating a Resolve project + importing the
      timeline. Hard fact from research: the *external* scripting API is Studio-only; the
      user has free (Lite, bundle id `com.blackmagic-design.DaVinciResolveLite`). User
      wants to TEST it on their machine anyway (sources conflict). To run the spike, the
      user must set **Resolve → Preferences → System → General → "External scripting
      using" = Local** and keep Resolve running; then run a tiny Python using
      `RESOLVE_SCRIPT_API`/`RESOLVE_SCRIPT_LIB` (paths in the README inside the .app) to
      try `scriptapp("Resolve")` + `ImportTimelineFromFile`. If it connects on free →
      build real auto-import; if gated → keep the manual import (UI automation is the
      brittle fallback we'd avoid). Note: user's Python is 3.14 (fusionscript may not load
      there — part of what the spike reveals).
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
