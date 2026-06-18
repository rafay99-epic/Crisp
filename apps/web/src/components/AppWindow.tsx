/**
 * A pixel-faithful HTML/CSS recreation of the real Crisp window
 * (apps/desktop/Sources/Crisp/Views/ContentView.swift and friends). Rendered as
 * markup rather than a screenshot so it stays razor-sharp at any size and on any
 * display — the same reason Apple renders its own product shots.
 *
 * Light-mode macOS: traffic lights + gear toolbar, the header, the drop card with
 * a selected file, the "How much to cut" options, the backup row, and the
 * prominent Clean Video button. `<ResultPanel/>` is the green done-state card,
 * reused on its own elsewhere on the page.
 */
import { AppIcon } from "./Logo";
import { Scissors, Gear, CheckSeal, Folder } from "./Icons";

const STRENGTHS = ["Gentle", "Balanced", "Aggressive", "Very", "Custom"];

function TrafficLights() {
  return (
    <div className="flex items-center gap-2">
      <span className="size-3 rounded-full bg-[#ff5f57] ring-1 ring-black/10" />
      <span className="size-3 rounded-full bg-[#febc2e] ring-1 ring-black/10" />
      <span className="size-3 rounded-full bg-[#28c840] ring-1 ring-black/10" />
    </div>
  );
}

/** macOS-style switch, fixed on. */
function Switch() {
  return (
    <span className="relative inline-flex h-[22px] w-[38px] items-center rounded-full bg-[var(--color-system-blue)] px-[2px]">
      <span className="size-[18px] translate-x-[16px] rounded-full bg-white shadow-sm" />
    </span>
  );
}

export function AppWindow({ className = "" }: { className?: string }) {
  return (
    <div
      className={`overflow-hidden rounded-[12px] bg-white ring-1 ring-black/[0.08] ${className}`}
      style={{ boxShadow: "0 40px 80px -20px rgba(0,0,0,0.30), 0 12px 30px -12px rgba(0,0,0,0.18)" }}
    >
      {/* Title bar */}
      <div className="relative flex h-[44px] items-center justify-between border-b border-black/[0.06] bg-[#f6f6f6] px-4">
        <TrafficLights />
        <span className="absolute left-1/2 -translate-x-1/2 text-[13px] font-medium text-[var(--color-ink-soft)]">
          Crisp
        </span>
        <Gear className="size-[18px] text-[var(--color-ink-soft)]" />
      </div>

      {/* Content — mirrors ContentView's 24pt padding / 16pt stack spacing */}
      <div className="flex flex-col gap-4 p-6">
        {/* Header */}
        <div className="flex items-center gap-3.5">
          <AppIcon className="size-[46px] drop-shadow-sm" />
          <div className="flex flex-col gap-0.5">
            <span className="text-[22px] font-bold leading-none tracking-tight">Crisp</span>
            <span className="text-[13px] text-[var(--color-ink-soft)]">
              Remove pauses &amp; filler words from your recordings.
            </span>
          </div>
        </div>

        {/* Drop card — selected-file state */}
        <div className="flex flex-col items-center gap-2.5 rounded-[14px] border-[1.5px] border-dashed border-[var(--color-system-blue)]/40 bg-[var(--color-system-blue)]/[0.04] py-6">
          <CheckSeal className="size-7 text-[var(--color-system-blue)]" />
          <span className="text-[15px] font-semibold">Keynote-walkthrough.mov</span>
          <span className="text-[13px] text-[var(--color-ink-soft)]">Drag a video here, or</span>
          <button className="rounded-md bg-[var(--color-mist)] px-3 py-1 text-[13px] font-medium text-[var(--color-ink) ] ring-1 ring-black/[0.06]">
            Choose video…
          </button>
        </div>

        {/* Options card */}
        <div className="flex flex-col gap-3.5 rounded-[14px] bg-[var(--color-mist)] p-4">
          <div className="flex flex-col gap-1.5">
            <span className="text-[15px] font-semibold">How much to cut</span>
            <div className="flex rounded-[7px] bg-black/[0.05] p-[2px] text-[12px] font-medium">
              {STRENGTHS.map((s) => (
                <span
                  key={s}
                  className={`flex-1 rounded-[5px] px-2 py-[5px] text-center ${
                    s === "Aggressive"
                      ? "bg-white text-[var(--color-ink)] shadow-sm"
                      : "text-[var(--color-ink-soft)]"
                  }`}
                >
                  {s}
                </span>
              ))}
            </div>
            <span className="text-[13px] text-[var(--color-ink-soft)]">
              Cuts short “thinking” gaps too. Recommended.
            </span>
          </div>
          <div className="h-px bg-black/[0.07]" />
          <div className="flex items-center justify-between">
            <div className="flex flex-col gap-0.5">
              <span className="text-[15px] font-semibold">Remove filler words</span>
              <span className="text-[13px] text-[var(--color-ink-soft)]">um, uh, hmm, erm, aww…</span>
            </div>
            <Switch />
          </div>
        </div>

        {/* Backup status row */}
        <div className="flex items-center gap-2.5 rounded-[14px] bg-[var(--color-mist)] px-3.5 py-2.5">
          <ShieldCheck className="size-[18px] shrink-0 text-[var(--color-system-blue)]" />
          <div className="flex min-w-0 flex-col">
            <span className="text-[13px] font-medium">Originals are backed up</span>
            <span className="truncate text-[11px] text-[var(--color-ink-soft)]">~/.crisp/Originals</span>
          </div>
          <span className="ml-auto text-[11px] text-[var(--color-system-blue)]">Show in Finder</span>
        </div>

        {/* Primary action */}
        <button className="flex items-center justify-center gap-2 rounded-[8px] bg-[var(--color-system-blue)] py-2.5 text-[15px] font-semibold text-white shadow-sm">
          <Scissors className="size-[18px]" />
          Clean Video
        </button>
      </div>
    </div>
  );
}

function ShieldCheck({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" className={className} aria-hidden>
      <path d="M12 3 5 6v5c0 4.2 2.9 7.6 7 9 4.1-1.4 7-4.8 7-9V6l-7-3Z" />
      <path d="m9 12 2 2 4-4" />
    </svg>
  );
}

/** The green done-state card (ResultCard.swift). Standalone — used in the page. */
export function ResultPanel({ className = "" }: { className?: string }) {
  return (
    <div
      className={`flex flex-col gap-3 rounded-[14px] bg-[#e9f8ec] p-4 ring-1 ring-[#34c759]/20 ${className}`}
    >
      <div className="flex items-center gap-2.5">
        <CheckSeal className="size-6 text-[#34c759]" />
        <div className="flex flex-col">
          <span className="text-[15px] font-semibold text-[var(--color-ink)]">Cleaned!</span>
          <span className="text-[13px] text-[var(--color-ink-soft)]">
            Removed 1:24 of pauses &amp; fillers.
          </span>
        </div>
      </div>
      <div className="flex gap-6">
        {[
          ["8:30 → 7:06", "Length"],
          ["42", "Pauses cut"],
          ["18", "Fillers cut"],
        ].map(([value, label]) => (
          <div key={label} className="flex flex-col">
            <span className="text-[17px] font-bold text-[var(--color-ink)]">{value}</span>
            <span className="text-[11px] text-[var(--color-ink-soft)]">{label}</span>
          </div>
        ))}
      </div>
      <div className="flex gap-2 pt-1">
        <span className="flex items-center gap-1.5 rounded-md bg-white px-3 py-1.5 text-[13px] font-medium ring-1 ring-black/[0.06]">
          <Folder className="size-4" /> Show in Finder
        </span>
        <span className="flex items-center gap-1.5 rounded-md bg-white px-3 py-1.5 text-[13px] font-medium ring-1 ring-black/[0.06]">
          Clean another
        </span>
      </div>
    </div>
  );
}
