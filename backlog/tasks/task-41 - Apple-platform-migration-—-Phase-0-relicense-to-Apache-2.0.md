---
id: TASK-41
title: 'Apple-platform migration — Phase 0: relicense to Apache-2.0'
status: Done
assignee: []
created_date: '2026-09-03 20:59'
labels:
  - ios
  - migration
  - licensing
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/191'
priority: high
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GPL-3.0 is incompatible with App Store distribution (anti-tivoization vs Apple's per-device usage terms), which blocks the iOS/iPadOS port entirely. Relicense to Apache-2.0: open source, explicit patent grant, withholds trademark rights on the Crisp name and branding. Sole copyright holder (89 of 90 commits), so this is unilateral.

Includes NOTICE listing the bundled third-party binaries (FFmpeg, whisper.cpp, CPython) and model provenance, plus the website Terms/Privacy copy.
<!-- SECTION:DESCRIPTION:END -->
