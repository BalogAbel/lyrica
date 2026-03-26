# Product Vision

## Summary

Lyrica helps worship and music teams prepare, organize, and run services with reliable access to songs and plans even when connectivity is poor or unavailable for extended periods.

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
- The next executable local-first read slice validates that the latest successfully fetched authenticated song catalog remains readable offline from a current user-owned active-organization cache, with hard offline relaunch guarantees centered on native Flutter targets.
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

The domain model remains expressive internally, while the UI presents guided actions and simple mental models. For example, "new list" should gather the event and session names instead of exposing the entire event/session/session_item structure up front.

## Operating Constraints

- Organizations are the top-level tenant boundary for all business data.
- Group-scoped workflows narrow access inside an organization but never bypass organization scope.
- ChordPro remains the canonical editable song representation, while attachments stay supplemental.
- The MVP favors stable, inspectable workflows over automation-heavy collaboration features.
- Explicit sign-out must remove authenticated cached song access instead of leaving a device-global local archive.
