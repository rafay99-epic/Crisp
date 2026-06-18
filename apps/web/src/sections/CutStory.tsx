import { useRef, useState } from "react";
import {
  motion,
  useScroll,
  useTransform,
  useMotionValueEvent,
  type MotionValue,
} from "framer-motion";
import { seededHeights } from "../components/Wave";
import { Scissors } from "../components/Icons";

/** keep = speech we keep (blue); cut = a pause/filler that gets removed (red). */
const SEGMENTS: Array<{ keep: boolean; w: number }> = [
  { keep: true, w: 5 },
  { keep: false, w: 2.4 },
  { keep: true, w: 6 },
  { keep: false, w: 3 },
  { keep: true, w: 3.5 },
  { keep: false, w: 2 },
  { keep: true, w: 6.5 },
  { keep: false, w: 2.6 },
  { keep: true, w: 4 },
  { keep: false, w: 3.2 },
  { keep: true, w: 5.5 },
];

function fmtTime(totalSec: number) {
  const s = Math.max(0, Math.round(totalSec));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function Segment({ seg, index, progress }: { seg: { keep: boolean; w: number }; index: number; progress: MotionValue<number> }) {
  // cut segments collapse to nothing between 35%–60% scroll
  const grow = useTransform(progress, [0.35, 0.6], [seg.w, seg.keep ? seg.w : 0.0001]);
  const opacity = useTransform(progress, [0.4, 0.56], [1, seg.keep ? 1 : 0]);
  const bars = seededHeights(Math.round(seg.w * 3), index + 2);
  return (
    <motion.div
      style={{ flexGrow: grow, opacity }}
      className="flex h-full min-w-0 items-center gap-[2px] overflow-hidden"
    >
      {bars.map((h, i) => (
        <span
          key={i}
          className="w-full rounded-full"
          style={{
            height: `${seg.keep ? Math.round(h * 100) : 10}%`,
            background: seg.keep
              ? "linear-gradient(180deg,#7dc0ff,var(--color-accent))"
              : "var(--color-cut)",
            boxShadow: seg.keep ? "0 0 10px rgba(10,132,255,0.3)" : "none",
          }}
        />
      ))}
    </motion.div>
  );
}

export function CutStory() {
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end end"] });

  const playheadX = useTransform(scrollYProgress, [0.33, 0.62], ["0%", "100%"]);
  const playheadOpacity = useTransform(scrollYProgress, [0.3, 0.36, 0.6, 0.66], [0, 1, 1, 0]);

  // phase label crossfades
  const p1 = useTransform(scrollYProgress, [0.05, 0.15, 0.32, 0.4], [0, 1, 1, 0]);
  const p2 = useTransform(scrollYProgress, [0.36, 0.44, 0.58, 0.64], [0, 1, 1, 0]);
  const p3 = useTransform(scrollYProgress, [0.64, 0.74, 0.95, 1], [0, 1, 1, 1]);

  const time = useTransform(scrollYProgress, (v) => fmtTime(510 - Math.max(0, (v - 0.35) / 0.27) * 84));
  const foundOpacity = useTransform(scrollYProgress, [0.08, 0.18, 0.34, 0.4], [0, 1, 1, 0]);

  return (
    <section id="cut" ref={ref} className="relative h-[340vh]">
      <div className="sticky top-0 flex h-screen flex-col items-center justify-center overflow-hidden px-5">
        <span
          className="orb left-1/2 top-1/2 size-[600px] -translate-x-1/2 -translate-y-1/2"
          style={{ background: "radial-gradient(circle, rgba(10,132,255,0.16), transparent 70%)" }}
        />

        {/* phase labels (stacked, crossfading) */}
        <div className="relative z-10 mx-auto mb-14 h-[170px] w-full max-w-3xl text-center sm:h-[190px]">
          <Phase op={p1} title="It listens first." sub="Crisp reads the real audio energy to find every pause and filler." />
          <Phase op={p2} title="Then it cuts." sub="Dead air and hesitation words are removed — audio and video together." />
          <Phase op={p3} title="Crisp." sub="What's left is tight, sharp, and the same quality you recorded." />
        </div>

        {/* the timeline */}
        <div className="relative z-10 w-full max-w-5xl">
          <div className="mb-4 flex items-center justify-between text-[13px] font-medium">
            <motion.span style={{ opacity: foundOpacity }} className="flex items-center gap-2 text-[var(--color-cut)]">
              <Scissors className="size-4" /> 5 pauses · 3 fillers found
            </motion.span>
            <span className="ml-auto font-mono text-white/70">
              <Readout mv={time} />
            </span>
          </div>

          <div className="relative flex h-[180px] items-center gap-[6px] rounded-2xl bg-white/[0.03] p-5 ring-1 ring-white/[0.07] sm:h-[220px]">
            {SEGMENTS.map((seg, i) => (
              <Segment key={i} seg={seg} index={i} progress={scrollYProgress} />
            ))}

            {/* sweeping cut playhead */}
            <motion.div
              style={{ left: playheadX, opacity: playheadOpacity }}
              className="pointer-events-none absolute top-0 bottom-0 z-20 w-[2px] -translate-x-1/2 bg-white shadow-[0_0_20px_5px_rgba(255,255,255,0.5)]"
            >
              <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-white p-1 text-black">
                <Scissors className="size-3.5" />
              </span>
            </motion.div>
          </div>

          <div className="mt-4 flex justify-between text-[12px] text-white/35">
            <span>0:00</span>
            <span>cut together, never downscaled</span>
          </div>
        </div>
      </div>
    </section>
  );
}

/** Renders a string MotionValue as live text (TS-safe vs. a raw child). */
function Readout({ mv }: { mv: MotionValue<string> }) {
  const [s, setS] = useState(mv.get());
  useMotionValueEvent(mv, "change", setS);
  return <>{s}</>;
}

function Phase({ op, title, sub }: { op: MotionValue<number>; title: string; sub: string }) {
  return (
    <motion.div style={{ opacity: op }} className="absolute inset-0 flex flex-col items-center">
      <h2 className="text-[40px] font-semibold tracking-[-0.02em] sm:text-[64px]">{title}</h2>
      <p className="mt-3 max-w-xl text-[17px] leading-relaxed text-white/55 sm:text-[19px]">{sub}</p>
    </motion.div>
  );
}
