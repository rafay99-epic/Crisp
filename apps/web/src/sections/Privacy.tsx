import { motion } from "framer-motion";
import { Reveal, KineticText } from "../components/Motion";
import { Lock } from "../components/Icons";

export function Privacy() {
  return (
    <section id="privacy" className="relative overflow-hidden px-5 py-32 sm:py-44">
      <span
        className="orb left-1/2 top-1/2 size-[680px] -translate-x-1/2 -translate-y-1/2"
        style={{ background: "radial-gradient(circle, rgba(10,132,255,0.18), transparent 70%)" }}
      />
      <div className="relative z-10 mx-auto max-w-3xl text-center">
        <motion.span
          initial={{ opacity: 0, scale: 0.8 }}
          whileInView={{ opacity: 1, scale: 1 }}
          viewport={{ once: true }}
          transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
          className="inline-flex size-16 items-center justify-center rounded-2xl bg-white/[0.06] text-white ring-1 ring-white/15 backdrop-blur"
        >
          <Lock className="size-8" />
        </motion.span>

        <KineticText
          text="Your recordings never leave your Mac."
          className="mx-auto mt-8 max-w-3xl text-[40px] font-semibold leading-[1.08] tracking-[-0.02em] sm:text-[60px]"
        />

        <Reveal delay={0.1}>
          <p className="mx-auto mt-7 max-w-xl text-[19px] leading-relaxed text-white/55">
            No account, no cloud, no upload. Finding the silence, transcribing the fillers,
            rendering the cut — every step runs on-device. And because Crisp is open source
            under the GPL-3.0, you can read exactly what it does.
          </p>
        </Reveal>

        <Reveal delay={0.2}>
          <div className="mt-10 flex flex-wrap items-center justify-center gap-x-8 gap-y-3 text-[14px] text-white/45">
            <span>No telemetry</span>
            <span className="hidden text-white/20 sm:block">·</span>
            <span>No network calls</span>
            <span className="hidden text-white/20 sm:block">·</span>
            <span>Open source</span>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
