---
id: TASK-35.9
title: 'Windows: GPU-accelerated encode + decode for rendering'
status: In Progress
assignee: []
created_date: '2026-07-02 09:25'
updated_date: '2026-07-03 08:22'
labels:
  - windows
  - performance
dependencies:
  - TASK-35.7
parent_task_id: TASK-35
priority: high
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rendering is the slowest part — slow on Mac, much slower on Windows — and is likely doing software encoding. Use hardware encode AND decode (NVENC/AMF/QSV, CUDA where it applies) for the trim/concat re-render, gated by GPU detection with software fallback. Must preserve output parity: same resolution/fps, no silent quality downgrade. Expected to be a long, painful effort but the main perf win. (Notes #17, #18, #21, #22)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Render uses HW encode and HW decode when available
- [ ] #2 Falls back to software automatically on failure
- [ ] #3 Output stays at parity with macOS (resolution/fps/quality unchanged)
- [ ] #4 Measurable render-time and end-of-encode CPU reduction vs the 83–90% baseline
<!-- AC:END -->
