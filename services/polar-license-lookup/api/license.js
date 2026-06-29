// Polar license-key lookup — maps a checkout_id to its license key so the Crisp
// desktop app can finish a purchase automatically (crisp://activate?checkout_id=…).
//
// The Polar API token lives ONLY here (Vercel env var), never in the shipped app.
// The endpoint returns just the key string for a completed checkout. checkout_ids are
// unguessable, and a key is only returned for a finished purchase.
//
// Env vars (set in Vercel → Project → Settings → Environment Variables):
//   POLAR_TOKEN   — a Polar Organization Access Token (read access to checkouts +
//                   license keys)
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
    // 1) checkout → customer (and confirm it actually completed)
    const checkout = await getJSON(`${POLAR_API}/v1/checkouts/${encodeURIComponent(checkoutId)}`, auth);
    if (!checkout) return res.status(404).json({ error: "checkout not found" });
    const status = checkout.status;
    if (status && !["succeeded", "confirmed", "complete"].includes(status)) {
      return res.status(409).json({ error: `checkout not complete (${status})` });
    }
    const customerId = checkout.customer_id || (checkout.customer && checkout.customer.id);
    if (!customerId) return res.status(404).json({ error: "no customer on checkout" });

    // 2) that customer's license key for this org
    const list = await getJSON(
      `${POLAR_API}/v1/license-keys?organization_id=${encodeURIComponent(org)}` +
        `&customer_id=${encodeURIComponent(customerId)}`,
      auth
    );
    const item = list && list.items && list.items[0];
    if (!item || !item.id) return res.status(404).json({ error: "no license key for customer" });

    // 3) full key (list endpoints return a masked/display key)
    const lk = await getJSON(`${POLAR_API}/v1/license-keys/${encodeURIComponent(item.id)}`, auth);
    if (!lk || !lk.key) return res.status(404).json({ error: "key unavailable" });

    return res.status(200).json({ key: lk.key });
  } catch (err) {
    return res.status(502).json({ error: "lookup failed" });
  }
}

async function getJSON(url, opts) {
  const r = await fetch(url, opts);
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`${url} -> ${r.status}`);
  return r.json();
}
