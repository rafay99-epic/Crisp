---
id: TASK-35.8
title: 'Windows: run transcription on GPU (whisper off CPU)'
status: To Do
assignee: []
created_date: '2026-07-02 09:25'
labels:
  - windows
  - performance
dependencies:
  - TASK-35.7
parent_task_id: TASK-35
priority: high
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Whisper transcription currently runs entirely on CPU on Windows — the single biggest CPU sink and a major cause of the ~700 MB whisper RAM + high CPU. Move it to GPU where available (whisper.cpp CUDA/Vulkan/etc.), gated by the GPU detection task, with CPU fallback. (Notes #12, #13)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Transcription uses the GPU when one is available
- [ ] #2 Falls back to CPU when no GPU
- [ ] #3 Measurable drop in CPU usage / transcription time vs current baseline
<!-- AC:END -->
