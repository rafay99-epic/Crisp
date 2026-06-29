// Polar license-key lookup — maps a checkout_id to its license key so the Crisp
// desktop app can finish a purchase automatically (crisp://activate?checkout_id=…).
//
// The Polar API token lives ONLY here (Vercel env var), never in the shipped app.
// Returns just the key string for a completed checkout.
//
// Env vars (Vercel → Project → Settings → Environment Variables):
//   POLAR_TOKEN   — Polar Organization Access Token with `checkouts:read` AND
//                   `license_keys:read`.
//   POLAR_ORG_ID  — your Polar organization id (ae6a2275-…)

const POLAR_API = "https://api.polar.sh";

export default async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");

  const checkoutId = String(req.query.checkout_id || "").trim();
  if (!checkoutId) return res.status(400).json({ error: "missing checkout_id" });

  const token = process.env.POLAR_TOKEN;
  const org = process.env.POLAR_ORG_ID;
  if (!token || !org) return res.status(500).json({ error: "server not configured" });

  const auth = { headers: { Authorization: `Bearer ${token}` } };

  try {
    // 1) checkout → customer. Polar identifies a checkout two ways: the client_secret
    //    (`polar_c_…`, in the confirmation URL) via a PUBLIC endpoint needing no auth,
    //    and the checkout id (UUID) via an authed endpoint (needs checkouts:read).
    //    Support both so it works whatever the deep link's {CHECKOUT_ID} carries.
    const coRes = checkoutId.startsWith("polar_c_")
      ? await fetch(`${POLAR_API}/v1/checkouts/client/${encodeURIComponent(checkoutId)}`)
      : await fetch(`${POLAR_API}/v1/checkouts/${encodeURIComponent(checkoutId)}`, auth);
    if (!coRes.ok) {
      return res.status(coRes.status === 404 ? 404 : 502)
        .json({ error: "checkout lookup failed", step: "checkout", status: coRes.status });
    }
    const checkout = await coRes.json();
    const status = checkout.status;
    if (status && !["succeeded", "confirmed", "complete"].includes(status)) {
      return res.status(409).json({ error: "checkout not complete", status });
    }
    const customerId = checkout.customer_id || (checkout.customer && checkout.customer.id);
    if (!customerId) return res.status(404).json({ error: "no customer on checkout" });

    // 2) that customer's granted license key — the list response includes the full key,
    //    so no extra per-key fetch is needed (needs license_keys:read).
    const lkRes = await fetch(
      `${POLAR_API}/v1/license-keys/?organization_id=${encodeURIComponent(org)}` +
        `&customer_id=${encodeURIComponent(customerId)}`,
      auth
    );
    if (!lkRes.ok) {
      return res.status(502).json({ error: "license lookup failed", step: "license_keys", status: lkRes.status });
    }
    const list = await lkRes.json();
    const items = (list && list.items) || [];
    const item = items.find((k) => k.status === "granted") || items[0];
    if (!item || !item.key) return res.status(404).json({ error: "no license key for customer" });

    return res.status(200).json({ key: item.key });
  } catch {
    // Don't echo raw error text back to the client.
    return res.status(502).json({ error: "lookup failed" });
  }
}
