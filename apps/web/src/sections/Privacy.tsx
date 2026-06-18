import { Lock } from "../components/Icons";

export function Privacy() {
  return (
    <section id="privacy" className="px-5 py-24 sm:py-32">
      <div className="reveal relative mx-auto max-w-5xl overflow-hidden rounded-[28px] bg-[var(--color-app-bg)] px-8 py-20 text-center sm:px-16">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 top-0 mx-auto h-72 max-w-xl rounded-full opacity-40 blur-3xl"
          style={{ background: "radial-gradient(closest-side, rgba(0,122,255,0.45), transparent)" }}
        />
        <span className="relative inline-flex size-14 items-center justify-center rounded-2xl bg-white/10 text-white ring-1 ring-white/15">
          <Lock className="size-7" />
        </span>
        <h2 className="relative mx-auto mt-7 max-w-3xl text-[36px] font-semibold leading-[1.08] tracking-[-0.02em] text-white sm:text-[56px]">
          Your recordings never leave your Mac.
        </h2>
        <p className="relative mx-auto mt-6 max-w-xl text-[19px] leading-relaxed text-white/65">
          There’s no account, no cloud, no upload. Every step — finding the silence,
          transcribing the fillers, rendering the cut — runs entirely on-device. And because
          Crisp is open source under the GPL-3.0, you can read exactly what it does.
        </p>
        <div className="relative mt-9 flex flex-wrap items-center justify-center gap-x-8 gap-y-3 text-[14px] text-white/55">
          <span>No telemetry</span>
          <span className="hidden sm:block">·</span>
          <span>No network calls</span>
          <span className="hidden sm:block">·</span>
          <span>Open source</span>
        </div>
      </div>
    </section>
  );
}
