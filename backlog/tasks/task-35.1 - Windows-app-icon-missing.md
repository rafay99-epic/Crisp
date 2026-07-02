---
id: TASK-35.1
title: 'Windows: app icon missing'
status: To Do
assignee: []
created_date: '2026-07-02 09:24'
labels:
  - windows
  - bug
dependencies: []
parent_task_id: TASK-35
priority: medium
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Windows build ships with no app icon in place. Wire up the per-channel Windows icon (mirror the macOS channel-colored icon: blue stable / amber nightly / purple dev) so the app has a proper icon in the taskbar, window, and installer. (Note #4)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 App shows a proper icon in the taskbar, title bar, and Alt-Tab
- [ ] #2 Installer and .exe carry the icon
- [ ] #3 Icon varies per channel like macOS
<!-- AC:END -->
