/**
 * Small, faithful recreations of pieces of the real Crisp UI, dark variant —
 * used as crisp "product shots" inside the cinematic feature blocks. CSS/SVG, so
 * they stay sharp.
 */
import { useState } from "react";
import { motion } from "framer-motion";
import { Scissors } from "./Icons";
import { seededHeights } from "./Wave";

const panel = "rounded-2xl bg-white/[0.04] ring-1 ring-white/[0.08] backdrop-blur";

/** The "How much to cut" control + two of the Custom knobs (Settings). */
export function StrengthControl() {
  const segs = ["Gentle", "Balanced", "Aggressive", "Very", "Custom"];
  return (
    <div className={`${panel} p-6`}>
      <p className="text-[14px] font-semibold text-white">How much to cut</p>
      <div className="mt-3 flex rounded-[8px] bg-black/40 p-[2px] text-[12px] font-medium">
        {segs.map((s) => (
          <span
            key={s}
            className={`flex-1 rounded-[6px] px-2 py-[6px] text-center ${
              s === "Aggressive" ? "bg-white/15 text-white shadow-sm" : "text-white/50"
            }`}
          >
            {s}
          </span>
        ))}
      </div>
      <div className="mt-6 space-y-5">
        {[
          ["Pause length", 0.42],
          ["Keep around cuts", 0.28],
        ].map(([label, frac]) => (
          <div key={label as string}>
            <div className="mb-2 text-[12px] text-white/50">{label}</div>
            <div className="relative h-1.5 rounded-full bg-white/10">
              <div
                className="absolute inset-y-0 left-0 rounded-full bg-[var(--color-accent)]"
                style={{ width: `${(frac as number) * 100}%` }}
              />
              <div
                className="absolute top-1/2 size-[15px] -translate-y-1/2 rounded-full bg-white shadow"
                style={{ left: `calc(${(frac as number) * 100}% - 7px)` }}
              />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

/** A transcript line; filler words get caught and struck out, one by one. */
export function FillerTranscript() {
  const tokens: Array<[string, boolean]> = [
    ["So today I want to", false],
    ["um", true],
    ["walk you through the", false],
    ["uh", true],
    ["new dashboard — and", false],
    ["hmm", true],
    ["here's the best part.", false],
  ];
  let fillerIdx = 0;
  return (
    <div className={`${panel} p-6 text-[17px] leading-[2.1] text-white`}>
      {tokens.map(([t, filler], i) => {
        if (!filler) return <span key={i} className="text-white/85">{t} </span>;
        const delay = 0.3 + fillerIdx++ * 0.5;
        return (
          <span key={i} className="relative mx-0.5 inline-block">
            <motion.span
              className="rounded-[5px] bg-[var(--color-cut)]/15 px-1.5 py-0.5 text-[#ff6b62]"
              initial={{ opacity: 0.9 }}
              whileInView={{ opacity: [0.9, 1, 0.45] }}
              viewport={{ once: true }}
              transition={{ duration: 0.6, delay, times: [0, 0.4, 1] }}
            >
              {t}
            </motion.span>
            {/* the strike-through line animating across */}
            <motion.span
              className="absolute left-1 top-1/2 h-[2px] rounded bg-[#ff6b62]"
              initial={{ width: 0 }}
              whileInView={{ width: "calc(100% - 8px)" }}
              viewport={{ once: true }}
              transition={{ duration: 0.35, delay: delay + 0.1, ease: "easeOut" }}
            />{" "}
          </span>
        );
      })}
    </div>
  );
}

/** A dark waveform strip with the silent gaps marked for the cut. */
export function SilenceVisual() {
  const pattern = [1, 1, 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1];
  const hs = seededHeights(pattern.length, 11);
  return (
    <div className={`${panel} p-6`}>
      <div className="mb-4 flex items-center gap-2 text-[13px] text-white/45">
        <Scissors className="size-4 text-[var(--color-cut)]" /> Silence found from real audio energy
      </div>
      <div className="flex h-28 items-center gap-[3px]">
        {pattern.map((v, i) => (
          <motion.span
            key={i}
            className={`w-full rounded-full ${v ? "" : "bg-[var(--color-cut)]/60"}`}
            style={
              v
                ? { background: "linear-gradient(180deg,#7dc0ff,var(--color-accent))" }
                : undefined
            }
            initial={{ scaleY: 0.2, opacity: 0 }}
            whileInView={{ scaleY: 1, opacity: 1 }}
            viewport={{ once: true }}
            transition={{ duration: 0.5, delay: i * 0.02, ease: "easeOut" }}
            // silent bars stay short; speech bars use their seeded height
          >
            <span className="block" style={{ height: `${v ? Math.round(hs[i] * 100) : 9}%` }} />
          </motion.span>
        ))}
      </div>
    </div>
  );
}

/** Film strip + waveform, sliced together — audio & video locked. */
export function FilmStrip() {
  const frames = Array.from({ length: 7 });
  return (
    <div className={`${panel} overflow-hidden p-6`}>
      <div className="relative">
        {/* video frames */}
        <div className="flex gap-1.5">
          {frames.map((_, i) => (
            <div
              key={i}
              className="relative h-16 flex-1 rounded-md"
              style={{
                background: `linear-gradient(135deg, hsl(${210 + i * 6} 60% ${22 + i * 3}%), hsl(${220 + i * 5} 70% ${12 + i * 2}%))`,
              }}
            >
              <span className="absolute inset-x-1 top-1 flex justify-between">
                {[0, 1, 2].map((d) => (
                  <span key={d} className="size-1 rounded-full bg-black/40" />
                ))}
              </span>
            </div>
          ))}
        </div>
        {/* waveform locked beneath */}
        <div className="mt-2 flex h-8 items-center gap-[3px]">
          {seededHeights(frames.length * 5, 5).map((h, i) => (
            <span
              key={i}
              className="w-full rounded-full"
              style={{ height: `${Math.round(h * 100)}%`, background: "linear-gradient(180deg,#7dc0ff,var(--color-accent))" }}
            />
          ))}
        </div>
        {/* the cut line through both */}
        <motion.span
          className="absolute -top-1 bottom-0 w-[2px] bg-white shadow-[0_0_16px_4px_rgba(255,255,255,0.5)]"
          initial={{ left: "10%", opacity: 0 }}
          whileInView={{ left: "62%", opacity: 1 }}
          viewport={{ once: true }}
          transition={{ duration: 1.1, ease: [0.16, 1, 0.3, 1], delay: 0.2 }}
        />
      </div>
    </div>
  );
}

/** A copy-to-clipboard command line (Homebrew install). Dark by default. */
export function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      /* clipboard unavailable */
    }
  };
  return (
    <button
      onClick={copy}
      className="group flex w-full items-center gap-3 rounded-full bg-white/[0.06] px-5 py-3 text-left font-mono text-[13px] text-white ring-1 ring-white/10 transition-colors hover:bg-white/[0.1]"
    >
      <span className="text-[var(--color-accent-bright)]">$</span>
      <span className="flex-1 truncate">{command}</span>
      <span className="font-sans text-[12px] text-white/50 group-hover:text-white/80">
        {copied ? "Copied ✓" : "Copy"}
      </span>
    </button>
  );
}
