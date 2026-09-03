---
id: TASK-35.10
title: 'Windows: speed up review-footage flow'
status: To Do
assignee: []
created_date: '2026-07-02 09:25'
labels:
  - windows
  - performance
dependencies: []
parent_task_id: TASK-35
priority: medium
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The review-footage screen was broken (old-style terminal window) and is now fixed and working, but it's slow. It runs the same shared Python code as the cleaner, so it benefits from the GPU decode work, but review-specific perf should be checked too. (Notes #3, #23)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Review footage loads/plays without noticeable lag
- [ ] #2 No terminal/console window involved
- [ ] #3 Review speed comparable to macOS
<!-- AC:END -->
