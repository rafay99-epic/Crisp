---
id: TASK-35.4
title: 'Windows: native updater (stop pointing at the macOS update system)'
status: To Do
assignee: []
created_date: '2026-07-02 09:24'
labels:
  - windows
  - bug
dependencies: []
parent_task_id: TASK-35
priority: high
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The update module currently targets the macOS update flow. Windows needs its own channel-aware updater consuming the Windows release feed. Per the windows-release-feed design: the DMG + .exe share ONE GitHub release per channel (stable v0.<count>, rolling nightly); mac owns the release (upsert, no delete) and windows.yml uploads the .exe. The Windows updater should download/install the .exe and compare versions numerically (never go backwards). (Note #8)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Updater reads the shared per-channel release and picks the .exe asset
- [ ] #2 Version comparison is numeric and monotonic
- [ ] #3 Update disabled on dev channel like macOS
- [ ] #4 No macOS-specific (DMG/Sparkle) assumptions remain
<!-- AC:END -->
