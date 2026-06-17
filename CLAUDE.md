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
2. **Never lose the user's footage** — the original is **always** backed up to an
   `_originals/` folder next to it before anything runs. The app only ever writes a
   new `<name>_cleaned.mp4`; it never overwrites or deletes a source file.
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

- `Sources/Crisp/App.swift` — `@main`, single `Window` scene, channel-titled,
  "Check for Updates…" command.
- `Sources/Crisp/CleanModel.swift` — `@MainActor @Observable` model that locates
  the bundled engine (`Engine`), spawns `python3 clean_video.py … --ndjson`, and
  decodes the NDJSON event stream (`log` / `progress` / `result` / `error`) into
  published state.
- `Sources/Crisp/ContentView.swift` — display only: header (+ channel badge),
  update banner, drop card, options, progress, result card.
- `Sources/Crisp/Channel.swift` — channel identity from `CrispChannel`.
- `Sources/Crisp/Updater.swift` — GitHub-release updater, channel-aware, auths via
  `gh auth token` (private repo). Self-contained (no notification/settings deps).

## The engine (`Resources/engine/clean_video.py`)

- Pure Python **stdlib** — no pip dependencies (the user's Python is bleeding-edge;
  ML wheels don't exist for it). It shells out to **ffmpeg** and **whisper.cpp**.
- Pipeline: backup → `ffmpeg silencedetect` finds pauses from real audio energy
  (accurate; whisper word-timestamps absorb trailing silence so they can't) →
  whisper.cpp (`ggml-base.en.bin`) supplies filler-word timestamps → `ffmpeg`
  trim/concat re-render (same resolution/fps, H.264 CRF 20, AAC 192k).
- `--ndjson` emits one JSON object per line for the Swift UI; the human CLI mode
  prints `→` lines. `--no-fillers` skips transcription (faster, pauses only).
- **Self-contained packaging.** The shipped app bundles `clean_video.py` **plus
  the binaries it drives** — `ffmpeg`, `ffprobe`, `whisper-cli`, and a
  `python-build-standalone` runtime — under `Resources/engine/bin/`, signed with
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
