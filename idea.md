# Crisp — roadmap

The roadmap is **not** tracked in GitHub anymore. The "Crisp Roadmap" Project
board and its feature issues were removed — a new project-tracking tool is being
chosen.

For now, ideas and planned features live in a local **`ROADMAP.md`** on the
maintainer's machine (gitignored, not shipped). It's grouped Shipped /
In progress / Planned, with the shipping PR noted on each done item.

## GitHub Issues = bugs only

Open an issue **only** for a real defect (a reproducible bug, a regression, a
crash). **Do not** file features, ideas, or roadmap items as issues — those go in
`ROADMAP.md`. Keeping the tracker to actual bugs is deliberate.

> `area:*` labels still auto-apply to **PRs** by changed path (see
> `.github/labeler.yml`) — that's independent of issues and stays.
