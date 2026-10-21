# Sharing apps with other people, and a "poor man's app store"

Status: decided 2026-10-21 (Molly took all defaults); built locally as Worker 0.2.0 / contract 1.1.0, not deployed.
Map entries: I-0002, D-0007 / D-0008 / D-0009 in `docs/ai-notes/PLAN.md`.

## Question
How can Molly share one of her apps with someone else, so that the other person has to present a
token before they can download it? And should the gateway grow into a small private app store?

## Findings (how it works today)
- `worker/src/index.ts` checks one shared secret, `APP_UPDATER_TOKEN` (D-0002), on
  `GET /api/v1/update/:appId`, then hands out a 15-minute HMAC-signed `/api/v1/download` link.
- Giving that token to a friend gives them **every** app, forever, and the only way to take it
  back is to rotate the token on every one of Molly's own devices.
- A new person has no app installed yet, so they can't use the in-app Settings token field to get
  the first APK. Today the bootstrap is Google Drive (`G:\My Drive\AFL.APK`), which is Molly-only.
- There is no list of apps: the Worker only knows an app when asked for its exact `appId`.
- Good news: the SDKs don't care whose token it is. If the Worker accepted per-person tokens, a
  friend could paste theirs into the same Settings field and get updates with **no SDK change**.

## Options
1. **Hand out the shared token.** Zero work. No per-app limit, no revoke, leaks Molly's whole set.
   Not recommended.
2. **Per-person access grants (recommended core).** Each person gets their own random token,
   limited to a list of apps, with an optional expiry. Worker accepts the master token *or* a
   valid grant.
3. **Grants + a small web store page served by the Worker (recommended, = the "poor man's app
   store").** Adds a catalog endpoint and one HTML page where the person enters their token, sees
   only the apps they were given, downloads the APK and copies the token for the app's Settings.
4. **A native "Store" Android app** that lists and installs/updates all granted apps. Nicest UX,
   but it's a 9th app to build and maintain, and option 3's page is still needed to install the
   store itself. Park as a later idea.

## Recommendation: option 3, in three small steps

### Step A - Access grants (Worker 0.1.0 -> 0.2.0)
- Grant record in the existing R2 bucket at `_grants/<sha256(token)>.json` (no new binding;
  only the hash is stored, so a bucket leak doesn't expose tokens):
  ```json
  { "name": "Sam", "apps": ["com.hawkspod.tennisspark_app"], "expires": "2027-04-21T00:00:00Z",
    "revoked": false, "created": "2026-10-21T00:00:00Z", "note": "tennis club" }
  ```
  `apps: ["*"]` = everything (how Molly's own devices could eventually move off the master token).
- `/api/v1/update/:appId`: master token -> as today. Otherwise hash the token, read the grant,
  return **404 "App manifest not found"** (same as an unknown app, so a grant can't probe which
  other apps exist) unless the grant is live and lists the app.
- The signed download URL stays as is; it is already short-lived and app-specific.
- Tokens are prefixed (`aug_` + 32 random bytes, base64url) so they are easy to recognise and
  can't be confused with the master token.

### Step B - Grant management script
`scripts/grant-access.ps1` (ASCII-only, like the other scripts):
- `-Name Sam -Apps com.a,com.b [-Days 180]` -> makes a token, uploads the hash record with
  Wrangler, prints the token and an invite link **once** (never written to disk or notes).
- `-Revoke -Name Sam` (sets `revoked: true`), `-List` (names, apps, expiry; no tokens).
- Later: a signed Switchboard action (`grant_app_access`, high risk) like `publish_apk`.

### Step C - Catalog + store page (contract app-updater/1 1.0.0 -> 1.1.0, additive)
- New optional manifest fields, written by `publish-release.ps1`: `title`, `summary` (one line),
  `iconKey` (PNG in R2), `shareable` (default `false`: an app is never listed to grants unless
  Molly opts it in, even if a grant names it). Old manifests stay valid.
- `GET /api/v1/catalog` (Bearer) -> the apps the token may see: `appId`, `title`, `summary`,
  `versionName`, `versionCode`, `releaseDate`, `fileSize`, `sha256`, signed `downloadUrl`.
  Built from `RELEASES_BUCKET.list()` on `<appId>/version.json`; ~10 apps, so no cache needed.
- `GET /` (or `/store`) -> one static HTML page, inlined in the Worker (no framework):
  - Invite link `https://<gateway>/store#t=<token>`: the token sits in the URL **fragment**, so it
    is never sent to the server, logged, or kept in proxies; the page reads it, then clears the
    address bar. Otherwise there is a paste box.
  - Shows each app with version, size, notes, a **Download** button and a **Copy token** button
    plus three plain steps: allow "Install unknown apps" for the browser, install, open the app >
    Settings (gear) > paste the token. From then on the app updates itself as today.
  - Token kept in `localStorage` only if the person ticks "remember on this device".
  - Light/dark colours with checked 4.5:1 contrast (project rule).

### What the person being shared to does
1. Molly runs `grant-access.ps1 -Name Sam -Apps com.hawkspod.tennisspark_app` and sends Sam the
   invite link over Signal/WhatsApp.
2. Sam opens it on their phone, taps Download, installs, opens the app, pastes the token in
   Settings. Done; launch checks and ntfy-free updates work from then on.
3. Molly can revoke Sam at any time without touching anyone else.

## Things to be aware of
- **Signing:** friends must trust Molly's keystore; Play Protect will warn on first install.
  Never change the keystore for a shared app, or updates fail to install.
- **App IDs:** `com.example.afl_flutter_app` still uses `com.example`; fine privately, worth
  renaming before sharing (a rename = a new app for Android).
- **ntfy:** the release push goes to Molly's topic only. Friends just get the on-launch check
  (D-0003 is unchanged). A per-app public ntfy topic could come later.
- **Costs:** a grant check is one extra R2 read per update check: negligible.
- **Abuse:** one leaked friend token only exposes that friend's apps until revoked. Optional
  later: record `lastSeen` per grant (one R2 write per check; maybe only once a day).
- **The gateway URL** becomes something friends see. If that matters, put the Worker on a
  custom domain first (Switchboard already defaults to `https://updater.mollyfud.com`, which
  differs from the live `workers.dev` URL - see HANDOFF 2026-10-20).
- **D-0002** (single shared token) changes to "master token for Molly + per-person grants".

## Needs Molly's call
- D-0007: Build sharing? Options: grants + store page (A+B+C) / grants only (A+B, send the APK by
  hand) / not now. Default: grants + store page.
- D-0008: Where to keep grants? Options: R2 `_grants/` prefix / a new Workers KV namespace.
  Default: R2 (no new binding, consistent with releases).
- D-0009: Should Molly's own devices move from the master token to an `apps: ["*"]` grant?
  Options: keep master token / move later. Default: keep the master token for now.

## Decision
2026-10-21 Molly: take the defaults - D-0007 grants + store page (A+B+C), D-0008 grants in R2
`_grants/`, D-0009 keep the master (owner) token on her own devices.

### Built differently from the proposal above (and why)
- **Listing is its own file** (`<appId>/listing.json`, `scripts/set-listing.ps1`) instead of new
  manifest fields: `publish-release.ps1` rewrites `version.json` on every publish and would wipe
  them. The manifest schema is unchanged.
- **Grants are made through a Worker admin API** (`/api/v1/admin/*`) behind a new, separate secret
  `APP_UPDATER_ADMIN_TOKEN`, not by Wrangler uploads: Wrangler can't list R2 objects (needed for
  -List/-Revoke), and a token leaked from a phone must not be able to mint grants.
- **No icons yet** (would need another public or signed endpoint); the catalog carries no download
  links - the store page asks `/update/:appId` for a fresh signed link on each tap.
- Exact API: `contracts/README.md` section 4.

## Follow-ups
- Native "Store" Android app (option 4), once the catalog endpoint exists.
- Switchboard action for grants; Switchboard Projects page could show who has access to what.
- Windows `.zip` artifacts (I-0001) would appear in the same catalog for free.
