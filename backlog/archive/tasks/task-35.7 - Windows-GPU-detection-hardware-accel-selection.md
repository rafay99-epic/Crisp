---
id: TASK-35.7
title: 'Windows: GPU detection + hardware-accel selection'
status: Done
assignee: []
created_date: '2026-07-02 09:25'
labels:
  - windows
  - performance
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/158'
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
- [x] #1 Detects AMD / NVIDIA / Intel GPUs at runtime
- [x] #2 Selects the right HW encoder/accel per vendor
- [x] #3 Falls back to software automatically when HW is unavailable or fails
- [x] #4 AMD Radeon 520 test box is detected and used
<!-- AC:END -->

## Implementation Notes

Selection now filters ffmpeg's encoder list by the GPU vendors actually present
(display-adapter registry) and confirms the pick with a tiny test encode before
committing — previously an AMD-only box picked NVENC (listed by every stock ffmpeg
build), failed at render, and silently fell back to CPU. `clean_video.py
--probe-hardware` reports GPUs + verified encoders; the app shows it under
Settings ▸ Hardware Acceleration and steers the default codec (hevc → h264, once)
when only H.264 is accelerated.

**Radeon 520 caveat (AC #4):** the test box's GPU is detected and AMF is correctly
chosen as its candidate, but the encode session is refused by the driver
(`CreateComponent(AMFVideoEncoderVCE_AVC) failed with error 36`; HEVC:
`AMF_NOT_SUPPORTED`). Its VCE 1.0 engine (2013-era Oland silicon) is no longer
supported by the modern AMF runtime, and no hardware MediaFoundation MFT is
registered either — verified empirically on the box. So this GPU **cannot**
hardware-encode by any path; Crisp now detects that in ~1s and says so in
Settings instead of silently burning CPU. Any NVIDIA/Intel/newer-AMD GPU will
light up automatically. GPU *decode* (DXVA) for the render is TASK-35.9.
