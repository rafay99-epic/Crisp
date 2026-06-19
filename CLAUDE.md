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
  into `nightly`**. The user squash-merges. **Never** hand-commit to `main` or
  directly to `nightly`.
- **Use Graphite (`gt`) for the PR workflow — the user reviews every PR through
  Graphite (the GitHub PR *view* is broken for them).** `gt` is installed + authed.
  Use it for branch + stack management and pushing: `gt track --parent heads/nightly`
  to put a branch on the stack, `gt submit --draft --no-interactive` to push, `gt
  sync` to pull + restack, `gt ls`/`gt log` to see the stack. Then the user reviews
  in the Graphite app. **Caveat — opening PRs:** this repo names *both* a branch and
  the rolling-release tag `nightly`, so Graphite's trunk is stored as `heads/nightly`
  to disambiguate locally — but `gt submit` then hands GitHub base `heads/nightly`,
  which it rejects, and setting the trunk to plain `nightly` breaks `gt`'s local
  resolution (no single value works for both). So **`gt submit` pushes the branch but
  can't create the PR.** Open it with `gh pr create --base nightly --draft` once `gt`
  has pushed the branch — the user still reviews it in Graphite. **Never** use `gh pr
  view`/`gh pr edit` (the broken UI). `gh api` (read-only, e.g. CodeRabbit comments)
  and `gh pr comment` (replies) are fine. Keep the no-AI-attribution rule above in
  every PR.
- **Promotion `nightly → main` is automated and uses a script, never the merge
  button.** Each promotion adds a squash commit to `main` that never lands on
  `nightly`, so the branches don't share recent history — GitHub's merge button
  (squash/merge/rebase, all of them) then does a 3-way merge against a stale base
  and conflicts on every promotion. `.github/scripts/promote.sh` sidesteps that: it
  sets `main`'s tree to exactly `origin/nightly` as one commit and pushes (no merge
  → no conflict, no rewind → no force-push). `main` keeps one commit per release, so
  the Stable version stays `0.<commit count on main>`. `promotion.yml` runs it
  **every Thursday 14:00 PKT (09:00 UTC)** + on manual dispatch: it first
  **verifies nightly** (Swift build + test + SwiftLint, and the Python engine
  tests) and only if all pass opens the changelog PR and runs `promote.sh` (pushes
  `main`, closes the PR); the push triggers `ci.yml`'s release. A red build/test
  never reaches Stable (the promote job `needs` the verify job). **Needs the `PROMOTION_TOKEN` secret** — a PAT with
  Contents + Pull requests + Workflows R/W (the push must be by a PAT to trigger
  the release, and may touch workflow files). To cut a release off-schedule, run
  `promote.sh` locally or dispatch the workflow.
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
swift test            # the Swift suite CI gates on
# engine core tests (stdlib-only, no ffmpeg/whisper); CI gates on these too:
python3 -m unittest discover -s Resources/engine/tests -t Resources/engine
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
- `Common/` — cross-cutting: `Channel` (identity from `CrispChannel`; also owns
  `logsDirectory`), `AppInfo` (bundle-id base + the `logger(_:)` factory),
  `Formatting` (`formatTime`), and the logging system (`FileLog`).
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

## Logging

Both layers write to one **per-channel, per-day** file:
`~/.crisp*/logs/<yyyy-MM-dd>.log` (beside `Originals/`, `models/`, `config/`).
- **Swift:** `AppInfo.logger(_:)` returns a `CrispLog` that tees every line to
  Apple unified logging (Console.app, unchanged) **and** the file via `FileLog`
  (a serial-queue, `O_APPEND`, daily-rotating writer — so the app, watcher, Finder
  helper, and parallel cleans can all append safely). `CrispLog` accepts the same
  `\(x, privacy: .public)` interpolation as `os.Logger`, so existing call sites
  were untouched. `CrispApp` logs a launch line + prunes files >30 days old;
  Settings has a "Reveal in Finder" row. `CleanRunner` sets `CRISP_LOG_DIR` for the
  engine and captures its stderr (uncaught Python tracebacks).
- **Python:** `crisp/enginelog.py` (`EngineLogger`) writes to the **same** daily
  file (told the dir via `CRISP_LOG_DIR` / `--log-dir`; a no-op when unset, so the
  bare CLI/library are unchanged). It's threaded through the pipeline to log every
  ffmpeg/whisper **command + exit code + stderr-on-failure** (previously discarded)
  and turns unexpected exceptions into a logged traceback + a clean NDJSON `error`.
  Line format matches Swift's for one merged timeline.

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
- **Output container** is `--container {auto,mp4,mkv,mov,m4v,ts,webm}` (also in
  `crisp/encode.py`: `resolve_container` + `container_args`). **Default `auto`
  matches the input** — an `.mkv` recording stays `.mkv`, an `.mp4` stays `.mp4`;
  an input we can't mux into (`.avi`/`.flv`) falls back to `.mp4`. `faststart` is
  applied only to the mp4 family. **`webm` is special** — it can only hold VP9/AV1
  video + Opus/Vorbis audio, so `resolve_codecs` coerces the codec choice to
  **VP9 + Opus** (software-only; no Apple HW VP9 encoder) and logs each swap.
  VP9 is software-only and slower; the Settings UI disables the video/audio/HW
  controls when WebM is selected (`OutputContainer.forcesOwnCodecs`) since they
  don't apply. The other codec combos (H.264/HEVC, AAC/Opus) cover every other
  container.
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
