# Song Reader UI Discovery Spec

> Status: Implemented; partially superseded by `docs/specs/2026-04-16-song-reader-tablet-immersive-shell.md`

## Goal

Define the first visual and interaction direction for the Lyron Chords song reader so the team can evaluate reader-first UI decisions before Flutter implementation.

## Problem

The current song reader already proves core functionality such as ChordPro rendering, transpose, and navigation, but its presentation is still primarily functional. The next stage of the product needs a reader experience that feels modern, minimal, and performance-oriented without losing the current workflow simplicity.

The repository also needs a shared design artifact that captures the intended reader behavior before visual exploration turns into ad hoc chat history or disconnected implementation experiments.

## Scope

- Define the product-level UI direction for the song reader.
- Define the compact reader behavior for touch-first mobile and tablet use.
- Define the expanded reader behavior for large desktop-style viewports.
- Define the role of persistent context, temporary controls, and reader gestures.
- Define theme-system expectations for standard, high-contrast, and black-oriented variants.
- Ship a static prototype that lets the team inspect the direction visually.

## Non-Goals

- No Flutter implementation in this slice.
- No final design system rollout across the whole application.
- No exact typography, spacing, or color token lock-in for the shipped app.
- No persistence rules for reader preferences in this discovery slice.
- No redesign of song list, planning list, or plan-detail screens yet.
- No commitment yet to the exact viewport breakpoint values.

## Product Direction

The song reader should be the strongest first-impression surface in the app. Its primary job is to maximize song legibility and minimize interface noise during real use.

The reader should feel:

- modern
- minimal
- characterful but not loud
- operationally simple
- suitable for multiple theme systems without layout rework

The reader should not feel like a dense control panel by default.

## Core Reader Principle

The reader is content-first. The song owns almost the entire screen. Persistent interface chrome is minimized to one quiet contextual layer that helps orientation without competing with the song itself.

The default state should present:

- the song content as the dominant visual surface
- a subtle persistent bottom context bar in compact mode
- no always-visible editing or display controls

Controls should appear only on explicit user interaction and then disappear again after inactivity.

## Interaction Model

The interaction model should privilege direct manipulation over persistent controls.

Required interaction direction:

- single tap toggles the control overlay
- pinch adjusts reading scale quickly
- double tap triggers automatic fit behavior
- transpose is available inside the temporary control layer
- the user should interact with the content area naturally instead of hunting for buttons

The gesture model must support performance use where the UI should disappear from attention quickly after adjustment.

## Layout Modes

### Compact Reader

Compact mode covers:

- phones
- native tablets
- web tablets
- any touch-first or smaller viewport where persistent side panels would reduce content space too much

Compact mode should:

- keep the song centered as the main surface
- keep a persistent bottom context bar
- use temporary overlays for active controls
- prefer calm automatic layout decisions, including multiple columns where appropriate

### Expanded Reader

Expanded mode covers:

- large desktop-style viewports
- web or desktop contexts where side space is meaningfully available

Expanded mode should use a three-zone layout:

- left panel for navigation and performance context
- center panel for the song itself
- right panel for reader tools

These side panels should remain visually restrained. Expanded mode is not a dashboard. It is the same reader experience with more stable supporting surfaces.

## Platform Rule

The distinction is not native versus web. The distinction is compact versus expanded viewport behavior.

That means:

- web tablet behavior should stay aligned with native tablet behavior
- large web or desktop-like viewports may expose persistent side panels
- the core reading model must remain the same across platforms

## Context Model

The reader should retain a persistent sense of sequence.

Required context direction:

- in compact mode, a bottom bar remains visible at all times
- the bar should provide lightweight orientation such as previous and next song names
- the context bar should stay present even when the main controls are hidden
- if the reader is opened from a scoped planning or session flow, that context may be surfaced in the same structural area

The context layer must remain quiet enough that the song stays visually dominant.

## Layout Adaptation

The reader should optimize for showing more useful song content at once.

The layout system may:

- choose one or multiple columns automatically
- adapt to viewport width and current reading scale
- preserve a clear reading order

The goal is not decorative layout. The goal is density without confusion.

## Theme System Direction

The visual system should be designed to support multiple themes cleanly.

Initial discovery themes:

- standard
- high-contrast
- black

Theme changes should not alter structure. They should mainly affect color tokens, contrast, emphasis, and panel treatment. Typography, spacing rhythm, and content hierarchy should remain stable across themes.

## Prototype Requirements

The first prototype should demonstrate:

- compact reader default state
- compact reader controls-visible state
- compact reader controls auto-hiding after inactivity
- touch-first gesture intent for reveal, pinch-scale, and double-tap auto-fit
- expanded reader with left and right side panels
- standard and black theme examples
- compact and expanded as reviewer-selected viewport simulations rather than shipped reader controls
- overlay visibility as a reviewer-controlled compact-mode comparison
- no overlay in expanded mode because reader tools live in the side panels there
- enough realism to evaluate hierarchy and calmness without implying final production polish

## Success Criteria

This discovery slice succeeds if:

- the team can evaluate the reader direction visually instead of only verbally
- compact and expanded reader behavior are both understandable
- the context bar, temporary controls, and side-panel logic feel coherent
- the theme-capable visual structure holds together without redesigning the layout
- the resulting prototype is strong enough to guide a later implementation plan
