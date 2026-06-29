# Crisp for Windows — macOS parity checklist

Tracks every macOS feature against the Windows (Avalonia/.NET) port. The build loop
works the next unchecked item each iteration. All work lands on `feat/windows-port` (#119).

Legend: ✅ done · 🔜 remaining · 🟡 partial · ⛔ N/A on Windows (Apple-only / covered differently)

## Core pipeline (backend)
- ✅ Engine subprocess driver + NDJSON streaming (`CrispEngine` ← `CleanRunner`)
- ✅ OS-aware encoders — macOS VideoToolbox untouched; Windows NVENC→QSV→AMF→software
- ✅ Process teardown guarded for Windows (`sys.platform`)
- ✅ Cut detection / filler / retake removal (engine, via flags)
- ✅ Engine tool/log env contract (`CRISP_FFMPEG/FFPROBE/WHISPER/LOG_DIR`)
- 🟡 HW pixel formats for 10-bit (auto-converts today; p010le tuning needs a Windows GPU)

## Encoding & output settings (all wired into RecipeArgs)
- ✅ Video codec (h264/hevc) · hardware toggle · quality
- ✅ Container (mp4/mkv/mov/m4v/ts/webm — engine coerces webm→VP9/Opus)
- ✅ Audio codec (aac/opus) + bitrate
- ✅ Color depth (auto/8/10) · frame-rate mode + value
- ✅ Captions (none/srt/vtt/both)
- ✅ Backup original (`--backup-dir ~/.crisp/Originals/<date>`)
- ✅ Editor handoff (FCPXML timeline export)
- ✅ Split tracks (separate video + audio)
- ✅ Custom cutting knobs (pause/noise/keep-pause/min-keep) + smoothing (fade/crossfade/snap)
- ✅ Retake sensitivity

## Models
- ✅ Catalog: Base (147 MB) + Large v3 Turbo (574 MB)
- ✅ Resumable download + SHA-256 verify + atomic publish + self-heal
- ✅ Model picker + custom `.bin` path
- ⛔ Core ML on-device filler classifier (Apple-only; whisper path covers it)

## App UI / workflow
- ✅ Main clean screen (drop card, strength, progress, result)
- ✅ Batch queue (per-row status, remove/retry/reveal)
- ✅ Bottom-bar recipe + Clean-All + summary
- ✅ Parallel batch cleaning (bounded concurrency)
- ✅ Settings window (all knobs)
- ✅ History (past cleans, persisted, reveal)
- ✅ First-run onboarding
- ✅ Update banner (GitHub-release check via `gh auth token`)
- ✅ Drag-drop / file picker / "Open With" (multi-file, video allow-list)

## Remaining app features (the loop is working through these)
- ✅ Watch folder (auto-clean a folder) — in-app watcher; background-when-closed = Windows service follow-up
- 🔜 Presets (named recipes a queue row can pick)
- ✅ Savings estimate (pre-flight "≈ X saved" before cleaning)
- 🔜 Preview player (play the cleaned output in-app)
- 🔜 Review & edit cuts (waveform timeline, manual keep/cut)
- 🔜 Cut preview (waveform of what will be removed)
- ✅ Notifications when a batch finishes (in-app toast; OS-level toast = follow-up)
- 🔜 Tray / menu-bar quick-drop
- 🔜 Explorer right-click "Clean with Crisp" (← macOS Quick Action)
- 🔜 Restore original from backup
- 🔜 Open in detected editor (← EditorDetector; today: reveal the project)
- ✅ What's New after an update (release notes viewer)
- ✅ Diagnostics: reveal the log file
- 🔜 Channel system (stable/nightly/dev) — partial (`CrispVersion`)

## Shipping
- 🟡 Cross-publish `win-x64` self-contained — verified from macOS
- 🔜 Packaging: `vendor-win.ps1` (win64 ffmpeg/whisper/python) + MSIX/installer + signing
- 🔜 CI `windows-latest` job (build + engine tests + publish artifact)

## Deferred / N/A
- ⛔ App Intents / Shortcuts (macOS); a CLI could substitute
- ⛔ xattr output tag (BSD-only; `.crisp-source` sidecar covers re-clean dedup)
- ⛔ ResourceGovernor / Ultra preflight (replaced by simple bounded concurrency)
- 🔜 Licensing (Polar.sh) — after it lands in `nightly`
