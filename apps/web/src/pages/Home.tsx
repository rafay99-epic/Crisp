import { Nav } from "../sections/Nav";
import { Hero } from "../sections/Hero";
import { CutStory } from "../sections/CutStory";
import { Capabilities } from "../sections/Capabilities";
import { Stats } from "../sections/Stats";
import { TheApp } from "../sections/TheApp";
import { Privacy } from "../sections/Privacy";
import { Download } from "../sections/Download";
import { Footer } from "../sections/Footer";

export function Home() {
  return (
    <>
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
    </>
  );
}
