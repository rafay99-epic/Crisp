---
id: TASK-33
title: Fix O(n²) render filter graph for many cuts
status: To Do
assignee: []
created_date: '2026-07-01 21:07'
labels: []
dependencies: []
priority: medium
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
build_filter_graph emits one trim/atrim branch per kept segment all fed from [0:v]/[0:a], so every decoded frame passes through every branch. Measured (60s clip, ultrafast): 50 cuts=0.7s, 150=4.6s, 300=16.9s, 600=61s — quadruples per doubling. Hour-long talking-head footage easily hits hundreds of cuts (fillers+pauses), so graph overhead can dwarf the encode. Fix for the default hard-cut path (crossfade=0): a single select='between(t,a,b)+...'/aselect + setpts/asetpts pair, or batch segments through intermediate concats. Keep the current graph for crossfade mode.
<!-- SECTION:DESCRIPTION:END -->
