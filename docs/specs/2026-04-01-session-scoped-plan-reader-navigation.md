# Session-Scoped Plan Reader Navigation Spec

> Status: Implemented on branch `feat/session-scoped-plan-reader-navigation`; the later slug-routing slice superseded the public route shape with `/plans/:planSlug/sessions/:sessionSlug/items/songs/:songSlug` while preserving the same internal reader-context behavior.

## Goal

Extend the existing planning and song reader flow so that song items inside plan detail open the existing song reader, and when the reader was opened from a plan session item it exposes previous and next navigation limited to that same session.

## Problem

The current planning slice proves that plans, sessions, and ordered song-backed session items can be rendered, but it stops at read-only display. The current song reader also already exists as a standalone detail route, but it has no concept of being opened from planning and no session-scoped navigation model.

That leaves a gap in the core planning workflow:

- users can see songs inside a session but cannot open them from plan detail
- once a song is open, the reader cannot move through the rest of the current session
- the browser route cannot yet preserve plan-session reader context across reload for this workflow

This slice closes that gap without expanding into broader reader navigation models.

## Scope

- Make song-backed session items inside plan detail explicitly tappable.
- Open the existing song reader from plan detail without introducing a second reader screen.
- Add session-scoped reader context for plan-origin navigation.
- Show previous and next reader navigation only when the reader was opened from a plan session item.
- Keep previous and next navigation strictly within the current session.
- Preserve the current reader-local state across previous and next navigation within the same in-app reading session:
  - chords and lyrics vs lyrics only
  - transpose offset
  - shared font scale
- Make the plan-origin reader route reload-safe in the browser so refreshing the page restores the same song in the same session-scoped reader context.
- Return from a plan-origin reader back to the same plan detail route.
- Preserve the prior plan detail scroll position when returning from the reader.
- Define the minimum widget, route, and integration test coverage for this slice.

## Non-Goals

- No swipe navigation.
- No cross-session navigation.
- No global catalog-based previous and next navigation.
- No new standalone planning reader screen.
- No reader UX redesign beyond adding the minimum clear session-scoped controls.
- No persisted reader preferences or restored reader-local controls after browser reload.
- No planning write actions.
- No backend authorization changes.
- No new backend capability for partial song visibility inside a readable plan.

## Product Slice Summary

This slice should prove one narrow but complete planning workflow:

1. a signed-in user opens plan detail
2. the user taps a song item inside a session
3. the existing reader opens for that song
4. the reader shows previous and next navigation for the surrounding session only
5. the user can move within the current session without returning to plan detail after every song
6. leaving the reader returns the user to the same plan detail context

This is intentionally not a general-purpose reader navigation model. It is a planning-origin reader enhancement with explicit session boundaries.

## Current Context

The current repository already establishes these relevant constraints:

- plan detail renders ordered sessions and ordered song-backed session items
- the reader is already a full-screen detail route
- the signed-in song list remains the signed-in home route
- direct song reader entry remains supported outside planning
- reader back behavior outside planning already returns to the song list when no route stack is available

This slice must preserve those existing behaviors unless the reader was opened with explicit plan-session context.

## Core Product Rules

- Every visible session item in this slice is song-backed and intended to open the reader.
- For the intended product path, repository-exposed readable plan detail items are expected to resolve to readable songs within the same organization scope.
- Session-scoped previous and next navigation must only consider items in the current session.
- Session-scoped navigation must not wrap from the last item back to the first item, or from the first item to the last item.
- The reader-local controls remain session-local runtime state only. They are preserved while moving between songs in the same running app session, but they are not persisted across browser reload.
- When the reader is opened outside planning, the new previous and next affordance must not appear.

## Routing And Context Requirements

### Reader Entry Modes

The existing reader remains the only song reader screen, but it supports two explicit entry modes:

- standard reader entry with song context only
- session-scoped reader entry with song context plus planning session context

The spec does not require a second screen, a second reader feature set, or a separate planning-reader implementation branch.

### Session-Scoped Route Context

When the reader is opened from plan detail, the route must carry enough information to reconstruct the session-scoped reader after browser reload.

The route or route-resolvable context must identify:

- the current song
- the owning plan
- the owning session
- the selected session item

This slice should prefer stable identifiers over index-only route state. Session position may still be derived at runtime from the current session data, but reload-safe restoration must not depend only on transient in-memory state.

Session-scoped navigation identity is anchored to the selected session item, not only to the song. This is required so that a session may legally contain the same song more than once without making previous and next navigation ambiguous.

The implementation must use a canonical reload-safe URL shape for required planning context. Required session-scoped context must not rely on transient router extras or other in-memory-only navigation state.

This slice standardizes on a dedicated plan-origin reader URL that carries stable identifiers in the URL itself. The exact segment layout may follow the current router conventions, but it must encode:

- `planId`
- `sessionId`
- `sessionItemId`
- `songId`

### Reload Behavior

When the browser reloads while the user is on a session-scoped reader route:

- auth restoration and online planning-data re-fetch remain prerequisites for restoring session-scoped planning context
- the same selected session item must reload when it still exists in the same readable plan-session context
- the same song content must reload for that selected session item
- the same plan-session reader context must reload when it can be re-fetched online
- previous and next neighbors must be recomputed from the latest readable ordering of the current session
- reader-local settings may reset to their default values

Reload must not drop the user back to the song list or to plan detail.

If the song content resolves but the planning context cannot be re-fetched, or if the selected session item no longer exists or no longer belongs to the declared session, the reader must show the explicit error state for invalid or unavailable session context.

### Back Behavior

When the reader was opened from plan detail and the current navigation stack still contains the originating plan detail route:

- back returns to the same plan detail route
- returning to plan detail must restore the prior scroll offset closely enough that the previously opened session item remains visible without manual re-scrolling

When the reader was opened from plan detail but there is no in-memory route stack available, such as after direct entry or browser reload:

- the reader back affordance must navigate explicitly to the canonical plan detail route for the current plan
- this no-stack fallback does not need to restore the prior scroll offset

When the reader was not opened from planning:

- existing reader back behavior remains unchanged

## Plan Detail Requirements

### Song Item Interaction

Song-backed session items inside plan detail must be rendered as explicitly interactive UI, not as plain non-interactive text.

Minimum requirement:

- each visible song item can be tapped to open the reader for that song within the current session context

This slice does not require final visual polish for tappable styling, but the item must be clearly operable as an interactive control.

### Plan Detail State Preservation

Opening a song from plan detail must not discard the user’s position in the plan detail view. When the user returns through the same in-app stack, the previously opened session item must still be visible without manual re-scrolling.

The spec intentionally defines this as an observable outcome requirement rather than a mandated implementation technique.

## Reader UX Requirements

### Existing Reader Reuse

The song content presentation remains the existing reader experience. This slice only adds the minimum session-scoped navigation affordance needed to prove the workflow.

### Session Navigation Affordance

When the reader has valid session-scoped plan context:

- previous and next controls must be visible
- the controls must be clear enough to discover and use without extra explanation
- the exact visual placement may follow the easiest clear implementation in the current reader layout

This slice does not require final placement or polished motion design.

### No Session Context

When the reader does not have session-scoped plan context:

- previous and next controls must not be shown

Disabled controls must not be shown for non-planning reader entry, because that would imply a broader reader navigation model than this slice actually supports.

### Session Boundaries

Within a valid session-scoped reader:

- the first item shows previous as disabled
- the last item shows next as disabled
- a single-item session shows both previous and next as disabled

The controls remain visible at the session edges for clarity, but they do not wrap.

### Reader-Local State Preservation

When the user moves between songs using session-scoped previous and next during the same in-app reading session:

- the current reader view mode is preserved
- the current transpose offset is preserved
- the current shared font scale is preserved

This runtime preservation does not imply persistent preferences or browser-reload restoration.

## Data Resolution And Failure Rules

### Data Source Boundary

For this slice, the normal repository expectation is intentionally split:

- plan and session context resolve through the existing planning repository path
- song content resolves through the existing song reader path
- plan detail session items exposed to the client are song-backed
- repository and backend-owned authorization boundaries determine what planning data and song data are readable
- the client must not infer song readability from plan readability on its own

For the intended product path in this slice, repository-exposed plan detail items are expected to resolve to readable songs inside the same organization scope. If stale, inconsistent, or unexpected data violates that invariant, the client must use the explicit error handling defined below rather than inventing fallback authorization behavior in the UI.

### Explicit Failure Handling

If the reader cannot resolve the requested song or the session-scoped reader context consistently:

- the route remains on the requested reader location
- the reader shows an explicit error state instead of song content
- the implementation must not silently fall back to standard song-only reader behavior
- the implementation must not silently redirect to the song list or to plan detail

This keeps route behavior deterministic and makes invalid context visible during testing instead of masking the problem.

### Invalid Session Context

If the route describes a mismatched or inconsistent plan-session-item combination:

- the reader must show an explicit error state
- previous and next navigation must not activate

The implementation should treat invalid route context as a real failure, not as a hint to degrade into a broader reader mode.

## Architecture And Boundary Requirements

- Keep the current signed-in route policy intact.
- Keep backend-owned authorization boundaries intact.
- Keep planning reads and song reads behind repository and application boundaries rather than embedding access logic in widgets.
- Do not introduce a broader global reader navigation abstraction in this slice.
- Do not couple the standard reader entry path to planning-specific assumptions.

This slice may add narrowly scoped reader-context or navigation data structures if needed, but those structures must express session-scoped planning context only.

## Testing Requirements

TDD is mandatory for implementation of this slice.

### Widget Tests

At minimum, cover:

- plan detail renders song items as tappable controls
- tapping a plan detail song item opens the session-scoped reader route
- a session-scoped reader shows previous and next controls
- a standard reader entry does not show session-scoped previous and next controls
- previous is disabled at the first session item
- next is disabled at the last session item
- both controls are disabled for a single-item session
- session-scoped routes continue to navigate in session order after resolving the matching internal session item
- moving previous and next preserves reader-local state during the same app session
- inconsistent session-scoped route context shows an explicit error state

### Router Tests

At minimum, cover:

- direct session-scoped reader entry from its canonical URL shape
- auth redirect behavior for the session-scoped reader route
- reader back fallback from a session-scoped route with no prior stack to canonical plan detail
- direct non-planning reader entry still behaves as before

### Integration Tests

At minimum, cover:

- signed-in flow from plan list to plan detail to session-scoped reader
- previous and next move only within the current session
- back from a plan-origin reader returns to the same plan detail route
- returning from the reader preserves the prior plan detail scroll position
- direct scoped entry resolves to the correct session item and preserves session order

### Browser Reload Verification

At minimum, cover through the best available repository-owned verification mechanism:

- browser reload from a session-scoped reader restores the same song and session context when auth is restored and planning data can be re-fetched online
- browser reload recomputes previous and next from the latest readable session ordering
- browser reload shows the explicit error state when the song resolves but planning context does not

### Regression Coverage

The change must not break:

- signed-in song list as the home route
- direct song reader entry
- existing reader back behavior outside planning
- existing planning list and plan detail rendering
- current auth redirect behavior

## Success Criteria

- Users can open the existing reader directly from a song item inside plan detail.
- When the reader was opened from a session item, it shows previous and next navigation limited to that session only.
- Previous and next controls are absent for non-planning reader entry.
- Session edges are explicit through disabled controls rather than disappearing controls.
- Session-scoped reader browser reload restores the same song and session context when auth is restored and planning data can be re-fetched online.
- Returning from a plan-origin reader through the same in-app stack restores the same plan detail context closely enough that the previously opened item remains visible without manual re-scrolling.
- The slice proves the planning-to-reader workflow without introducing swipe navigation, cross-session navigation, or global reader navigation.
