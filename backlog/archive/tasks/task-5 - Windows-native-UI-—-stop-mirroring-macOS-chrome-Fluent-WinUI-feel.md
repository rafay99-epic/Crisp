---
id: TASK-5
title: Windows-native UI — stop mirroring macOS chrome (Fluent/WinUI feel)
status: Done
assignee: []
created_date: '2026-07-01 19:21'
updated_date: '2026-07-02'
labels: []
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/153'
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Goal
Make the Windows app feel like a **native Windows application**, not a port that mirrors macOS chrome. Functionality is already 1:1 (see #87) — this is purely the look, layout, and interaction language.

## Why
Right now `apps/desktop-win` reproduces the macOS layout closely. It works, but it reads as a "macOS app on Windows." Windows users expect Windows conventions.

## Direction (to refine with visual feedback)
- **Fluent / WinUI feel** — Mica/Acrylic backdrop, Segoe UI Variable, Fluent iconography, native title bar + window controls, standard Windows spacing/affordances.
- **Windows-native patterns** — `NavigationView` / breadcrumb where it fits, Windows-style settings page, native context menus, proper light/dark + accent-color following the system.
- **Keep the shared functionality + engine contract identical** — only the View layer changes; ViewModels/Services stay.
- Revisit: drag-drop affordance, the queue list, the Review/waveform surface, the model-download UX — each re-skinned to Windows.

## Sequencing
1. First: confirm the **functional** first iteration works on a real Windows machine (#87 / #119).
2. Then: iterate the UI here with screenshots/visual feedback until it feels native.

## Non-goals
- No functional change; no engine change.
- Not blocking the functional merge to nightly.

> Tracking epic — UI-only PRs. Depends on #87 landing first.
<!-- SECTION:DESCRIPTION:END -->
