/**
 * Small, faithful recreations of pieces of the real Crisp UI — used as crisp
 * "product shots" inside the bento grid. All CSS/SVG, so they stay sharp.
 */
import { useState } from "react";
import { Scissors } from "./Icons";

/** The "How much to cut" control + a couple of the Custom knobs (Settings). */
export function StrengthControl() {
  const segs = ["Gentle", "Balanced", "Aggressive", "Very", "Custom"];
  return (
    <div className="rounded-2xl bg-white p-5 ring-1 ring-black/[0.06] shadow-sm">
      <p className="text-[14px] font-semibold text-[var(--color-ink)]">How much to cut</p>
      <div className="mt-2.5 flex rounded-[8px] bg-black/[0.05] p-[2px] text-[12px] font-medium">
        {segs.map((s) => (
          <span
            key={s}
            className={`flex-1 rounded-[6px] px-2 py-[6px] text-center ${
              s === "Aggressive"
                ? "bg-white text-[var(--color-ink)] shadow-sm"
                : "text-[var(--color-ink-soft)]"
            }`}
          >
            {s}
          </span>
        ))}
      </div>
      <div className="mt-5 space-y-4">
        {[
          ["Pause length", 0.42],
          ["Keep around cuts", 0.28],
        ].map(([label, frac]) => (
          <div key={label as string}>
            <div className="mb-1.5 flex justify-between text-[12px] text-[var(--color-ink-soft)]">
              <span>{label}</span>
            </div>
            <div className="relative h-1.5 rounded-full bg-black/[0.08]">
              <div
                className="absolute inset-y-0 left-0 rounded-full bg-[var(--color-system-blue)]"
                style={{ width: `${(frac as number) * 100}%` }}
              />
              <div
                className="absolute top-1/2 size-[15px] -translate-y-1/2 rounded-full bg-white shadow ring-1 ring-black/10"
                style={{ left: `calc(${(frac as number) * 100}% - 7px)` }}
              />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

/** A transcript line with the filler words struck out, the way Crisp finds them. */
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
  return (
    <div className="rounded-2xl bg-white p-5 text-[15px] leading-[2] ring-1 ring-black/[0.06] shadow-sm">
      {tokens.map(([t, filler], i) => (
        <span key={i}>
          {filler ? (
            <span className="mx-0.5 rounded-[5px] bg-[#ff5f57]/12 px-1.5 py-0.5 text-[#d63a32] line-through decoration-[#d63a32]/70">
              {t}
            </span>
          ) : (
            <span className="text-[var(--color-ink)]">{t}</span>
          )}{" "}
        </span>
      ))}
    </div>
  );
}

/** A dark waveform strip with the silent gaps marked for the cut. */
export function SilenceVisual() {
  // 1 = speech (tall, blue), 0 = silence (flat, dim/red)
  const pattern = [1, 1, 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 0, 1, 1];
  return (
    <div className="rounded-2xl bg-[#161617] p-5">
      <div className="mb-3 flex items-center gap-2 text-[12px] text-white/45">
        <Scissors className="size-3.5" /> Silence detected from real audio energy
      </div>
      <div className="flex h-20 items-center gap-[3px]">
        {pattern.map((v, i) => {
          // pseudo-random but stable heights per index for the speech bars
          const h = v ? 28 + ((i * 37) % 60) : 8;
          return (
            <span
              key={i}
              className={`w-full rounded-full ${v ? "bg-[var(--color-system-blue)]" : "bg-[#ff5f57]/60"}`}
              style={{ height: `${h}%` }}
            />
          );
        })}
      </div>
    </div>
  );
}

/** A simple copy-to-clipboard command line, used for the Homebrew install. */
export function CopyCommand({ command, dark = false }: { command: string; dark?: boolean }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      /* clipboard unavailable — no-op */
    }
  };
  const base = dark
    ? "bg-white/10 text-white ring-white/15"
    : "bg-[var(--color-mist)] text-[var(--color-ink)] ring-black/[0.06]";
  return (
    <button
      onClick={copy}
      className={`group flex w-full items-center gap-3 rounded-full px-5 py-3 text-left font-mono text-[13px] ring-1 transition-colors ${base}`}
    >
      <span className={dark ? "text-white/40" : "text-[var(--color-ink-soft)]"}>$</span>
      <span className="flex-1 truncate">{command}</span>
      <span className={`text-[12px] font-sans ${dark ? "text-white/55" : "text-[var(--color-ink-soft)]"}`}>
        {copied ? "Copied" : "Copy"}
      </span>
    </button>
  );
}
