import { Reveal, KineticText } from "../components/Motion";
import { XCircle, CheckSeal, Clock, Bolt } from "../components/Icons";

/** The lived difference — the tedious manual edit vs. dropping a file in Crisp. */
const WITHOUT = [
  "Scrub the timeline hunting for every “um” and dead gap.",
  "Ripple-delete each pause by hand, one cut at a time.",
  "Re-watch the whole thing to catch the ones you missed.",
  "Learn Premiere or Final Cut just to trim silence.",
  "An eight-minute recording eats your whole afternoon.",
];

const WITH = [
  "Drop the file in. That’s the entire workflow.",
  "Every pause and filler found automatically, at the exact frame.",
  "Picture and sound cut together — nothing drifts out of sync.",
  "Same resolution, same fps — never downscaled.",
  "Your original is backed up first and never touched.",
];

function Column({
  eyebrow,
  time,
  timeLabel,
  points,
  tone,
}: {
  eyebrow: string;
  time: string;
  timeLabel: string;
  points: string[];
  tone: "cut" | "accent";
}) {
  const isCut = tone === "cut";
  const Icon = isCut ? XCircle : CheckSeal;
  const accent = isCut ? "var(--color-cut)" : "var(--color-accent-bright)";
  const surface = isCut
    ? "bg-white/[0.02] ring-white/[0.07]"
    : "bg-[var(--color-accent)]/[0.06] ring-[var(--color-accent)]/25";
  return (
    <div className={`relative h-full rounded-2xl p-7 ring-1 sm:p-8 ${surface}`}>
      <p
        className="text-[13px] font-semibold uppercase tracking-[0.25em]"
        style={{ color: isCut ? "var(--color-dim)" : accent }}
      >
        {eyebrow}
      </p>

      <div className="mt-5 flex items-baseline gap-2">
        <span
          className="text-[44px] font-semibold tracking-tight tabular-nums sm:text-[56px]"
          style={{ color: isCut ? "var(--color-text)" : accent }}
        >
          {time}
        </span>
        <span className="inline-flex items-center gap-1.5 text-[13px] text-white/45">
          {isCut ? <Clock className="size-4" /> : <Bolt className="size-4" />}
          {timeLabel}
        </span>
      </div>

      <ul className="mt-7 flex flex-col gap-3.5">
        {points.map((p) => (
          <li key={p} className="flex items-start gap-3 text-[15px] leading-relaxed text-white/70">
            <Icon className="mt-0.5 size-[18px] shrink-0" style={{ color: accent }} />
            <span className={isCut ? "text-white/55" : "text-white/80"}>{p}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

export function BeforeAfter() {
  return (
    <section id="before-after" className="relative mx-auto max-w-6xl px-5 py-24 sm:py-32">
      <span
        className="orb left-1/2 top-1/3 size-[560px] -translate-x-1/2"
        style={{ background: "radial-gradient(circle, rgba(10,132,255,0.12), transparent 70%)" }}
      />

      <div className="relative z-10 mx-auto max-w-3xl text-center">
        <KineticText
          text="The edit used to be the worst part."
          className="text-[40px] font-semibold leading-[1.06] tracking-[-0.025em] sm:text-[60px]"
        />
        <Reveal delay={0.1}>
          <p className="mx-auto mt-6 max-w-xl text-[19px] leading-relaxed text-white/55">
            Same recording, two very different afternoons. Crisp does the pass you dread — before
            you’ve even opened an editor.
          </p>
        </Reveal>
      </div>

      <div className="relative z-10 mt-14 grid items-stretch gap-5 lg:grid-cols-2 lg:gap-6">
        <Reveal>
          <Column
            eyebrow="Without Crisp"
            time="~1 hr"
            timeLabel="of manual cutting"
            points={WITHOUT}
            tone="cut"
          />
        </Reveal>
        <Reveal delay={0.1}>
          <Column
            eyebrow="With Crisp"
            time="< 1 min"
            timeLabel="drop it in, done"
            points={WITH}
            tone="accent"
          />
        </Reveal>
      </div>
    </section>
  );
}
