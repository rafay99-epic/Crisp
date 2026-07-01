---
id: TASK-34
title: 'Engine error-path hardening (fail fast, not fail wrong)'
status: Done
assignee: []
created_date: '2026-07-01 21:07'
updated_date: '2026-07-01 21:31'
labels: []
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/154'
priority: medium
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Grab-bag from the deep review, one PR: (1) detect_silences returns [] on nonzero ffmpeg exit → a 'successful' clean that cut nothing; raise CleanError instead. (2) transcribe() ignores whisper's exit code — truncated JSON surfaces as a raw ValueError. (3) Core ML filler helper: hard 600s timeout kills legit multi-hour runs (scale with duration), and its JSON shape validation misses top-level arrays / malformed spans. (4) clean_video.py error prints bypass the cp1252 ASCII fallback that user_log has; catch BrokenPipeError in emit → os._exit(1). (5) backup runs before ffprobe validates the file — a corrupt multi-GB source gets fully copied then rejected; probe first. (6) hw→sw→8-bit fallback re-runs FULL renders on any CleanError incl. disk-full at 95% — only fall back on early failures. (7) --keep-file + --captions silently writes no captions; warn like the fcpxml path. (8) waveform_summary loads the whole WAV (~230MB transient/hour) — stream per bucket. (9) three separate ffprobe spawns per clean could be one combined probe.
<!-- SECTION:DESCRIPTION:END -->
