---
id: TASK-44
title: 'Apple-platform migration — Phase 2: AVFoundationBackend on macOS'
status: To Do
assignee: []
created_date: '2026-09-03 20:59'
labels:
  - ios
  - migration
  - engine
  - media
dependencies:
  - TASK-43
priority: high
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The de-risking phase. Build probe / extractPCM / silence detection / render against AVFoundation behind a MediaBackend protocol, shipped on macOS behind a setting defaulted off, so both backends can run over the same file and be compared.

- ffprobe metadata + fps -> AVAsset / AVAssetTrack
- ffmpeg audio extract -> AVAssetReaderAudioMixOutput (16 kHz mono PCM, no temp WAV)
- ffmpeg silencedetect -> vDSP RMS over that PCM (pure, deterministic, no stderr parsing)
- ffmpeg trim/concat/xfade -> AVMutableComposition + AVAssetWriter. NOT AVAssetExportSession, which has documented trim drift.

Blocking sub-task: AVAssetWriter has no CRF. Needs a bitrate ladder (resolution x fps x codec) calibrated against current CRF-20 HEVC High output on a fixture set, measured with VMAF/SSIM. This is the one place the port can silently get worse; do not ship on a guess.

Validate: identical cut points, A/V sync across long timelines, frame counts on VFR sources.
<!-- SECTION:DESCRIPTION:END -->
