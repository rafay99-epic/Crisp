import { useRef } from "react";
import { motion, useScroll, useTransform, useInView } from "framer-motion";
import { LiveWave } from "../components/Wave";
import { CopyCommand } from "../components/AppBits";
import { Magnetic } from "../components/Motion";
import { Apple } from "../components/Icons";
import { REQUIREMENTS, BREW_INSTALL } from "../site";

const EASE = [0.16, 1, 0.3, 1] as const;

export function Hero() {
  const ref = useRef<HTMLElement>(null);
  const inView = useInView(ref, { margin: "0px" }); // pause ambient motion off-screen
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end start"] });
  const waveY = useTransform(scrollYProgress, [0, 1], [0, 160]);
  const waveScale = useTransform(scrollYProgress, [0, 1], [1, 1.15]);
  const contentY = useTransform(scrollYProgress, [0, 1], [0, -60]);
  const fade = useTransform(scrollYProgress, [0, 0.7], [1, 0]);

  return (
    <section id="top" ref={ref} className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden px-5 pt-24">
      {/* drifting glow orbs */}
      <motion.span
        className="orb left-[10%] top-[12%] size-[460px]"
        style={{ background: "radial-gradient(circle, rgba(10,132,255,0.30), transparent 70%)", willChange: "transform" }}
        animate={inView ? { x: [0, 60, 0], y: [0, 40, 0] } : {}}
        transition={{ duration: 18, repeat: Infinity, ease: "easeInOut" }}
      />
      <motion.span
        className="orb right-[8%] bottom-[14%] size-[420px]"
        style={{ background: "radial-gradient(circle, rgba(100,210,255,0.22), transparent 70%)", willChange: "transform" }}
        animate={inView ? { x: [0, -50, 0], y: [0, -30, 0] } : {}}
        transition={{ duration: 22, repeat: Infinity, ease: "easeInOut" }}
      />

      <motion.div style={{ y: contentY, opacity: fade }} className="relative z-10 flex flex-col items-center text-center">
        <motion.p
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, ease: EASE, delay: 0.1 }}
          className="text-[14px] font-medium uppercase tracking-[0.3em] text-white/45"
        >
          Native for macOS · 100% on-device
        </motion.p>

        <h1 className="mt-7 max-w-5xl text-[56px] font-semibold leading-[0.98] tracking-[-0.03em] sm:text-[104px]">
          <Line text="Make your" delay={0.18} />
          <Line text="recordings" delay={0.28} />
          <span className="block overflow-hidden">
            <motion.span
              className="grad-blue inline-block"
              initial={{ y: "110%" }}
              animate={{ y: "0%" }}
              transition={{ duration: 1, ease: EASE, delay: 0.42 }}
            >
              crisp.
            </motion.span>
          </span>
        </h1>
      </motion.div>

      {/* The living waveform — the hero's centerpiece */}
      <motion.div
        style={{ y: waveY, scale: waveScale, opacity: fade }}
        className="relative z-0 mt-10 h-[200px] w-full max-w-5xl sm:h-[260px]"
      >
        <LiveWave bars={76} />
        {/* the cut line down the middle */}
        <motion.span
          className="absolute left-1/2 top-1/2 h-[70%] w-px -translate-x-1/2 -translate-y-1/2 bg-white/40"
          initial={{ scaleY: 0 }}
          animate={{ scaleY: 1 }}
          transition={{ duration: 0.8, ease: EASE, delay: 0.9 }}
        />
      </motion.div>

      <motion.div
        style={{ opacity: fade }}
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.9, ease: EASE, delay: 0.7 }}
        className="relative z-10 mt-10 flex flex-col items-center"
      >
        <p className="max-w-2xl text-center text-[19px] leading-relaxed text-white/65 sm:text-[22px]">
          Crisp finds the long pauses and filler words — the “um,” the “uh,” the dead air —
          and cuts them out of your audio and video together. Tight jump-cuts, right on your Mac.
        </p>

        <div className="mt-9 flex flex-col items-center gap-3 sm:flex-row">
          <Magnetic strength={0.35}>
            <a
              href="#download"
              className="flex items-center gap-2 rounded-full bg-white px-8 py-4 text-[17px] font-semibold text-black shadow-[0_10px_40px_-8px_rgba(255,255,255,0.4)] transition-transform hover:scale-[1.02]"
            >
              <Apple className="size-[19px]" />
              Install for Mac
            </a>
          </Magnetic>
          <a href="#cut" className="rounded-full px-6 py-4 text-[17px] font-medium text-white/70 transition-colors hover:text-white">
            Watch it cut ›
          </a>
        </div>

        <div className="mt-6 w-full max-w-sm">
          <p className="mb-2 text-center text-[12px] uppercase tracking-[0.2em] text-white/35">
            One line in Terminal
          </p>
          <CopyCommand command={BREW_INSTALL} />
        </div>
        <p className="mt-4 text-[13px] text-white/40">Free · open source · {REQUIREMENTS}</p>
      </motion.div>

      {/* scroll cue */}
      <motion.div
        style={{ opacity: fade }}
        className="absolute bottom-7 left-1/2 -translate-x-1/2"
        animate={{ y: [0, 8, 0] }}
        transition={{ duration: 1.8, repeat: Infinity, ease: "easeInOut" }}
      >
        <div className="flex h-9 w-5 items-start justify-center rounded-full border border-white/25 p-1">
          <span className="h-2 w-px rounded bg-white/60" />
        </div>
      </motion.div>
    </section>
  );
}

function Line({ text, delay }: { text: string; delay: number }) {
  return (
    <span className="block overflow-hidden">
      <motion.span
        className="inline-block"
        initial={{ y: "110%" }}
        animate={{ y: "0%" }}
        transition={{ duration: 1, ease: EASE, delay }}
      >
        {text}
      </motion.span>
    </span>
  );
}
