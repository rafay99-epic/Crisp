---
id: TASK-35.6
title: 'Windows: verify log file location'
status: Done
assignee: []
created_date: '2026-07-02 09:25'
updated_date: '2026-07-03 08:22'
labels:
  - windows
dependencies: []
parent_task_id: TASK-35
priority: low
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Confirm where the Windows build writes logs. They should land in the per-channel data dir alongside Originals/, models/, config/ — mirroring the macOS ~/.crisp*/logs/<yyyy-MM-dd>.log daily-rotating file, with both the app and the Python engine (via CRISP_LOG_DIR) writing to the same file. Add a "reveal logs" affordance if missing. (Note #25)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Logs written to the per-channel data dir, daily-rotating
- [ ] #2 App and Python engine share the same log file
- [ ] #3 User can reveal the logs folder from the UI
<!-- AC:END -->
