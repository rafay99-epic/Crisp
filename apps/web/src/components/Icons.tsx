/**
 * SF Symbol-flavoured inline icons (stroke, rounded joins, currentColor) so the
 * site reads as native macOS without shipping a font. Sized via className.
 */
import type { SVGProps } from "react";

type IconProps = SVGProps<SVGSVGElement>;

function Base({ children, ...props }: IconProps & { children: React.ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.6}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      {...props}
    >
      {children}
    </svg>
  );
}

export const Scissors = (p: IconProps) => (
  <Base {...p}>
    <circle cx="6" cy="6" r="2.6" />
    <circle cx="6" cy="18" r="2.6" />
    <path d="M8.2 7.6 20 18M20 6 8.2 16.4" />
  </Base>
);

export const Waveform = (p: IconProps) => (
  <Base {...p}>
    <path d="M3 12h1.5M7 8v8M10.5 4v16M14 7v10M17.5 9.5v5M21 12h-.5" />
  </Base>
);

export const Sparkles = (p: IconProps) => (
  <Base {...p}>
    <path d="M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6L12 3Z" />
    <path d="M18.5 14.5l.7 1.9 1.9.7-1.9.7-.7 1.9-.7-1.9-1.9-.7 1.9-.7.7-1.9Z" />
  </Base>
);

export const Lock = (p: IconProps) => (
  <Base {...p}>
    <rect x="5" y="10.5" width="14" height="9.5" rx="2.4" />
    <path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" />
    <circle cx="12" cy="15" r="1" />
  </Base>
);

export const Bolt = (p: IconProps) => (
  <Base {...p}>
    <path d="M13 3 5 13h6l-1 8 8-10h-6l1-8Z" />
  </Base>
);

export const Gauge = (p: IconProps) => (
  <Base {...p}>
    <path d="M4 17a8 8 0 1 1 16 0" />
    <path d="M12 17l4-5" />
    <circle cx="12" cy="17" r="1" />
  </Base>
);

export const Layers = (p: IconProps) => (
  <Base {...p}>
    <path d="M12 3 3 7.5l9 4.5 9-4.5L12 3Z" />
    <path d="M3 12.5 12 17l9-4.5M3 16.5 12 21l9-4.5" />
  </Base>
);

export const CheckSeal = (p: IconProps) => (
  <Base {...p}>
    <path d="M12 3.2 14 5l2.6-.4.9 2.5 2.3 1.3-.9 2.5.9 2.5-2.3 1.3-.9 2.5L14 19l-2 1.8L10 19l-2.6.4-.9-2.5L4.2 15.6l.9-2.5-.9-2.5 2.3-1.3.9-2.5L10 5l2-1.8Z" />
    <path d="m9 12 2 2 4-4" />
  </Base>
);

export const Gear = (p: IconProps) => (
  <Base {...p}>
    <circle cx="12" cy="12" r="3" />
    <path d="M12 2.5v3M12 18.5v3M21.5 12h-3M5.5 12h-3M18.7 5.3l-2.1 2.1M7.4 16.6l-2.1 2.1M18.7 18.7l-2.1-2.1M7.4 7.4 5.3 5.3" />
  </Base>
);

export const Apple = (p: IconProps) => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden {...p}>
    <path d="M16.5 12.4c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.8-.8-3-.8c-1.5 0-2.9.9-3.7 2.3-1.6 2.7-.4 6.8 1.1 9 .7 1.1 1.6 2.3 2.8 2.2 1.1 0 1.5-.7 2.9-.7s1.7.7 2.9.7 2-1 2.7-2.1c.9-1.2 1.2-2.4 1.2-2.5 0 0-2.3-.9-2.3-3.6Zm-2.3-6.6c.6-.8 1-1.8.9-2.9-.9 0-2 .6-2.6 1.4-.6.7-1.1 1.7-.9 2.8 1 0 2-.6 2.6-1.3Z" />
  </svg>
);

export const ArrowDown = (p: IconProps) => (
  <Base {...p}>
    <path d="M12 4v14M6 12l6 6 6-6" />
  </Base>
);

export const Folder = (p: IconProps) => (
  <Base {...p}>
    <path d="M3 7.5A2 2 0 0 1 5 5.5h3.2a2 2 0 0 1 1.4.6l1 1h9.4a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7.5Z" />
  </Base>
);
