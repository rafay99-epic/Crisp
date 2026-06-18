import { Hero } from "../sections/Hero";
import { CutStory } from "../sections/CutStory";
import { Capabilities } from "../sections/Capabilities";
import { Stats } from "../sections/Stats";
import { TheApp } from "../sections/TheApp";
import { Privacy } from "../sections/Privacy";
import { Download } from "../sections/Download";
import { Footer } from "../sections/Footer";

// The fixed <Nav/> is rendered by the router shell (outside the page-transition
// layer) so its `position: fixed` isn't trapped by the transition transform.
export function Home() {
  return (
    <>
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
    </>
  );
}
