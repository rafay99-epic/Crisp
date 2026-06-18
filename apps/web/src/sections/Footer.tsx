import { Waveform } from "../components/Logo";
import { REPO, AUTHOR, AUTHOR_URL } from "../site";

export function Footer() {
  return (
    <footer className="border-t border-black/[0.06] py-10">
      <div className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-5 px-5 text-[13px] text-[var(--color-ink-soft)] sm:flex-row">
        <div className="flex items-center gap-2">
          <Waveform className="size-4" />
          <span className="font-semibold text-[var(--color-ink)]">Crisp</span>
          <span>— make your recordings crisp.</span>
        </div>
        <div className="flex items-center gap-6">
          <a href={REPO} className="transition-colors hover:text-[var(--color-ink)]">
            GitHub
          </a>
          <a href={`${REPO}/blob/main/LICENSE`} className="transition-colors hover:text-[var(--color-ink)]">
            GPL-3.0
          </a>
          <a href={AUTHOR_URL} className="transition-colors hover:text-[var(--color-ink)]">
            {AUTHOR}
          </a>
        </div>
      </div>
      <p className="mt-6 text-center text-[12px] text-[var(--color-ink-soft)]">
        © {new Date().getFullYear()} {AUTHOR} · Abdul Rafay
      </p>
    </footer>
  );
}
