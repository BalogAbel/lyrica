# Domain Model

## Canonical Aggregates

- `organizations`
- `groups`
- `memberships`
- `songs`
- `plans`
- `events`
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

### plans

High-level planning containers, often corresponding to a service set or rehearsal plan.

Key fields:

- `id`
- `organization_id`
- `group_id`
- `name`
- `description`
- `scheduled_for`
- `version`
- `base_version`
- `sync_status`
- `updated_at`
- `last_modified_by`

If `group_id` is present, it must belong to the same organization as the plan.

### events

Calendar-facing occurrence or service context. Events may own one or more sessions.

Key fields:

- `id`
- `organization_id`
- `group_id`
- `plan_id`
- `name`
- `starts_at`
- `ends_at`
- `location`
- `version`
- `base_version`
- `sync_status`
- `updated_at`
- `last_modified_by`

If `plan_id` or `group_id` is present, both references must remain inside the same organization as the event.

### sessions

Editable operational lists used during preparation or execution. Sessions belong to events.

Key fields:

- `id`
- `organization_id`
- `group_id`
- `event_id`
- `name`
- `notes`
- `version`
- `base_version`
- `sync_status`
- `updated_at`
- `last_modified_by`

Session organization scope is inherited from the owning event and must never diverge from it.

### session_items

Ordered items within a session. An item can point to a song, attachment, or free-form note depending on type.

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

### sync_status

Expected values:

- `pending_create`
- `pending_update`
- `pending_delete`
- `synced`
- `conflict`

## Relationships

- An organization has many groups.
- An organization has many songs, plans, events, sessions, and attachments.
- A group belongs to an organization.
- A plan may have many events.
- An event may have many sessions.
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
