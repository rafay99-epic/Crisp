import { AppWindow } from "../components/AppWindow";
import { Tilt, Reveal, KineticText } from "../components/Motion";

export function TheApp() {
  return (
    <section className="relative overflow-hidden px-5 py-24 sm:py-32">
      <div className="mx-auto max-w-3xl text-center">
        <Reveal>
          <p className="text-[13px] font-semibold uppercase tracking-[0.25em] text-[var(--color-accent-bright)]">
            The whole app
          </p>
        </Reveal>
        <KineticText
          text="One window. Drop, choose, done."
          className="mx-auto mt-4 max-w-2xl text-[34px] font-semibold leading-[1.07] tracking-[-0.02em] sm:text-[52px]"
        />
        <Reveal delay={0.1}>
          <p className="mx-auto mt-5 max-w-xl text-[18px] leading-relaxed text-white/55">
            No timeline to learn, no project to set up. It looks and behaves like an app Apple
            would ship — because it's built to.
          </p>
        </Reveal>
      </div>

      <Reveal delay={0.15} className="mt-16 flex justify-center">
        <div className="relative">
          <span
            className="orb left-1/2 top-1/2 size-[560px] -translate-x-1/2 -translate-y-1/2"
            style={{ background: "radial-gradient(circle, rgba(10,132,255,0.22), transparent 70%)" }}
          />
          <Tilt max={7} className="relative w-[min(92vw,560px)]" style={{ transformStyle: "preserve-3d" }}>
            <AppWindow />
          </Tilt>
        </div>
      </Reveal>
    </section>
  );
}
