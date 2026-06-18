/**
 * A faithful HTML/CSS recreation of the real Crisp window in macOS **dark**
 * mode (apps/desktop/.../Views/ContentView.swift). Rendered as markup, not a
 * screenshot, so it stays razor-sharp at any size — and the dark chrome matches
 * the app's identity. `<ResultPanel/>` is the green done-state card.
 */
import { AppIcon } from "./Logo";
import { Scissors, Gear, CheckSeal } from "./Icons";

const STRENGTHS = ["Gentle", "Balanced", "Aggressive", "Very", "Custom"];

function TrafficLights() {
  return (
    <div className="flex items-center gap-2">
      <span className="size-3 rounded-full bg-[#ff5f57]" />
      <span className="size-3 rounded-full bg-[#febc2e]" />
      <span className="size-3 rounded-full bg-[#28c840]" />
    </div>
  );
}

function Switch() {
  return (
    <span className="relative inline-flex h-[22px] w-[38px] items-center rounded-full bg-[var(--color-accent)] px-[2px]">
      <span className="size-[18px] translate-x-[16px] rounded-full bg-white shadow" />
    </span>
  );
}

export function AppWindow({ className = "" }: { className?: string }) {
  return (
    <div
      className={`overflow-hidden rounded-[12px] bg-[#1c1c1e] ring-1 ring-white/10 ${className}`}
      style={{ boxShadow: "0 60px 120px -30px rgba(0,0,0,0.8), 0 20px 50px -20px rgba(0,0,0,0.6)" }}
    >
      {/* Title bar */}
      <div className="relative flex h-[44px] items-center justify-between border-b border-white/[0.07] bg-[#2a2a2c] px-4">
        <TrafficLights />
        <span className="absolute left-1/2 -translate-x-1/2 text-[13px] font-medium text-white/55">
          Crisp
        </span>
        <Gear className="size-[18px] text-white/50" />
      </div>

      {/* Content — mirrors ContentView's 24pt padding / 16pt stack spacing */}
      <div className="flex flex-col gap-4 p-6">
        {/* Header */}
        <div className="flex items-center gap-3.5">
          <AppIcon className="size-[46px] drop-shadow-md" />
          <div className="flex flex-col gap-0.5">
            <span className="text-[22px] font-bold leading-none tracking-tight text-white">Crisp</span>
            <span className="text-[13px] text-white/55">
              Remove pauses &amp; filler words from your recordings.
            </span>
          </div>
        </div>

        {/* Drop card — selected-file state */}
        <div className="flex flex-col items-center gap-2.5 rounded-[14px] border-[1.5px] border-dashed border-[var(--color-accent)]/45 bg-[var(--color-accent)]/[0.07] py-6">
          <CheckSeal className="size-7 text-[var(--color-accent-bright)]" />
          <span className="text-[15px] font-semibold text-white">Keynote-walkthrough.mov</span>
          <span className="text-[13px] text-white/50">Drag a video here, or</span>
          <button className="rounded-md bg-white/10 px-3 py-1 text-[13px] font-medium text-white/90 ring-1 ring-white/10">
            Choose video…
          </button>
        </div>

        {/* Options card */}
        <div className="flex flex-col gap-3.5 rounded-[14px] bg-white/[0.04] p-4 ring-1 ring-white/[0.06]">
          <div className="flex flex-col gap-1.5">
            <span className="text-[15px] font-semibold text-white">How much to cut</span>
            <div className="flex rounded-[7px] bg-black/30 p-[2px] text-[12px] font-medium">
              {STRENGTHS.map((s) => (
                <span
                  key={s}
                  className={`flex-1 rounded-[5px] px-2 py-[5px] text-center ${
                    s === "Aggressive" ? "bg-white/15 text-white shadow-sm" : "text-white/55"
                  }`}
                >
                  {s}
                </span>
              ))}
            </div>
            <span className="text-[13px] text-white/50">Cuts short “thinking” gaps too. Recommended.</span>
          </div>
          <div className="h-px bg-white/[0.07]" />
          <div className="flex items-center justify-between">
            <div className="flex flex-col gap-0.5">
              <span className="text-[15px] font-semibold text-white">Remove filler words</span>
              <span className="text-[13px] text-white/50">um, uh, hmm, erm, aww…</span>
            </div>
            <Switch />
          </div>
        </div>

        {/* Backup status row */}
        <div className="flex items-center gap-2.5 rounded-[14px] bg-white/[0.04] px-3.5 py-2.5 ring-1 ring-white/[0.06]">
          <ShieldCheck className="size-[18px] shrink-0 text-[var(--color-accent-bright)]" />
          <div className="flex min-w-0 flex-col">
            <span className="text-[13px] font-medium text-white">Originals are backed up</span>
            <span className="truncate text-[11px] text-white/45">~/.crisp/Originals</span>
          </div>
          <span className="ml-auto text-[11px] text-[var(--color-accent-bright)]">Show in Finder</span>
        </div>

        {/* Primary action */}
        <button className="flex items-center justify-center gap-2 rounded-[8px] bg-[var(--color-accent)] py-2.5 text-[15px] font-semibold text-white shadow-[0_8px_30px_-6px_rgba(10,132,255,0.6)]">
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

/** The green done-state card (ResultCard.swift), dark variant. */
export function ResultPanel({ className = "" }: { className?: string }) {
  return (
    <div
      className={`flex flex-col gap-3 rounded-[16px] bg-[#34c759]/[0.12] p-5 ring-1 ring-[#34c759]/25 ${className}`}
    >
      <div className="flex items-center gap-2.5">
        <CheckSeal className="size-6 text-[#30d158]" />
        <div className="flex flex-col">
          <span className="text-[15px] font-semibold text-white">Cleaned!</span>
          <span className="text-[13px] text-white/55">Removed 1:24 of pauses &amp; fillers.</span>
        </div>
      </div>
      <div className="flex gap-7">
        {[
          ["8:30 → 7:06", "Length"],
          ["42", "Pauses cut"],
          ["18", "Fillers cut"],
        ].map(([value, label]) => (
          <div key={label} className="flex flex-col">
            <span className="text-[18px] font-bold text-white">{value}</span>
            <span className="text-[11px] text-white/45">{label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
