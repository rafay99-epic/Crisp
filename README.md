<div align="center">

# 🎬 Crisp

**Make your recordings crisp.**

A native macOS app that automatically removes **long pauses/silence** and
**filler words** (um, uh, hmm, aww…) from your screen-recordings — from the audio
*and* the video together — producing tight jump-cuts so you can skip straight to
the real editing.

Your original is **never touched**: it's backed up first, and the result is saved
as a new `…_cleaned.mp4` next to it.

**📖 [Read the docs](https://www.cubic.dev/wikis/rafay99-epic/Crisp)**

</div>

---

## Install (build from source)

Crisp is a native SwiftUI app. You need **macOS 14+**, **Xcode**, and **Homebrew**.

```sh
git clone https://github.com/rafay99-epic/Crisp.git
cd Crisp
./setup.sh                     # installs ffmpeg + whisper.cpp, downloads the model
cd apps/desktop && ./dev.sh    # builds & launches "Crisp Dev"
```

For a Stable build instead of Dev: `cd apps/desktop && ./build.sh` →
`build/Crisp.app`.

## Using it

1. Open Crisp. **Drag a video onto the window** (or click *Choose video…*). You
   can pick several at once.
2. Choose **how much to cut** (Gentle → Very aggressive) and whether to remove
   filler words.
3. Click **Clean Video** and watch the progress bar. Expand **Details** for the
   live log.
4. Click **Show in Finder** when it's done.

Everything runs **100% locally** — nothing is uploaded.

## How it works

1. **Backup** — copies your original to `_originals/`.
2. **Detect pauses** — `ffmpeg silencedetect` finds silence from the real audio
   energy (accurate even when speech timing isn't).
3. **Find fillers** — [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
   transcribes word-level timestamps; hesitation words are matched.
4. **Re-render** — `ffmpeg` keeps only the wanted segments and joins them, audio
   and video locked together. Same resolution and frame rate; no downscaling.

## Channels

Crisp builds in three channels that install side by side (separate app, icon, and
settings): **Stable** (`Crisp.app`), **Nightly** (`Crisp Nightly.app`), and
**Dev** (`Crisp Dev.app`, local only). Stable and Nightly auto-update from GitHub
Releases; Dev never does. See [`CLAUDE.md`](CLAUDE.md) for the full layout.

## Research — custom models (experimental)

Crisp is experimenting with its own small, **on-device** ML models for filler
detection — a fast, opt-in alternative to running full speech-to-text. The first,
**Wren** 🐦, is a tiny CNN trained on
[PodcastFillers](https://podcastfillers.github.io/) that spots "um"/"uh" at ~600×
real-time (0.94 precision on held-out speakers).

All the training code, benchmarks, and a native eval dashboard live in
**[`research/`](research/README.md)** — kept separate from the shipped app, which
is unchanged. Trained models are published to
**[Hugging Face](https://huggingface.co/rafay99-epic/crisp-models)**.

## Roadmap & docs

The roadmap, tasks, and project notes are managed with
**[Backlog.md](https://github.com/MrLesk/Backlog.md)** — plain Markdown files
tracked in git under [`backlog/`](backlog/), so what's shipped, in progress, and
planned all live in one place (no external service, no lock-in).

Install it once, then browse the board:

```sh
bun i -g backlog.md          # or: npm i -g backlog.md   /   brew install backlog-md

backlog board                # To Do / In Progress / Done, in the terminal
backlog browser              # the same as a web Kanban at http://localhost:6420
```

Everyday commands:

```sh
backlog task list                                   # list tasks
backlog task create "New idea" -d "…" --priority medium
backlog task edit task-7 -s "In Progress"           # move a task across the board
backlog doc list                                    # research notes & design docs
backlog doc view doc-3                               # read one
```

- **Tasks** (`backlog/tasks/`) are the roadmap — each has a status, a priority,
  and, once shipped, the PR link in its `references`.
- **Docs** (`backlog/docs/`) hold the research findings and design notes (retake
  detection, model research, …).
- **AI agents** keep tasks in sync via the MCP server —
  `claude mcp add backlog --scope user -- backlog mcp start`.

GitHub Issues are for **real bugs only**; features and ideas are Backlog.md tasks.

## License

[GPL-3.0](LICENSE) · © Syntax Lab Technology / Abdul Rafay ([rafay99.com](https://rafay99.com))
