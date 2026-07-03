/**
 * The Crisp brand mark — a blue waveform split by a vertical "cut" line, the
 * same motif as the macOS app icon (Scripts/MakeIcon.swift). Drawn as SVG so it
 * stays crisp at every size. Two forms:
 *   <AppIcon/>  — the full rounded-square dark icon (hero / download).
 *   <Waveform/> — just the bars, for the nav and inline use.
 */

// Symmetric spindle envelope: bars rise toward the centre cut, mirrored.
const HALF = [0.34, 0.52, 0.72, 0.92, 1, 0.82, 0.6, 0.44];
const BARS = [...HALF, ...[...HALF].reverse()];

function Bars({ color = "url(#crispBlue)" }: { color?: string }) {
  const n = BARS.length;
  const slot = 100 / (n + 2);
  const barW = slot * 0.62;
  const gapCenter = 50; // the cut runs down the middle
  return (
    <>
      {BARS.map((h, i) => {
        const cx = slot * (i + 1.5);
        // push the two halves apart to leave room for the cut line
        const shift = cx < gapCenter ? -2.4 : 2.4;
        const height = 22 + h * 60;
        const y = 50 - height / 2;
        return (
          <rect
            key={i}
            x={cx + shift - barW / 2}
            y={y}
            width={barW}
            height={height}
            rx={barW / 2}
            fill={color}
          />
        );
      })}
    </>
  );
}

export function AppIcon({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 100 100" className={className} aria-hidden>
      <defs>
        <linearGradient id="crispBlue" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#4aa6ff" />
          <stop offset="1" stopColor="#0a84ff" />
        </linearGradient>
        <linearGradient id="crispCase" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3a3a3c" />
          <stop offset="1" stopColor="#1c1c1e" />
        </linearGradient>
      </defs>
      <rect x="2" y="2" width="96" height="96" rx="23" fill="url(#crispCase)" />
      <rect
        x="2.5"
        y="2.5"
        width="95"
        height="95"
        rx="22.5"
        fill="none"
        stroke="#ffffff"
        strokeOpacity="0.08"
      />
      <Bars />
      {/* the cut: two faint vertical guide lines down the middle */}
      <line
        x1="47.6"
        y1="22"
        x2="47.6"
        y2="78"
        stroke="#ffffff"
        strokeOpacity="0.22"
        strokeWidth="0.7"
      />
      <line
        x1="52.4"
        y1="22"
        x2="52.4"
        y2="78"
        stroke="#ffffff"
        strokeOpacity="0.22"
        strokeWidth="0.7"
      />
    </svg>
  );
}

/** The "PRO" pill — pairs with the wordmark on Crisp Pro surfaces (pricing, banners). */
export function ProBadge({ className = "" }: { className?: string }) {
  return (
    <span
      className={`inline-flex items-center rounded-full bg-[var(--color-accent-bright)]/15 px-2 py-0.5 text-[10px] font-bold uppercase tracking-[0.14em] text-[var(--color-accent-bright)] ring-1 ring-inset ring-[var(--color-accent-bright)]/30 ${className}`}
    >
      Pro
    </span>
  );
}

export function Waveform({ className = "", color }: { className?: string; color?: string }) {
  return (
    <svg viewBox="0 0 100 100" className={className} aria-hidden>
      {!color && (
        <defs>
          <linearGradient id="crispBlueFlat" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#3a9bff" />
            <stop offset="1" stopColor="#007aff" />
          </linearGradient>
        </defs>
      )}
      <Bars color={color ?? "url(#crispBlueFlat)"} />
    </svg>
  );
}
