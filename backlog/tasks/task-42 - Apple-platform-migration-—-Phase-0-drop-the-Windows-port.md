---
id: TASK-42
title: 'Apple-platform migration — Phase 0: drop the Windows port'
status: Done
assignee: []
created_date: '2026-09-03 20:59'
labels:
  - ios
  - migration
  - cleanup
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/192'
priority: high
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Crisp targets Apple platforms only. Remove apps/desktop-win (Avalonia/.NET), windows.yml, the area:platform labeler entry, and the 20 Windows backlog tasks (archived).

The real win is engine simplification: tools.py loses the .exe resolution branch and the whole registry GPU detection + hardware-encoder probing block; encode.py collapses the per-platform encoder table, vendor filter and NVENC/QSV/AMF quality args to a VideoToolbox constant. Apple Silicon always has a media engine, so none of that probing was load-bearing here.

108 files, -7629 lines.
<!-- SECTION:DESCRIPTION:END -->
