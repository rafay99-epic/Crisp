import { motion } from "framer-motion";
import { AppIcon } from "../components/Logo";
import { CopyCommand } from "../components/AppBits";
import { Magnetic, Reveal, KineticText } from "../components/Motion";
import { Apple } from "../components/Icons";
import { RELEASES, REPO, REQUIREMENTS, BREW_INSTALL } from "../site";

export function Download() {
  return (
    <section id="download" className="relative overflow-hidden px-5 py-32 sm:py-44">
      <span
        className="orb left-1/2 top-[30%] size-[640px] -translate-x-1/2 -translate-y-1/2"
        style={{ background: "radial-gradient(circle, rgba(10,132,255,0.20), transparent 70%)" }}
      />
      <div className="relative z-10 mx-auto max-w-2xl text-center">
        <motion.div
          initial={{ opacity: 0, scale: 0.7, y: 30 }}
          whileInView={{ opacity: 1, scale: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 1, ease: [0.16, 1, 0.3, 1] }}
          className="mx-auto w-28"
        >
          <AppIcon className="size-28 drop-shadow-[0_20px_60px_rgba(10,132,255,0.45)]" />
        </motion.div>

        <KineticText
          text="Get Crisp."
          className="mt-8 text-[52px] font-semibold tracking-[-0.02em] sm:text-[80px]"
        />
        <Reveal delay={0.1}>
          <p className="mx-auto mt-5 max-w-lg text-[19px] leading-relaxed text-white/60">
            Free and open source. Install with Homebrew and it keeps itself up to date — or
            grab the DMG directly.
          </p>
        </Reveal>

        <Reveal delay={0.15}>
          <div className="mx-auto mt-10 max-w-md">
            <CopyCommand command={BREW_INSTALL} />
          </div>

          <div className="mt-6 flex items-center gap-4 text-[13px] text-white/35">
            <span className="h-px flex-1 bg-white/10" />
            or
            <span className="h-px flex-1 bg-white/10" />
          </div>

          <div className="mt-6 flex flex-col items-center justify-center gap-3 sm:flex-row">
            <Magnetic strength={0.35}>
              <a
                href={RELEASES}
                className="flex items-center gap-2 rounded-full bg-white px-8 py-4 text-[17px] font-semibold text-black shadow-[0_10px_40px_-8px_rgba(255,255,255,0.4)] transition-transform hover:scale-[1.02]"
              >
                <Apple className="size-[19px]" />
                Download the DMG
              </a>
            </Magnetic>
            <a href={REPO} className="rounded-full px-6 py-4 text-[17px] font-medium text-white/70 transition-colors hover:text-white">
              View on GitHub ›
            </a>
          </div>
          <p className="mt-5 text-[13px] text-white/40">{REQUIREMENTS}</p>
        </Reveal>

        <Reveal delay={0.2}>
          <p className="mx-auto mt-12 max-w-md text-[14px] leading-relaxed text-white/40">
            Want the newest builds? Install the Nightly channel beside your stable copy with{" "}
            <code className="rounded bg-white/[0.07] px-1.5 py-0.5 font-mono text-[12px] text-white/70">
              brew install --cask rafay99-epic/apps/crisp-nightly
            </code>
            .
          </p>
        </Reveal>
      </div>
    </section>
  );
}
