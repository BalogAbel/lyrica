# Mobile And Tablet Reader Navigation Spec

> Status: Implemented

## Goal

Make Lyron Chords song-reader navigation feel platform-correct on Android and iOS while keeping the current full-screen reader model on both phones and tablets.

## Scope

- The song list must remain the root screen of the signed-in reading flow.
- The song reader must remain a separate detail screen.
- Navigating from the song list to the song reader must behave like a true forward navigation step, not a route swap.
- Users must be able to return clearly from the song reader to the song list.
- The song-reader UI must include a visible back affordance.
- On Android, system back from the song reader must return to the song list.
- If a user lands directly on the song-reader route and there is no back stack, leaving the reader must return to the song list.
- Tablets must continue to use the full-screen reader model as the primary reading experience.

## Non-Goals

- No master-detail or split-view layout in this slice.
- No slide-in or overlay song list.
- No new tablet-specific multi-panel layout.
- No redesign of the reader workflow or information architecture.
- No new in-reader song-selection mechanism.
- No changes to auth, offline cache, or backend authorization-boundary behavior.

## Product Slice Summary

The current app flow is functionally centered around the song list and song reader, but the navigation does not behave in a platform-correct way. On Android, system back from the reader exits the app instead of returning to the list. On iOS there is no hardware back, so the reader screen currently lacks a clear return path.

This slice does not introduce a new tablet layout system. The goal is to correct navigation in the existing signed-in reading flow while keeping the reader full-screen and leaving room for a future side-sheet or split-view design.

## User Flows

### Signed-In Song Browsing

1. The user signs in successfully or starts with a restored session.
2. The app shows the song-list screen.
3. The song list is the root screen of the signed-in reading flow.

### Open Song Reader

1. The user selects a song from the list.
2. The app opens the song-reader detail view.
3. The reader behaves as a separate navigation level above the song list.

### Return From Song Reader

1. The user uses the visible back affordance in the reader or presses the Android system back button.
2. If navigation history exists, the app pops back to the song list.
3. If no navigation history exists, the app returns to the song-list route with history-replace behavior rather than pushing another song-list entry above the reader.

### Root-Level Exit Behavior

1. The user is on the song-list screen.
2. There is no dedicated back affordance from this root state.
3. On Android, system back follows the platform's normal root-level behavior.

## UX Requirements

### Song List

- The song list must remain a simple root screen.
- The song-list UI must not show a back affordance.
- Transitioning from the song list to the reader must remain direct and fast.

### Song Reader

- The song reader must always be clearly dismissible.
- The reader must show a visible back affordance.
- The back affordance must unambiguously mean "return to the song list."
- The reader must remain full-screen on tablets.
- Returning must not depend on hidden gestures or platform-specific knowledge.
- The full-screen reader navigation model must not remove the previously specified persistent online, offline, refreshing, or refresh-failed status surfaces from the reader experience.

### Tablet Behavior

- In this slice, the primary tablet reading model remains a full-screen reader.
- The spec does not require a permanently visible list beside the reader.
- The current solution must not block a future side sheet, overlay list, or split view.

## Routing And Navigation Requirements

### Navigation Model

- The song list -> song reader transition must feel like a true forward step to the user.
- The song-reader route must not replace the song-list route in a way that removes natural back navigation.
- Returning from the reader should primarily use `pop` when there is something to pop.

### Fallback Return Behavior

- If the song reader is opened by direct route entry and there is no back stack, leaving the reader must return to the song-list route.
- This fallback return must use history-replace behavior or an equivalent, not push a new song-list route above the reader.
- The fallback behavior must not produce a blank screen, app exit, or ineffective back action.
- The fallback behavior must not create a back loop where the user gets stuck bouncing between the song list and a directly opened reader.

### Auth Boundary

- The signed-in route policy remains unchanged.
- Signed-out users still cannot access the song-list or song-reader routes.
- The navigation correction must not weaken centralized auth-redirect rules.

## Platform Expectations

### Android

- System back from the song reader must return to the song list.
- System back from the song-list root must follow the platform's usual behavior.
- Back from the reader must not close the app when returning to the song list is still meaningful.

### iOS

- The song-reader screen must show a visible, native-feeling back affordance.
- Users must not remain trapped in the reader without a clear way out.
- The navigation pattern should match iOS expectations, where returning from a detail screen is available through visible UI.

## Deep Linking Expectations

- The song-reader route may remain directly addressable.
- Even with direct entry, the user must still have a meaningful way back to the song list.
- A deep link must not turn the reader into a dead end.

## Testing Requirements

TDD is mandatory for the implementation.

### Widget Tests

Cover:

- navigation from the song list into the reader
- presence of the reader back affordance
- return from the reader to the list
- the fallback case where the reader returns to the list because there is no poppable navigation history

### Integration Tests

Cover:

- signed-in flow: song list -> reader -> back to the list
- correct reader navigation when the app starts from a restored session
- return to the list after direct entry to the reader route

### Regression Coverage

- The change must not break the current auth-redirect behavior.
- The change must not break the local-first authenticated reader flow.
- The change must not alter the root status of the song list.

## Success Criteria

- On Android, back from the song reader returns to the song list instead of exiting the app.
- On iOS, the user can return to the song list through a visible UI affordance in the reader.
- The song list remains the root screen of the signed-in reading flow.
- The reader remains full-screen on both phones and tablets.
- Direct reader-route entry still does not create a navigation dead end.
- The solution does not force a master-detail layout now, but it also does not block one later.
