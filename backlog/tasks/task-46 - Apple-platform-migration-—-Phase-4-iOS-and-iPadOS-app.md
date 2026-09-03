---
id: TASK-46
title: 'Apple-platform migration — Phase 4: iOS and iPadOS app'
status: To Do
assignee: []
created_date: '2026-09-03 20:59'
labels:
  - ios
  - migration
  - app
dependencies:
  - TASK-45
priority: medium
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
New target sharing CrispKit and the shared SwiftUI layer. iPad first (bigger thermal budget, closest to the existing desktop layout), iPhone second with a tighter default preset.

- Photos + Files import, security-scoped bookmarks
- BGContinuedProcessingTask for the render, with Live Activity progress
- Share Extension; App Intents already exist (CleanWithCrispIntent), so Shortcuts works day one
- Per-device-class duration and resolution guardrails at preflight: refuse a job that will die at 70% rather than starting it
- StoreKit 2 for the Pro tier (App Store review requires IAP); Polar stays for the direct Mac build
- Updater and the three-channel scheme become macOS-only; TestFlight is the iOS nightly

Not available on iOS: mkv/webm/ts containers, VP9, Opus, watch folders, Finder Quick Action, external editor detection. FCPXML export survives but hands off via Files/AirDrop.
<!-- SECTION:DESCRIPTION:END -->
