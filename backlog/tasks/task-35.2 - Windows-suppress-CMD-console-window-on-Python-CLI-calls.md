---
id: TASK-35.2
title: 'Windows: suppress CMD console window on Python/CLI calls'
status: To Do
assignee: []
created_date: '2026-07-02 09:24'
labels:
  - windows
  - bug
dependencies: []
parent_task_id: TASK-35
priority: high
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every time the app shells out to the Python engine (or any CLI), a cmd/console window flashes on screen. It should never appear. Spawn child processes with no console window (CREATE_NO_WINDOW / hidden window / UseShellExecute=false + CreateNoWindow=true) across all engine invocations. (Note #5)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No console window appears during clean, review, or model download
- [ ] #2 Applies to every python/ffmpeg/whisper child process, not just one path
- [ ] #3 Process stdout/stderr still captured for logging
<!-- AC:END -->
