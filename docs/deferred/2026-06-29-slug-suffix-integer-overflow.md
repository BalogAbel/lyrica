# Slug Suffix Integer Overflow in Planning Write Contract (product bug)

**Found by:** local-first-validation slice (live two-device integration run)
**Severity:** real bug, security-adjacent (user/attacker-controlled input)
**Area:** backend write contracts (slug generation) — separate subsystem from this slice's
offline/sync seam, so deferred to a focused fix rather than folded into the validation PR.

## The bug

`supabase/migrations/202604100001_planning_write_contract.sql` defines `plan_next_slug`
(line ~56) and `session_next_slug` (line ~90), each containing:

```sql
slug_number := substring(normalized_base_slug from '([0-9]+)$')::integer;
```

The trailing digit run of a slugified name is cast straight to `integer` (int4) with **no
bounds check and no exception handling**. Any plan/session name ending in a number
≥ 2_147_483_648 overflows the cast and raises an unhandled Postgres `22003`
("value ... is out of range for type integer").

## Repro / impact

- A name ending in a large number — e.g. `DateTime.now().microsecondsSinceEpoch` (16 digits),
  or any user-typed name like "Set 99999999999" — triggers it.
- Observed live: `value "1782711809759068" is out of range for type integer`.
- The error surfaces to the client as a raw `PostgrestException`, mapped to
  `PlanningMutationSyncErrorCode.unknown`. The offline mutation then stays `pending` with a
  generic "unknown" error and **no user-facing explanation** — effectively a silent failure to
  create the plan/session.
- Because the name is user-controlled (and could be attacker-controlled via shared orgs), this
  is a denial-of-write vector, not just a rare edge case.

## Suggested fix

Make the suffix parse overflow-safe in both functions. Options:
- Bound the regex to a safe digit count, or cast to `bigint`/`numeric` and clamp, or
- Wrap the cast in a `BEGIN ... EXCEPTION WHEN numeric_value_out_of_range THEN slug_number := 1; END;`
  block so a non-parseable/oversized suffix falls back to starting at 1.

Ship as a NEW migration (do not edit the shipped `202604100001` migration), add a backend
write-contract test (`scripts/backend-write-contracts.sh` / the planning write-contract test)
covering a large-numeric-suffix name, and run the migration-lint gate.

## Workaround already in place

`two_device_conflict_matrix_test.dart` dodges the bug by prefixing its scratch-session name
suffix with a non-digit (`run$runId` instead of `$runId`); a comment at the create-session
call site documents this. Remove the workaround once the backend is fixed.
