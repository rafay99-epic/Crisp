import { StrengthControl, FillerTranscript, SilenceVisual } from "../components/AppBits";
import { ResultPanel } from "../components/AppWindow";

function Tile({
  className = "",
  title,
  body,
  children,
}: {
  className?: string;
  title: string;
  body: string;
  children?: React.ReactNode;
}) {
  return (
    <div
      className={`reveal flex flex-col gap-5 rounded-[28px] bg-[var(--color-fog)] p-8 ring-1 ring-black/[0.05] ${className}`}
    >
      <div>
        <h3 className="text-[24px] font-semibold tracking-tight">{title}</h3>
        <p className="mt-2 text-[16px] leading-relaxed text-[var(--color-ink-soft)]">{body}</p>
      </div>
      {children && <div className="mt-auto">{children}</div>}
    </div>
  );
}

export function Features() {
  return (
    <section id="features" className="mx-auto max-w-6xl px-5 py-28 sm:py-36">
      <div className="reveal mx-auto max-w-3xl text-center">
        <h2 className="text-[40px] font-semibold leading-[1.07] tracking-[-0.02em] sm:text-[56px]">
          The tedious first pass,
          <br className="hidden sm:block" /> done automatically.
        </h2>
        <p className="mx-auto mt-5 max-w-xl text-[19px] leading-relaxed text-[var(--color-ink-soft)]">
          Drop a recording in and Crisp does the cutting nobody wants to do — accurately,
          and without ever touching your original.
        </p>
      </div>

      <div className="mt-16 grid gap-5 lg:grid-cols-6">
        <Tile
          className="lg:col-span-4"
          title="Long pauses, gone."
          body="Crisp reads the real audio energy to find dead air and thinking gaps, then cuts them — far more accurate than guessing from a transcript."
        >
          <SilenceVisual />
        </Tile>

        <Tile
          className="lg:col-span-2"
          title="Filler words, gone."
          body="An on-device model timestamps every “um,” “uh,” and “hmm,” and snips each one out at the frame."
        >
          <FillerTranscript />
        </Tile>

        <Tile
          className="lg:col-span-3"
          title="Cut as much as you like."
          body="Gentle to very aggressive — or dial in your own thresholds. Recommended settings are one tap away."
        >
          <StrengthControl />
        </Tile>

        <Tile
          className="lg:col-span-3"
          title="Tighter in seconds."
          body="Audio and video stay locked together, so every cut reads as one clean jump-cut. Then you get the numbers."
        >
          <ResultPanel />
        </Tile>

        <Tile
          className="lg:col-span-3"
          title="Your footage is safe."
          body="Crisp only ever writes a new cleaned file, and backs up the original first. It never overwrites or deletes your source — by design."
        />

        <Tile
          className="lg:col-span-3"
          title="No quality loss."
          body="Same resolution, same frame rate, hardware-accelerated on Apple Silicon. Tight, never downscaled."
        >
          <div className="flex flex-wrap gap-2">
            {["Same resolution", "Same fps", "H.264 · HEVC", "Hardware-accelerated"].map((c) => (
              <span
                key={c}
                className="rounded-full bg-white px-3.5 py-1.5 text-[13px] font-medium text-[var(--color-ink-soft)] ring-1 ring-black/[0.06]"
              >
                {c}
              </span>
            ))}
          </div>
        </Tile>
      </div>
    </section>
  );
}
