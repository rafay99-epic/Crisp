import { Waveform, Sparkles, Layers, Lock, CheckSeal, Gauge } from "../components/Icons";
import type { SVGProps } from "react";

type Feature = {
  Icon: (p: SVGProps<SVGSVGElement>) => React.JSX.Element;
  title: string;
  body: string;
};

const FEATURES: Feature[] = [
  {
    Icon: Waveform,
    title: "Long pauses, gone",
    body: "Crisp reads the real audio energy to find dead air and thinking gaps, then cuts them — far more accurate than guessing from the transcript.",
  },
  {
    Icon: Sparkles,
    title: "Filler words, gone",
    body: "An on-device speech model timestamps every “um,” “uh,” “hmm,” and “erm,” and Crisp snips each one out at the frame.",
  },
  {
    Icon: Layers,
    title: "Audio &amp; video, locked",
    body: "Every cut moves the picture and the sound together, so lips stay in sync and the result reads as one clean jump-cut.",
  },
  {
    Icon: Lock,
    title: "100% on your Mac",
    body: "Nothing is ever uploaded. Detection, transcription, and rendering all run locally — your footage never leaves the machine.",
  },
  {
    Icon: CheckSeal,
    title: "Your footage is safe",
    body: "Crisp only ever writes a new cleaned file and backs up the original first. It never overwrites or deletes your source.",
  },
  {
    Icon: Gauge,
    title: "No quality loss",
    body: "Same resolution, same frame rate, high-quality H.264/HEVC — hardware-accelerated on Apple Silicon. Tight, never downscaled.",
  },
];

export function Features() {
  return (
    <section id="features" className="mx-auto max-w-5xl px-5 py-24 sm:py-32">
      <div className="reveal mx-auto max-w-2xl text-center">
        <h2 className="text-[34px] font-bold tracking-tight sm:text-[44px]">
          Tighter cuts, less busywork.
        </h2>
        <p className="mt-4 text-[18px] leading-relaxed text-[var(--color-ink-soft)]">
          The tedious first pass of every edit — done automatically, the moment you drop
          a file in.
        </p>
      </div>

      <div className="mt-16 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {FEATURES.map(({ Icon, title, body }, i) => (
          <div
            key={title}
            className="reveal rounded-2xl bg-[var(--color-fog)] p-7 ring-1 ring-black/[0.04]"
            style={{ transitionDelay: `${(i % 3) * 80}ms` }}
          >
            <span className="flex size-11 items-center justify-center rounded-xl bg-[var(--color-system-blue)]/10 text-[var(--color-system-blue)]">
              <Icon className="size-[22px]" />
            </span>
            <h3
              className="mt-5 text-[19px] font-semibold tracking-tight"
              dangerouslySetInnerHTML={{ __html: title }}
            />
            <p
              className="mt-2 text-[15px] leading-relaxed text-[var(--color-ink-soft)]"
              dangerouslySetInnerHTML={{ __html: body }}
            />
          </div>
        ))}
      </div>
    </section>
  );
}
