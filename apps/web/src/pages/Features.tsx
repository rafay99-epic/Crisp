import { Link } from "@tanstack/react-router";
import { motion } from "framer-motion";
import { ProBadge, Waveform } from "../components/Logo";
import { Footer } from "../sections/Footer";
import { Reveal, KineticText } from "../components/Motion";
import { CopyCommand } from "../components/AppBits";
import { BREW_INSTALL } from "../site";

const EASE = [0.16, 1, 0.3, 1] as const;

type Feature = { title: string; body: string; optIn?: boolean };
type Group = { eyebrow: string; title: string; features: Feature[] };

// Lifted near-verbatim from content/features.md — bold lead-ins become titles,
// the rest of each bullet becomes the description.
const GROUPS: Group[] = [
  {
    eyebrow: "The cut",
    title: "It does the first edit for you.",
    features: [
      {
        title: "Silence, gone.",
        body: "Crisp measures the real audio energy to find dead air and long thinking gaps — far more accurate than guessing from a transcript — then cuts them out.",
      },
      {
        title: "Fillers, gone.",
        body: 'An on-device speech model timestamps every "um," "uh," "hmm," and "erm," and Crisp snips each one out at the exact frame.',
      },
      {
        title: "Retakes, gone.",
        body: "Flubbed a line and said it again? Crisp spots the redo, cuts the flub, and keeps the take you meant. Sensitivity is adjustable, and it understands meaning — an intentional repeated phrase isn't a retake, and it knows the difference.",
      },
      {
        title: "Tighten, don't chop.",
        body: "Pauses don't have to vanish entirely — tighten mode keeps a small breath of silence at each cut so your pacing still sounds human.",
      },
      {
        title: "Cuts you can't hear.",
        body: "Every join gets a short audio fade, cut points snap to the nearest zero-crossing, and an optional crossfade dissolves one segment into the next. No clicks, no pops.",
      },
      {
        title: "One dial, or every knob.",
        body: "Pick a strength — Gentle to Aggressive — or open Custom and set the exact pause threshold, noise floor, and breathing room yourself.",
      },
      {
        title: "Presets.",
        body: "Save a full recipe — cut, encode, output, backup — under a name, and apply it per file. Your podcast setup and your tutorial setup don't have to fight.",
      },
      {
        title: "See the cut before you commit.",
        body: "Live preview analyzes your audio once, then shows the waveform with every slice that would go — updating as you drag the knobs — plus the pause count and time saved.",
      },
      {
        title: "Veto any cut.",
        body: "The review timeline plays your video with every detected cut marked. Toggle the ones you disagree with, preview the result, then render exactly that.",
      },
      {
        title: "Know before you clean.",
        body: "A pre-flight estimate shows how much your queued videos will shrink before you commit to anything.",
      },
    ],
  },
  {
    eyebrow: "Your footage is safe",
    title: "That's a guarantee, not a setting.",
    features: [
      {
        title: "Never overwrites.",
        body: "Crisp only ever writes a new _cleaned file. It can't touch your source — there is no code path that deletes or replaces it.",
      },
      {
        title: "Backs up first.",
        body: "Before cutting, the original is copied to a dated backup folder. On by default, and you can point it anywhere.",
      },
      {
        title: "One-click restore.",
        body: "Reveal the backed-up original or copy it back from the queue or History, any time.",
      },
    ],
  },
  {
    eyebrow: "Honest quality",
    title: "Cuts re-encode. Nothing degrades.",
    features: [
      {
        title: "Same resolution, same frame rate.",
        body: "Frame-accurate cuts require a re-encode, so Crisp does it at high quality and never downscales. What went in is what comes out — minus the dead air.",
      },
      {
        title: "Hardware encoding by default.",
        body: "Apple's media engine encodes HEVC fast on every Apple Silicon Mac. If hardware ever fails, Crisp falls back to software on its own.",
      },
      {
        title: "Your codecs, your call.",
        body: "H.264 or HEVC video, AAC or Opus audio, named quality levels from Smaller to Maximum, adjustable audio bitrate.",
      },
      {
        title: "Container that matches.",
        body: "An .mkv recording stays .mkv, an .mp4 stays .mp4 — or force mp4, mkv, mov, m4v, ts, or webm.",
      },
      {
        title: "10-bit stays 10-bit.",
        body: "Output color depth matches the source. HDR footage is never silently crushed to 8-bit.",
      },
      {
        title: "Screen recordings welcome.",
        body: "Variable-frame-rate sources are normalized to constant so audio and video never drift.",
      },
      {
        title: "Split export.",
        body: "Optionally write separate video-only and audio-only files beside the cleaned output — for finishing picture and sound in different apps.",
        optIn: true,
      },
      {
        title: "Captions that match the cut.",
        body: "Optional SRT or WebVTT sidecars, re-timed to the cleaned video, shaped to broadcast conventions (two lines max, readable durations).",
        optIn: true,
      },
    ],
  },
  {
    eyebrow: "Fits how you work",
    title: "One window. Drop, choose, done — or never open the window at all.",
    features: [
      {
        title: "Queue.",
        body: "Drop a batch, reorder while waiting, assign different presets per file, and watch per-file progress.",
      },
      {
        title: "Parallel cleans.",
        body: "Automatic concurrency sized to your Mac's free RAM and CPU — or take manual control, up to an Ultra mode that pushes the machine to its checked limit.",
      },
      {
        title: "Watch folder.",
        body: "Point Crisp at a folder and every recording dropped in gets cleaned automatically — in the background, even with the app closed.",
      },
      {
        title: "Menu-bar drop.",
        body: "Drop a file on the menu-bar icon and it's cleaned headlessly with your default recipe. The main window never opens.",
      },
      {
        title: "Right-click in Finder.",
        body: '"Clean with Crisp" is a Finder Quick Action — clean videos without launching anything.',
      },
      {
        title: "Shortcuts.",
        body: 'A "Clean with Crisp" action in the Shortcuts app, with your named strengths, for automations we haven\'t thought of.',
      },
      {
        title: "Hand off to your editor.",
        body: "Don't want a rendered file? Crisp writes a DaVinci Resolve project instead — your source plus an FCPXML timeline of every cut, ready to finish non-destructively.",
      },
      {
        title: "History.",
        body: "Every clean ever — from the queue, the watch folder, Finder, or Shortcuts — with its stats, reveal-in-Finder, and one-click re-clean.",
      },
      {
        title: "Spot-check the result.",
        body: "Play a cleaned file's audio right from its queue row before you upload it.",
      },
      {
        title: "Knows when to speak.",
        body: "A notification when the batch finishes — only if you've switched away to another app.",
      },
      {
        title: "Can't quit mid-render.",
        body: "While a clean is writing, ⌘Q, window close, and logout are held off so you never get a corrupt half-file. The moment output is safe, the guard lifts.",
      },
    ],
  },
  {
    eyebrow: "A Mac app, properly",
    title: "It looks and behaves like an app Apple would ship — because it's built to.",
    features: [
      {
        title: "Native everything.",
        body: "SF Symbols, system materials, system accent color, real AppKit/SwiftUI controls. No web view wearing a trench coat.",
      },
      {
        title: "An icon that follows your Mac.",
        body: "Light mode, dark mode, and the tinted icon styles in macOS 26 — the waveform mark adapts to all of them, in full color or your tint.",
      },
      {
        title: "First-run tour.",
        body: "A short welcome walks you through what Crisp does and sets your preferences — reopen it any time from Help.",
      },
      {
        title: "What's New, once.",
        body: "After an update, one sheet with the actual release notes. Then it gets out of your way.",
      },
      {
        title: "Everything on device.",
        body: "Transcription, detection, and encoding run locally. Your footage never leaves your Mac.",
      },
      {
        title: "Self-contained.",
        body: "ffmpeg, whisper, and the runtime ship inside the app — nothing to install, nothing to configure. Apple Silicon, built native.",
      },
      {
        title: "One log that tells the truth.",
        body: "App and engine write one daily log — every command, every exit code — with a Reveal in Finder right in Settings.",
      },
    ],
  },
  {
    eyebrow: "Updates, your way",
    title: "Fresh builds, on your terms.",
    features: [
      {
        title: "Built-in updater.",
        body: 'Crisp checks GitHub Releases and updates in place — plus a manual "Check for Updates…" whenever you want.',
      },
      {
        title: "Two channels, side by side.",
        body: "Stable for work, Nightly for the curious — separate apps, separate settings, separate icons, installable together without conflict.",
      },
      {
        title: "The speech model downloads once.",
        body: "The ~148 MB model isn't stuffed into every update — it's fetched on first run, verified, and resumes if interrupted.",
      },
    ],
  },
  {
    eyebrow: "Crisp Pro",
    title: "One subscription, nothing to compare.",
    features: [
      {
        title: "One plan. Everything.",
        body: "No tiers to compare, no feature gates. One subscription unlocks Crisp Pro in full — licensing runs through Polar, managed right in Settings.",
      },
    ],
  },
];

function FeatureCard({ title, body, optIn }: Feature) {
  return (
    <div className="rounded-2xl bg-white/[0.04] p-5 ring-1 ring-white/[0.08]">
      <div className="flex items-start justify-between gap-3">
        <p className="text-[15px] font-semibold text-white">{title}</p>
        {optIn && (
          <span className="shrink-0 rounded-full bg-white/10 px-2 py-0.5 text-[11px] font-medium text-white/50">
            Opt-in
          </span>
        )}
      </div>
      <p className="mt-1.5 text-[13.5px] leading-relaxed text-white/55">{body}</p>
    </div>
  );
}

function FeatureGroup({ eyebrow, title, features }: Group) {
  return (
    <section className="py-12 sm:py-16">
      <Reveal>
        <p className="text-[13px] font-semibold uppercase tracking-[0.25em] text-[var(--color-accent-bright)]">
          {eyebrow}
        </p>
        <h2 className="mt-3 max-w-2xl text-[26px] font-semibold leading-[1.15] tracking-[-0.02em] sm:text-[32px]">
          {title}
        </h2>
      </Reveal>
      <Reveal delay={0.05}>
        <div className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {features.map((f) => (
            <FeatureCard key={f.title} {...f} />
          ))}
        </div>
      </Reveal>
    </section>
  );
}

export function Features() {
  return (
    <>
      {/* slim header — matches Pricing/LegalPage */}
      <header className="sticky top-0 z-50 border-b border-white/[0.06] bg-black/55 backdrop-blur-xl">
        <nav className="mx-auto flex h-14 max-w-6xl items-center justify-between px-5">
          <Link to="/" className="flex items-center gap-2 font-semibold tracking-tight text-white">
            <Waveform className="size-[18px]" />
            Crisp
          </Link>
          <Link
            to="/"
            hash="download"
            className="text-[13px] font-medium text-white/60 transition-colors hover:text-white"
          >
            Install ›
          </Link>
        </nav>
      </header>

      <main className="relative overflow-hidden px-5 pt-20 pb-32 sm:pt-28">
        <span
          className="orb left-1/2 top-0 size-[640px] -translate-x-1/2 -translate-y-1/3"
          style={{ background: "radial-gradient(circle, rgba(10,132,255,0.18), transparent 70%)" }}
        />
        <div className="relative z-10 mx-auto max-w-2xl text-center">
          <motion.p
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, ease: EASE }}
            className="text-[13px] font-semibold uppercase tracking-[0.25em] text-[var(--color-accent-bright)]"
          >
            Features
          </motion.p>
          <KineticText
            text="Everything Crisp does."
            className="mt-4 text-[44px] font-semibold tracking-[-0.02em] sm:text-[60px]"
          />
          <Reveal delay={0.1}>
            <p className="mx-auto mt-5 max-w-lg text-[18px] leading-relaxed text-white/60">
              Every cut, every guardrail, every quiet convenience — in one place, no marketing gloss
              required.
            </p>
          </Reveal>
        </div>

        <div className="relative z-10 mx-auto mt-6 max-w-6xl divide-y divide-white/[0.06]">
          {GROUPS.map((g) => (
            <FeatureGroup key={g.eyebrow} {...g} />
          ))}
        </div>

        {/* Pro banner — everything above is one plan. */}
        <Reveal>
          <div className="relative z-10 mx-auto mt-16 flex max-w-2xl flex-wrap items-center justify-center gap-x-3 gap-y-2 rounded-2xl border border-[var(--color-accent-bright)]/20 bg-[var(--color-accent-bright)]/[0.06] px-6 py-4 text-center">
            <span className="flex items-center gap-2 font-semibold text-white">
              <Waveform className="size-[16px]" />
              Crisp Pro
              <ProBadge />
            </span>
            <span className="text-[14px] text-white/60">
              Everything on this page, one subscription.
            </span>
            <Link
              to="/pricing"
              className="text-[14px] font-semibold text-[var(--color-accent-bright)] transition-colors hover:text-white"
            >
              Upgrade to Pro ›
            </Link>
          </div>
        </Reveal>

        <Reveal>
          <div className="relative z-10 mx-auto mt-8 max-w-md rounded-2xl border border-white/[0.08] bg-white/[0.03] p-8 text-center">
            <p className="text-[20px] font-semibold tracking-[-0.01em] text-white">
              See it on your own footage.
            </p>
            <p className="mt-2 text-[14px] text-white/55">
              Free to try, Apple Silicon, nothing to configure.
            </p>
            <div className="mt-6">
              <CopyCommand command={BREW_INSTALL} />
            </div>
            <Link
              to="/"
              hash="download"
              className="mt-4 block text-[12px] text-white/40 transition-colors hover:text-white/70"
            >
              Or download the .dmg directly
            </Link>
          </div>
        </Reveal>
      </main>

      <Footer />
    </>
  );
}
