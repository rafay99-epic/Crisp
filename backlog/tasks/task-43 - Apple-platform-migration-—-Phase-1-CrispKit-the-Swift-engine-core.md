---
id: TASK-43
title: 'Apple-platform migration — Phase 1: CrispKit, the Swift engine core'
status: Done
assignee: []
created_date: '2026-09-03 20:59'
labels:
  - ios
  - migration
  - engine
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/193'
priority: high
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port the platform-free half of the engine to Swift as packages/CrispKit (macOS 15 / iOS 18): config, filler matching, retake detection, captions, frame-rate policy, waveform, plus a difflib-compatible Ratcliff-Obershelp ratio.

Parity is proved, not assumed: Tools/generate-fixtures.py runs the Python engine over a corpus and writes JSON goldens; Swift tests assert against those. CI re-runs the generator and fails on drift, so the two implementations cannot diverge while both exist.

Not wired into the app — the media layer is the risky part and should land on a core already proven correct.
<!-- SECTION:DESCRIPTION:END -->
