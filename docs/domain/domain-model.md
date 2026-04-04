# Domain Model

## Canonical Aggregates

- `organizations`
- `groups`
- `memberships`
- `songs`
- `plans`
- `sessions`
- `session_items`
- `attachments`

`auth.users` is the identity source, but it is Supabase-managed infrastructure rather than a repository-owned business aggregate.

## Entity Overview

### organizations

Tenant boundary for business data, memberships, authorization policies, and song ownership.

Key fields:

- `id`
- `name`
- `slug`
- `created_at`
- `updated_at`

### groups

Scoped collaboration units inside an organization. Groups partition access for teams, ministries, or service crews.

Key fields:

- `id`
- `organization_id`
- `name`
- `description`
- `created_at`
- `updated_at`

### memberships

Normalized representation of organization and group membership. Memberships are modeled separately so authorization logic can evolve without spreading role strings across application code.

Key fields:

- `id`
- `organization_id`
- `group_id`
- `user_id`
- `scope_type`
- `role_code`
- `status`
- `created_at`
- `updated_at`

Invariants:

- `scope_type = 'organization'` requires `group_id` to be `null`.
- `scope_type = 'group'` requires `group_id` to reference a group in the same organization.
- Organization-scoped roles cannot be assigned to group-scoped memberships and vice versa.
- Organization-scoped memberships must be unique by `(organization_id, user_id, role_code)` when `group_id` is `null`.

Operational note:

- The local repair migration for previously duplicated organization-scoped memberships keeps the earliest row by `created_at, id` before enforcing uniqueness.

### songs

Organization-owned song records. ChordPro text is canonical. Structured metadata is stored in dedicated columns and mapped during import/export. The current executable slice proves authenticated backend song reads through a repository boundary that returns only minimal song summaries and raw ChordPro source. Parsing and reader projection remain in the Flutter app.

Key fields:

- `id`
- `organization_id`
- `slug`
- `title`
- `artist`
- `key_signature`
- `tempo_bpm`
- `tags`
- `chordpro_source`
- `metadata_json`
- `version`
- `base_version`
- `sync_status`
- `updated_at`
- `last_modified_by`

Slug rule:

- `slug` is required and unique within `(organization_id, slug)`.
- The slug is the public URL segment for song routes; the internal song identifier remains `id`.

Local-first read-model note:

- The authenticated reader cache persists one active full visible catalog snapshot per authenticated user for the currently active organization context.
- That snapshot stores only `SongSummary` values and raw `SongSource` payloads for the active visible catalog.
- ChordPro parsing, diagnostics, and reader projection remain Flutter-owned concerns and are not persisted as backend-owned rendered projections.
- Explicit sign-out removes access to that cached authenticated song catalog.

### plans

High-level planning containers, often corresponding to a service set or rehearsal plan.

Key fields:

- `id`
- `organization_id`
- `group_id`
- `slug`
- `name`
- `description`
- `scheduled_for`
- `version`
- `base_version`
- `sync_status`
- `updated_at`
- `last_modified_by`

If `group_id` is present, it must belong to the same organization as the plan.

Slug rule:

- `slug` is required and unique within `(organization_id, slug)`.
- The slug is the public URL segment for plan routes; the internal plan identifier remains `id`.

Read-model note:

- In the current executable planning slice, visible plans for the active organization are synchronized into a local normalized read model owned by the authenticated user plus active organization boundary.
- Planning writes remain capability-based backend decisions; the read-side slice does not introduce a separate planning view capability.

### sessions

Editable operational lists used during preparation or execution. In the current executable planning slice, sessions belong directly to plans.

Key fields:

- `id`
- `organization_id`
- `group_id`
- `plan_id`
- `slug`
- `position`
- `name`
- `notes`
- `version`
- `base_version`
- `sync_status`
- `updated_at`
- `last_modified_by`

Session organization scope is inherited from the owning plan and must never diverge from it. When `group_id` is present on a session, it must stay aligned with the owning plan.

Slug rule:

- `slug` is required and unique within `(plan_id, slug)`.
- The slug is the public URL segment for session-scoped reader routes; the internal session identifier remains `id`.

Read-model note:

- In the current executable planning slice, readable sessions inherit the same organization-scoped visibility boundary as the owning plan and are persisted locally with canonical `sessionId`, parent `planId`, and deterministic ordering fields.
- Public session-scoped reader URLs use `planSlug`, `sessionSlug`, and `songSlug`; the route layer resolves the matching internal `sessionItemId` before entering the existing id-based reader context.

### session_items

Ordered items within a session. The wider schema can support songs, attachments, or notes by item type, but the first executable planning slice uses only song-backed entries.

Key fields:

- `id`
- `organization_id`
- `session_id`
- `song_id`
- `attachment_id`
- `item_type`
- `title_override`
- `position`
- `notes`
- `version`
- `base_version`
- `sync_status`
- `updated_at`
- `last_modified_by`

Invariants:

- `item_type = 'song'` requires `song_id` and forbids `attachment_id`.
- `item_type = 'attachment'` requires `attachment_id` and forbids `song_id`.
- `item_type = 'note'` forbids both `song_id` and `attachment_id`.
- Referenced songs and attachments must remain in the same organization as the owning session.
- A session may contain a given song at most once.

Read-model note:

- In the current executable planning slice, readable session items inherit the same organization-scoped visibility boundary as the owning session and are persisted locally by explicit `sessionItemId`, even though the public scoped reader URL resolves through `songSlug` within a session.

### attachments

Non-canonical supporting assets such as PDFs. Attachments supplement songs and may be referenced from session items, but do not replace canonical text storage.

Key fields:

- `id`
- `organization_id`
- `song_id`
- `storage_bucket`
- `storage_path`
- `mime_type`
- `file_name`
- `version`
- `base_version`
- `sync_status`
- `updated_at`
- `last_modified_by`

Attachments are organization-scoped and currently song-owned. Session items reference attachments by `attachment_id`; attachments do not own reverse pointers into session items.

## Sync Metadata

Offline-synced aggregates include:

- `version`
- `base_version`
- `updated_at`
- `last_modified_by`
- `sync_status`

The first real Drift-backed feature must persist this metadata locally together with a durable sync queue entry for each pending mutation.

The currently executable slices are narrower than full sync: the app stores a read-only authenticated song-catalog cache with snapshot metadata (`refreshed_at`, snapshot version, and authenticated user plus active-organization ownership), and it stores a read-only authenticated planning projection with ownership metadata plus normalized plan, session, and session-item rows for the active organization. It does not yet introduce write-side sync records for songs, plans, or sessions.

### sync_status

Expected values:

- `pending_create`
- `pending_update`
- `pending_delete`
- `synced`
- `conflict`

## Relationships

- An organization has many groups.
- An organization has many songs, plans, sessions, and attachments.
- A group belongs to an organization.
- A plan has many sessions.
- A session has many session items.
- A session item may reference one song or one attachment.
- Cross-aggregate references must keep `organization_id` aligned; cross-organization foreign-key combinations are invalid.

## Capability Model

Authorization evaluates capabilities, not raw role strings in application code. Examples:

- `canEditSongs`
- `canViewSongs`
- `canManageOrganizationMembers`
- `canManageGroupMembers`
- `canEditSessions`
- `canManagePlans`

Roles map to capabilities in backend-owned policy logic.

Membership administration is also capability-based:

- organization-scoped membership changes require `canManageOrganizationMembers`
- group-scoped membership changes require `canManageGroupMembers`

## ChordPro Rules

- `chordpro_source` is canonical for song content.
- Metadata remains separately queryable.
- Import/export maps metadata into and out of ChordPro directives.
- PDF is always a fallback attachment, never the canonical editable source.
- The first song-reader slice supports a documented ChordPro subset only; unsupported directives produce recoverable warnings and preserve renderable content when possible.

## Song Reading Slice

The first product slice adds app-local song-reading concepts that sit at the repository boundary:

- `SongSummary` is the minimal list projection with `id` and `title`.
- `SongSource` returns the raw ChordPro source for a song ID.
- `ParsedSong`, `SongSection`, `SongLine`, and `LyricSegment` model the parsed reader document.
- `ParseDiagnostic` records warning or error context for parser output.
- `SongReaderResult` pairs a parsed song with derived warning state for the reader UI.

Current catalog and parsing rules for this slice:

- The authenticated executable slice reads the current three-song catalog from backend seed data through `SongSummary` and raw `SongSource`.
- The bundled `.pro` assets remain parser/reference fixtures, not the authenticated runtime catalog for this slice.
- Unknown song IDs fail through a not-found exception rather than an infrastructure leak.
- Explicit backend permission-denied failures can surface as access-denied at the app boundary, while RLS-hidden rows remain unavailable.
- Unsupported directives and recoverable parser issues stay visible in diagnostics for developer logging and UI warning surfaces.
