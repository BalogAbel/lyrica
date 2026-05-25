# Organization Read-Only Role Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a new `organization_read_only` role that grants read access to an organization's songs, plans, sessions, and session items, and no write capability, so a guest musician can rehearse from the catalog without modifying it.

**Architecture:** Extend the `public.role_code` enum and `memberships_role_scope_consistency` check, rewrite `public.has_capability` so the new role contributes to `canViewSongs` only, broaden the `invitations.role_code` check to accept the new role, and gate the Flutter write affordances on the existing `Capability` enum via a single capability resolver provider. Read RLS policies already gate on `current_organization_ids()` and `canViewSongs`, so they require no rewrite.

**Tech Stack:** PostgreSQL (Supabase), pg RLS, bash + python3 contract test runner, Flutter, Riverpod.

---

## File Structure

**Database (create):**
- `supabase/migrations/202605250001_organization_read_only_role_enum.sql` — add the enum value.
- `supabase/migrations/202605250002_organization_read_only_role_constraints.sql` — replace `memberships_role_scope_consistency`, rewrite `public.has_capability`, replace the `invitations.role_code` check.

**Database tests (create):**
- `scripts/tests/organization-read-only-role-test.sh` — bash + python3 contract test that asserts enum membership, constraint behaviour, and `has_capability` results for the new role.

**Database tests (modify):**
- `scripts/tests/song-crud-write-contract-test.sh` — add a read-only-user case that asserts every write fails with the expected capability-denied error.
- `scripts/tests/planning-write-contract-test.sh` — add a read-only-user case that asserts every plan / session / session-item write fails.

**Flutter (create):**
- `apps/lyron_app/lib/src/application/auth/capability_resolver.dart` — Riverpod provider that resolves the active organization's capabilities for the signed-in user via `public.has_capability`, with cache invalidation on auth or membership change.
- `apps/lyron_app/test/src/application/auth/capability_resolver_test.dart` — unit tests for the resolver.

**Flutter (modify):**
- `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart` — wrap the create / import / edit / delete affordances in a capability gate.
- `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart` — refuse to enter edit mode for users without `Capability.editSongs`.
- `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart` — gate plan create.
- `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart` — gate plan edit, session create / edit / delete, session-item add / reorder / delete.
- `apps/lyron_app/test/src/presentation/song_library/song_list_screen_test.dart` (and existing equivalents for the screens above) — assert that the gated affordances are not rendered when the relevant capability is missing.

**Documentation (modify):**
- `docs/domain/domain-model.md` — list `organization_read_only` in the role enumeration and capability narrative.

---

## Conventions And Local Test Bootstrap

Every database test in this plan reuses the existing harness:

```bash
./scripts/supabase.sh start >/dev/null
./scripts/db-reset.sh >/dev/null
./scripts/provision-local-demo-user.sh >/dev/null
```

The provisioning script creates `demo@lyron.local` and an organization-scoped admin membership. The new tests below add a second auth user (`guest@lyron.local`) and an `organization_read_only` membership before exercising assertions.

Commit cadence: one commit per task. Test-first, implementation second.

---

### Task 1: Add `organization_read_only` Enum Value (Migration A)

**Files:**
- Create: `supabase/migrations/202605250001_organization_read_only_role_enum.sql`

- [ ] **Step 1: Write the failing test**

Add a temporary assertion to verify the enum will not currently accept the new value. From the repo root:

```bash
./scripts/supabase.sh start >/dev/null
./scripts/db-reset.sh >/dev/null
./scripts/supabase.sh db query "select 'organization_read_only'::public.role_code"
```

Expected: `ERROR: invalid input value for enum public.role_code: "organization_read_only"`.

- [ ] **Step 2: Add the migration**

Create `supabase/migrations/202605250001_organization_read_only_role_enum.sql`:

```sql
alter type public.role_code add value if not exists 'organization_read_only';
```

This migration stands alone because Postgres does not allow a new enum value to be referenced by other DDL inside the same transaction.

- [ ] **Step 3: Verify the value is present**

```bash
./scripts/db-reset.sh >/dev/null
./scripts/supabase.sh db query "select 'organization_read_only'::public.role_code"
```

Expected: a row containing `organization_read_only`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/202605250001_organization_read_only_role_enum.sql
git commit -m "feat(db): add organization_read_only role enum value"
```

---

### Task 2: Constraints, Capability, And Invitations Check (Migration B)

**Files:**
- Create: `supabase/migrations/202605250002_organization_read_only_role_constraints.sql`

- [ ] **Step 1: Write the failing assertion**

```bash
./scripts/db-reset.sh >/dev/null
./scripts/supabase.sh db query "
  insert into public.memberships (organization_id, user_id, scope_type, role_code, status)
  values ('11111111-1111-1111-1111-111111111111',
          '88888888-8888-8888-8888-888888888888',
          'organization', 'organization_read_only', 'active');
"
```

Expected: `ERROR: new row for relation \"memberships\" violates check constraint \"memberships_role_scope_consistency\"`.

- [ ] **Step 2: Add the migration**

Create `supabase/migrations/202605250002_organization_read_only_role_constraints.sql`:

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

create or replace function public.has_capability(
  target_organization_id uuid,
  capability text,
  target_group_id uuid default null
)
returns boolean
language plpgsql
stable
as $$
declare
  matched_role public.role_code;
begin
  select membership.role_code
  into matched_role
  from public.memberships as membership
  where membership.user_id = auth.uid()
    and membership.organization_id = target_organization_id
    and membership.status = 'active'
    and (
      membership.scope_type = 'organization'
      or (target_group_id is not null and membership.group_id = target_group_id)
    )
  order by case membership.role_code
    when 'organization_admin' then 1
    when 'group_admin' then 2
    when 'organization_member' then 3
    when 'group_member' then 4
    when 'organization_read_only' then 5
    when 'group_read_only' then 6
    else 7
  end
  limit 1;

  if matched_role is null then
    return false;
  end if;

  return case capability
    when 'canViewSongs' then matched_role in (
      'organization_admin',
      'organization_member',
      'organization_read_only',
      'group_admin',
      'group_member',
      'group_read_only'
    )
    when 'canEditSongs' then matched_role in (
      'organization_admin',
      'organization_member',
      'group_admin',
      'group_member'
    )
    when 'canManageOrganizationMembers' then matched_role = 'organization_admin'
    when 'canManageGroupMembers' then matched_role in (
      'organization_admin',
      'group_admin'
    )
    when 'canEditSessions' then matched_role in (
      'organization_admin',
      'organization_member',
      'group_admin',
      'group_member'
    )
    when 'canManagePlans' then matched_role in (
      'organization_admin',
      'organization_member',
      'group_admin',
      'group_member'
    )
    else false
  end;
end;
$$;

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

Note: the original `invitations.role_code` check is an unnamed inline column check. If `\d public.invitations` reports a generated name other than `invitations_role_code_check`, drop by that generated name instead. The `db-reset` step will reveal the actual name after Task 1.

- [ ] **Step 3: Verify the insert now succeeds**

```bash
./scripts/db-reset.sh >/dev/null
./scripts/supabase.sh db query "
  insert into public.memberships (organization_id, user_id, scope_type, role_code, status)
  values ('11111111-1111-1111-1111-111111111111',
          '88888888-8888-8888-8888-888888888888',
          'organization', 'organization_read_only', 'active')
  returning role_code;
"
```

Expected: a row containing `organization_read_only`.

- [ ] **Step 4: Verify the cross-scope insert still fails**

```bash
./scripts/supabase.sh db query "
  insert into public.memberships (organization_id, user_id, group_id, scope_type, role_code, status)
  values ('11111111-1111-1111-1111-111111111111',
          '88888888-8888-8888-8888-888888888888',
          '22222222-2222-2222-2222-222222222222',
          'group', 'organization_read_only', 'active');
"
```

Expected: `ERROR: ... memberships_role_scope_consistency`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202605250002_organization_read_only_role_constraints.sql
git commit -m "feat(db): wire organization_read_only into role constraints, capability, invitations"
```

---

### Task 3: Capability Regression Test Script

**Files:**
- Create: `scripts/tests/organization-read-only-role-test.sh`

- [ ] **Step 1: Write the failing test**

Create the script with assertions that depend on Migration B. Skipping bootstrap when the parent harness has already started Supabase:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

if [[ "${BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP:-0}" != "1" ]]; then
  ./scripts/supabase.sh start >/dev/null
  ./scripts/db-reset.sh >/dev/null
  ./scripts/provision-local-demo-user.sh >/dev/null
fi

db_container_name="$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1)"

if [[ -z "$db_container_name" ]]; then
  echo "Could not find the local Supabase database container." >&2
  exit 1
fi

python3 - "$db_container_name" <<'PY'
import subprocess
import sys
from textwrap import dedent

container = sys.argv[1]
org_id = "11111111-1111-1111-1111-111111111111"
guest_id = "77777777-7777-7777-7777-777777777777"

def run_sql(sql, expect_error=False):
    cmd = ["docker", "exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres",
           "-v", "ON_ERROR_STOP=1", "-c", sql]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if expect_error:
        if result.returncode == 0:
            raise SystemExit(f"expected failure, got success for: {sql}")
        return result.stderr
    if result.returncode != 0:
        raise SystemExit(f"sql failed: {sql}\nstderr: {result.stderr}")
    return result.stdout

# 1. Enum value is present.
out = run_sql("select 'organization_read_only'::public.role_code;")
assert "organization_read_only" in out, out

# 2. Org-scope insert succeeds; group-scope insert fails.
run_sql(dedent(f"""
    insert into auth.users (id, email)
      values ('{guest_id}', 'guest@lyron.local')
      on conflict (id) do nothing;
    insert into public.memberships
      (organization_id, user_id, scope_type, role_code, status)
    values
      ('{org_id}', '{guest_id}', 'organization', 'organization_read_only', 'active')
      on conflict do nothing;
"""))

err = run_sql(dedent(f"""
    insert into public.memberships
      (organization_id, user_id, group_id, scope_type, role_code, status)
    values
      ('{org_id}', '{guest_id}',
       '22222222-2222-2222-2222-222222222222',
       'group', 'organization_read_only', 'active');
"""), expect_error=True)
assert "memberships_role_scope_consistency" in err, err

# 3. has_capability returns true for canViewSongs and false for writes when
#    auth.uid() is the guest user.
def cap(name, group_id="null"):
    return run_sql(dedent(f"""
        set local "request.jwt.claim.sub" to '{guest_id}';
        select public.has_capability('{org_id}', '{name}', {group_id});
    """))

assert " t" in cap("canViewSongs"), cap("canViewSongs")
for write_cap in ("canEditSongs", "canManagePlans", "canEditSessions",
                  "canManageOrganizationMembers", "canManageGroupMembers"):
    out = cap(write_cap)
    assert " f" in out, (write_cap, out)

# 4. Invitations check accepts the new role and rejects unknown ones.
run_sql(dedent(f"""
    insert into public.invitations
      (token, organization_id, role_code, expires_at)
    values
      ('test-guest-token', '{org_id}', 'organization_read_only',
       timezone('utc', now()) + interval '7 days');
"""))

err = run_sql(dedent(f"""
    insert into public.invitations
      (token, organization_id, role_code, expires_at)
    values
      ('test-group-token', '{org_id}', 'group_member',
       timezone('utc', now()) + interval '7 days');
"""), expect_error=True)
assert "invitations_role_code_check" in err, err

print("organization-read-only-role-test OK")
PY
```

- [ ] **Step 2: Make the script executable and run it**

```bash
chmod +x scripts/tests/organization-read-only-role-test.sh
./scripts/tests/organization-read-only-role-test.sh
```

Expected output: `organization-read-only-role-test OK`.

- [ ] **Step 3: Wire into the backend contract runner**

Add a new dispatch line to `scripts/backend-write-contracts.sh` after the existing dispatches:

```bash
organization_read_only_test_script="${ORGANIZATION_READ_ONLY_TEST_SCRIPT:-./scripts/tests/organization-read-only-role-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$organization_read_only_test_script"
```

- [ ] **Step 4: Run the umbrella script**

```bash
./scripts/backend-write-contracts.sh
```

Expected: all three tests print OK lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/organization-read-only-role-test.sh scripts/backend-write-contracts.sh
git commit -m "test(db): assert organization_read_only role grants read-only access"
```

---

### Task 4: Extend Song Write-Contract Test With Read-Only Denial

**Files:**
- Modify: `scripts/tests/song-crud-write-contract-test.sh`

- [ ] **Step 1: Read the existing script and locate the python block**

The script provisions a demo admin user and runs SQL through a python heredoc. Identify the section that exercises `upsert_song` / `delete_song`.

- [ ] **Step 2: Write the failing extension**

Inside the existing python heredoc, after the admin-success cases, add a read-only-user block:

```python
guest_id = "77777777-7777-7777-7777-777777777777"

run_sql(dedent(f"""
    insert into auth.users (id, email)
      values ('{guest_id}', 'guest@lyron.local')
      on conflict (id) do nothing;
    insert into public.memberships
      (organization_id, user_id, scope_type, role_code, status)
    values
      ('{organization_id}', '{guest_id}', 'organization', 'organization_read_only', 'active')
      on conflict do nothing;
"""))

for sql in [
    dedent(f"""
        set local "request.jwt.claim.sub" to '{guest_id}';
        select public.upsert_song(
          target_organization_id => '{organization_id}',
          song_id => gen_random_uuid(),
          title => 'guest write attempt',
          chordpro_source => '',
          payload => '{{}}'::jsonb
        );
    """),
    dedent(f"""
        set local "request.jwt.claim.sub" to '{guest_id}';
        select public.delete_song(
          target_organization_id => '{organization_id}',
          song_id => gen_random_uuid()
        );
    """),
]:
    err = run_sql(sql, expect_error=True)
    assert "canEditSongs" in err or "capability" in err.lower(), err
```

Use the actual function signatures and error fragments observed in `202604080001_song_crud_write_contract.sql`. If the existing tests assert on a specific error code or message, mirror that exact string.

- [ ] **Step 3: Run the test**

```bash
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=0 \
  bash scripts/tests/song-crud-write-contract-test.sh
```

Expected: the script exits 0 and prints its existing OK line.

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/song-crud-write-contract-test.sh
git commit -m "test(db): assert organization_read_only is denied song writes"
```

---

### Task 5: Extend Planning Write-Contract Test With Read-Only Denial

**Files:**
- Modify: `scripts/tests/planning-write-contract-test.sh`

- [ ] **Step 1: Read the script and find the success cases for plan / session / session_item writes**

- [ ] **Step 2: Add a read-only-user block mirroring Task 4**

Insert after the existing positive cases:

```python
guest_id = "77777777-7777-7777-7777-777777777777"

run_sql(dedent(f"""
    insert into auth.users (id, email)
      values ('{guest_id}', 'guest@lyron.local')
      on conflict (id) do nothing;
    insert into public.memberships
      (organization_id, user_id, scope_type, role_code, status)
    values
      ('{organization_id}', '{guest_id}', 'organization', 'organization_read_only', 'active')
      on conflict do nothing;
"""))

write_attempts = [
    # Plan create
    dedent(f"""
        set local "request.jwt.claim.sub" to '{guest_id}';
        select public.upsert_plan(
          target_organization_id => '{organization_id}',
          plan_id => gen_random_uuid(),
          payload => '{{"title":"guest"}}'::jsonb
        );
    """),
    # Session create
    dedent(f"""
        set local "request.jwt.claim.sub" to '{guest_id}';
        select public.upsert_session(
          target_organization_id => '{organization_id}',
          session_id => gen_random_uuid(),
          payload => '{{"title":"guest"}}'::jsonb
        );
    """),
    # Session-item create
    dedent(f"""
        set local "request.jwt.claim.sub" to '{guest_id}';
        select public.upsert_session_item(
          target_organization_id => '{organization_id}',
          session_id => '{seeded_session_id}',
          session_item_id => gen_random_uuid(),
          payload => '{{}}'::jsonb
        );
    """),
]

for sql in write_attempts:
    err = run_sql(sql, expect_error=True)
    assert "capability" in err.lower(), err
```

Adjust function names and parameters to match the actual signatures defined in `202604100001_planning_write_contract.sql` and `202604110001_planning_session_item_write_contract.sql`. Reuse the `seeded_session_id` variable already established earlier in the script; if not present, create a session as admin first and capture its id.

- [ ] **Step 3: Run the test**

```bash
bash scripts/tests/planning-write-contract-test.sh
```

Expected: script exits 0 with its existing OK line.

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/planning-write-contract-test.sh
git commit -m "test(db): assert organization_read_only is denied plan/session writes"
```

---

### Task 6: Capability Resolver Provider

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/capability_resolver.dart`
- Create: `apps/lyron_app/test/src/application/auth/capability_resolver_test.dart`

- [ ] **Step 1: Write the failing test**

Create `apps/lyron_app/test/src/application/auth/capability_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/capability_resolver.dart';
import 'package:lyron_app/src/domain/core/capability.dart';

class _FakeCapabilityGateway implements CapabilityGateway {
  _FakeCapabilityGateway(this._capabilities);
  final Set<Capability> _capabilities;
  int calls = 0;

  @override
  Future<Set<Capability>> resolve(String organizationId) async {
    calls += 1;
    return _capabilities;
  }
}

void main() {
  test('caches resolved capabilities per organization id', () async {
    final gateway = _FakeCapabilityGateway({Capability.viewSongs});
    final resolver = CapabilityResolver(gateway: gateway);

    final first = await resolver.capabilitiesFor('org-1');
    final second = await resolver.capabilitiesFor('org-1');

    expect(first, equals({Capability.viewSongs}));
    expect(second, equals({Capability.viewSongs}));
    expect(gateway.calls, equals(1));
  });

  test('invalidate clears the cache', () async {
    final gateway = _FakeCapabilityGateway({Capability.viewSongs});
    final resolver = CapabilityResolver(gateway: gateway);

    await resolver.capabilitiesFor('org-1');
    resolver.invalidate();
    await resolver.capabilitiesFor('org-1');

    expect(gateway.calls, equals(2));
  });

  test('hasCapability returns false when capability is missing', () async {
    final gateway = _FakeCapabilityGateway({Capability.viewSongs});
    final resolver = CapabilityResolver(gateway: gateway);

    expect(await resolver.hasCapability('org-1', Capability.editSongs), isFalse);
    expect(await resolver.hasCapability('org-1', Capability.viewSongs), isTrue);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd apps/lyron_app
flutter test test/src/application/auth/capability_resolver_test.dart
```

Expected: compilation error — `CapabilityResolver` / `CapabilityGateway` not found.

- [ ] **Step 3: Implement the resolver**

Create `apps/lyron_app/lib/src/application/auth/capability_resolver.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/core/capability.dart';

abstract class CapabilityGateway {
  Future<Set<Capability>> resolve(String organizationId);
}

class SupabaseCapabilityGateway implements CapabilityGateway {
  SupabaseCapabilityGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<Set<Capability>> resolve(String organizationId) async {
    final results = <Capability>{};
    for (final capability in Capability.values) {
      final response = await _client.rpc<bool>(
        'has_capability',
        params: {
          'target_organization_id': organizationId,
          'capability': capability.code,
        },
      );
      if (response == true) {
        results.add(capability);
      }
    }
    return results;
  }
}

class CapabilityResolver extends ChangeNotifier {
  CapabilityResolver({required CapabilityGateway gateway}) : _gateway = gateway;

  final CapabilityGateway _gateway;
  final Map<String, Set<Capability>> _cache = {};

  Future<Set<Capability>> capabilitiesFor(String organizationId) async {
    final cached = _cache[organizationId];
    if (cached != null) {
      return cached;
    }
    final resolved = await _gateway.resolve(organizationId);
    _cache[organizationId] = resolved;
    return resolved;
  }

  Future<bool> hasCapability(String organizationId, Capability capability) async {
    final set = await capabilitiesFor(organizationId);
    return set.contains(capability);
  }

  void invalidate() {
    _cache.clear();
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
flutter test test/src/application/auth/capability_resolver_test.dart
```

Expected: all three tests pass.

- [ ] **Step 5: Register the provider**

Add to `apps/lyron_app/lib/src/application/providers.dart` (alongside the other Riverpod providers — follow the existing patterns there):

```dart
final capabilityResolverProvider = ChangeNotifierProvider<CapabilityResolver>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final resolver = CapabilityResolver(gateway: SupabaseCapabilityGateway(client));
  ref.listen(authStateChangesProvider, (_, __) => resolver.invalidate());
  ref.listen(activeOrganizationProvider, (_, __) => resolver.invalidate());
  return resolver;
});
```

If `supabaseClientProvider`, `authStateChangesProvider`, or `activeOrganizationProvider` do not exist under those exact names, follow the names already established in the file. The invalidation hooks are required so a sign-in, sign-out, or active-organization swap clears stale capabilities.

- [ ] **Step 6: Commit**

```bash
git add \
  apps/lyron_app/lib/src/application/auth/capability_resolver.dart \
  apps/lyron_app/test/src/application/auth/capability_resolver_test.dart \
  apps/lyron_app/lib/src/application/providers.dart
git commit -m "feat(app): add capability resolver provider backed by has_capability"
```

---

### Task 7: Gate Song UI On `Capability.editSongs`

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart`
- Modify (or create): `apps/lyron_app/test/src/presentation/song_library/song_list_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

In `song_list_screen_test.dart`, add:

```dart
testWidgets('hides create / import / edit affordances without canEditSongs',
    (tester) async {
  final container = ProviderContainer(overrides: [
    capabilityResolverProvider.overrideWith((ref) =>
        CapabilityResolver(gateway: _StaticGateway({Capability.viewSongs}))),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: SongListScreen()),
  ));
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('song-create-button')), findsNothing);
  expect(find.byKey(const Key('song-import-button')), findsNothing);
});
```

`_StaticGateway` is a small test double that returns the configured capability set synchronously. Define it alongside other shared test doubles or inline at the top of the file.

- [ ] **Step 2: Run the test to confirm it fails**

```bash
flutter test test/src/presentation/song_library/song_list_screen_test.dart
```

Expected: assertion failure because the affordances are currently rendered unconditionally.

- [ ] **Step 3: Add capability gating helpers**

Add a small consumer widget in `song_list_screen.dart`:

```dart
class _IfCapability extends ConsumerWidget {
  const _IfCapability({
    required this.capability,
    required this.organizationId,
    required this.child,
  });

  final Capability capability;
  final String organizationId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolver = ref.watch(capabilityResolverProvider);
    return FutureBuilder<bool>(
      future: resolver.hasCapability(organizationId, capability),
      builder: (context, snap) => snap.data == true ? child : const SizedBox.shrink(),
    );
  }
}
```

Wrap the create button, the ChordPro import button, and the per-row edit / delete actions in `_IfCapability(capability: Capability.editSongs, organizationId: activeOrganizationId, child: ...)`.

Add corresponding `Key` values (`song-create-button`, `song-import-button`, `song-row-edit`, `song-row-delete`) so the widget tests can target them precisely.

- [ ] **Step 4: Gate `song_editor_screen.dart`**

At the top of the editor's `build`, resolve `Capability.editSongs`. If the user lacks it, return a read-only viewer (existing reader screen) or pop with a snackbar. Add a `Key('song-editor-write-blocked')` indicator widget so tests can assert the gate.

- [ ] **Step 5: Run the tests**

```bash
flutter test test/src/presentation/song_library/song_list_screen_test.dart
flutter test test/src/presentation/song_editor/
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_library/ \
        apps/lyron_app/lib/src/presentation/song_editor/ \
        apps/lyron_app/test/src/presentation/song_library/
git commit -m "feat(app): gate song write affordances on canEditSongs"
```

---

### Task 8: Gate Plan And Session UI On `Capability.managePlans` / `Capability.editSessions`

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify (or create): `apps/lyron_app/test/src/presentation/planning/plan_list_screen_test.dart`
- Modify (or create): `apps/lyron_app/test/src/presentation/planning/plan_detail_screen_test.dart`

- [ ] **Step 1: Write the failing widget tests**

For `plan_list_screen_test.dart`:

```dart
testWidgets('hides plan create button without canManagePlans', (tester) async {
  final container = ProviderContainer(overrides: [
    capabilityResolverProvider.overrideWith((ref) =>
        CapabilityResolver(gateway: _StaticGateway({Capability.viewSongs}))),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: PlanListScreen()),
  ));
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('plan-create-button')), findsNothing);
});
```

For `plan_detail_screen_test.dart`: assert `plan-edit-button`, `session-create-button`, `session-delete-button`, `session-item-add-button`, `session-item-delete-button` are absent without the relevant capabilities.

- [ ] **Step 2: Confirm the tests fail**

```bash
flutter test test/src/presentation/planning/plan_list_screen_test.dart
flutter test test/src/presentation/planning/plan_detail_screen_test.dart
```

Expected: assertion failures.

- [ ] **Step 3: Wrap the affordances in `_IfCapability`**

Reuse the `_IfCapability` helper from Task 7 (lift it to a shared file such as `apps/lyron_app/lib/src/presentation/shared/if_capability.dart` once it is needed in two screens; update Task 7's imports accordingly).

- In `plan_list_screen.dart` line ~40: wrap the create FAB with `Capability.managePlans`.
- In `plan_detail_screen.dart`:
  - line ~60: wrap the edit-plan button with `Capability.managePlans`.
  - line ~64: wrap the create-session button with `Capability.editSessions`.
  - line ~543: wrap the delete-session button with `Capability.editSessions`.
  - line ~1231: wrap the delete-session-item button with `Capability.editSessions`.
  - Wrap the session-item add / reorder controls with `Capability.editSessions`.
- Add the `Key` values referenced in Step 1.

- [ ] **Step 4: Run the tests**

```bash
flutter test test/src/presentation/planning/
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/planning/ \
        apps/lyron_app/lib/src/presentation/shared/if_capability.dart \
        apps/lyron_app/test/src/presentation/planning/
git commit -m "feat(app): gate plan and session write affordances on capabilities"
```

---

### Task 9: Combined-Membership Priority Regression Test

**Files:**
- Modify: `scripts/tests/organization-read-only-role-test.sh`

- [ ] **Step 1: Add the failing case**

A guest who is also a `group_member` in the same organization must retain group-scope write capability. After the existing assertions in the test script, append:

```python
group_id = "22222222-2222-2222-2222-222222222222"

run_sql(dedent(f"""
    insert into public.memberships
      (organization_id, group_id, user_id, scope_type, role_code, status)
    values
      ('{org_id}', '{group_id}', '{guest_id}', 'group', 'group_member', 'active')
      on conflict do nothing;
"""))

# When asked about the group scope, the group_member capability must win.
out = run_sql(dedent(f"""
    set local "request.jwt.claim.sub" to '{guest_id}';
    select public.has_capability('{org_id}', 'canEditSessions', '{group_id}');
"""))
assert " t" in out, out

# When asked about the organization scope (no group_id), org_read_only still wins.
out = run_sql(dedent(f"""
    set local "request.jwt.claim.sub" to '{guest_id}';
    select public.has_capability('{org_id}', 'canEditSongs');
"""))
assert " f" in out, out

print("organization-read-only-role-test combined-membership OK")
```

- [ ] **Step 2: Run the script**

```bash
./scripts/tests/organization-read-only-role-test.sh
```

Expected: both OK lines printed.

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/organization-read-only-role-test.sh
git commit -m "test(db): assert priority ordering when guest also holds group_member"
```

---

### Task 10: Domain Documentation Update

**Files:**
- Modify: `docs/domain/domain-model.md`

- [ ] **Step 1: Add the new role to the membership section**

Inside the role enumeration narrative (around line 55–65 and again under the `Capability Model` section near line 354), document `organization_read_only` explicitly:

- list it alongside `organization_admin` and `organization_member` where org-scope roles are enumerated;
- note that it grants `canViewSongs` only and explicitly does not grant any write capability;
- note that invitations may carry this role and that redemption produces an org-scope membership accordingly.

- [ ] **Step 2: Verify rendering**

```bash
git diff docs/domain/domain-model.md | head -80
```

Expected: clean diff that adds the new role wording without altering unrelated paragraphs.

- [ ] **Step 3: Commit**

```bash
git add docs/domain/domain-model.md
git commit -m "docs(domain): document organization_read_only role and capabilities"
```

---

## Final Verification

- [ ] **Step 1: Full backend contract pass**

```bash
./scripts/backend-write-contracts.sh
```

Expected: all three scripts (`planning-write-contract`, `song-crud-write-contract`, `organization-read-only-role`) print OK.

- [ ] **Step 2: Full Flutter test suite**

```bash
cd apps/lyron_app
flutter test
```

Expected: pass.

- [ ] **Step 3: Local CI parity check**

```bash
./scripts/run-ci-locally.sh
```

Expected: pass.

- [ ] **Step 4: Confirm branch state**

```bash
git log --oneline origin/main..HEAD
```

Expected: ten commits, in the order Task 1 → Task 10, each scoped to its files.
