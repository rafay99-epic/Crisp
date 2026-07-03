# Everything Crisp does

Content source for the site's features page. Written in the site's voice — lift
sections, headlines, and blurbs as-is. Groups map to sections; each entry is a
feature name plus site-ready copy. Items marked _(opt-in)_ ship off by default.

---

## The cut

_It does the first edit for you._

- **Silence, gone.** Crisp measures the real audio energy to find dead air and long
  thinking gaps — far more accurate than guessing from a transcript — then cuts them out.
- **Fillers, gone.** An on-device speech model timestamps every "um," "uh," "hmm," and
  "erm," and Crisp snips each one out at the exact frame.
- **Retakes, gone.** Flubbed a line and said it again? Crisp spots the redo, cuts the
  flub, and keeps the take you meant. Sensitivity is adjustable, and it understands
  meaning — an intentional repeated phrase isn't a retake, and it knows the difference.
- **Tighten, don't chop.** Pauses don't have to vanish entirely — tighten mode keeps a
  small breath of silence at each cut so your pacing still sounds human.
- **Cuts you can't hear.** Every join gets a short audio fade, cut points snap to the
  nearest zero-crossing, and an optional crossfade dissolves one segment into the next.
  No clicks, no pops.
- **One dial, or every knob.** Pick a strength — Gentle to Aggressive — or open Custom
  and set the exact pause threshold, noise floor, and breathing room yourself.
- **Presets.** Save a full recipe — cut, encode, output, backup — under a name, and
  apply it per file. Your podcast setup and your tutorial setup don't have to fight.
- **See the cut before you commit.** Live preview analyzes your audio once, then shows
  the waveform with every slice that would go — updating as you drag the knobs — plus
  the pause count and time saved.
- **Veto any cut.** The review timeline plays your video with every detected cut marked.
  Toggle the ones you disagree with, preview the result, then render exactly that.
- **Know before you clean.** A pre-flight estimate shows how much your queued videos
  will shrink before you commit to anything.

## Your footage is safe

_That's a guarantee, not a setting._

- **Never overwrites.** Crisp only ever writes a new `_cleaned` file. It can't touch
  your source — there is no code path that deletes or replaces it.
- **Backs up first.** Before cutting, the original is copied to a dated backup folder.
  On by default, and you can point it anywhere.
- **One-click restore.** Reveal the backed-up original or copy it back from the queue
  or History, any time.

## Honest quality

_Cuts re-encode. Nothing degrades._

- **Same resolution, same frame rate.** Frame-accurate cuts require a re-encode, so
  Crisp does it at high quality and never downscales. What went in is what comes out —
  minus the dead air.
- **Hardware encoding by default.** Apple's media engine encodes HEVC fast on every
  Apple Silicon Mac. If hardware ever fails, Crisp falls back to software on its own.
- **Your codecs, your call.** H.264 or HEVC video, AAC or Opus audio, named quality
  levels from Smaller to Maximum, adjustable audio bitrate.
- **Container that matches.** An `.mkv` recording stays `.mkv`, an `.mp4` stays `.mp4` —
  or force mp4, mkv, mov, m4v, ts, or webm.
- **10-bit stays 10-bit.** Output color depth matches the source. HDR footage is never
  silently crushed to 8-bit.
- **Screen recordings welcome.** Variable-frame-rate sources are normalized to constant
  so audio and video never drift.
- **Split export.** _(opt-in)_ Optionally write separate video-only and audio-only files
  beside the cleaned output — for finishing picture and sound in different apps.
- **Captions that match the cut.** _(opt-in)_ Optional SRT or WebVTT sidecars, re-timed
  to the cleaned video, shaped to broadcast conventions (two lines max, readable
  durations).

## Fits how you work

_One window. Drop, choose, done — or never open the window at all._

- **Queue.** Drop a batch, reorder while waiting, assign different presets per file,
  and watch per-file progress.
- **Parallel cleans.** Automatic concurrency sized to your Mac's free RAM and CPU — or
  take manual control, up to an Ultra mode that pushes the machine to its checked limit.
- **Watch folder.** Point Crisp at a folder and every recording dropped in gets cleaned
  automatically — in the background, even with the app closed.
- **Menu-bar drop.** Drop a file on the menu-bar icon and it's cleaned headlessly with
  your default recipe. The main window never opens.
- **Right-click in Finder.** "Clean with Crisp" is a Finder Quick Action — clean videos
  without launching anything.
- **Shortcuts.** A "Clean with Crisp" action in the Shortcuts app, with your named
  strengths, for automations we haven't thought of.
- **Hand off to your editor.** Don't want a rendered file? Crisp writes a DaVinci
  Resolve project instead — your source plus an FCPXML timeline of every cut, ready to
  finish non-destructively.
- **History.** Every clean ever — from the queue, the watch folder, Finder, or
  Shortcuts — with its stats, reveal-in-Finder, and one-click re-clean.
- **Spot-check the result.** Play a cleaned file's audio right from its queue row
  before you upload it.
- **Knows when to speak.** A notification when the batch finishes — only if you've
  switched away to another app.
- **Can't quit mid-render.** While a clean is writing, ⌘Q, window close, and logout are
  held off so you never get a corrupt half-file. The moment output is safe, the guard
  lifts.

## A Mac app, properly

_It looks and behaves like an app Apple would ship — because it's built to._

- **Native everything.** SF Symbols, system materials, system accent color, real
  AppKit/SwiftUI controls. No web view wearing a trench coat.
- **An icon that follows your Mac.** Light mode, dark mode, and the tinted icon styles
  in macOS 26 — the waveform mark adapts to all of them, in full color or your tint.
- **First-run tour.** A short welcome walks you through what Crisp does and sets your
  preferences — reopen it any time from Help.
- **What's New, once.** After an update, one sheet with the actual release notes. Then
  it gets out of your way.
- **Everything on device.** Transcription, detection, and encoding run locally. Your
  footage never leaves your Mac.
- **Self-contained.** ffmpeg, whisper, and the runtime ship inside the app — nothing to
  install, nothing to configure. Apple Silicon, built native.
- **One log that tells the truth.** App and engine write one daily log — every command,
  every exit code — with a Reveal in Finder right in Settings.

## Updates, your way

- **Built-in updater.** Crisp checks GitHub Releases and updates in place — plus a
  manual "Check for Updates…" whenever you want.
- **Two channels, side by side.** Stable for work, Nightly for the curious — separate
  apps, separate settings, separate icons, installable together without conflict.
- **The speech model downloads once.** The ~148 MB model isn't stuffed into every
  update — it's fetched on first run, verified, and resumes if interrupted.

## Crisp Pro

- **One plan. Everything.** No tiers to compare, no feature gates. One subscription
  unlocks Crisp Pro in full — licensing runs through Polar, managed right in Settings.
