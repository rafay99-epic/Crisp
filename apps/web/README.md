# @crisp/web — the Crisp marketing site

The product website for Crisp. A **dark, cinematic** site built around the app's
own identity — the blue waveform split by a cut — with heavy, premium motion.
Apple *Pro*-page energy (Final Cut / Pro Display), not a generic light template.

**Stack:** Vite + React + TypeScript + Tailwind CSS v4, **Framer Motion** for
animation and **Lenis** for smooth scroll. Package manager: **bun**.

## Highlights

- **Living waveform hero** — a continuously animating audio visualizer split by
  the cut line (`components/Wave.tsx`).
- **The cut, on scroll** — a pinned, scroll-driven section where the waveform
  removes its own silent gaps and tightens in real time, with a live time counter
  (`sections/CutStory.tsx`).
- **Cinematic feature blocks** (no bento) — alternating text + faithful CSS/SVG
  recreations of the real app UI: silence detection, a transcript with fillers
  struck out, a film-strip cut, the strength control (`components/AppBits.tsx`).
- **Premium primitives** — reveal-on-scroll, kinetic text, magnetic buttons, 3D
  tilt, count-ups (`components/Motion.tsx`).
- **The real app window**, recreated in dark-mode macOS markup so it's razor-sharp
  at any size (`components/AppWindow.tsx`, from `ContentView.swift`).
- **Install** via Homebrew (`brew install --cask rafay99-epic/apps/crisp`) or the
  direct DMG.

## Develop

From the repo root (Turborepo) or this folder:

```sh
bun install          # once, from the repo root
bun run dev          # vite dev server (turbo: `bun run dev` at root)
bun run build        # type-check + production build → dist/
bun run preview      # serve the production build
bun run lint         # tsc -b (type-check only)
```

The brand mark and favicons in `public/` are derived from the app's
`Resources/AppIcon.icns`.

## Deploy (Vercel, web UI)

This is a Turborepo, so the only thing to set is the project root:

1. **Add New… → Project**, import the `Crisp` repo.
2. Set **Root Directory** to **`apps/web`** (click *Edit* next to it). Leave
   "Include files outside the root directory" on — Vercel enables it for monorepos
   so `bun.lock` and the workspace resolve.
3. Everything else comes from `apps/web/vercel.json` — framework (Vite),
   `bun install`, `bun run build`, output `dist/`, the SPA rewrite (so `/privacy`
   and `/terms` resolve), asset caching, and security headers. Just click **Deploy**.

No env vars are required. Production deploys on every push to `main`; other branches
and PRs get preview URLs automatically.
