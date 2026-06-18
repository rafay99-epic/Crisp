# @crisp/web — the Crisp marketing site

The product website for Crisp, built with **Vite + React + TypeScript + Tailwind
CSS v4**. Native, Apple-like design that mirrors the macOS app's language (SF Pro
via the system stack, macOS system colors, the waveform-with-cut brand mark).

The product shot in the hero is **not a screenshot** — it's a faithful HTML/CSS
recreation of the real app window (`components/AppWindow.tsx`, built from
`apps/desktop/.../Views/ContentView.swift`), so it stays sharp at any resolution.

## Develop

From the repo root (Turborepo) or this folder:

```sh
pnpm install         # once, from the repo root
pnpm dev             # vite dev server (turbo: `pnpm dev` at root)
pnpm build           # type-check + production build → dist/
pnpm preview         # serve the production build
pnpm lint            # tsc -b (type-check only)
```

## Layout

- `src/components/` — `Logo` (SVG brand mark), `Icons` (SF Symbol-style),
  `AppWindow` (the app recreation + `ResultPanel`).
- `src/sections/` — `Nav`, `Hero`, `Features`, `HowItWorks`, `Privacy`,
  `Download`, `Footer`.
- `src/site.ts` — shared links/copy (repo URL, release link, requirements).
- `src/index.css` — Tailwind import + the design tokens (`@theme`).

The brand mark and favicons in `public/` are derived from the app's
`Resources/AppIcon.icns`.
