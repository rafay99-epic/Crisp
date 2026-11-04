import { useEffect } from "react";
import { SITE_URL, OG_IMAGE } from "./site";

/**
 * Per-route SEO for a client-rendered SPA. Updates the document title and the
 * social/canonical meta tags in place (reusing the static tags in index.html,
 * creating canonical/og:url when absent) so Google — which renders JS — sees
 * the right head on every route. Social scrapers that don't run JS still get the
 * homepage card baked into index.html.
 */
type Seo = { title: string; description: string; path: string; image?: string };

function tag(selector: string, create: () => HTMLElement): HTMLElement {
  let el = document.head.querySelector<HTMLElement>(selector);
  if (!el) {
    el = create();
    document.head.appendChild(el);
  }
  return el;
}

function meta(kind: "name" | "property", key: string, content: string) {
  const el = tag(`meta[${kind}="${key}"]`, () => {
    const m = document.createElement("meta");
    m.setAttribute(kind, key);
    return m;
  });
  el.setAttribute("content", content);
}

export function useSeo({ title, description, path, image = OG_IMAGE }: Seo) {
  useEffect(() => {
    const url = SITE_URL + path;
    document.title = title;
    meta("name", "description", description);
    meta("property", "og:title", title);
    meta("property", "og:description", description);
    meta("property", "og:url", url);
    meta("property", "og:image", image);
    meta("name", "twitter:title", title);
    meta("name", "twitter:description", description);
    meta("name", "twitter:image", image);

    const canonical = tag('link[rel="canonical"]', () => {
      const l = document.createElement("link");
      l.setAttribute("rel", "canonical");
      return l;
    }) as HTMLLinkElement;
    canonical.setAttribute("href", url);
  }, [title, description, path, image]);
}
