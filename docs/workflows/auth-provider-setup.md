# Auth Provider Setup

This document captures the dashboard-only configuration that cannot be expressed in `supabase/config.toml`.

## Google

1. Create OAuth client IDs for iOS, Android, and Web in the Google Cloud Console.
2. Configure them as `SUPABASE_AUTH_GOOGLE_CLIENT_ID` (web client) and `SUPABASE_AUTH_GOOGLE_SECRET` in the Supabase project secrets and locally in `.env.local`.

## Apple

1. Create a Services ID, key, and team ID in the Apple Developer portal.
2. Configure them as `SUPABASE_AUTH_APPLE_CLIENT_ID` (Services ID) and `SUPABASE_AUTH_APPLE_SECRET` (signing payload).
3. iOS native sign-in additionally requires `com.apple.developer.applesignin` capability in the entitlements file.

## Same-email linking

In the Supabase dashboard, navigate to Authentication → Providers → "Manually link same emails" and enable it. There is no `config.toml` flag for this option at the CLI version pinned in `tooling/supabase`.

## Magic-link email template

The default Supabase template is acceptable for staging. Production rollout replaces the template via `auth/email-templates/magic_link.html` once a transactional provider is wired (deferred from this slice).
