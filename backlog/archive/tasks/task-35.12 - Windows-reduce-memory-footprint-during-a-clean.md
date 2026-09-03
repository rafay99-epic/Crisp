---
id: TASK-35.12
title: 'Windows: reduce memory footprint during a clean'
status: To Do
assignee: []
created_date: '2026-07-02 09:25'
labels:
  - windows
  - performance
dependencies: []
parent_task_id: TASK-35
priority: low
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A running clean peaks around ~4.5 GB (total ~7 GB): ffmpeg ~700 MB + whisper model ~700 MB (approx) plus the rest. Investigate trimming peak memory — moving whisper/render to the GPU should also change the CPU-RAM profile. Idle app is already lean at ~100 MB. (Notes #14, #27)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Peak memory during a clean measurably lower than ~4.5 GB baseline
- [ ] #2 No parity regression
- [ ] #3 Idle memory stays low (~100 MB)
<!-- AC:END -->
