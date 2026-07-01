---
id: TASK-30
title: Wire pause tighten mode into the Windows app
status: To Do
assignee: []
created_date: '2026-07-01 20:56'
updated_date: '2026-07-01 20:56'
labels: []
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/152'
priority: medium
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The engine already supports --pause-mode {remove,tighten} + --tight-pause (PR #152), and the shared settings.json schema defines pauseMode/tightPause (written by the Mac app). The Windows app just needs the wiring: EngineConfig.cs + Preset.cs properties, EngineSettings.cs (observable props, Save/Load, RecipeArgs flags), a SettingsWindow row (ComboBox + conditional gap slider), and the tighten offset mirrored in ReviewModel.cs cut proposals + MainWindowViewModel Estimate(). A complete ready-made diff exists in PR #152's history (commit 717b15a, reverted in 4dcec60 to avoid conflicting with the UI revamp) — reapply/adapt it once the new Windows UI lands. Blocked on: Windows UI revamp.
<!-- SECTION:DESCRIPTION:END -->
