---
id: TASK-35
title: 'Windows port: POC → macOS parity (refinement)'
status: To Do
assignee: []
created_date: '2026-07-02 09:24'
labels:
  - windows
dependencies: []
priority: high
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Umbrella for refining the Windows port (Avalonia/.NET app at apps/desktop-win, shared Python engine). First real test on Windows hardware proved the port works and output is IDENTICAL to the macOS app (same clean_video.py) — so this is refinement, not build-from-scratch. Subtasks track the specific Windows-only bugs and performance work; this parent holds the shared context, principles, benchmarks, and completed items.

PRINCIPLES (do not violate):
- Parity gate: if the Windows output matches the macOS app, ship it; if it doesn't, it's not done.
- Mac first: new features land on macOS first, port to Windows later.
- Windows 11 look is the target, but this build is a POC — theme/polish comes after correctness.
- Build ON Windows: use native Windows toolchains (CUDA, HW encoders) rather than assuming the Mac path.

DONE so far:
- Onboarding process removed on Windows.
- Speech model no longer bundled inside the app (engine unbundled). NOTE: still shipped inside the INSTALLER — see subtask to make it a first-run download.

POC BENCHMARKS (first Windows run — baseline to beat):
- Output identical to macOS (same engine).
- Idle app memory ~100 MB (good).
- Peak memory while running ~4.5 GB; ffmpeg ~700 MB + whisper model ~700 MB (approx), total ~7 GB.
- CPU at end of encoding: 83–90%.
- Dell Inspiron 15 (8th Gen): ~46% CPU overall (whole system, after reducing process count).
- Rendering slow on MacBook, much slower on Windows.
- When a clean finishes the UI shows Play / Reveal / Backup / Restore (matches Mac).

ROOT CAUSE for most perf work: on Windows the GPU is idle and everything (transcribe, encode, decode) runs on CPU — likely software encoding. Moving whisper + render to the GPU is the main arc.
<!-- SECTION:DESCRIPTION:END -->
