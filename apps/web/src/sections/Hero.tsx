import { AppWindow } from "../components/AppWindow";
import { CopyCommand } from "../components/AppBits";
import { Apple } from "../components/Icons";
import { RELEASES, REQUIREMENTS, BREW_INSTALL } from "../site";

export function Hero() {
  return (
    <section id="top" className="relative overflow-hidden">
      {/* soft ambient glow behind the product shot */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-[-12%] mx-auto h-[720px] max-w-4xl rounded-full opacity-60 blur-3xl"
        style={{
          background:
            "radial-gradient(closest-side, rgba(0,122,255,0.16), rgba(0,122,255,0.05) 60%, transparent)",
        }}
      />

      <div className="relative mx-auto max-w-5xl px-5 pt-24 pb-10 text-center sm:pt-32">
        <p className="text-[15px] font-medium text-[var(--color-ink-soft)]">
          Native for macOS · 100% on-device
        </p>

        <h1 className="mx-auto mt-4 max-w-4xl text-[52px] font-semibold leading-[1.04] tracking-[-0.025em] sm:text-[88px]">
          Make your recordings
          <br className="hidden sm:block" /> <span className="text-[var(--color-system-blue)]">crisp.</span>
        </h1>

        <p className="mx-auto mt-7 max-w-2xl text-[20px] leading-relaxed text-[var(--color-ink-soft)] sm:text-[24px]">
          Crisp automatically removes long pauses and filler words — the “um,” the “uh,”
          the dead air — from your screen recordings. Audio and video, cut together into
          tight jump-cuts. Right on your Mac.
        </p>

        <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <a
            href={RELEASES}
            className="flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-7 py-3.5 text-[17px] font-medium text-white shadow-sm transition-colors hover:bg-[var(--color-accent-hover)]"
          >
            <Apple className="size-[19px]" />
            Download for Mac
          </a>
          <a
            href="#how"
            className="rounded-full px-6 py-3.5 text-[17px] font-medium text-[var(--color-accent)] transition-colors hover:underline"
          >
            See how it works ›
          </a>
        </div>

        <div className="mx-auto mt-5 max-w-md">
          <CopyCommand command={BREW_INSTALL} />
        </div>
        <p className="mt-4 text-[13px] text-[var(--color-ink-soft)]">
          Free · open source · {REQUIREMENTS}
        </p>

        {/* The product — a faithful render of the real app, not a screenshot */}
        <div className="relative mx-auto mt-20 max-w-[600px]">
          <AppWindow />
        </div>
      </div>
    </section>
  );
}
