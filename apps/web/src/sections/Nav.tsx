import { useState } from "react";
import { Link } from "@tanstack/react-router";
import { motion, useScroll, useMotionValueEvent } from "framer-motion";
import { Waveform } from "../components/Logo";
import { Magnetic } from "../components/Motion";

const LINKS = [
  ["Overview", "#cut"],
  ["Features", "#features"],
  ["Privacy", "#privacy"],
];

export function Nav() {
  const { scrollY } = useScroll();
  const [hidden, setHidden] = useState(false);
  const [solid, setSolid] = useState(false);

  useMotionValueEvent(scrollY, "change", (y) => {
    const prev = scrollY.getPrevious() ?? 0;
    setHidden(y > prev && y > 320);
    setSolid(y > 40);
  });

  return (
    <motion.header
      initial={{ y: 0 }}
      animate={{ y: hidden ? "-110%" : "0%" }}
      transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
      className={`fixed inset-x-0 top-0 z-50 transition-colors duration-300 ${
        solid ? "border-b border-white/[0.06] bg-black/55 backdrop-blur-xl" : ""
      }`}
    >
      <nav className="mx-auto flex h-14 max-w-6xl items-center justify-between px-5">
        <a href="#top" className="flex items-center gap-2 font-semibold tracking-tight text-white">
          <Waveform className="size-[18px]" />
          Crisp
        </a>
        <div className="hidden items-center gap-8 text-[13px] text-white/60 sm:flex">
          {LINKS.map(([label, href]) => (
            <a key={href} href={href} className="transition-colors hover:text-white">
              {label}
            </a>
          ))}
          <Link to="/pricing" className="text-[13px] text-white/60 transition-colors hover:text-white">
            Pricing
          </Link>
        </div>
        <Magnetic strength={0.5}>
          <a
            href="#download"
            className="rounded-full bg-white px-4 py-1.5 text-[13px] font-semibold text-black transition-transform hover:scale-[1.03]"
          >
            Install
          </a>
        </Magnetic>
      </nav>
    </motion.header>
  );
}
