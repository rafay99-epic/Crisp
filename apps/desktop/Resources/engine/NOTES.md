# Engine notes & journal

Companion to the model journal in `research/NOTES.md`. This file tracks the
**engine** (the stdlib-only Python that detects pauses/fillers and renders the
cut). Newest first.

---

## Cut smoothing — why jump-cuts sounded janky, and the fix

**Symptom.** Cleaned videos had audible clicks/pops at every cut, rough enough
that the cuts often needed hand-fixing in a video editor afterwards.

**Root cause.** `edit.render()` trimmed each kept segment and joined them with a
bare `concat` — a *hard splice*. Cut points land at arbitrary millisecond
positions, never at a zero-crossing, so at each join the audio waveform jumps
from one amplitude to another instantly. That step discontinuity is a click. The
video hard-jump is inherent to jump-cuts and reads fine; it's the audio click
that made it feel broken. There were no fades, crossfades, or boundary snapping
anywhere, and no knob for any of it.

**Fix — three phases**, all in `crisp/edit.py`, all config-driven (`crisp/config.py`)
and exposed on the CLI (`clean_video.py`), so the desktop app gets them with no
Swift change (it drives the CLI; defaults apply):

- **Phase 1 — audio micro-fade** (`--fade-ms`, default **10 ms**, on). A short
  `afade` in/out on every segment before `concat`, so the waveform meets zero at
  each splice instead of jumping. Inaudible as a fade; kills the click. Each
  segment keeps its exact length → audio and video stay perfectly in sync. Capped
  at half a segment so brief slivers still work. This is the 80/20 fix.
- **Phase 2 — matched A/V crossfade** (`--crossfade-ms`, default **0 = off**).
  When >0, consecutive segments *dissolve* instead of hard-cutting: video `xfade`
  + audio `acrossfade` at the **same** duration, so both streams shorten equally
  and stay synced (verified: N segments at crossfade `c` shorten the output by
  exactly `(N-1)·c`). Clamped to the shortest segment so a brief kept sliver can't
  break the dissolve; falls back to a hard concat when there's nothing long enough
  (or only one segment). Opt-in because a dissolve is an editorial style choice,
  not always wanted.
- **Phase 3 — zero-crossing snap** (`--snap-ms`, default **12 ms**, on). Before
  rendering, nudge each interior cut boundary to the nearest audio zero-crossing
  within ±window, reading a small slice around each boundary from the analysis WAV
  (stdlib `wave`, the 16-bit mono one `extract_audio` already wrote). A boundary
  that lands where the signal is already ~0 splices silently — reducing the work
  the Phase-1 fade has to do and avoiding mid-syllable cuts. Best-effort: any read
  problem leaves the cut list unchanged (the fade still covers it), and the clip's
  own head/tail are left alone. Skipped in reviewed-keep-file mode (the user chose
  those exact boundaries).

**Testing.** The graph builder (`build_filter_graph`) and the snap logic
(`_nearest_zero_crossing`, `snap_keep_to_zero_crossings`) are pure/IO-light and
unit-tested in `tests/test_edit.py` (no ffmpeg needed — snap writes a tiny WAV).
Smoke-tested end-to-end against real footage: both the default fade path and the
120 ms crossfade path render valid MP4s, and the crossfade output is shorter by
exactly `(N-1)·c`.

### Settings wiring (DONE)

The three knobs are exposed in the app's Settings under a **"Cut smoothing"**
section (its own section, not the "Custom cutting" one — they apply to *every*
clean, like the encoder choices). Flow mirrors the encoder settings:
`EngineConfig` fields (`fadeMs`/`crossfadeMs`/`snapMs`, ms, forward-compatible
decode) → `EngineSettings` observable → `CleanParameters` (always from config) →
`CleanRunner` argv (`--fade-ms`/`--crossfade-ms`/`--snap-ms`). Presets inherit the
defaults via `Preset.parameters()` (built from `EngineConfig.defaults`).

### Future / TODO
- **Per-model config.** Fade/crossfade/snap could move into the model's
  `config.json` later if a model wants different cut feel (like
  `recommended_threshold`).
- **Phase 3 at source sample rate.** Snapping uses the 16 kHz analysis WAV; a
  zero-crossing there is only *near*-zero at the source's 48 kHz. With the Phase-1
  fade this is already inaudible, but snapping against the source audio directly
  would be exact.
- **Cut-position precision.** The filtergraph formats all times with `%.6f`
  (microseconds), not milliseconds — ms rounding would re-round the zero-crossing
  snap away and let absolute cut positions drift. Video and audio are trimmed at the
  *same* timestamps, so there is no A/V *desync* (no lip-sync error); the only
  residual is absolute cut position, now sub-microsecond.
- **Consider a small default crossfade.** If user feedback says hard jump-cuts
  still feel abrupt even without clicks, a tiny default `crossfade_ms` (~40–60 ms)
  would soften the picture too — but measure first; dissolves change the look.
