---
id: TASK-3
title: >-
  Restructure into a connected monorepo (packages/core + services, apps/*,
  research/)
status: Done
assignee: []
created_date: '2026-07-01 19:21'
labels: []
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/134'
  - 'https://github.com/rafay99-epic/Crisp/pull/135'
  - 'https://github.com/rafay99-epic/Crisp/pull/137'
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Goal
Turn Crisp into a **connected monorepo** where the engine, services, and apps are cleanly separated — so a feature added to one surface flows to the others, and the Python core is independent with its own structure + tests (not buried inside the Swift app's `Resources/`).

## Problem today
- The Python engine lives under `apps/desktop/Resources/engine/` — i.e. **shoved inside the macOS Swift app**, and the Windows app reaches *up and over* into it (`apps/desktop-win` → `apps/desktop/Resources/engine`).
- The Polar licensing service (`services/polar-license-lookup`) sits at the repo root, not packaged.
- ML/research code has no settled home.

## Proposed structure
```
packages/
  core/            # the Python cleaning engine — independent, own tests + packaging
    crisp/         # the package (config, tools, detect, edit, encode, pipeline, …)
    clean_video.py # CLI entrypoint
    tests/
    pyproject.toml
  services/
    polar-license/ # the Node licensing/payment service (moved from services/)
apps/
  desktop/         # macOS (Swift/SwiftUI)
  desktop-win/     # Windows (Avalonia/.NET)
  website/
research/          # ML data, training/eval code, model research (Wren, etc.)
```

## Why
- **One core, two apps.** Both desktop apps consume `packages/core` via the same NDJSON contract + env vars (`CRISP_ENGINE_SCRIPT`, `CRISP_FFMPEG`, …) — already the seam, just relocated.
- **Independent core.** `packages/core` gets its own `pyproject.toml` + test suite + CI, versioned on its own.
- **Shared contracts → automatic parity.** A new engine flag or NDJSON field is added once in core; both apps pick it up. (UI still per-platform, but the capability is shared.)

## Migration (incremental, each step green)
- [x] Move `apps/desktop/Resources/engine` → `packages/core` (git-mv, preserve history)
- [x] Update `build.sh` / `vendor.sh` (macOS) + `ResolveEngineScript` / `windows.yml` (Windows) to point at `packages/core`
- [x] Update both CI engine-test jobs to run `packages/core/tests`
- [x] Move `services/polar-license-lookup` → `packages/services/polar-license`
- [x] Create `research/` and relocate ML/research assets
- [x] Add a top-level README documenting the monorepo layout + how each app finds the core

## Open questions
- Does the macOS bundle still vendor the core from `packages/core` at build time? (Yes — same `vendor.sh`, new path.)
- Versioning: does `packages/core` get its own version, or stay pinned to the app version?

> Tracking epic — child PRs land incrementally on `nightly`. Does **not** block the Windows port (#87 / #119), which can merge first against the current layout.
<!-- SECTION:DESCRIPTION:END -->
