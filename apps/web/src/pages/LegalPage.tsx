import { Link } from "@tanstack/react-router";
import { motion } from "framer-motion";
import { Waveform } from "../components/Logo";
import { Footer } from "../sections/Footer";
import type { LegalDoc } from "../content/legal";

const EASE = [0.16, 1, 0.3, 1] as const;

export function LegalPage({ doc }: { doc: LegalDoc }) {
  return (
    <>
      {/* slim header */}
      <header className="sticky top-0 z-50 border-b border-white/[0.06] bg-black/55 backdrop-blur-xl">
        <nav className="mx-auto flex h-14 max-w-3xl items-center justify-between px-5">
          <Link to="/" className="flex items-center gap-2 font-semibold tracking-tight text-white">
            <Waveform className="size-[18px]" />
            Crisp
          </Link>
          <Link to="/" hash="download" className="text-[13px] font-medium text-white/60 transition-colors hover:text-white">
            Install ›
          </Link>
        </nav>
      </header>

      <main className="relative overflow-hidden">
        <span
          className="orb left-1/2 top-0 size-[560px] -translate-x-1/2 -translate-y-1/3"
          style={{ background: "radial-gradient(circle, rgba(10,132,255,0.14), transparent 70%)" }}
        />
        <article className="relative z-10 mx-auto max-w-3xl px-5 pt-20 pb-24 sm:pt-28">
          <motion.div
            initial={{ opacity: 0, y: 24 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.9, ease: EASE }}
          >
            <p className="text-[13px] font-semibold uppercase tracking-[0.25em] text-[var(--color-accent-bright)]">
              Crisp
            </p>
            <h1 className="mt-4 text-[40px] font-semibold tracking-[-0.02em] sm:text-[56px]">
              {doc.title}
            </h1>
            <p className="mt-3 text-[14px] text-white/45">Last updated {doc.updated}</p>
            <p className="mt-7 text-[18px] leading-relaxed text-white/70">{doc.intro}</p>
            <p className="mt-5 rounded-xl border border-white/[0.08] bg-white/[0.03] px-4 py-3 text-[13px] leading-relaxed text-white/45">
              {doc.note}
            </p>
          </motion.div>

          <div className="mt-14 space-y-12">
            {doc.sections.map((s, i) => (
              <motion.section
                key={s.heading}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: "-10% 0px" }}
                transition={{ duration: 0.7, ease: EASE, delay: Math.min(i, 3) * 0.04 }}
              >
                <h2 className="text-[22px] font-semibold tracking-tight text-white sm:text-[26px]">
                  {s.heading}
                </h2>
                <div className="mt-3 text-[16px] leading-relaxed text-white/65 [&_a]:text-[var(--color-accent-bright)]">
                  {s.body}
                </div>
              </motion.section>
            ))}
          </div>

          <div className="mt-16 border-t border-white/[0.07] pt-8 text-[14px] text-white/45">
            <Link to="/" className="transition-colors hover:text-white">
              ‹ Back to Crisp
            </Link>
          </div>
        </article>
      </main>

      <Footer />
    </>
  );
}
