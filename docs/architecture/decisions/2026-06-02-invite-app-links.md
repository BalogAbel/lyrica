# ADR: Invite deep links via App Links; magic link stays custom scheme

- Date: 2026-06-02
- Status: Accepted

## Context

Web is served at `lyron.pages.dev` (same Flutter app, web build). We want
shared invite links to open the mobile app when installed, and the browser
otherwise.

## Decision

- Invitation links (`/invite?token=...`) use verified Android App Links / iOS
  Universal Links on host `lyron.pages.dev`. Invite tokens carry no
  client-bound secret, so any client may open them.
- Magic-link authentication keeps the custom scheme
  `io.lyron.app://auth/callback` on mobile. It uses PKCE; the `code_verifier`
  lives only on the initiating client. An https App Link can be opened by a
  different client than the initiator, causing `bad_code_verifier` (previously
  fixed for web in commit `dbfb19d`). The custom scheme guarantees the app is
  the sole handler.
- The verified App Link filter is scoped to `/invite` only; `/auth/callback`
  is intentionally excluded from https verification.

## Consequences

- App Link verification depends on correct `assetlinks.json` (package
  `io.lyron.chords` + release/Play signing SHA-256) and
  `apple-app-site-association` (`<TeamID>.com.lyron.lyronApp`), served from
  `lyron.pages.dev/.well-known/` with `application/json` and no redirect.
- Misconfiguration degrades silently to the browser (no crash), so manual
  verification (`adb shell pm get-app-links`, `curl` of `.well-known`) is
  part of the release checklist.
