---
id: TASK-35.5
title: 'Windows: versioning scheme'
status: To Do
assignee: []
created_date: '2026-07-02 09:25'
labels:
  - windows
  - bug
dependencies: []
parent_task_id: TASK-35
priority: medium
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The current Windows version system is poor; find a Windows-appropriate alternative. It must stay consistent with the shared scheme (stable = 0.<total commit count on main>, nightly ordered by build number) and must be monotonic since the updater compares numerically. Decide how the .exe/installer version metadata is stamped on Windows. (Note #9)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Windows version derives from the same source as macOS (commit count / build number)
- [ ] #2 Version is monotonic and never goes backwards
- [ ] #3 Installer/.exe file version metadata matches the app-reported version
<!-- AC:END -->
