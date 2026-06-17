# CLAUDE.md — Crisp

Crisp is a native macOS app (`apps/desktop`, Swift/SwiftUI) that cleans up
screen-recordings / talking-head videos by removing **long pauses/silence** and
**filler words** (um, uh, hmm, aww…) from audio + video together, producing tight
jump-cuts. The heavy lifting is a stdlib-only Python engine
(`apps/desktop/Resources/engine/clean_video.py`) the Swift app drives as a
subprocess. License: **GPL-3.0**. Conventions mirror the Vitals project.

## Product philosophy (drives every decision)

1. **Don't stick out** — the app must look like Apple made it. System fonts, SF
   Symbols, native materials, standard controls.
2. **Never lose the user's footage** — the app only ever writes a new
   `<name>_cleaned.mp4`; it **never** overwrites or deletes a source file. By
   default it also backs the original up first (an opt-out toggle in Settings):
   the app copies it into a dated folder under the data home
   (`~/.crisp*/Originals/<yyyy-MM-dd>/`); the bare CLI defaults to an `_originals/`
   folder beside the input.
3. **Honest about quality** — cuts re-encode (required for frame-accurate trims)
   but never downscale: same resolution, same fps, high-quality H.264 (CRF 20).
   Don't silently degrade. If a tradeoff exists, surface it.
4. **Layers that don't leak** — the Python engine knows nothing about the UI
   (it speaks `--ndjson` on stdout). Swift `Services`/model drive it and publish
   progress; `Views` only display.
5. **One system, not two** — a surface that shows up in more than one place is one
   shared component, never a copy. Reuse first; generalize before forking.

## Workflow rules (explicit requirements — do not violate)

- **No Claude / AI attribution anywhere**: no `Co-Authored-By`, no "Generated with
  Claude" in commits, PR titles/bodies, changelogs, or in-app credits. Credited to
  **Syntax Lab Technology / Abdul Rafay (rafay99.com)**.
- **`nightly` is the integration branch; `main` is the default + protected Stable
  branch.** Every feature on its own branch **from `nightly`** → push → **draft PR
  into `nightly`**. The user squash-merges. **Never** hand-commit to `main` (it
  moves only via the user's weekly `nightly → main` squash promotion, which cuts
  the Stable release) or directly to `nightly`.
- **Test on the Dev build, never disturb Stable.** During development, build +
  install with **`./dev.sh`** (from `apps/desktop`) — it builds **`Crisp Dev.app`**
  (bundle id `…crisp.dev`) and installs+launches it side by side with the user's
  Stable `/Applications/Crisp.app`. **Never** `ditto` a dev build over
  `/Applications/Crisp.app` or quit/relaunch the Stable "Crisp" app.
- Verify UI changes visually against the **"Crisp Dev"** window (activate it first,
  then `screencapture`).

## Versioning, channels & releases

- **Stable version = `0.<total commit count on main>`** (computed in `ci.yml` and
  `build.sh`; `CRISP_VERSION` overrides). Nightly orders by `CrispBuildNumber`
  (the CI run number, never resets) with a cosmetic `0.<count>-nightly` string.
  Dev has no feed. The version must never go backwards (the updater compares
  numerically).
- **Three channels** (`CRISP_CHANNEL`, default `stable`), installable side by side
  (distinct bundle id + name + data dir + icon):
  - **stable** → `Crisp.app` / `Crisp.dmg`, `com.syntaxlabtechnology.crisp`, blue
    icon, clean numeric version.
  - **nightly** → `Crisp Nightly.app` / `Crisp-Nightly.dmg`, `…crisp.nightly`,
    amber + `NIGHTLY` icon, `…-nightly` version, baked `CrispBuildInfo`
    (`branch@sha`) + `CrispBuildNumber`.
  - **dev** → `Crisp Dev.app`, `…crisp.dev`, purple + `DEV` icon. **Local only —
    publishes no DMG and its updater is disabled** (`Channel.updatesEnabled == false`).
  Everything channel-specific derives at runtime from the bundle's `CrispChannel`
  Info.plist key via the `Channel` enum — never hardcoded `isDev` checks.
- **Two feeds, both test-gated.** Stable → `ci.yml` (push to `main`) publishes a
  release with `Crisp.dmg`. Nightly → `nightly.yml` (push to `nightly`) refreshes a
  single rolling `nightly` pre-release with `Crisp-Nightly.dmg`. The release title
  **must contain `build <n>`** — the Nightly updater parses it. CI is one pipeline:
  publish `needs:` build `needs:` test + lint, so a red test never reaches users.
- **`./dev.sh`** / **`./nightly.sh`** build those channels locally next to Stable.

## Commands

```sh
# from apps/desktop:
swift build           # debug compile
swift test            # the suite CI gates on
./build.sh            # universal release build → build/Crisp.app  (CRISP_CHANNEL selects channel)
./dev.sh              # build + install "Crisp Dev" next to Stable
./make-dmg.sh         # package the channel's DMG
swiftlint             # lint (CI uses --reporter github-actions-logging)
```

## Desktop architecture

`Sources/Crisp/` is organized by layer (SwiftPM recurses, so subfolders need no
`Package.swift` change; one module = one namespace, so moving a type between files
is a pure move):

- `App/CrispApp.swift` — `@main`, single `Window` scene, channel-titled,
  "Check for Updates…" command; owns the `CleanModel`, `Updater`, `ModelStore`.
- `Common/` — cross-cutting: `Channel` (identity from `CrispChannel`), `AppInfo`
  (bundle-id base + the shared `Logger` subsystem), `Formatting` (`formatTime`).
- `Models/` — plain value types: `Strength`, `CleanResult`.
- `Services/` — the logic (knows nothing about views):
  - `Cleaning/` — `CleanModel` (`@MainActor @Observable`; spawns
    `python3 clean_video.py … --ndjson` and decodes the `log`/`progress`/`result`/
    `error` stream) + `CleanEngine` (locates the bundled script/bins/python).
  - `Model/` — `ModelStore` (speech-model lifecycle) + `ChunkedDownloader`.
  - `Updates/` — `Updater`: GitHub-release updater, channel-aware, auths via
    `gh auth token` (private repo). Self-contained.
- `Views/` — display only: `ContentView` composes `DropCard`, `OptionsCard`,
  `ProgressSection`, `ResultCard`, `UpdateBanner`, `ModelStatusView`; `SettingsView`
  is the ⌘, window for the Custom cutting knobs;
  `Components/Card.swift` is the shared `.cardBackground(…)` surface every card uses.

## The engine (`Resources/engine/`)

- `clean_video.py` is a thin CLI wrapper (argparse + NDJSON/human emit); the engine
  lives in the `crisp/` package beside it — `config` (tunables + filler vocab),
  `tools` (ffmpeg/ffprobe/whisper resolution), `text` (`is_filler`), `detect`
  (pauses + transcription), `edit` (backup/cut/render), `pipeline` (`clean_video`).
  Library users `from crisp import clean_video`; Swift drives the CLI.
- Pure Python **stdlib** — no pip dependencies (the user's Python is bleeding-edge;
  ML wheels don't exist for it). It shells out to **ffmpeg** and **whisper.cpp**.
- Pipeline: backup → `ffmpeg silencedetect` finds pauses from real audio energy
  (accurate; whisper word-timestamps absorb trailing silence so they can't) →
  whisper.cpp (`ggml-base.en.bin`) supplies filler-word timestamps → `ffmpeg`
  trim/concat re-render (same resolution/fps, H.264 CRF 20, AAC 192k).
- `--ndjson` emits one JSON object per line for the Swift UI; the human CLI mode
  prints `→` lines. `--no-fillers` skips transcription (faster, pauses only).
- **Cutting knobs** are CLI flags — `--pause`, `--noise`, `--keep-pause`,
  `--min-keep`. The `Strength` presets set them; a **Custom** strength uses the
  user's saved values.
- **Encoder choice** is also configurable (`crisp/encode.py` builds the args):
  `--video-codec {h264,hevc}`, `--hardware` (Apple VideoToolbox), `--quality`
  (named levels → CRF for software / `-q:v` for hardware), `--audio-codec
  {aac,opus}`, `--audio-bitrate`. These apply to **every** clean (cuts always
  re-encode). **Default is hardware HEVC at High** — every Apple-Silicon Mac has a
  HEVC media engine, so it's the fast default; if a hardware encode fails (e.g. a
  macOS VM with no media engine) the pipeline **falls back to software automatically**.
  (Opus is muxed into the `.mp4`; plays in modern players/VLC, but QuickTime may
  not.)
- Both sets live in a JSON config at **`~/.crisp*/config/settings.json`** (edited
  in the Settings window, ⌘,). It's in the user's home — not the bundle — so updates
  never disturb it, and `EngineConfig` decodes each field with a default so new keys
  added later don't break an existing file (`Services/Cleaning/EngineSettings.swift`,
  defaults mirror `crisp/config.py`).
- **Self-contained packaging.** The shipped app bundles `clean_video.py` + the
  `crisp/` package **plus the binaries it drives** — `ffmpeg`, `ffprobe`,
  `whisper-cli`, and a `python-build-standalone` runtime — under
  `Resources/engine/bin/`, signed with
  the app. `Scripts/vendor.sh` produces that tree (pinned + hash-checked downloads;
  whisper-cli built from a pinned `whisper.cpp` tag via **cmake** — a build-time
  dep, CI runners have it), and `build.sh` stages + signs it. The engine resolves
  each tool from `CRISP_FFMPEG`/`CRISP_FFPROBE`/`CRISP_WHISPER` (set by Swift to
  the bundled paths), falling back to PATH so the bare CLI / a dev's Homebrew still
  work. Everything is **arm64-only** — Crisp is Apple-Silicon only; Intel Macs are
  not supported (`build.sh` compiles a single arm64 slice).
- **The speech model is downloaded, not bundled.** `ggml-base.en.bin` (~148 MB)
  would bloat every build + re-ship on each update, so `ModelStore` fetches it once
  on first run into the channel data dir (`~/.crisp*/models/`), with HTTP-Range
  resume + SHA-256 verify + atomic publish. State is derived from disk each launch,
  so interrupted/corrupt/deleted downloads self-heal. The Clean action is gated
  until the model is ready (only when "Remove filler words" is on).

## Design language

Native, Apple-like. SF Symbols, `.regularMaterial`/`.quaternary` cards (radius
12–14), `.borderedProminent` primary action, `.segmented` strength picker,
`.switch` toggles, system accent. The Dock/app icon is a waveform with a cut
(`Scripts/MakeIcon.swift`), recolored per channel.

## Environment gotchas

- The user's shell aliases `cd` through zoxide — it can fail inside chained
  commands. Run Bash from absolute paths or put a plain `cd /abs/path` first.
- This ffmpeg has no libwebp; use `sips` for image conversion.
- `screencapture` captures whatever is frontmost at the coordinates — activate the
  target window first and re-read its bounds in the same osascript.

## License & credit

GPL-3.0 (`LICENSE` at root). Credited to Syntax Lab Technology / Abdul Rafay.
