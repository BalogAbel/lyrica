# Invitation App Links Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `https://lyron.pages.dev/invite?token=...` open the installed mobile app via verified Android App Links / iOS Universal Links, falling back to the web build when the app is absent.

**Architecture:** Config-only change. The Dart `DeepLinkListener` is already host-agnostic for `/invite`, so no auth/runtime logic changes. Work is: fix the Android verified intent-filter host, correct the `assetlinks.json` / `apple-app-site-association` association files (right package/bundle + real signing fingerprints), add the iOS associated domain, and verify hosting. Magic link stays on the custom scheme `io.lyron.app://auth/callback` (untouched) to preserve PKCE `code_verifier` locality.

**Tech Stack:** Flutter (`apps/lyron_app`), Android manifest + Play App Signing, iOS entitlements, Cloudflare Pages (`lyron.pages.dev`).

**Reference spec:** `docs/specs/2026-06-02-invite-app-links-design.md`

**Known identifiers (verified from repo):**
- Android `applicationId` (release): `io.lyron.chords`
- iOS bundle id: `com.lyron.lyronApp`
- Custom scheme (unchanged): `io.lyron.app` host `auth`
- Web host: `lyron.pages.dev`

---

### Task 1: Regression test — listener captures token from `lyron.pages.dev/invite`

Guards the host-agnostic behavior the whole feature relies on, so a future host check cannot silently break invite capture.

**Files:**
- Test: `apps/lyron_app/test/application/auth/deep_link_listener_test.dart`

- [ ] **Step 1: Add the failing test**

Append this test inside `main()` in `apps/lyron_app/test/application/auth/deep_link_listener_test.dart`:

```dart
  test('captures token from https://lyron.pages.dev/invite', () async {
    final controller = StreamController<Uri>();
    final pending = PendingInviteTokenController();
    final listener = DeepLinkListener(
      stream: controller.stream,
      pendingTokens: pending,
    );

    listener.start();
    controller.add(Uri.parse('https://lyron.pages.dev/invite?token=PAGESDEV'));

    await Future<void>.delayed(Duration.zero);

    expect(pending.current?.token, 'PAGESDEV');

    await listener.dispose();
  });
```

- [ ] **Step 2: Run the test**

Run: `cd apps/lyron_app && flutter test test/application/auth/deep_link_listener_test.dart`
Expected: PASS (listener already matches `uri.path == '/invite'` host-agnostically). This test locks that contract in place. If it fails, stop — the listener was changed and the spec assumption is wrong.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/application/auth/deep_link_listener_test.dart
git commit -m "test(auth): lock host-agnostic invite capture for lyron.pages.dev

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Android — point verified App Link at `lyron.pages.dev`, scope to `/invite`

**Files:**
- Modify: `apps/lyron_app/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Replace the placeholder verified intent-filter**

Find this block:

```xml
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data
                    android:scheme="https"
                    android:host="app.lyron.staging-domain"
                    android:pathPrefix="/invite" />
                <data
                    android:scheme="https"
                    android:host="app.lyron.staging-domain"
                    android:pathPrefix="/auth/callback" />
            </intent-filter>
```

Replace with (new host, `/auth/callback` removed — magic link stays on custom scheme):

```xml
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data
                    android:scheme="https"
                    android:host="lyron.pages.dev"
                    android:pathPrefix="/invite" />
            </intent-filter>
```

Leave the custom-scheme `io.lyron.app` host `auth` intent-filter unchanged.

- [ ] **Step 2: Verify the manifest is still valid**

Run: `cd apps/lyron_app && flutter build apk --debug 2>&1 | tail -5`
Expected: build succeeds (no manifest merge error). If the debug build needs dart-defines, use the project's usual `--dart-define SUPABASE_URL=... --dart-define SUPABASE_ANON_KEY=...`.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/android/app/src/main/AndroidManifest.xml
git commit -m "feat(auth): verify lyron.pages.dev App Link for /invite on Android

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Android — correct `assetlinks.json` package and signing fingerprint

**Files:**
- Modify: `apps/lyron_app/web/.well-known/assetlinks.json`

- [ ] **Step 1: Obtain the release signing SHA-256 fingerprint**

The release keystore is wired via `apps/lyron_app/android/app/key.properties` (see `build.gradle.kts`). Read `storeFile`/`keyAlias` from it, then:

Run: `keytool -list -v -keystore <storeFile> -alias <keyAlias>` (enter the store password)
Copy the `SHA256:` line value (colon-separated hex, e.g. `AB:CD:...`).

If the app is distributed through **Google Play App Signing**, the fingerprint that must be trusted is the **Play-managed app signing key**, found in Play Console → your app → Release → Setup → App signing → "App signing key certificate" SHA-256. Include both the upload key and the Play signing key fingerprints when in doubt.

- [ ] **Step 2: Write the corrected file**

Replace the full contents of `apps/lyron_app/web/.well-known/assetlinks.json` with (substitute the real fingerprint(s) from Step 1; list multiple as separate array entries):

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "io.lyron.chords",
      "sha256_cert_fingerprints": ["REPLACE_WITH_SHA256_FROM_STEP_1"]
    }
  }
]
```

- [ ] **Step 3: Validate it is well-formed JSON**

Run: `python3 -m json.tool apps/lyron_app/web/.well-known/assetlinks.json`
Expected: pretty-printed JSON, no error. Confirm `package_name` is `io.lyron.chords` and the fingerprint contains no `<...>` placeholder.

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/web/.well-known/assetlinks.json
git commit -m "fix(auth): correct assetlinks package id and signing fingerprint

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: iOS — correct `apple-app-site-association`

**Files:**
- Modify: `apps/lyron_app/web/.well-known/apple-app-site-association`

- [ ] **Step 1: Obtain the Apple Team ID**

From Apple Developer portal (Membership page) or Xcode → Runner target → Signing & Capabilities → Team (the 10-char ID, e.g. `A1B2C3D4E5`). The iOS bundle id is `com.lyron.lyronApp` (verified in `project.pbxproj`).

- [ ] **Step 2: Write the corrected file**

Replace the full contents of `apps/lyron_app/web/.well-known/apple-app-site-association` with (substitute the real Team ID; `/invite/*` only, `/auth/callback/*` dropped for PKCE):

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "REPLACE_WITH_TEAM_ID.com.lyron.lyronApp",
        "paths": ["/invite/*"]
      }
    ]
  }
}
```

- [ ] **Step 3: Validate JSON**

Run: `python3 -m json.tool apps/lyron_app/web/.well-known/apple-app-site-association`
Expected: valid JSON, `appID` has no `<...>` placeholder.

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/web/.well-known/apple-app-site-association
git commit -m "fix(auth): correct AASA appID and scope paths to /invite

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: iOS — set associated domain entitlement

**Files:**
- Modify: `apps/lyron_app/ios/Runner/Runner.entitlements`

- [ ] **Step 1: Replace the placeholder associated domain**

In `apps/lyron_app/ios/Runner/Runner.entitlements`, find:

```xml
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>applinks:app.lyron.&lt;staging-domain&gt;</string>
	</array>
```

Replace with:

```xml
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>applinks:lyron.pages.dev</string>
	</array>
```

Leave the `com.apple.developer.applesignin` entry unchanged.

- [ ] **Step 2: Verify the plist is well-formed**

Run: `plutil -lint apps/lyron_app/ios/Runner/Runner.entitlements`
Expected: `OK`. (On non-macOS, skip and rely on CI/Xcode build.)

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/ios/Runner/Runner.entitlements
git commit -m "feat(auth): associate lyron.pages.dev universal link on iOS

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

> Manual portal step (cannot be done in repo, note it for the release owner): the App ID `com.lyron.lyronApp` must have the **Associated Domains** capability enabled in the Apple Developer portal, and the provisioning profile regenerated.

---

### Task 6: Verify `.well-known` hosting on Cloudflare Pages

No code change — a verification gate. App Link verification fails silently if these are not served correctly.

**Files:** none (verification only).

- [ ] **Step 1: Confirm files ship in the web build**

Run: `cd apps/lyron_app && flutter build web 2>&1 | tail -3 && ls build/web/.well-known/`
Expected: `assetlinks.json` and `apple-app-site-association` present in `build/web/.well-known/`.

- [ ] **Step 2: After deploy, verify reachability**

Run:
```bash
curl -sI https://lyron.pages.dev/.well-known/assetlinks.json
curl -sI https://lyron.pages.dev/.well-known/apple-app-site-association
```
Expected for both: `HTTP/2 200`, `content-type: application/json`, **no** redirect (no `301/302`). The AASA file must be served with no extension and `application/json`.

- [ ] **Step 3: If a redirect/404 occurs, exclude `.well-known` from SPA fallback**

Cloudflare Pages SPA fallback can shadow these. Add a `apps/lyron_app/web/_routes.json` to exclude the path from the SPA function/redirect:

```json
{
  "version": 1,
  "include": ["/*"],
  "exclude": ["/.well-known/*"]
}
```

Rebuild + redeploy, then re-run Step 2. Commit only if this file was needed:

```bash
git add apps/lyron_app/web/_routes.json
git commit -m "fix(web): exclude .well-known from SPA fallback for App Links

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Document the invite link base URL

The repo has no server-side invite-URL construction (`supabase/migrations/202605160002_invitations_functions.sql` produces tokens, not URLs). Whoever shares invites must use `https://lyron.pages.dev/invite?token=<token>`. Record this so it does not live only in chat (AGENTS.md rule 1, 2).

**Files:**
- Modify: `docs/workflows/` (add or extend the relevant invite/onboarding workflow doc; create `docs/workflows/invitations.md` if none exists)

- [ ] **Step 1: Add the invite link format note**

Create `docs/workflows/invitations.md` (or append a section if a matching workflow doc already exists) containing:

```markdown
# Invitations

## Shareable invite link format

Invite links MUST use the web origin so they resolve on every platform:

```
https://lyron.pages.dev/invite?token=<token>
```

On a phone with the app installed and the domain verified (App Links / Universal
Links), the OS opens the app, which captures the token via `DeepLinkListener`
and runs the redeem flow. Without the app, the same link opens the web build.

The `token` comes from the invitation row created by
`supabase/migrations/202605160002_invitations_functions.sql`. The app/site
extracts `?token=` from the `/invite` URL; a bare token is also accepted in the
"paste invite link" field (`InviteRequiredScreen`).

Magic-link authentication deliberately does NOT use this https link — it uses
the custom scheme `io.lyron.app://auth/callback` to keep the PKCE
`code_verifier` on the initiating client. See
`docs/specs/2026-06-02-invite-app-links-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add docs/workflows/invitations.md
git commit -m "docs(workflows): document lyron.pages.dev invite link format

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Record the architectural decision

App Links scope + the magic-link-stays-custom-scheme call is a durable decision (AGENTS.md rule 2; `docs/architecture/decisions/`).

**Files:**
- Create: `docs/architecture/decisions/2026-06-02-invite-app-links.md`

- [ ] **Step 1: Write the ADR**

Create `docs/architecture/decisions/2026-06-02-invite-app-links.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/architecture/decisions/2026-06-02-invite-app-links.md
git commit -m "docs(adr): record invite App Links vs magic-link scheme decision

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Manual end-to-end verification (release build)

App Link verification cannot be unit-tested; this is the acceptance gate.

**Files:** none.

- [ ] **Step 1: Android verified-link check**

Install the release build (`io.lyron.chords`) on a device, then:

Run: `adb shell pm get-app-links io.lyron.chords`
Expected: `lyron.pages.dev` listed with state `verified`.

- [ ] **Step 2: Android intent open**

Run: `adb shell am start -a android.intent.action.VIEW -d "https://lyron.pages.dev/invite?token=TESTTOKEN"`
Expected: the app launches (not the browser) and the invite redeem flow receives `TESTTOKEN`.

- [ ] **Step 3: iOS open**

On an iOS device with the app installed, tap `https://lyron.pages.dev/invite?token=TESTTOKEN` from Notes or Messages (not Safari address bar — that won't trigger Universal Links).
Expected: the app opens and receives the token.

- [ ] **Step 4: Fallback check**

On a device without the app (or desktop), open the same URL.
Expected: the web build at `lyron.pages.dev` handles `/invite`.

---

## Notes

- The `INTERNET` permission fix in `apps/lyron_app/android/app/src/main/AndroidManifest.xml` and the `build.gradle.kts`/`pubspec.yaml` release-signing changes are **separate** in-flight work present in the working tree; they are prerequisites for any auth on release builds but are not part of this plan's commits.
