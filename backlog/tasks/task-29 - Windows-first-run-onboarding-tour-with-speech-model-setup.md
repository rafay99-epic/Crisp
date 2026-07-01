---
id: TASK-29
title: Windows first-run onboarding tour with speech-model setup
status: Done
assignee: []
created_date: '2026-07-02'
updated_date: '2026-07-02'
labels: []
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/155'
priority: high
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Goal
Replace the Windows app's single welcome overlay with the **full paged onboarding
tour** — the same flow and logic as macOS (welcome → what it removes → what it
preserves → how it works → **speech-model choice + download as a mandatory gate** →
preferences → automate → done), expressed in the Windows 11 design language
(Fluent icons, cards, accent action, page dots) so it feels native, not a port.

## Key points
- Models are **never bundled** — Base / Large v3 Turbo download from Hugging Face
  during onboarding (resumable, SHA-256 verified, atomic publish), so the installer
  stays small.
- A **custom whisper.cpp `.bin`** can be loaded instead (Browse in the tour and in
  Settings) — on stable, nightly, and dev alike; each channel keeps its own choice
  in its own data home.
- Skip routes to the unsatisfied model step (never exits past the gate); completion
  persists per channel; re-openable from Settings ▸ About ▸ Welcome Tour.
- Headless `--onboarding-test` self-test wired into windows.yml CI.
<!-- SECTION:DESCRIPTION:END -->
