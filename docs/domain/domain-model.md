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

Organization-owned song records. ChordPro text is canonical. Structured metadata is stored in dedicated columns and mapped during import/export. The current executable slice proves authenticated backend song reads through a repository boundary that returns only minimal song summaries and raw ChordPro source. Parsing and reader projection remain in the Flutter app. A later song CRUD slice adds offline-created UUID-backed rows plus write-side sync metadata without moving authorization into Flutter.

Key fields:

- `id` (UUID v4)
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
- The slug is generated at creation time and remains stable across later title edits unless an explicit slug-edit slice is introduced.
- Offline-created songs must also keep local slug uniqueness within the active organization before sync succeeds.

Deletion rule:

- A song may be deleted only when no `session_items` still reference it.
- Accepted song deletion cascades to song-owned `attachments`.

Local-first read-model note:

- The authenticated reader cache persists one active full visible catalog snapshot per authenticated user for the currently active organization context.
- That snapshot stores only `SongSummary` values and raw `SongSource` payloads for the active visible catalog.
- ChordPro parsing, diagnostics, and reader projection remain Flutter-owned concerns and are not persisted as backend-owned rendered projections.
- Explicit sign-out removes access to that cached authenticated song catalog.
- In the future song CRUD slice, rows marked `pending_delete` are hidden from normal reads and slug lookups until the deletion is either synchronized or discarded.

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

Local-first write note:

- Visible plans for the active organization are synchronized into a local normalized planning projection owned by the authenticated user plus active organization boundary.
- Plan create/edit is implemented through a separate persisted planning mutation store instead of writing directly into projection rows.
- New plan creates in the current slice are organization-scoped only and therefore persist `group_id = null`.
- Local plan edits are limited to `name`, `description`, and `scheduled_for`.
- Pending local plan creates and edits are merged into normal reads immediately, while failed authorization, dependency, remote-missing, and conflict states move out of the normal overlay path into explicit mutation-status UI.
- Explicit sign-out removes both the authenticated planning projection and the authenticated planning mutation state.

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

Local-first write note:

- Readable sessions inherit the same organization-scoped visibility boundary as the owning plan and are persisted locally with canonical `sessionId`, parent `planId`, and deterministic ordering fields.
- Session create, rename, delete, and reorder are implemented through the persisted planning mutation store and overlaid into plan detail immediately.
- Session create appends deterministically after the current locally visible last session for the plan.
- Session rename is limited to `name`.
- Session delete is allowed only for locally empty sessions, and the backend re-checks that invariant before accepting the delete.
- Session reorder is a plan-scoped collection mutation that captures the owning plan's synchronized `base_version`, compacts to the latest locally intended sibling order, and reconciles canonical accepted order back into the read projection when the immediate post-write refresh fails.
- Public session-scoped reader URLs use `planSlug`, `sessionSlug`, and `songSlug`; the route layer resolves the matching internal `sessionItemId` before entering the existing id-based reader context.
- Async widget lifecycles in the planning UI now use `context.mounted` guards to prevent runtime crashes during background synchronization and state invalidation.

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
- Song-backed session-item add, delete, and reorder are implemented through the persisted planning mutation store rather than mutating synchronized projection rows directly.
- Session-item add is currently limited to visible songs from the active organization's locally available song catalog and appends deterministically after the current locally visible last item for the session.
- Session-item add, delete, and reorder capture the owning session's synchronized `base_version`, keep backend authorization and duplicate-song enforcement on the write RPC boundary, and reconcile accepted canonical order back into the read projection when the immediate refresh fails.

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

The currently executable slices now cover both sides:

- the app stores an authenticated song-catalog cache plus song write-side sync records for the active organization
- the app stores an authenticated planning projection plus persisted planning mutation records for plan create/edit and session create/rename/delete
- the app stores an authenticated planning projection plus persisted planning mutation records for plan create/edit, session create/rename/delete/reorder, and song-backed session-item add/delete/reorder
- planning mutation records retain aggregate ownership, provisional slugs, ordering, ordered sibling ids, base-version metadata for optimistic concurrency, and sync failure classification for explicit retry/review flows

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

Song mutation note:

- `canEditSongs` gates song create, update, delete, and explicit conflict-overwrite actions at the backend boundary.

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
