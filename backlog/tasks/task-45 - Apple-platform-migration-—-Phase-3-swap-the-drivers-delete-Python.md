---
id: TASK-45
title: 'Apple-platform migration — Phase 3: swap the drivers, delete Python'
status: To Do
assignee: []
created_date: '2026-09-03 20:59'
labels:
  - ios
  - migration
  - engine
dependencies:
  - TASK-44
priority: high
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WhisperKit (MIT, Core ML, DTW word timestamps) replaces whisper-cli. crisp-filler and crisp-embed flip from .executableTarget to library targets and are called in-process — they are already Swift on iOS-available frameworks (Core ML + Accelerate, NaturalLanguage), so the target type is the whole change.

Delete packages/engine, Scripts/vendor.sh, and the vendored python/ffmpeg/ffprobe/whisper-cli tree. CleanRunner stops being a subprocess driver and becomes an async call; the NDJSON Event decoder and StderrDrain go with it. macOS keeps FFmpegBackend as the optional advanced-container path (mkv/webm/ts, VP9, Opus).

Risk: WhisperKit DTW timestamps will be close but not identical to whisper.cpp's -dtw -ojf output, and retake detection keys on exact word onsets. Diff on a fixture corpus with a tolerance budget BEFORE deleting the old path; retune RETAKE_* thresholds if the drift is systematic.
<!-- SECTION:DESCRIPTION:END -->
