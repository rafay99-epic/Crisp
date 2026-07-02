import { Link } from "@tanstack/react-router";
import { motion } from "framer-motion";
import { Waveform } from "../components/Logo";
import { Footer } from "../sections/Footer";
import { Reveal, KineticText } from "../components/Motion";
import { CheckSeal } from "../components/Icons";
import { POLAR_CHECKOUT, POLAR_PORTAL } from "../site";

const EASE = [0.16, 1, 0.3, 1] as const;

const FEATURES = [
  "Removes long pauses & filler words automatically",
  "Native macOS app — fast, no browser upload",
  "Never downscales — same resolution & fps, high-quality H.264/HEVC",
  "Backs up your original footage before every clean",
  "Free updates on the stable channel",
];

export function Pricing() {
  return (
    <>
      {/* slim header — matches LegalPage */}
      <header className="sticky top-0 z-50 border-b border-white/[0.06] bg-black/55 backdrop-blur-xl">
        <nav className="mx-auto flex h-14 max-w-3xl items-center justify-between px-5">
          <Link to="/" className="flex items-center gap-2 font-semibold tracking-tight text-white">
            <Waveform className="size-[18px]" />
            Crisp
          </Link>
          <Link
            to="/"
            hash="download"
            className="text-[13px] font-medium text-white/60 transition-colors hover:text-white"
          >
            Install ›
          </Link>
        </nav>
      </header>

      <main className="relative overflow-hidden px-5 pt-20 pb-32 sm:pt-28">
        <span
          className="orb left-1/2 top-0 size-[640px] -translate-x-1/2 -translate-y-1/3"
          style={{ background: "radial-gradient(circle, rgba(10,132,255,0.18), transparent 70%)" }}
        />
        <div className="relative z-10 mx-auto max-w-2xl text-center">
          <motion.p
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, ease: EASE }}
            className="text-[13px] font-semibold uppercase tracking-[0.25em] text-[var(--color-accent-bright)]"
          >
            Pricing
          </motion.p>
          <KineticText
            text="One plan. Everything."
            className="mt-4 text-[52px] font-semibold tracking-[-0.02em] sm:text-[64px]"
          />
          <Reveal delay={0.1}>
            <p className="mx-auto mt-5 max-w-lg text-[18px] leading-relaxed text-white/60">
              No tiers to compare, no feature gates. One subscription unlocks Crisp Pro in full.
            </p>
          </Reveal>

          <Reveal delay={0.15}>
            <div className="mx-auto mt-14 max-w-md rounded-2xl border border-white/[0.08] bg-white/[0.03] p-8 text-left">
              <p className="text-[15px] font-semibold text-white">Crisp Pro</p>
              <p className="mt-2 flex items-baseline gap-1.5">
                <span className="text-[48px] font-semibold tracking-[-0.02em] text-white">$8</span>
                <span className="text-[15px] text-white/45">/month</span>
              </p>
              <p className="mt-2 text-[14px] text-white/60">Everything in Crisp, unlocked.</p>

              <ul className="mt-7 flex flex-col gap-2.5">
                {FEATURES.map((f) => (
                  <li key={f} className="flex items-start gap-2.5 text-[14px] leading-relaxed text-white/65">
                    <CheckSeal className="mt-0.5 size-[16px] shrink-0 text-[var(--color-accent-bright)]" />
                    {f}
                  </li>
                ))}
              </ul>

              <a
                href={POLAR_CHECKOUT}
                className="mt-8 block rounded-full bg-white px-5 py-3 text-center text-[14px] font-semibold text-black transition-transform hover:scale-[1.02]"
              >
                Get Crisp Pro
              </a>
              <p className="mt-3 text-center text-[12px] text-white/40">
                Checkout & billing are handled securely by Polar.
              </p>
              <a
                href={POLAR_PORTAL}
                className="mt-4 block text-center text-[12px] text-white/40 transition-colors hover:text-white/70"
              >
                Manage an existing subscription
              </a>
            </div>
          </Reveal>
        </div>
      </main>

      <Footer />
    </>
  );
}
