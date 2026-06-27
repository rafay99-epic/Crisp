# Analytics dashboard — future idea (Abdul, this session)

A "was it worth it?" view: over time, as you use Crisp, show what it saved you.

## The pitch
A beautiful stats screen that proves the app's value back to the user — how much
editing time they saved, how many retakes / pauses / fillers Crisp caught, trends
over time. Turns invisible savings into something you can *see*.

## What to show
- **Headline:** total time saved across all cleans (e.g. "You've saved 4h 12m").
- **Counts over time:** retakes removed, pauses removed, fillers removed.
- **Charts:** a bar chart (per clean, or per week/month) + progress-bar style summaries.
- **Per-video and aggregate** views.
- Maybe: average % shorter, number of videos cleaned, biggest single save.

## Data layer
- **Local SQLite** DB (on-device only, privacy-preserving — matches the app's ethos).
- Each clean writes a row: timestamp, input name, orig seconds, new seconds, saved
  seconds, fillers, pauses, retakes, sensitivity, channel.
- NOTE: there's already a `HistoryEntry` + `~/.crisp*/history.jsonl` (HistoryStore)
  that records most of this per clean. The dashboard could **read the existing
  history first** (no migration needed) and only move to SQLite if the JSONL grows
  too big or we need real querying/aggregation. Start by aggregating the JSONL;
  graduate to SQLite if needed.

## Build notes
- New window/tab (like the History window). Swift Charts for the graphs (native,
  macOS 14+). 
- Read from HistoryStore (already populated by every surface — app, watcher,
  Shortcuts). Each `HistoryEntry` already has fillers/pauses/retakes/saved seconds.
- Keep it native + Apple-like (matches product philosophy #1).

## Sequence
Future update — AFTER the retake feature (PR #73) is solid and merged. The UX bits
(progress "Finding repeated takes" step, pause count in estimate) shipped first.
