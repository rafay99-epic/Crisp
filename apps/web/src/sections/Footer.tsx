import { Link } from "@tanstack/react-router";
import { Waveform } from "../components/Logo";
import { REPO, AUTHOR, AUTHOR_URL } from "../site";

export function Footer() {
  return (
    <footer className="border-t border-white/[0.07] py-12">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-6 px-5 text-[13px] text-white/45 sm:flex-row">
        <div className="flex items-center gap-2">
          <Waveform className="size-4" />
          <span className="font-semibold text-white">Crisp</span>
          <span className="text-white/40">— make your recordings crisp.</span>
        </div>
        <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2">
          <Link to="/pricing" className="transition-colors hover:text-white">
            Pricing
          </Link>
          <Link to="/privacy" className="transition-colors hover:text-white">
            Privacy
          </Link>
          <Link to="/terms" className="transition-colors hover:text-white">
            Terms
          </Link>
          <a href={REPO} className="transition-colors hover:text-white">
            GitHub
          </a>
          <a href={`${REPO}/blob/main/LICENSE`} className="transition-colors hover:text-white">
            GPL-3.0
          </a>
          <a href={AUTHOR_URL} className="transition-colors hover:text-white">
            {AUTHOR}
          </a>
        </div>
      </div>
      <p className="mt-7 text-center text-[12px] text-white/30">
        © {new Date().getFullYear()} {AUTHOR} · Abdul Rafay
      </p>
    </footer>
  );
}
