---
id: TASK-31
title: Atomic render output — never write the cleaned file in place
status: Done
assignee: []
created_date: '2026-07-01 21:07'
updated_date: '2026-07-01 21:31'
labels: []
dependencies: []
references:
  - 'https://github.com/rafay99-epic/Crisp/pull/154'
priority: high
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
render() (crisp/edit.py ~400) hands ffmpeg the final out_path directly. Because a re-clean of the same source deliberately resolves to its PREVIOUS output (xattr match, pipeline.py ~416), a failed/cancelled render (NDJSON cancel = SIGKILL of the process group, no cleanup) truncates or corrupts the user's existing good _cleaned file — the one real data-loss path in the engine, and it violates product philosophy #2. Fix: render to '<stem>.part<suffix>' in the same dir and os.replace() on success, mirroring _publish_atomic on the editor path. Also: wrap the progress loop so a callback exception kills ffmpeg instead of orphaning it.
<!-- SECTION:DESCRIPTION:END -->
