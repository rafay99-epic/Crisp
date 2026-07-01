---
id: TASK-33
title: Fix O(n²) render filter graph for many cuts
status: Done
assignee: []
created_date: '2026-07-01 21:07'
updated_date: '2026-07-01 22:47'
labels: []
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/156'
priority: medium
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
build_filter_graph emits one trim/atrim branch per kept segment all fed from [0:v]/[0:a], so every decoded frame passes through every branch. Measured (60s clip, ultrafast): 50 cuts=0.7s, 150=4.6s, 300=16.9s, 600=61s — quadruples per doubling. Hour-long talking-head footage easily hits hundreds of cuts (fillers+pauses), so graph overhead can dwarf the encode. Fix for the default hard-cut path (crossfade=0): a single select='between(t,a,b)+...'/aselect + setpts/asetpts pair, or batch segments through intermediate concats. Keep the current graph for crossfade mode.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Excluded from PR #154 on purpose — needs a render-architecture change (per-segment fades rule out a plain select= graph; likely per-segment encodes + concat demuxer, or a select fast-path when fade==0). Next up as its own PR.
<!-- SECTION:NOTES:END -->
