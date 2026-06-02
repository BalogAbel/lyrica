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
