import { Hero } from "../sections/Hero";
import { CutStory } from "../sections/CutStory";
import { Capabilities } from "../sections/Capabilities";
import { Stats } from "../sections/Stats";
import { BeforeAfter } from "../sections/BeforeAfter";
import { TheApp } from "../sections/TheApp";
import { Privacy } from "../sections/Privacy";
import { Download } from "../sections/Download";
import { Footer } from "../sections/Footer";
import { useSeo } from "../useSeo";

// The fixed <Nav/> is rendered by the router shell (outside the page-transition
// layer) so its `position: fixed` isn't trapped by the transition transform.
export function Home() {
  useSeo({
    title: "Crisp — Make your recordings crisp.",
    description:
      "A native macOS app that automatically removes long pauses and filler words from your screen recordings — audio and video together — for tight jump-cuts. 100% local. Your footage is never touched.",
    path: "/",
  });
  return (
    <>
      <main>
        <Hero />
        <CutStory />
        <Capabilities />
        <Stats />
        <BeforeAfter />
        <TheApp />
        <Privacy />
        <Download />
      </main>
      <Footer />
    </>
  );
}
