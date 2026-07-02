---
id: TASK-35.7
title: 'Windows: GPU detection + hardware-accel selection'
status: To Do
assignee: []
created_date: '2026-07-02 09:25'
labels:
  - windows
  - performance
dependencies: []
parent_task_id: TASK-35
priority: high
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GPU detection needs work — the test box has an AMD Radeon 520 that sits idle while everything runs on CPU. Detect the machine's GPU(s) and pick a hardware path: AMD (AMF), NVIDIA (CUDA/NVENC), Intel (QSV), with automatic software fallback when no usable GPU/media engine exists (same pattern as the macOS HW→SW fallback). This is the foundation for GPU transcription and GPU render. (Notes #6, #13, #18)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Detects AMD / NVIDIA / Intel GPUs at runtime
- [ ] #2 Selects the right HW encoder/accel per vendor
- [ ] #3 Falls back to software automatically when HW is unavailable or fails
- [ ] #4 AMD Radeon 520 test box is detected and used
<!-- AC:END -->
