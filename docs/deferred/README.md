# Deferred Work

This directory records intentionally deferred work that is important enough to remain visible in the repository, but was not shipped inside the originating slice.

Use this directory for deferred items that meet all of these conditions:

- They affect correctness, sync semantics, authorization boundaries, or other durable product behavior.
- They were consciously left out of the current slice instead of being forgotten.
- They need to influence future planning, not just ad hoc implementation.

Do not use this directory as a generic idea dump or a replacement for issue tracking. Keep entries narrow, technical, and tied to a concrete slice or shipped behavior.

## Planning Rule

- Before writing or approving a new slice plan, review any relevant files in `docs/deferred/`.
- If a deferred item touches the same workflow, state machine, or backend contract as the new slice, treat it as priority work rather than optional polish.
- Close deferred correctness and sync-consistency gaps as soon as a related slice re-enters that area of the system.

## Tracking Rule

- Keep the durable context in this repository directory.
- Track execution separately in GitHub issues or pull requests when active work begins.
- Remove or update the deferred entry in the same change that resolves or supersedes it.
