# Session-Transition Coordinator

**Found:** 2026-10-11, while specifying `fix/reauth-wipe-recount`
(`docs/specs/2026-10-11-reauth-wipe-recount.md`).
**Related:** ADR-020, ADR-029, ADR-035 (D5.5's concurrency model), ADR-037
(current-user ownership), `docs/specs/2026-10-07-sign-out-pending-work-guard.md`,
`docs/deferred/2026-10-09-sign-out-guard-residuals.md` (R1–R17).

**Status:** architecture direction only. Not implemented, and not to be
implemented as part of a residual fix without its own spec.

## Problem

Four flows change whose local data the device holds, and each one runs as its
own process with its own guards:

| flow | where it runs | its own guards |
|---|---|---|
| explicit sign-out | `SignOutCommand` (count, dialog, holder purges), then `AppAuthController.signOut()`, then the `signedOut` listeners and the identity clear on the identity resolution chain | command lock, SO6's per-step `isStillCountedUser`, SO7's import refusal, SO4's `CurrentUserOwnership`, `_isSigningOut` |
| different-user reauth | `lastKnownIdentityPersistenceProvider`'s serial resolution chain: count, prompt, wipe | generation epoch plus live-session currentness (ADR-029 D3), prompt supersession, RW2's recount, RW3's import check |
| reauth cancel | `AppAuthController.cancelReauthToPriorSession` | `_pendingReauthCancelSession` and its generation |
| purge (D1, D5 membership revocation) | `LocalDataLifecycle`'s chain and the verified-empty coordinator; catalog and planning purge handlers | D5.5's six rules: one chain, no dialog inside it, re-validation on re-entry |

Each guard is correct for the flow it was written for. The defects come from
overlaps between flows, where one flow's guard does not know about the other
flow:

- **R1:** a sign-in lands inside `signOut()`.
- **R2:** a sign-out overlaps an in-flight reauth cancel.
- **R3:** the sign-out identity clear queues behind a signed-in resolution.
- **R5:** the ownership is lost on a provider rebuild.
- **R9:** the reauth host pops the sign-out dialog.
- **R10, R16:** import rows outlive the user they were captured for.
- **R12:** planning state after a superseded sign-out.
- **R14:** Delete account during a token refresh.
- **R17:** a duplicate-resolution commit lands in the next user's catalog.
- **The reauth wipe that did not recount.** It was fixed by RW2/RW3 as one
  more local guard, which is the pattern this entry questions.

Every fix so far added one more local check, and each review round of the
sign-out PR found a hole in the previous round's check
(`docs/specs/2026-10-07-sign-out-pending-work-guard.md`, B1–B3 and round 2).

## Proposed direction

One serialized transition chain, modelled on `LocalDataLifecycle`'s chain
(D5.5):

- **One chain, global.** Not keyed by user, because the identity row is
  global.
- **Every transition is an entry with the same shape.** Each of sign-out,
  different-user resolution, reauth cancel, Delete account and purge does
  the following:
  1. capture its premises (the current user, the counts) inside the chain;
  2. leave the chain for any dialog;
  3. re-enter and re-validate every premise;
  4. act, or decline.
- **Background writers register with the coordinator.** The ChordPro import
  is the only one today. "No destructive transition while a writer for the
  affected user runs" then becomes one rule instead of SO7 plus RW3.
- **Auth edges stay events.** The coordinator orders the reactions to them;
  it does not replace gotrue's stream or the `AppAuthController` state
  machine.

Expected effect: R1, R2, R3, R9, R12 and the recount class disappear as
interleavings instead of being guarded one by one. R10, R16 and R17 reduce
to the writer-registration rule.

## Trigger

Re-evaluate when either of these happens:

- the next time an R-residual from
  `docs/deferred/2026-10-09-sign-out-guard-residuals.md` is picked up;
- a new auth flow is added (account switching, a new sign-in method,
  multi-account).

Before adding another local guard at that point, write the coordinator spec.

Roadmap (2026-10-12): stays trigger-gated (S9). Closing R8 and R15 in S6a did not trigger it: they were feedback fixes, not transition guards. The S3 brainstorm re-evaluates it before S3 adds another local guard around a purge.
