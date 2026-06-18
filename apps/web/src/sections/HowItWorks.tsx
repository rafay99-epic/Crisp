import { ResultPanel } from "../components/AppWindow";

const STEPS = [
  {
    n: "1",
    title: "Drop your video in",
    body: "Drag a recording onto the window — or pick several at once. MP4, MOV, MKV; whatever you recorded.",
  },
  {
    n: "2",
    title: "Pauses & fillers are found",
    body: "ffmpeg finds silence from the real audio energy; whisper.cpp timestamps every filler word. All on-device.",
  },
  {
    n: "3",
    title: "Cut together, re-rendered",
    body: "Crisp keeps only the good segments and joins them — audio and video as one — at full resolution and frame rate.",
  },
  {
    n: "4",
    title: "A new, crisp file",
    body: "You get <name>_cleaned next to the original, which was safely backed up first. Open it in Finder and you’re done.",
  },
];

/** A little before/after timeline: red = removed pauses/fillers, blue = kept. */
function Timeline() {
  const segs = [
    ["keep", 14],
    ["cut", 6],
    ["keep", 20],
    ["cut", 4],
    ["keep", 10],
    ["cut", 8],
    ["keep", 16],
    ["cut", 5],
    ["keep", 17],
  ] as const;
  return (
    <div className="rounded-2xl bg-[var(--color-app-bg)] p-5">
      <div className="mb-3 flex items-center justify-between text-[12px] text-white/50">
        <span>Original — 8:30</span>
        <span className="flex items-center gap-3">
          <span className="flex items-center gap-1.5">
            <span className="size-2 rounded-full bg-[#ff5f57]" /> removed
          </span>
          <span className="flex items-center gap-1.5">
            <span className="size-2 rounded-full bg-[var(--color-system-blue)]" /> kept
          </span>
        </span>
      </div>
      <div className="flex h-3 gap-[2px] overflow-hidden rounded-full">
        {segs.map(([kind, w], i) => (
          <span
            key={i}
            style={{ flexGrow: w }}
            className={kind === "cut" ? "bg-[#ff5f57]/70" : "bg-[var(--color-system-blue)]"}
          />
        ))}
      </div>
      <div className="mt-3 flex h-3 gap-[2px] overflow-hidden rounded-full">
        {segs
          .filter(([k]) => k === "keep")
          .map(([, w], i) => (
            <span key={i} style={{ flexGrow: w }} className="bg-[var(--color-system-blue)]" />
          ))}
      </div>
      <p className="mt-3 text-[12px] text-white/50">Cleaned — 7:06</p>
    </div>
  );
}

export function HowItWorks() {
  return (
    <section id="how" className="bg-[var(--color-fog)] py-24 sm:py-32">
      <div className="mx-auto max-w-5xl px-5">
        <div className="reveal mx-auto max-w-2xl text-center">
          <h2 className="text-[34px] font-bold tracking-tight sm:text-[44px]">
            Drop it in. Get it back tighter.
          </h2>
          <p className="mt-4 text-[18px] leading-relaxed text-[var(--color-ink-soft)]">
            Four steps, fully automatic — and your original is never touched.
          </p>
        </div>

        <div className="mt-16 grid items-start gap-12 lg:grid-cols-2">
          <ol className="flex flex-col gap-8">
            {STEPS.map((s) => (
              <li key={s.n} className="reveal flex gap-4">
                <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-[var(--color-system-blue)] text-[15px] font-semibold text-white">
                  {s.n}
                </span>
                <div>
                  <h3 className="text-[18px] font-semibold tracking-tight">{s.title}</h3>
                  <p
                    className="mt-1 text-[15px] leading-relaxed text-[var(--color-ink-soft)]"
                    dangerouslySetInnerHTML={{ __html: s.body }}
                  />
                </div>
              </li>
            ))}
          </ol>

          <div className="reveal flex flex-col gap-5">
            <Timeline />
            <ResultPanel />
          </div>
        </div>
      </div>
    </section>
  );
}
