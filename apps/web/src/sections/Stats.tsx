import { CountUp, Reveal } from "../components/Motion";

const fmtClock = (v: number) => `${Math.floor(v / 60)}:${String(Math.round(v % 60)).padStart(2, "0")}`;

const STATS: Array<{ to: number; format?: (v: number) => string; label: string }> = [
  { to: 42, label: "pauses removed" },
  { to: 18, label: "filler words cut" },
  { to: 84, format: fmtClock, label: "of runtime saved" },
  { to: 0, label: "files uploaded" },
];

export function Stats() {
  return (
    <section className="relative mx-auto max-w-5xl px-5 py-20 sm:py-28">
      <Reveal>
        <p className="text-center text-[13px] font-semibold uppercase tracking-[0.25em] text-white/40">
          On a typical 8-minute screen recording
        </p>
      </Reveal>
      <div className="mt-12 grid grid-cols-2 gap-10 sm:grid-cols-4">
        {STATS.map((s, i) => (
          <Reveal key={s.label} delay={i * 0.08} className="text-center">
            <CountUp
              to={s.to}
              format={s.format}
              className="grad-blue block text-[52px] font-semibold tracking-tight sm:text-[72px]"
            />
            <span className="mt-1 block text-[14px] text-white/50">{s.label}</span>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
