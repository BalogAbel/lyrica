# ADR-018: Invite-Only Auth with Token Redemption

## Status

Accepted

## Context

Lyron Chords is invite-only and supports three identity providers (Google, Apple, magic link). Apple Private Relay breaks email-based whitelisting, so we cannot gate access on email alone. We also need a path to delete the account on user request.

## Decision

Identity and authorization are separated:

- Supabase Auth owns identity (Google OAuth, Apple OAuth, magic link).
- An `invitations` table plus a `redeem_invitation` SQL function owns authorization. The function inserts a membership row only when a non-expired, unredeemed token is presented by an authenticated caller.
- A deep-link landing route (`/invite?token=...`) captures the token before sign-in; after sign-in, the client calls the RPC. The router blocks app entry until the user holds an active membership.
- Provider sign-in alone is insufficient to enter the app, so `auth.users` rows may exist without authorization. An hourly `pg_cron` job deletes orphan rows older than 24 hours.
- Account deletion runs a `delete_account` security-definer RPC that removes the caller's `auth.users` row and cascades memberships. `last_modified_by` foreign keys on content tables migrate to `on delete set null`.
- Supabase's "same-email linking" setting is enabled, so a user who arrives through Google and later through magic link with the same verified email becomes one identity. Apple Private Relay users cannot auto-link.

## Consequences

- Backend enforces authorization end-to-end; the client cannot grant itself membership.
- The single-organization product model is preserved; tokens already carry `organization_id` so multi-org work later does not require schema migration.
- Manual identity linking for Apple Private Relay is deferred; users are advised to keep their email-sharing choice consistent.
- Orphan auth identities can be observed in the dashboard for up to 24 hours; this is acceptable for staging.
