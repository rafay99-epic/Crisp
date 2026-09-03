---
id: TASK-35.13
title: 'Windows: premium queue row — icon actions + backup overflow'
status: Done
assignee: []
created_date: '2026-07-02 23:15'
labels:
  - windows
  - ui
dependencies: []
parent_task_id: TASK-35
priority: medium
ordinal: 48000
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/158'
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The queue row's text buttons (Play / Reveal / Backup / Restore, plus Retry and
Review) read as clutter and the Backup–Restore pair was confusing. Replace them
with quiet Fluent icon buttons with tooltips, collapse Backup + Restore into one
"⋯" overflow flyout ("Show Backed-up Original" / "Restore a Copy…"), and demote
Add Videos / Clear to quiet commands so the accent action stands alone — the
Win11 command-bar look.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Row actions are icon buttons with tooltips + automation names
- [x] #2 Backup/Restore live in one overflow menu, verified working end-to-end
- [x] #3 One accent (primary) action visible at a time
<!-- AC:END -->
