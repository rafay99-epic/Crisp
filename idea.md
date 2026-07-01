# Crisp — roadmap

The roadmap is managed with **[Backlog.md](https://github.com/MrLesk/Backlog.md)** —
plain Markdown task files tracked in git under **`backlog/`**, viewed as a Kanban
board. It is **not** in GitHub Issues/Projects.

## Use it

```sh
backlog board                       # Kanban in the terminal
backlog browser                     # web UI at http://localhost:6420 (drag-and-drop)
backlog task list                   # list tasks
backlog task create "New idea" -d "…" --priority medium
backlog task edit task-7 -s "In Progress"
```

Tasks live in `backlog/tasks/*.md`. Each has a **status** (`To Do` / `In Progress`
/ `Done`), a **priority** (`high`/`medium`/`low`), and — for shipped work — the
**PR URL in its `references`**. A user-scope **MCP server** (`backlog mcp start`)
lets AI agents create/update tasks as PRs progress, so every PR stays tracked.

## GitHub Issues = bugs only

Open a GitHub issue **only** for a real defect (a reproducible bug, a regression,
a crash). **Do not** file features, ideas, or roadmap items as issues — those are
Backlog.md tasks.

> `area:*` labels still auto-apply to **PRs** by changed path (see
> `.github/labeler.yml`) — that's independent of issues and stays.
