# Slug-Based Routing For Songs, Plans, And Sessions

> Status: Proposed

## Goal

Replace `id`-based public route segments for songs, plans, and sessions with slug-based route segments while keeping `id` as the canonical internal identifier across repositories, local projections, relationships, and provider state.

## Problem

The current application exposes backend identifiers directly in URLs:

- `/songs/:songId`
- `/plans/:planId`
- `/plans/:planId/sessions/:sessionId/items/:sessionItemId/songs/:songId`

That works technically, but it makes URLs opaque and ties public navigation shape to storage identifiers. The domain direction for the next slice is clearer public routing:

- songs, plans, and sessions should have human-readable slugs
- internal read and relation boundaries should continue to use stable ids
- route resolution should translate slugs into ids before entering the existing screen and provider flows

The repository does not currently support that model for songs, plans, or sessions. The initial schema contains no `slug` columns on those tables, so the next slice must establish the storage contract first.

## Scope

- Add `slug` columns to `songs`, `plans`, and `sessions`.
- Backfill slugs for existing development data.
- Enforce slug uniqueness with scope-appropriate database constraints.
- Change canonical app routes to use slugs instead of ids for songs, plans, and sessions.
- Resolve route slugs back to internal ids before existing detail and reader flows execute.
- Preserve existing internal repository, projection, and navigation logic as id-based after route resolution.
- Treat missing slug matches as explicit not-found behavior.
- Keep slug generation app-owned for future create and edit flows.
- Constrain each session so the same song can appear at most once in that session.

## Non-Goals

- No slug history or redirect support.
- No support for old id-based URLs after the routing slice lands.
- No change to the current write capability surface for songs, plans, or sessions.
- No requirement to expose slug editing UI in this slice.
- No migration of internal foreign keys, provider families, Drift rows, or repository contracts to use slug as their primary key.
- No global session slug uniqueness.

## Product Rules

- Public URLs for songs, plans, and sessions must become slug-based.
- Public session-scoped reader URLs use `planSlug`, `sessionSlug`, and `songSlug` only.
- Internal aggregate identity remains id-based.
- A missing or invalid slug must surface as not found, not as a silent fallback to some other route or entity.
- Changing a slug in the future may invalidate older URLs; this slice intentionally accepts that behavior.
- Route helpers should construct canonical slug-based URLs rather than leaking id-based path segments.
- A session may contain a given song at most once, so `songSlug` is sufficient to identify the selected session item within that session.

## Data Model Requirements

### New Columns

- `songs.slug`
- `plans.slug`
- `sessions.slug`

Each new slug column must be non-null after backfill and available for future write flows.

### Uniqueness Boundaries

- Songs: unique by `(organization_id, slug)`
- Plans: unique by `(organization_id, slug)`
- Sessions: unique by `(plan_id, slug)`

This keeps song and plan URLs organization-readable while allowing session names such as `opening` or `worship` to repeat across unrelated plans.

### Backfill Rules

Existing rows should be backfilled by:

1. deriving a base slug from the current title or name
2. normalizing to the repository's slug format
3. resolving collisions within the constraint scope using numeric suffixes such as `-2`, `-3`, `-4`

The repository is currently backed only by a local development database, so this slice does not need production-safe redirect or compatibility logic.

## Routing Requirements

### Canonical Routes

The canonical route templates should become:

- `/songs/:songSlug`
- `/plans/:planSlug`
- `/plans/:planSlug/sessions/:sessionSlug/items/songs/:songSlug`

The scoped reader route omits a public session-item segment because each session may contain a given song at most once. The route layer resolves `songSlug` within the already-resolved session, then passes the matching internal `sessionItemId` into the existing reader context.

### Route Resolution

Routing must perform a slug-to-id resolution step before existing screen flows execute.

This resolution should happen behind a dedicated async route boundary so the app can surface a loading state while a slug lookup is in flight and can fail fast to explicit not-found behavior before the current screen trees mount.

Required lookups:

- song slug to song id within the active organization
- plan slug to plan id within the active organization
- session slug to session id within the resolved plan
- session-scoped song slug to the matching session item id within the resolved session

After resolution succeeds, the rest of the application should continue to operate on ids.

### Not-Found Behavior

If any required slug cannot be resolved:

- the route must fail explicitly
- the application must not fall back to unrelated song-only or plan-only behavior
- the app must not attempt fuzzy matching or redirect heuristics

## Application Boundary

### Internal Identity Stability

This slice must preserve the current id-based internal contracts:

- repository methods continue to accept and return ids where they do today
- local-first read models and relationships remain keyed by ids
- session-scoped reader context remains anchored to `planId`, `sessionId`, `sessionItemId`, and `songId`
- provider families remain free to use ids internally once routing resolution is complete

The route layer changes. The aggregate identity model does not.

### Lookup Responsibility

Slug resolution should be centralized behind a thin route-resolution boundary or dedicated lookup providers rather than duplicated across screens. Presentation should receive resolved ids or explicit not-found state, not reimplement slug lookup independently in each route target.

Route-facing view models or DTOs must carry the slug values needed to construct canonical URLs, while the underlying repositories and reader context remain id-based after resolution.

## Future Write-Flow Rules

This slice establishes the rules that later create and edit flows must follow:

- on create, the app generates a default slug from the entered title or name
- the editor may override that slug manually
- slug is a first-class field rather than a transient derived value
- later title changes must not silently rewrite slug values

That preserves stable URLs unless an editor explicitly changes the slug and accepts the consequence.

## Testing Requirements

The slice should include tests for:

- migration and backfill behavior for existing rows
- uniqueness enforcement for song, plan, and session slugs in their intended scopes
- route constant and route helper updates
- direct route entry using valid slugs
- not-found behavior for invalid plan, session, or song slugs
- regression coverage proving existing id-based internal providers and repositories still function after slug resolution

## Documentation Impact

The implementation should update:

- `docs/domain/domain-model.md` to record slug fields and uniqueness boundaries
- `docs/architecture/architecture.md` if the route-resolution boundary becomes a durable application pattern
- `docs/testing/testing-strategy.md` if slug migration and route-resolution tests introduce new standing expectations
