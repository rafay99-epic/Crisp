import { useEffect } from "react";
import {
  createRootRoute,
  createRoute,
  createRouter,
  Outlet,
  useRouterState,
} from "@tanstack/react-router";
import { AnimatePresence, motion } from "framer-motion";
import { ReactLenis, useLenis } from "lenis/react";
import { Nav } from "./sections/Nav";
import { Home } from "./pages/Home";
import { Pricing } from "./pages/Pricing";
import { Features } from "./pages/Features";
import { LegalPage } from "./pages/LegalPage";
import { privacyDoc, termsDoc } from "./content/legal";

const EASE = [0.16, 1, 0.3, 1] as const;

/** Lives inside ReactLenis so useLenis() resolves; runs the page swipe + scroll reset. */
function Shell() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const lenis = useLenis();

  useEffect(() => {
    if (lenis) lenis.scrollTo(0, { immediate: true });
    else window.scrollTo(0, 0);
  }, [pathname, lenis]);

  return (
    <div className="grain">
      {/* The fixed nav lives OUTSIDE the animated layer so the page transform
          never turns it into its containing block (which would break `fixed`). */}
      {pathname === "/" && <Nav />}
      <AnimatePresence mode="wait" initial={false}>
        <motion.div
          key={pathname}
          initial={{ opacity: 0, x: 64 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -64 }}
          transition={{ duration: 0.5, ease: EASE }}
        >
          <Outlet />
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

function RootLayout() {
  return (
    <ReactLenis root options={{ lerp: 0.1, smoothWheel: true, anchors: true }}>
      <Shell />
    </ReactLenis>
  );
}

const rootRoute = createRootRoute({ component: RootLayout });

const indexRoute = createRoute({ getParentRoute: () => rootRoute, path: "/", component: Home });
const pricingRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/pricing",
  component: Pricing,
});
const featuresRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/features",
  component: Features,
});
const privacyRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/privacy",
  component: () => <LegalPage doc={privacyDoc} />,
});
const termsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/terms",
  component: () => <LegalPage doc={termsDoc} />,
});

const routeTree = rootRoute.addChildren([
  indexRoute,
  pricingRoute,
  featuresRoute,
  privacyRoute,
  termsRoute,
]);

export const router = createRouter({
  routeTree,
  defaultPreload: "intent",
  scrollRestoration: false, // Lenis + our own reset handle this
  defaultNotFoundComponent: Home,
});

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
