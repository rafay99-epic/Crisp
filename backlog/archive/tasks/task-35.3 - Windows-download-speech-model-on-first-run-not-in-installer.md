---
id: TASK-35.3
title: 'Windows: download speech model on first run (not in installer)'
status: In Progress
assignee: []
created_date: '2026-07-02 09:24'
updated_date: '2026-07-03 08:22'
labels:
  - windows
  - bug
dependencies: []
parent_task_id: TASK-35
priority: high
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The engine no longer bundles the model inside the app, but it's still packed into the Windows INSTALLER, which bloats the download and re-ships on every update. It should be downloaded on first run into the channel data dir, mirroring the macOS ModelStore (HTTP-Range resume + SHA-256 verify + atomic publish + self-heal from disk state). Gate the Clean action until the model is ready (only when filler removal is on). (Notes #2, #7)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Installer no longer contains ggml-base.en.bin
- [ ] #2 Model downloads once on first run with resume + SHA-256 verify + atomic publish
- [ ] #3 Interrupted/corrupt/deleted download self-heals on next launch
- [ ] #4 Clean gated until model ready when filler removal is on
<!-- AC:END -->
