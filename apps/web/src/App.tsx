import { ReactLenis } from "lenis/react";
import { Nav } from "./sections/Nav";
import { Hero } from "./sections/Hero";
import { CutStory } from "./sections/CutStory";
import { Capabilities } from "./sections/Capabilities";
import { Stats } from "./sections/Stats";
import { TheApp } from "./sections/TheApp";
import { Privacy } from "./sections/Privacy";
import { Download } from "./sections/Download";
import { Footer } from "./sections/Footer";

export function App() {
  return (
    <ReactLenis root options={{ lerp: 0.1, smoothWheel: true, anchors: true }}>
      <div className="grain">
        <Nav />
        <main>
          <Hero />
          <CutStory />
          <Capabilities />
          <Stats />
          <TheApp />
          <Privacy />
          <Download />
        </main>
        <Footer />
      </div>
    </ReactLenis>
  );
}
