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

- Teams can view, create, and edit songs offline.
- Teams can create and manage plans, events, sessions, and session items offline.
- Data can remain usable for at least one week without internet access.
- Sync conflicts are surfaced explicitly and resolved manually in the MVP.
- Android, iOS, and Web share a coherent product model and workflow vocabulary.
- Authorization decisions remain backend-owned even when the UI exposes role-aware affordances.

## Non-Goals For MVP

- Desktop-specific UX
- Real-time co-editing
- Song sharing between organizations
- FreeShow runtime integration
- Rich visual chord editing
- Automatic conflict merging beyond explicit manual resolution

## UX Direction

The domain model remains expressive internally, while the UI presents guided actions and simple mental models. For example, "new list" should gather the event and session names instead of exposing the entire event/session/session_item structure up front.

## Operating Constraints

- Organizations are the top-level tenant boundary for all business data.
- Group-scoped workflows narrow access inside an organization but never bypass organization scope.
- ChordPro remains the canonical editable song representation, while attachments stay supplemental.
- The MVP favors stable, inspectable workflows over automation-heavy collaboration features.
