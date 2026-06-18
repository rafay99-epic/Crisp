import { AppIcon } from "../components/Logo";
import { Apple } from "../components/Icons";
import { RELEASES, REPO, REQUIREMENTS } from "../site";

export function Download() {
  return (
    <section className="bg-[var(--color-fog)] py-24 sm:py-32">
      <div className="reveal mx-auto max-w-2xl px-5 text-center">
        <AppIcon className="mx-auto size-24 drop-shadow-xl" />
        <h2 className="mt-7 text-[34px] font-bold tracking-tight sm:text-[46px]">
          Get Crisp.
        </h2>
        <p className="mt-4 text-[18px] leading-relaxed text-[var(--color-ink-soft)]">
          Free and open source. Download the latest release, drag it to Applications, and
          clean up your first recording in seconds.
        </p>

        <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <a
            href={RELEASES}
            className="flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-7 py-3.5 text-[16px] font-medium text-white shadow-sm transition-colors hover:bg-[var(--color-accent-hover)]"
          >
            <Apple className="size-[18px]" />
            Download for Mac
          </a>
          <a
            href={REPO}
            className="rounded-full px-6 py-3.5 text-[16px] font-medium text-[var(--color-accent)] transition-colors hover:underline"
          >
            View on GitHub
          </a>
        </div>
        <p className="mt-4 text-[13px] text-[var(--color-ink-soft)]">{REQUIREMENTS}</p>

        <p className="mx-auto mt-10 max-w-md text-[13px] leading-relaxed text-[var(--color-ink-soft)]">
          Ships in three channels that install side by side — Stable for everyday use and
          Nightly for the newest builds. Prefer to build it yourself? Clone the repo and run{" "}
          <code className="rounded bg-black/[0.05] px-1.5 py-0.5 font-mono text-[12px]">./dev.sh</code>.
        </p>
      </div>
    </section>
  );
}
