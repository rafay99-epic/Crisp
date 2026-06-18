import { motion } from "framer-motion";
import { Reveal, KineticText } from "../components/Motion";
import { SilenceVisual, FillerTranscript, FilmStrip, StrengthControl } from "../components/AppBits";
import { CheckSeal, Lock } from "../components/Icons";
import { MiniWave } from "../components/Wave";

function Block({
  eyebrow,
  title,
  body,
  flip = false,
  children,
}: {
  eyebrow: string;
  title: string;
  body: string;
  flip?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="grid items-center gap-10 py-20 lg:grid-cols-2 lg:gap-20 lg:py-28">
      <Reveal className={flip ? "lg:order-2" : ""}>
        <p className="text-[13px] font-semibold uppercase tracking-[0.25em] text-[var(--color-accent-bright)]">
          {eyebrow}
        </p>
        <h3 className="mt-4 text-[34px] font-semibold leading-[1.05] tracking-[-0.02em] sm:text-[48px]">
          {title}
        </h3>
        <p className="mt-5 max-w-md text-[18px] leading-relaxed text-white/60">{body}</p>
      </Reveal>
      <motion.div
        className={flip ? "lg:order-1" : ""}
        initial={{ opacity: 0, scale: 0.94, y: 30 }}
        whileInView={{ opacity: 1, scale: 1, y: 0 }}
        viewport={{ once: true, margin: "-15% 0px" }}
        transition={{ duration: 1, ease: [0.16, 1, 0.3, 1] }}
      >
        {children}
      </motion.div>
    </div>
  );
}

function SafeFiles() {
  const panel = "rounded-2xl bg-white/[0.04] ring-1 ring-white/[0.08]";
  return (
    <div className={`${panel} p-6`}>
      <div className="flex items-center gap-3 rounded-xl bg-white/[0.04] p-3.5 ring-1 ring-white/[0.06]">
        <Lock className="size-5 text-white/55" />
        <span className="text-[14px] text-white/80">talk.mov</span>
        <span className="ml-auto rounded-full bg-white/10 px-2.5 py-1 text-[11px] text-white/55">untouched</span>
      </div>
      <div className="my-2 ml-6 h-5 w-px bg-white/10" />
      <div className="flex items-center gap-3 rounded-xl bg-[var(--color-accent)]/12 p-3.5 ring-1 ring-[var(--color-accent)]/30">
        <CheckSeal className="size-5 text-[var(--color-accent-bright)]" />
        <span className="text-[14px] text-white">talk_cleaned.mov</span>
        <span className="ml-auto rounded-full bg-[var(--color-accent)]/20 px-2.5 py-1 text-[11px] text-[var(--color-accent-bright)]">new file</span>
      </div>
      <p className="mt-4 text-center text-[12px] text-white/40">Originals are copied to a dated backup first.</p>
    </div>
  );
}

export function Capabilities() {
  return (
    <section id="features" className="relative mx-auto max-w-6xl px-5 py-24 sm:py-32">
      <div className="mx-auto max-w-3xl text-center">
        <KineticText
          text="It does the first edit for you."
          className="text-[40px] font-semibold leading-[1.06] tracking-[-0.025em] sm:text-[60px]"
        />
        <Reveal delay={0.1}>
          <p className="mx-auto mt-6 max-w-xl text-[19px] leading-relaxed text-white/55">
            The tedious pass nobody wants to do — finding every pause and filler — happens
            the moment you drop a file in.
          </p>
        </Reveal>
      </div>

      <div className="mt-12 divide-y divide-white/[0.06]">
        <Block
          eyebrow="Pauses"
          title="It hears the silence."
          body="Crisp measures the real audio energy to find dead air and long thinking gaps — far more accurate than guessing from a transcript — then cuts them out."
        >
          <SilenceVisual />
        </Block>

        <Block
          eyebrow="Fillers"
          title="It catches every “um.”"
          body="An on-device speech model timestamps every “um,” “uh,” “hmm,” and “erm,” and Crisp snips each one out at the exact frame."
          flip
        >
          <FillerTranscript />
        </Block>

        <Block
          eyebrow="Locked together"
          title="One cut. Picture and sound."
          body="Every cut moves the video and the audio as one, so nothing drifts out of sync. Same resolution, same frame rate, hardware-accelerated — never downscaled."
        >
          <FilmStrip />
        </Block>

        <Block
          eyebrow="Your call"
          title="Cut as much as you like."
          body="Gentle to very aggressive in one tap — or open the Custom knobs and dial in your own thresholds. Recommended settings are right there."
          flip
        >
          <StrengthControl />
        </Block>

        <Block
          eyebrow="Safe by design"
          title="It never touches your original."
          body="Crisp only ever writes a new cleaned file, and backs the original up first. It can't overwrite or delete your source — that's a guarantee, not a setting."
        >
          <SafeFiles />
        </Block>
      </div>

      <div className="mt-16 flex justify-center opacity-50">
        <MiniWave bars={60} tone="dim" className="h-8 w-full max-w-md" />
      </div>
    </section>
  );
}
