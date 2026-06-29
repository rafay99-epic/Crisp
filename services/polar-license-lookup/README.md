# Polar license-key lookup

A one-endpoint serverless function that lets the Crisp desktop app **finish a purchase
automatically**. After checkout, Polar redirects to `crisp://activate?checkout_id=…`;
the app calls this function with that `checkout_id`, the function looks up the license
key using a server-side Polar token, and the app activates silently.

The Polar API token lives **only here** (a Vercel env var) — never in the shipped app.

## Deploy (Vercel)

1. From this folder: `vercel deploy --prod` (or import `services/polar-license-lookup`
   as a Vercel project — root directory = this folder).
2. Set two environment variables in **Vercel → Project → Settings → Environment Variables**:
   - `POLAR_TOKEN` — a Polar **Organization Access Token** (Polar → Settings →
     Developers / API tokens) with read access to checkouts + license keys.
   - `POLAR_ORG_ID` — `ae6a2275-d1b4-4449-8760-29d6d19e2e68`.
3. Note the deployed URL, e.g. `https://crisp-license.vercel.app/api/license`.

## Wire it up

- **In the app:** the deployed `/api/license` URL is not hardcoded — it's injected at
  build time. Set the **`CRISP_POLAR_LOOKUP_URL`** environment variable (in the
  gitignored `apps/desktop/.polar.env` for local dev builds, or as a GitHub Actions
  secret for release builds); `apps/desktop/build.sh` writes it into the app's
  Info.plist as **`CrispPolarLookupURL`**, which `PolarConfig.licenseLookupURL` reads at
  runtime. (Same pattern for `CRISP_POLAR_ORG_ID` / `CHECKOUT_URL` / `PORTAL_URL`.)
- **In Polar:** set the **checkout link's Success URL** to
  `crisp://activate?checkout_id={CHECKOUT_ID}`.

## Test

`curl "https://<your-deployment>/api/license?checkout_id=<a-real-checkout-id>"`
→ `{ "key": "CRISP-…" }`

## Security notes

- Returns only the key string, and only for a **completed** checkout.
- `checkout_id`s are unguessable random ids.
- No key is exposed unless the caller already holds a valid checkout id from a real
  purchase redirect.
