---
id: TASK-2
title: Windows support (shared Python core + native Windows UI)
status: Done
assignee: []
created_date: '2026-07-01 19:21'
labels: []
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/119'
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Committed foundation #2 — do second.** Reuse the stdlib Python engine as-is (ffmpeg/ffprobe/whisper.cpp all ship Windows builds) and build a native Windows front-end (WinUI 3 / Windows App SDK) mirroring the macOS UI/UX. Port the cross-cutting pieces: Channel identity, GitHub-release updater, binary vendoring + signing, data-home/logs paths, Explorer shell integration. One engine, two native shells.

Roadmap: idea.md #23.
<!-- SECTION:DESCRIPTION:END -->
