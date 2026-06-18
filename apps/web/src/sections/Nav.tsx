import { Waveform } from "../components/Logo";
import { RELEASES } from "../site";

const LINKS = [
  ["Features", "#features"],
  ["How it works", "#how"],
  ["Privacy", "#privacy"],
];

export function Nav() {
  return (
    <header className="sticky top-0 z-50 border-b border-black/[0.06] bg-white/70 backdrop-blur-xl backdrop-saturate-150">
      <nav className="mx-auto flex h-12 max-w-5xl items-center justify-between px-5">
        <a href="#top" className="flex items-center gap-2 font-semibold tracking-tight">
          <Waveform className="size-[18px]" />
          Crisp
        </a>
        <div className="hidden items-center gap-7 text-[13px] text-[var(--color-ink-soft)] sm:flex">
          {LINKS.map(([label, href]) => (
            <a key={href} href={href} className="transition-colors hover:text-[var(--color-ink)]">
              {label}
            </a>
          ))}
        </div>
        <a
          href={RELEASES}
          className="rounded-full bg-[var(--color-accent)] px-3.5 py-1.5 text-[13px] font-medium text-white transition-colors hover:bg-[var(--color-accent-hover)]"
        >
          Download
        </a>
      </nav>
    </header>
  );
}
