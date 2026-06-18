/**
 * The waveform — Crisp's whole identity, animated. A row of audio bars built
 * from a stable seeded envelope so it looks like real speech, not noise.
 *
 * <LiveWave/> breathes continuously (an idle audio visualizer) and is the hero's
 * centerpiece. The scroll-driven "cut" lives in the CutStory section, which
 * imports `seededHeights` to stay visually consistent with this.
 */
import { motion } from "framer-motion";

/** Deterministic 0..1 heights — same shape every render (no Math.random). */
export function seededHeights(n: number, seed = 1): number[] {
  const out: number[] = [];
  let s = seed * 9301 + 49297;
  for (let i = 0; i < n; i++) {
    s = (s * 9301 + 49297) % 233280;
    const r = s / 233280;
    // speech-like envelope: a slow swell across the row + per-bar jitter
    const swell = 0.55 + 0.4 * Math.sin((i / n) * Math.PI * 3 + seed);
    out.push(Math.max(0.08, Math.min(1, swell * (0.45 + r * 0.7))));
  }
  return out;
}

export function LiveWave({
  bars = 96,
  className = "",
}: {
  bars?: number;
  className?: string;
}) {
  const base = seededHeights(bars, 7);
  return (
    <div
      className={`flex h-full w-full items-center justify-center gap-[3px] ${className}`}
      style={{
        maskImage: "linear-gradient(90deg, transparent, #000 12%, #000 88%, transparent)",
        WebkitMaskImage: "linear-gradient(90deg, transparent, #000 12%, #000 88%, transparent)",
      }}
      aria-hidden
    >
      {base.map((h, i) => {
        // tallest near the centre, so the cut line sits in the loud part
        const dist = Math.abs(i - bars / 2) / (bars / 2);
        const peak = h * (0.35 + 0.85 * (1 - dist));
        const dur = 1.1 + ((i * 53) % 90) / 100; // 1.1–2.0s, stable per bar
        return (
          <motion.span
            key={i}
            className="w-[3px] flex-1 rounded-full"
            style={{
              transformOrigin: "center",
              background: "linear-gradient(180deg, #7dc0ff, var(--color-accent))",
              boxShadow: "0 0 12px rgba(10,132,255,0.35)",
              height: `${Math.round(peak * 100)}%`,
            }}
            initial={{ scaleY: 0.3, opacity: 0 }}
            animate={{
              scaleY: [peak * 0.5, peak, peak * 0.62, peak * 0.92, peak * 0.5],
              opacity: 1,
            }}
            transition={{
              scaleY: { duration: dur, repeat: Infinity, ease: "easeInOut" },
              opacity: { duration: 0.6, delay: i * 0.004 },
            }}
          />
        );
      })}
    </div>
  );
}

/** A small static waveform strip for inline use (feature blocks, footer). */
export function MiniWave({
  bars = 40,
  seed = 3,
  className = "",
  tone = "blue",
}: {
  bars?: number;
  seed?: number;
  className?: string;
  tone?: "blue" | "dim";
}) {
  const hs = seededHeights(bars, seed);
  return (
    <div className={`flex items-center gap-[2px] ${className}`} aria-hidden>
      {hs.map((h, i) => (
        <span
          key={i}
          className="w-full rounded-full"
          style={{
            height: `${Math.round(h * 100)}%`,
            background:
              tone === "blue"
                ? "linear-gradient(180deg,#7dc0ff,var(--color-accent))"
                : "rgba(255,255,255,0.18)",
          }}
        />
      ))}
    </div>
  );
}
