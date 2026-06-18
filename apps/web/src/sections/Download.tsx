import { AppIcon } from "../components/Logo";
import { CopyCommand } from "../components/AppBits";
import { Apple } from "../components/Icons";
import { RELEASES, REPO, REQUIREMENTS, BREW_INSTALL } from "../site";

export function Download() {
  return (
    <section id="download" className="bg-[var(--color-fog)] py-28 sm:py-36">
      <div className="reveal mx-auto max-w-2xl px-5 text-center">
        <AppIcon className="mx-auto size-28 drop-shadow-xl" />
        <h2 className="mt-8 text-[40px] font-semibold leading-[1.07] tracking-[-0.02em] sm:text-[56px]">
          Get Crisp.
        </h2>
        <p className="mt-5 text-[19px] leading-relaxed text-[var(--color-ink-soft)]">
          Free and open source. Install with Homebrew and it stays up to date, or grab the
          DMG directly.
        </p>

        {/* Homebrew — the recommended path */}
        <div className="mx-auto mt-9 max-w-md text-left">
          <p className="mb-2 text-center text-[13px] font-medium text-[var(--color-ink-soft)]">
            Install with Homebrew
          </p>
          <CopyCommand command={BREW_INSTALL} />
        </div>

        <div className="mt-6 flex items-center gap-4 text-[13px] text-[var(--color-ink-soft)]">
          <span className="h-px flex-1 bg-black/[0.08]" />
          or
          <span className="h-px flex-1 bg-black/[0.08]" />
        </div>

        <div className="mt-6 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <a
            href={RELEASES}
            className="flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-7 py-3.5 text-[17px] font-medium text-white shadow-sm transition-colors hover:bg-[var(--color-accent-hover)]"
          >
            <Apple className="size-[19px]" />
            Download the DMG
          </a>
          <a
            href={REPO}
            className="rounded-full px-6 py-3.5 text-[17px] font-medium text-[var(--color-accent)] transition-colors hover:underline"
          >
            View on GitHub ›
          </a>
        </div>
        <p className="mt-5 text-[13px] text-[var(--color-ink-soft)]">{REQUIREMENTS}</p>

        <p className="mx-auto mt-12 max-w-md text-[14px] leading-relaxed text-[var(--color-ink-soft)]">
          Want the newest builds? Install the Nightly channel side by side with{" "}
          <code className="rounded bg-black/[0.05] px-1.5 py-0.5 font-mono text-[12px]">
            brew install --cask rafay99-epic/apps/crisp-nightly
          </code>
          . Or build it yourself — clone the repo and run{" "}
          <code className="rounded bg-black/[0.05] px-1.5 py-0.5 font-mono text-[12px]">./dev.sh</code>.
        </p>
      </div>
    </section>
  );
}
