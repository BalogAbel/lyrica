# Invitation Deep Links via `lyron.pages.dev` App Links

- Status: Proposed
- Date: 2026-06-02
- Scope: Mobile (`apps/lyron_app`) Android + iOS, plus `.well-known` association files served from the web build (`lyron.pages.dev`).

## Goal

Make invitation links that point at the web origin (`https://lyron.pages.dev/invite?token=...`) open directly in the installed mobile app via verified App Links (Android) / Universal Links (iOS). When the app is not installed, the same link falls back to the web build in the browser. One link works everywhere.

## Non-Goal (explicit)

Magic-link authentication stays on the custom URL scheme `io.lyron.app://auth/callback` on mobile. It is **not** moved to `https://lyron.pages.dev`.

**Why:** magic link uses Supabase PKCE. The `code_verifier` is stored on the client that *initiated* `signInWithOtp`. An `https` App Link can be opened by a different client than the one that initiated (e.g. initiated in app, email opened in browser, or vice versa), producing `bad_code_verifier` — the failure already fixed for web in commit `dbfb19d`. The custom scheme guarantees only the app handles the callback, keeping the verifier local. Invitation links carry only an opaque token with no client-bound secret, so they are safe to share across clients.

## Current State

- `DeepLinkListener` (`apps/lyron_app/lib/src/application/auth/deep_link_listener.dart`) already captures the invite token when `uri.path == '/invite'`, **host-agnostic**, or when the custom-scheme callback fires. No Dart logic change is required for the new host.
- `InviteRequiredScreen._extractToken` accepts a pasted link or bare token. Unchanged.
- Android manifest (`apps/lyron_app/android/app/src/main/AndroidManifest.xml`) has an `autoVerify` App Link intent filter, but the host is the placeholder `app.lyron.staging-domain` and it covers both `/invite` and `/auth/callback`.
- Association files exist but are placeholders:
  - `apps/lyron_app/web/.well-known/assetlinks.json` — `package_name` is `io.lyron.app` (wrong; real `applicationId` is now `io.lyron.chords`), fingerprint is `<FINGERPRINT_HEX>`.
  - `apps/lyron_app/web/.well-known/apple-app-site-association` — `<APPLE_TEAM_ID>` placeholder, bundle `io.lyron.app`, paths `/invite/*` and `/auth/callback/*`.
- iOS custom scheme `io.lyron.app` is registered in `Info.plist`; `Runner.entitlements` exists.

## Design

### 1. Android App Link intent filter

In `AndroidManifest.xml`, change the `autoVerify="true"` intent-filter host to `lyron.pages.dev` and scope it to the invite path only:

- `scheme=https`, `host=lyron.pages.dev`, `pathPrefix=/invite`.
- **Remove** the `/auth/callback` `https` data entry from the verified filter. Magic link uses the custom scheme; a verified `https` `/auth/callback` could cause the app to intercept an auth callback and break PKCE. The existing custom-scheme filter (`io.lyron.app` host `auth`) is kept unchanged.

### 2. `assetlinks.json` (Android verification)

`apps/lyron_app/web/.well-known/assetlinks.json`:

- `package_name` → `io.lyron.chords` (must match the release `applicationId`).
- `sha256_cert_fingerprints` → the SHA-256 of the **release** signing certificate (the keystore wired in `build.gradle.kts`). Include the debug/upload-key fingerprint too if testing verified links on debug builds and if Play App Signing is used (the Play-managed key fingerprint must be listed for production installs from Play).

### 3. `apple-app-site-association` (iOS verification)

`apps/lyron_app/web/.well-known/apple-app-site-association`:

- `appID` → `<RealTeamID>.<real-ios-bundle-id>`.
- `paths` → `["/invite/*"]` only (drop `/auth/callback/*`, same PKCE reasoning).

### 4. iOS associated domains

`Runner.entitlements` must include `applinks:lyron.pages.dev`. Confirm/add the `com.apple.developer.associated-domains` entitlement and that it is enabled on the App ID in the Apple Developer portal.

### 5. Web hosting of `.well-known`

Cloudflare Pages (`lyron.pages.dev`) must serve:

- `https://lyron.pages.dev/.well-known/assetlinks.json`
- `https://lyron.pages.dev/.well-known/apple-app-site-association` (served with `Content-Type: application/json`, **no** `.json` extension, **no** redirect, HTTP 200).

Flutter web copies `web/` into the build output, so the files ship if the build is deployed to the Pages root. Verify the Pages config does not rewrite/redirect `.well-known/*` (SPA fallback rules often catch it).

### 6. Invitation link base URL

Invite links must be generated as `https://lyron.pages.dev/invite?token=<token>`. There is no server-side link construction in `supabase/migrations` today (invites are tokens; links appear to be assembled/shared manually or client-side). Action: confirm the single place where the shareable invite URL string is produced and ensure its base is `https://lyron.pages.dev`. If none exists yet, this is out of scope for code but must be documented for whoever shares invites.

## Data Flow

1. Inviter shares `https://lyron.pages.dev/invite?token=T`.
2. Recipient opens on phone:
   - App installed + domain verified → OS routes to app → `app_links` delivers `Uri` → `DeepLinkListener._handle` captures `token=T` → `PendingInviteTokenController.capture` → redeem flow.
   - App not installed / not verified → browser → web build handles `/invite`.
3. Desktop → browser → web build.

## Error Handling / Failure Modes

- **Verification fails silently** (wrong fingerprint, bad package, `.well-known` not served, Pages redirect): OS opens the browser instead of the app. No crash; degrades to web. This is the most likely real-world failure — verification correctness is the crux of this change.
- Token missing/empty in the link → listener ignores it (existing behavior).

## Testing

- Unit: extend `deep_link_listener_test.dart` with a `https://lyron.pages.dev/invite?token=ABC` case (asserts host-agnostic capture; guards against a future host check regression).
- Manual (release build, required — verification cannot be unit-tested):
  - `adb shell am start -a android.intent.action.VIEW -d "https://lyron.pages.dev/invite?token=TEST"` → app opens, token captured.
  - `adb shell pm get-app-links io.lyron.chords` → domain shows `verified`.
  - iOS: tap link from Notes/Messages → app opens.
- Verify `.well-known` reachability: `curl -sI https://lyron.pages.dev/.well-known/assetlinks.json` → 200, JSON.

## Risks

- SHA-256 fingerprint must match the actual signing key used for the distributed build (incl. Play App Signing key). Mismatch → silent fallback to browser.
- Cloudflare Pages SPA/redirect rules may shadow `.well-known/*`.
- Apple App ID associated-domains capability must be enabled server-side in the developer portal, not only in entitlements.
- Out of band but related: the `INTERNET` permission fix in the main manifest (separate bug) is required for *any* network/auth on release builds; tracked separately.
```
