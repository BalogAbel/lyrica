# Organization Read-Only Role (Guest Musician)

> Status: Draft

## Goal

Introduce a new organization-scoped role, `organization_read_only`, that grants read access to an organization's catalog (songs, plans, sessions, session items, attachments) without permitting any write to domain entities. The role is intended for guest musicians who must rehearse from the organization's material but must not edit it.

## Problem

The current `role_code` enum has two organization-scope roles, `organization_admin` and `organization_member`, both of which carry write capability (`canEditSongs`, `canManagePlans`, `canEditSessions`). The only existing read-only role, `group_read_only`, is restricted to `scope_type = 'group'` and cannot be used at the organization scope. There is no way to grant a user broad read access across the entire organization catalog without also granting write capability.

## Scope

- Add `organization_read_only` to `public.role_code`.
- Update `memberships_role_scope_consistency` to permit the new role at `scope_type = 'organization'`.
- Update `public.has_capability` so the new role grants read capabilities (`canViewSongs`) but no write capability.
- Permit `organization_read_only` in `invitations.role_code` so admins can populate invitations manually with the new role.
- Surface a write-disabled capability state in the Flutter client so write affordances are hidden when the user's effective role is `organization_read_only`.
- Preserve existing membership visibility: an `organization_read_only` member may see the organization, its groups, and the membership list (already covered by the `memberships are visible inside organization` policy).

## Non-Goals

- No invitation UI changes. The invitations table is currently populated manually; UI to issue invitations remains out of scope.
- No new role-management UI. Promote / demote between `organization_read_only` and the other org-scope roles remains a manual DB operation by an admin.
- No new local-first synchronization rules. Read-only members hit the existing local-first read path; their pending-mutation outbox simply cannot enqueue writes that the backend would reject.
- No quota or rate limiting specific to guest users.
- No changes to `group_read_only` semantics.

## Roles And Capability Matrix

Effective capabilities after this change:

| capability                       | organization_admin | organization_member | organization_read_only | group_admin | group_member | group_read_only |
|----------------------------------|--------------------|---------------------|------------------------|-------------|--------------|-----------------|
| canViewSongs                     | yes                | yes                 | **yes**                | yes         | yes          | yes             |
| canEditSongs                     | yes                | yes                 | **no**                 | yes         | yes          | no              |
| canManagePlans                   | yes                | yes                 | **no**                 | yes         | yes          | no              |
| canEditSessions                  | yes                | yes                 | **no**                 | yes         | yes          | no              |
| canManageOrganizationMembers     | yes                | no                  | **no**                 | no          | no           | no              |
| canManageGroupMembers            | yes                | no                  | **no**                 | yes         | no           | no              |

`has_capability` priority ordering (used to break ties when a user has both an org-scope and a group-scope membership) extends to:

```
organization_admin     -> 1
group_admin            -> 2
organization_member    -> 3
group_member           -> 4
organization_read_only -> 5
group_read_only        -> 6
```

This keeps writer roles ahead of read-only roles when a single user holds both kinds of memberships, so a guest who is also a group member retains their group write capability.

## Database Changes

Two migrations are required because `ALTER TYPE ... ADD VALUE` cannot be referenced by other DDL in the same transaction.

### Migration A — `<ts>_organization_read_only_role_enum.sql`

```sql
alter type public.role_code add value if not exists 'organization_read_only';
```

### Migration B — `<ts>_organization_read_only_role_constraints.sql`

1. Replace `memberships_role_scope_consistency`:

   ```sql
   alter table public.memberships
     drop constraint memberships_role_scope_consistency;

   alter table public.memberships
     add constraint memberships_role_scope_consistency check (
       (scope_type = 'organization'
         and role_code in (
           'organization_admin',
           'organization_member',
           'organization_read_only'
         ))
       or (scope_type = 'group'
         and role_code in (
           'group_admin',
           'group_member',
           'group_read_only'
         ))
     );
   ```

2. Recreate `public.has_capability` so the new role contributes to `canViewSongs` only and is added to the priority ordering. No other capability list includes `organization_read_only`.

3. Replace the `invitations.role_code` check:

   ```sql
   alter table public.invitations
     drop constraint invitations_role_code_check;

   alter table public.invitations
     add constraint invitations_role_code_check check (
       role_code in (
         'organization_admin',
         'organization_member',
         'organization_read_only'
       )
     );
   ```

   The existing `public.create_invitation(p_role public.role_code, ...)` function does not constrain `p_role` beyond the column type, so no function body change is required for ingestion. The check constraint enforces the allowed set.

### RLS impact

No RLS policy needs to be rewritten. All write policies on `songs`, `plans`, `sessions`, `session_items`, and `attachments` already gate on `has_capability(..., 'canEditSongs' | 'canManagePlans' | 'canEditSessions')`. After step 2 of Migration B those capability checks return `false` for `organization_read_only`, so writes are denied automatically. Read policies on `organizations`, `groups`, `memberships`, `plans`, `sessions`, `session_items` already gate on `current_organization_ids()`, which includes any active membership regardless of role. The `songs` and `attachments` read policies gate on `canViewSongs`, which is extended above.

### Write contract functions

The SQL write-contract functions introduced in `202604080001_song_crud_write_contract.sql`, `202604100001_planning_write_contract.sql`, and `202604110001_planning_session_item_write_contract.sql` already early-exit on `has_capability(..., '<write capability>') = false`. They will reject `organization_read_only` callers without modification.

## Client (Flutter) Changes

Goal: hide every write affordance for users whose effective capability set does not include the corresponding capability. Write attempts must remain blocked by RLS as the source of truth; the client is a UX layer.

1. **Capability resolution.** Add a thin async resolver in `apps/lyron_app/lib/src/domain/core/` that calls `public.has_capability` (or a batched variant) for the active `organization_id` and caches the result per `(userId, organizationId)`. Resolver invalidates on sign-in, sign-out, and on membership-revocation events already modeled by the active-membership policy.
2. **Capability surface.** Extend the existing `Capability` enum usage to gate the following UI entry points:
   - song create / edit / import buttons → `Capability.editSongs`
   - plan create / edit buttons → `Capability.managePlans`
   - session edit / session-item add / reorder / remove → `Capability.editSessions`
   - membership management screens → `Capability.manageOrganizationMembers` / `Capability.manageGroupMembers`
3. **Default behaviour.** When a capability is missing, the affordance is hidden, not merely disabled, so guest users do not see UI that suggests an editable workflow exists. Read-only navigation paths (song reader, plan reader, session reader) remain unchanged.
4. **No new role enum on the client.** The client does not pattern-match on `role_code` strings; gating is per capability only, so adding the new role does not require widening any client enum. The existing `Capability.viewSongs` already covers the read scope used by guest users.

## Invitations Flow (Manual)

`invitations.role_code` accepts `organization_read_only` after Migration B. The existing invitation lifecycle (`create_invitation`, `redeem_invitation`) propagates `role_code` directly into the inserted `memberships` row, so redeeming an `organization_read_only` invitation produces an org-scope membership with the new role. No function body changes are required.

## Testing

- **SQL migration tests.** Add `pgTAP`-style or scripted assertions verifying:
  - the enum contains `organization_read_only`
  - inserting a `memberships` row with `scope_type='organization'` and `role_code='organization_read_only'` succeeds
  - inserting with `scope_type='group'` and `role_code='organization_read_only'` fails the consistency check
  - `has_capability(org, 'canViewSongs')` returns `true` for an `organization_read_only` member
  - `has_capability(org, 'canEditSongs' | 'canManagePlans' | 'canEditSessions')` returns `false` for the same member
- **Write contract tests.** For each of `upsert_song`, `delete_song`, plan / session / session_item write contract functions, assert that a caller with `organization_read_only` receives the existing capability-denied error code.
- **Invitations test.** Assert that an invitation with `role_code='organization_read_only'` can be inserted (manual path) and that `redeem_invitation` produces a membership with the same role.
- **Client unit tests.** Add tests for the capability resolver and UI gating predicates that pin write affordances to the appropriate `Capability` values. Cover the case where a user has both an `organization_read_only` org-scope membership and a `group_member` membership in the same org — group-scope writes must still be permitted in that case (this is the priority-ordering case above).

## Rollout / Risk

- **Backward compatibility.** Adding an enum value is non-breaking. The constraint replacement is a CHECK swap, safe under normal load.
- **No data backfill.** Existing memberships are unaffected. No row carries the new role until manually assigned.
- **Reversibility.** Rolling back Migration B is safe (restore the prior CHECK and `has_capability`). Rolling back Migration A is more involved because Postgres does not support `DROP VALUE` from an enum; if rollback is required, the new value can remain unused on the type without runtime impact.
- **Observability.** No new telemetry. Existing capability-denied error paths already log at the write-contract layer.

## Open Questions

None at the time of writing. Memberships visibility for `organization_read_only` is intentionally unchanged.
