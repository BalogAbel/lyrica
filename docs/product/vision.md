# Product Vision

## Summary

Lyron Chords helps worship and music teams prepare, organize, and run services with reliable access to songs and plans even when connectivity is poor or unavailable for extended periods.

## Product Principles

1. Offline operation is a first-class requirement.
2. Operational simplicity matters more than exposing raw domain complexity.
3. Canonical data formats must remain durable and portable.
4. Collaboration must work across devices without making users think about infrastructure.
5. Authorization must preserve organizational boundaries and editing safety.

## MVP Outcomes

- Teams can sign in, browse a simple song list, and read ChordPro-backed songs on tablet-first layouts.
- Song content remains readable without exposing raw ChordPro source, PDF rendering, or staff notation.
- The first slice validates reader controls such as chord visibility, semitone transposition, shared font scaling, and visible song structure.
- The first executable backend slice validates authenticated song reads against organization-scoped Supabase data without moving ChordPro parsing or reader rendering out of the app.
- The next executable local-first read slice validates that the latest successfully fetched authenticated song catalog remains readable offline from a current user-owned active-organization cache, with automated proof centered on persistent cache reopen behavior and native offline relaunch acceptance centered on manual validation on Flutter targets.
- The next planned offline mutation slice validates that songs can be fully managed (Create, Update, Delete) locally and safely synchronized to the backend utilizing optimistic concurrency control, manual conflict resolution, and UUID v4 primary keys.
- The first executable planning slice validates a simplified `plan -> session -> session_items` hierarchy with real seeded Supabase data and a minimal signed-in read-only plan list/detail flow.
- The current planning write slice validates that plan create/edit and session create/rename/delete are recorded locally first, rendered through merged planning views immediately, persisted across restart, and cleared on explicit sign-out when they remain unsynced.
- The architecture preserves the repository, parser, and offline boundaries needed for later offline editing, sync, and planning workflows.
- Android, iOS, and Web share a coherent product model and workflow vocabulary.
- If durable offline desktop use becomes important later, it should be addressed through Flutter desktop rather than expanding the browser slice beyond best-effort offline relaunch.
- Authorization decisions remain backend-owned even when the UI exposes role-aware affordances.

## Non-Goals For MVP

- Desktop-specific UX
- Real-time co-editing
- Song sharing between organizations
- FreeShow runtime integration
- Rich visual chord editing
- Song editing, import, or persisted reader preferences in the first slice
- Automatic conflict merging beyond explicit manual resolution

## UX Direction

The domain model remains expressive internally, while the UI presents guided actions and simple mental models. For example, future planning creation should gather the plan and session names instead of exposing the entire session/session_item structure up front.

## Operating Constraints

- Organizations are the top-level tenant boundary for all business data.
- Group-scoped workflows narrow access inside an organization but never bypass organization scope.
- ChordPro remains the canonical editable song representation, while attachments stay supplemental.
- The MVP favors stable, inspectable workflows over automation-heavy collaboration features.
- Explicit sign-out must remove authenticated cached song and planning access instead of leaving a device-global local archive.
