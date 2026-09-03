---
id: TASK-35.14
title: 'Windows: onboarding step showcasing the detected GPU'
status: Done
assignee: []
created_date: '2026-07-03 00:05'
labels:
  - windows
  - ui
dependencies: []
parent_task_id: TASK-35
priority: medium
ordinal: 49000
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/158'
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a "Your hardware" page to the first-run tour (after "What Crisp preserves")
that shows the machine's detected GPU name(s) and the verified hardware-encoding
verdict from the launch probe, plus the CPU-fallback safety note. When no GPU is
detected the page is skipped entirely — Continue/Back navigation hops over it and
its footer dot is hidden. The verdict sentence is shared with the Settings
Hardware-Acceleration blurb (single source).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tour shows the detected GPU name(s) with what they accelerate
- [x] #2 Step + dot skipped when no GPU is found (verified with a stubbed probe)
- [x] #3 Back navigation also skips the hidden step
<!-- AC:END -->
