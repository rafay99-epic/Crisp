import { useEffect } from "react";
import { Routes, Route, useLocation } from "react-router-dom";
import { ReactLenis, useLenis } from "lenis/react";
import { Home } from "./pages/Home";
import { LegalPage } from "./pages/LegalPage";
import { privacyDoc, termsDoc } from "./content/legal";

/** Jump to the top on route change (Lenis-aware). */
function ScrollToTop() {
  const { pathname } = useLocation();
  const lenis = useLenis();
  useEffect(() => {
    if (lenis) lenis.scrollTo(0, { immediate: true });
    else window.scrollTo(0, 0);
  }, [pathname, lenis]);
  return null;
}

export function App() {
  return (
    <ReactLenis root options={{ lerp: 0.1, smoothWheel: true, anchors: true }}>
      <div className="grain">
        <ScrollToTop />
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/privacy" element={<LegalPage doc={privacyDoc} />} />
          <Route path="/terms" element={<LegalPage doc={termsDoc} />} />
          <Route path="*" element={<Home />} />
        </Routes>
      </div>
    </ReactLenis>
  );
}
