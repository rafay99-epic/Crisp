---
id: doc-9
title: macOS desktop — overview
type: readme
created_date: '2026-07-01 19:43'
---


# macOS desktop (`apps/desktop`)

The primary Crisp app — native SwiftUI, macOS 14+. This folder collects
macOS-desktop-specific docs (more to come).

- **Build / run:** from `apps/desktop`, `./dev.sh` (Dev channel, side by side with
  Stable) or `./build.sh` (Stable → `build/Crisp.app`).
- **Architecture:** layered under `Sources/Crisp/` (App / Common / Models /
  Services / Views), shared logic in `CrispCore`. See `CLAUDE.md` →
  "Desktop architecture".
- **Engine:** drives the shared Python core in `packages/engine` as a subprocess
  (NDJSON). See the "Core Python engine — notes" doc in `engine/`.
- **Channels:** Stable / Nightly / Dev — see `CLAUDE.md` → "Versioning, channels
  & releases".
