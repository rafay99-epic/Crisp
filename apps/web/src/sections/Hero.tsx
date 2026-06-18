import { AppWindow } from "../components/AppWindow";
import { Apple, ArrowDown } from "../components/Icons";
import { RELEASES, REPO, REQUIREMENTS } from "../site";

export function Hero() {
  return (
    <section id="top" className="relative overflow-hidden">
      {/* soft ambient glow behind the product shot */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-[-10%] mx-auto h-[640px] max-w-3xl rounded-full opacity-60 blur-3xl"
        style={{
          background:
            "radial-gradient(closest-side, rgba(0,122,255,0.18), rgba(0,122,255,0.06) 60%, transparent)",
        }}
      />

      <div className="relative mx-auto max-w-5xl px-5 pt-20 pb-12 text-center sm:pt-28">
        <a
          href={REPO}
          className="inline-flex items-center gap-2 rounded-full bg-[var(--color-mist)] px-3 py-1 text-[12px] font-medium text-[var(--color-ink-soft)] ring-1 ring-black/[0.05]"
        >
          <span className="size-1.5 rounded-full bg-[var(--color-accent)]" />
          Native macOS · 100% local · open source
        </a>

        <h1 className="mx-auto mt-6 max-w-3xl text-[44px] font-bold leading-[1.05] tracking-[-0.02em] sm:text-[68px]">
          Make your recordings{" "}
          <span className="bg-gradient-to-b from-[#3a9bff] to-[var(--color-system-blue)] bg-clip-text text-transparent">
            crisp.
          </span>
        </h1>

        <p className="mx-auto mt-5 max-w-2xl text-[18px] leading-relaxed text-[var(--color-ink-soft)] sm:text-[21px]">
          Crisp automatically removes long pauses and filler words — the “um,” the “uh,”
          the dead air — from your screen recordings. Audio and video, cut together into
          tight jump-cuts. Right on your Mac.
        </p>

        <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <a
            href={RELEASES}
            className="flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-6 py-3 text-[16px] font-medium text-white shadow-sm transition-colors hover:bg-[var(--color-accent-hover)]"
          >
            <Apple className="size-[18px]" />
            Download for Mac
          </a>
          <a
            href="#how"
            className="flex items-center gap-1.5 rounded-full px-5 py-3 text-[16px] font-medium text-[var(--color-accent)] transition-colors hover:underline"
          >
            See how it works <ArrowDown className="size-4" />
          </a>
        </div>
        <p className="mt-4 text-[13px] text-[var(--color-ink-soft)]">
          Free · {REQUIREMENTS} · GPL-3.0
        </p>

        {/* The product — a faithful render of the real app, not a screenshot */}
        <div className="relative mx-auto mt-16 max-w-[560px]">
          <AppWindow />
        </div>
      </div>
    </section>
  );
}
