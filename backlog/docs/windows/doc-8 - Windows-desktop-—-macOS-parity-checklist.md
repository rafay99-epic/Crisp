---
id: doc-8
title: Windows desktop — macOS parity checklist
type: other
created_date: '2026-07-01 19:42'
---


# Crisp for Windows — macOS parity checklist

Tracks every macOS feature against the Windows (Avalonia/.NET) port. The build loop
works the next unchecked item each iteration. All work lands on `feat/windows-port` (#119).

Legend: ✅ done · 🔜 remaining · 🟡 partial · ⛔ N/A on Windows (Apple-only / covered differently)

## Core pipeline (backend)
- ✅ Engine subprocess driver + NDJSON streaming (`CrispEngine` ← `CleanRunner`)
- ✅ OS-aware encoders — macOS VideoToolbox untouched; Windows NVENC→QSV→AMF→software
- ✅ Process teardown guarded for Windows (`sys.platform`)
- ✅ Engine imports + runs on real Windows (Windows CI caught + fixed: CDLL(None) TypeError, log-handle file lock)
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
- ✅ Model picker + custom `.bin` path (Browse picker in Settings and the onboarding
  model step; works on all three channels)
- 🟡 Wren filler classifier ("custom model") — app side fully ported: catalog pinned to
  the same HF URL/sha as macOS, download + sidecar config, onboarding option card,
  Settings toggle with the macOS enable/disable semantics (captions cleared+disabled,
  retakes disabled, whisper only for captions), `--filler-backend coreml
  --filler-model` + `CRISP_FILLER` wiring, per-model install banners. Shows honestly
  as "coming soon" until the remaining piece ships: a **Windows `crisp-filler.exe`
  inference helper** (the macOS one is Swift/Core ML; Windows needs an ONNX build
  from the published `Wren.pt` weights)

## App UI / workflow
- ✅ Main clean screen (drop card, strength, progress, result)
- ✅ Batch queue (per-row status, remove/retry/reveal)
- ✅ Bottom-bar recipe + Clean-All + summary
- ✅ Parallel batch cleaning (bounded concurrency)
- ✅ Settings window (all knobs)
- ✅ History (past cleans, persisted, reveal)
- ✅ First-run onboarding — the full paged tour (welcome → what it removes → what it
  preserves → how it works → **speech-model choice + download, a mandatory gate like
  macOS** → preferences → automate → done); Skip routes to the model step, completion
  persists per channel, re-openable from Settings ▸ About
- ✅ Update banner (GitHub-release check via `gh auth token`)
- ✅ Drag-drop / file picker / "Open With" (multi-file, video allow-list)

## Remaining app features (the loop is working through these)
- ✅ Watch folder (auto-clean a folder) — in-app watcher; background-when-closed = Windows service follow-up
- ✅ Presets (named recipes a queue row can pick) — model + macOS-shared round-trip (`--preset-test`); Settings card (save current / make default / delete) + per-row picker in the queue
- ✅ Savings estimate (pre-flight "≈ X saved" before cleaning)
- 🟡 Preview player — "Play" opens the cleaned output in the system player (fully testable); embedded in-app player would need a native video dependency (LibVLCSharp) = follow-up
- ✅ Review & edit cuts (waveform timeline, manual keep/cut) — `ReviewWindow`: analyzes the file, lists each proposed pause as a toggle, live-updates the waveform, and Apply renders exactly the approved segments via `--keep-file` (`ReviewPlan` math covered by `--review-test`). [GUI render verified by user E2E]
- ✅ Cut preview (waveform of what will be removed) — `WaveformView` draws `--analyze` peaks with removed pauses shaded red; "Preview cuts" button, live-updates as strength changes
- ✅ Notifications when a batch finishes (in-app toast; OS-level toast = follow-up)
- ✅ Tray icon (menu: Open Crisp / Quit; click to show) — port of the menu-bar item
- ✅ Explorer right-click "Clean with Crisp" (← macOS Quick Action) — registry verb via `reg.exe`, Settings toggle; registry behaviour is Windows-only (manual-test on Windows)
- ✅ Backed-up original — captured + a "Backup" row button reveals the pristine copy
- ✅ Open in detected editor — `EditorDetector` probes installed editors (Resolve/Premiere/Shotcut/Kdenlive on Win; Resolve/FCP on Mac); editor-export rows get an "Open in <editor>" button that launches it + reveals the project (`--editor-test`)
- ✅ What's New after an update (release notes viewer)
- ✅ Diagnostics: reveal the log file
- ✅ Channel system (stable/nightly/dev) — `Channel` enum (CRISP_CHANNEL), isolated data homes (~/.crisp / -nightly / -dev), display name + header badge, dev has no updater, nightly tracks pre-releases (`--channel-test`)

## Shipping
- ✅ Cross-publish `win-x64` self-contained — `dotnet publish` produces Crisp.exe (verified from macOS + in CI)
- ✅ CI `windows-latest` job (`windows.yml`: build + C# self-tests + shared-engine Python tests on real Windows + publish win-x64 artifact)
- 🟡 Packaging — `vendor-win.ps1` (pinned + hash-checked win64 ffmpeg 8.1.2 + python 3.13.14 + whisper-cli from tag v1.9.0) **validated on real Windows CI** + a `package` job that bundles the self-contained build and builds `Crisp-Setup.exe` via Inno Setup (`crisp.iss`). Remaining: **code signing only** (needs a cert so SmartScreen doesn't warn)

## Deferred / N/A
- ⛔ App Intents / Shortcuts (macOS); a CLI could substitute
- ⛔ xattr output tag (BSD-only; `.crisp-source` sidecar covers re-clean dedup)
- ⛔ ResourceGovernor / Ultra preflight (replaced by simple bounded concurrency)
- ⛔ Licensing — out of scope: Windows stays free + open source (no monetization until the
  port is a proven 1:1 functional match; no license code is added here)

## Credits
- **@codeboost-tr** — Windows engine hardening picked up from PRs #120 and #124:
  the `tools.py` `.exe` resolution that avoids `WinError 193`, the `clean_video.py`
  ASCII fallback for legacy Windows consoles, the fully-async `gh`-token lookup, and
  the de-duplicated video-extension list. Thank you. (Co-authored in git.)
