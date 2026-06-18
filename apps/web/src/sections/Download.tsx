import { motion } from "framer-motion";
import { AppIcon } from "../components/Logo";
import { CopyCommand } from "../components/AppBits";
import { Reveal, KineticText } from "../components/Motion";
import { CheckSeal } from "../components/Icons";
import { REPO, REQUIREMENTS, BREW_INSTALL } from "../site";

const PERKS = [
  "Installs cleanly — no Gatekeeper warnings",
  "Updates itself with your other casks",
  "One command to remove it completely",
];

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
          text="Install Crisp."
          className="mt-8 text-[52px] font-semibold tracking-[-0.02em] sm:text-[80px]"
        />
        <Reveal delay={0.1}>
          <p className="mx-auto mt-5 max-w-lg text-[19px] leading-relaxed text-white/60">
            One line in Terminal with Homebrew. It handles everything — signing, install, and
            updates — so you skip the “unidentified developer” song and dance.
          </p>
        </Reveal>

        <Reveal delay={0.15}>
          <div className="mx-auto mt-10 max-w-md">
            <CopyCommand command={BREW_INSTALL} />
          </div>

          <ul className="mx-auto mt-7 flex max-w-md flex-col items-start gap-2.5 text-left">
            {PERKS.map((p) => (
              <li key={p} className="flex items-center gap-2.5 text-[15px] text-white/65">
                <CheckSeal className="size-[18px] shrink-0 text-[var(--color-accent-bright)]" />
                {p}
              </li>
            ))}
          </ul>
          <p className="mt-7 text-[13px] text-white/40">{REQUIREMENTS}</p>
        </Reveal>

        <Reveal delay={0.2}>
          <div className="mx-auto mt-12 max-w-md space-y-2 text-[14px] leading-relaxed text-white/40">
            <p>
              Don't have Homebrew yet? Install it from{" "}
              <a href="https://brew.sh" className="text-[var(--color-accent-bright)] hover:underline">
                brew.sh
              </a>
              , then run the line above.
            </p>
            <p>
              Want the newest builds? Add the Nightly channel beside your stable copy:{" "}
              <code className="rounded bg-white/[0.07] px-1.5 py-0.5 font-mono text-[12px] text-white/70">
                brew install --cask rafay99-epic/apps/crisp-nightly
              </code>
            </p>
            <p>
              Prefer to read the source or build it yourself?{" "}
              <a href={REPO} className="text-[var(--color-accent-bright)] hover:underline">
                View on GitHub ›
              </a>
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
