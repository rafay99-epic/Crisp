---
id: TASK-35.11
title: 'Windows: improve parallelization'
status: To Do
assignee: []
created_date: '2026-07-02 09:25'
labels:
  - windows
  - performance
dependencies: []
parent_task_id: TASK-35
priority: medium
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Parallelization needs attention on Windows — opportunity to overlap detect / transcribe / render stages and use available cores better. Lower priority than the GPU work but part of the perf arc. (Note #15)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Independent pipeline stages overlap where safe
- [ ] #2 No regression in output parity
- [ ] #3 Measurable wall-clock improvement on multi-core machines
<!-- AC:END -->
