/**
 * A faithful HTML/CSS/SVG recreation of the current Crisp window in macOS
 * **dark** mode (apps/desktop/.../Views/ContentView.swift) — a queue-based
 * batch cleaner. Rendered as markup, not a screenshot, so it stays razor-sharp
 * at any size. Shows a lively mid-work composite: one done row, one cleaning
 * row, one waiting row, plus the bottom control bar.
 */
import { motion, useReducedMotion } from "framer-motion";
import {
  Scissors,
  Gear,
  Plus,
  Clock,
  Monitor,
  XCircle,
  ChevronUpDown,
  Waveform,
  Folder,
} from "./Icons";

function TrafficLights() {
  return (
    <div className="flex items-center gap-2">
      <span className="size-3 rounded-full bg-[#ff5f57]" />
      <span className="size-3 rounded-full bg-[#febc2e]" />
      <span className="size-3 rounded-full bg-[#28c840]" />
    </div>
  );
}

/** The right-side pill toolbar: add / history / settings. */
function Toolbar() {
  return (
    <div className="flex items-center gap-1 rounded-full bg-white/[0.05] p-1 ring-1 ring-white/10">
      {[Plus, Clock, Gear].map((Icon, i) => (
        <span key={i} className="grid size-[26px] place-items-center rounded-full">
          <Icon className="size-[15px] text-white/60" />
        </span>
      ))}
    </div>
  );
}

/** A green check inside a filled circle — a completed queue item. */
function DoneCircle() {
  // `initial={false}` skips straight to the final state for reduced-motion users.
  const reduceMotion = useReducedMotion();
  return (
    <motion.span
      className="grid size-[22px] place-items-center rounded-full bg-[#34c759]"
      initial={reduceMotion ? false : { scale: 0 }}
      whileInView={{ scale: 1 }}
      viewport={{ once: true }}
      transition={{ type: "spring", stiffness: 500, damping: 18, delay: 0.15 }}
    >
      <svg viewBox="0 0 24 24" fill="none" className="size-[13px]" aria-hidden>
        <path
          d="m7 12.5 3.2 3.2L17 8.5"
          stroke="white"
          strokeWidth={2.4}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </motion.span>
  );
}

/** A spinning progress indicator — an item mid-clean. */
function Spinner() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      className="size-[20px] text-white/70 motion-safe:animate-spin"
      aria-hidden
    >
      <circle cx="12" cy="12" r="8.5" stroke="currentColor" strokeOpacity={0.2} strokeWidth={2.2} />
      <path
        d="M12 3.5a8.5 8.5 0 0 1 8.5 8.5"
        stroke="currentColor"
        strokeWidth={2.2}
        strokeLinecap="round"
      />
    </svg>
  );
}

/** A blue filled checkbox with a white tick (Remove options). */
function Checkbox() {
  return (
    <span className="grid size-[18px] place-items-center rounded-[5px] bg-[var(--color-accent)]">
      <svg viewBox="0 0 24 24" fill="none" className="size-[12px]" aria-hidden>
        <path
          d="m6 12.5 3.5 3.5L18 7.5"
          stroke="white"
          strokeWidth={2.6}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </span>
  );
}

export function AppWindow({ className = "" }: { className?: string }) {
  const reduceMotion = useReducedMotion();
  return (
    <div
      className={`overflow-hidden rounded-[12px] bg-[#1c1c1e] ring-1 ring-white/10 ${className}`}
      style={{ boxShadow: "0 60px 120px -30px rgba(0,0,0,0.8), 0 20px 50px -20px rgba(0,0,0,0.6)" }}
    >
      {/* Title bar */}
      <div className="relative flex h-[44px] items-center justify-between border-b border-white/[0.07] bg-[#2a2a2c] px-4">
        <TrafficLights />
        <span className="absolute left-1/2 -translate-x-1/2 text-[13px] font-semibold text-white/60">
          Crisp
        </span>
        <Toolbar />
      </div>

      {/* Queue header */}
      <div className="flex items-center justify-between border-b border-white/[0.07] px-4 py-3">
        <span className="text-[13px] font-semibold text-white/55">Queue</span>
        <span className="text-[13px] text-white/55">1 of 3 done</span>
      </div>

      {/* Queue rows */}
      <div className="divide-y divide-white/[0.06]">
        {/* Done */}
        <div className="flex items-center gap-3 px-4 py-3.5">
          <DoneCircle />
          <div className="min-w-0 flex-1">
            <div className="truncate text-[15px] font-semibold text-white">
              Keynote-walkthrough.mov
            </div>
            <div className="text-[13px] text-[#30d158]">Cleaned — saved 1:24</div>
          </div>
          <Folder className="size-[17px] shrink-0 text-white/40" />
        </div>

        {/* Cleaning (active) */}
        <div className="flex items-center gap-3 px-4 py-3.5">
          <Spinner />
          <div className="min-w-0 flex-1">
            <div className="truncate text-[15px] font-semibold text-white">Team-update.mov</div>
            <div className="mt-1.5 flex items-center gap-3">
              <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/10">
                <motion.div
                  className="h-full rounded-full bg-[var(--color-accent)]"
                  initial={reduceMotion ? false : { width: "0%" }}
                  whileInView={{ width: "64%" }}
                  viewport={{ once: true }}
                  transition={{ duration: 1, ease: [0.16, 1, 0.3, 1], delay: 0.2 }}
                />
              </div>
              <span className="shrink-0 text-[13px] tabular-nums text-white/55">64%</span>
            </div>
            <div className="mt-1 text-[13px] text-white/50">Transcribing… 71%</div>
          </div>
        </div>

        {/* Waiting */}
        <div className="flex items-center gap-3 px-4 py-3.5">
          <span className="size-[20px] shrink-0 rounded-full border-[1.5px] border-dashed border-white/30" />
          <div className="min-w-0 flex-1">
            <div className="truncate text-[15px] font-semibold text-white">Product-demo.mov</div>
            <div className="text-[13px] text-white/50">Waiting</div>
          </div>
          <div className="flex shrink-0 items-center gap-3.5">
            <Monitor className="size-[17px] text-[var(--color-accent-bright)]" />
            <Waveform className="size-[17px] text-[var(--color-accent-bright)]" />
            <XCircle className="size-[17px] text-white/40" />
          </div>
        </div>
      </div>

      {/* Bottom control bar */}
      <div className="flex items-center justify-between gap-4 border-t border-white/[0.07] px-4 py-3">
        <div className="flex flex-col gap-2">
          <div className="flex items-center gap-3.5">
            {/* Cut popup */}
            <div className="flex items-center gap-2">
              <span className="text-[13px] text-white/45">Cut</span>
              <span className="flex items-center gap-1.5 whitespace-nowrap rounded-[6px] bg-white/10 px-2.5 py-1 text-[13px] font-medium text-white ring-1 ring-white/10">
                Balanced
                <ChevronUpDown className="size-[13px] text-white/50" />
              </span>
            </div>
            {/* Remove options */}
            <div className="flex items-center gap-2.5">
              <span className="text-[13px] text-white/45">Remove</span>
              <span className="flex items-center gap-1.5 whitespace-nowrap text-[13px] text-white">
                <Checkbox /> Fillers
              </span>
              <span className="flex items-center gap-1.5 whitespace-nowrap text-[13px] text-white">
                <Checkbox /> Repeated takes
              </span>
            </div>
          </div>
          <span className="text-[13px] text-[var(--color-accent-bright)]">Estimate savings</span>
        </div>

        {/* Primary action */}
        <button className="flex shrink-0 items-center gap-2 rounded-full bg-[var(--color-accent)] px-5 py-2.5 text-[15px] font-semibold text-white shadow-[0_8px_30px_-6px_rgba(10,132,255,0.6)]">
          <Scissors className="size-[17px]" />
          Clean Video
        </button>
      </div>

      {/* Footer guarantee */}
      <div className="border-t border-white/[0.07] px-4 py-2.5 text-[11px] text-white/35">
        Crisp only writes a cleaned copy — your originals are untouched.
      </div>
    </div>
  );
}
