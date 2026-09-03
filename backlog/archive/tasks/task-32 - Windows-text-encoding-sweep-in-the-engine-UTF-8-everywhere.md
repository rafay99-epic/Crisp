---
id: TASK-32
title: Windows text-encoding sweep in the engine (UTF-8 everywhere)
status: Done
assignee: []
created_date: '2026-07-01 21:07'
updated_date: '2026-07-01 21:31'
labels: []
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/154'
priority: high
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Systemic: every subprocess pipe uses text=True with no encoding= (detect.py 98/111/168/224, tools.py 55/89/198/291/303, split.py 70, pipeline.py 206, edit.py 393 stderr log + 390 concat list), and detect.py 188 reads whisper's UTF-8 JSON with the locale codepage. On Windows (cp1252, errors=strict) a non-ASCII filename or metadata crashes the clean — sometimes AFTER a successful hour-long render — or silently mojibakes captions/retake matching. Fix: encoding='utf-8', errors='replace' on every tool-output read (a shared runner helper would fix it once). Both review agents independently flagged this as the #1 Windows blocker for the shared engine.
<!-- SECTION:DESCRIPTION:END -->
