# Domain Vocabulary

Canonical term definitions for sync state, freshness, and mutation lifecycle. Use these terms consistently in specs, UI copy, models, and tests.

## Auth and Invite Terms

- **Invitation** — A single-use credential that grants membership when redeemed. Carries `organization_id` and `role_code` so redemption is forward-compatible with multi-organization flows.
- **Magic link** — A one-time email link that authenticates the recipient via Supabase Auth without a password.
- **Orphan auth identity** — An `auth.users` row without an active membership. Eligible for automatic cleanup after 24 hours via `pg_cron`.
- **Redeem** — The act of converting an invitation into an active membership row by calling the `redeem_invitation` RPC with a valid, unexpired, unredeemed token.

## Freshness Terms

- `fresh`: local projection was refreshed from the backend in the current online context.
- `stale`: local projection is usable, but the app could not confirm current backend freshness.
- `offline_cached`: local projection is usable while connectivity or backend reachability is unavailable.
- `refreshing`: the app is attempting to update the local projection from the backend.

## Mutation State Terms

- `pending_local`: local mutation exists and has not yet been accepted by the backend.
- `syncing`: pending local mutations are being sent to backend-authorized write contracts.
- `sync_failed`: a retryable sync attempt failed and local intent remains durable.
- `conflict`: backend state and local intent diverged and require explicit user choice.

## Failure Classification Terms

- `authorization_denied`: backend rejected a mutation because the user lacks the required capability.
- `dependency_blocked`: backend or local policy rejected a mutation because related data prevents it.
- `remote_missing`: backend reported that the target record no longer exists.

## Active-Organization Resolution Terms

- `selected(organizationId)`: a verified active organization is available.
- `verifiedEmpty`: backend lookup succeeded and returned no visible organization ids.
- `unknownConnectivityFailure`: the app cannot verify membership because the lookup failed with a connectivity-classified error.
- `unknownNonConnectivityFailure`: the lookup failed for a non-connectivity reason, including malformed responses or unexpected backend failures.

## Sync Activity Dimensions

Sync activity, connectivity, and freshness are orthogonal dimensions on any repository-owned local state:

- `sync_activity`: idle or running
- `connectivity`: online, offline, or unknown
- `freshness`: fresh, stale, or offline_cached

Syncing is transient activity over durable local states. It is not an entity lifecycle state.
