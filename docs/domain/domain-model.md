# Domain Model

## Canonical Aggregates

- `organizations`
- `groups`
- `users`
- `memberships`
- `songs`
- `plans`
- `events`
- `sessions`
- `session_items`
- `attachments`

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

### songs

Organization-owned song records. ChordPro text is canonical. Structured metadata is stored in dedicated columns and mapped during import/export.

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

### attachments

Non-canonical supporting assets such as PDFs. Attachments supplement songs or session items but do not replace canonical text storage.

Key fields:

- `id`
- `organization_id`
- `song_id`
- `session_item_id`
- `storage_bucket`
- `storage_path`
- `mime_type`
- `file_name`
- `version`
- `base_version`
- `sync_status`
- `updated_at`
- `last_modified_by`

## Sync Metadata

Offline-synced aggregates include:

- `version`
- `base_version`
- `updated_at`
- `last_modified_by`
- `sync_status`

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

## Capability Model

Authorization evaluates capabilities, not raw role strings in application code. Examples:

- `canEditSongs`
- `canViewSongs`
- `canManageOrganizationMembers`
- `canManageGroupMembers`
- `canEditSessions`
- `canManagePlans`

Roles map to capabilities in backend-owned policy logic.

## ChordPro Rules

- `chordpro_source` is canonical for song content.
- Metadata remains separately queryable.
- Import/export maps metadata into and out of ChordPro directives.
- PDF is always a fallback attachment, never the canonical editable source.
