# ADR-042: Song Key Layers

**Status:** Accepted (2026-10-13, S3 design gate). Not implemented yet;
delivered by S3 PRs 1–3.
**Context spec:** `docs/specs/2026-10-13-personal-song-settings.md` (PS1–PS24)
**Builds on:** S2's single ChordPro base
(`docs/specs/2026-10-12-chordpro-base-directives.md`), ADR-038 (plan content
version), ADR-039 (RPC-only writes)
**Amends:** "Reader-Local State Preservation" in
`docs/specs/2026-04-01-session-scoped-plan-reader-navigation.md`

## Context

Transpose and capo were reader runtime state: an offset over the song's
ChordPro base, carried over from song to song inside a plan session. Teams
need a key per song for a given service that every member sees, and a
musician who changes the key for a moment should not drag it to the next
song. The 2026-10-01 roadmap planned per-user saved values on a new personal
layer; the S3 brainstorm (2026-10-13) replaced that with shared layers and
kept per-user values as a possible later extension.

## Decision

1. **Three layers, resolved per field, first non-null wins:**
   1. **Temporary:** reader runtime only, never stored, cleared on every song
      change and when the reader closes;
   2. **Plan:** stored on the session item, shared by everyone who opens the
      song from that plan, only applied in that plan context;
   3. **Song:** the ChordPro base `{transpose}` / `{capo}`.

   Transpose and capo resolve independently. Every layer holds absolute
   values (relative to the written chords), so a base change never moves a
   plan value.
2. **The reader never writes the song base.** The base is edited only in the
   song editor, through the S2 base-region write. The reader's `±` changes
   only the temporary layer. Saving to the plan layer is a separate, explicit
   action for members with `canEditSessions`; there is no auto-save of a
   shared value.
3. **One resolver over an ordered list of layers.** The resolution is a single
   pure function. It returns each field's effective value and the id of the
   layer it came from. The reader, the projection, the source labels and the
   Save/Reset logic consume its output and never name a fixed pair of layers.
4. **Extension point: per-user layers.** A per-user song value and a per-user
   plan value are plausible later requests. They would be additional entries
   in the same chain, stored on the per-user personal layer that S4 builds,
   never as columns on shared tables. Their position in the chain is decided
   when they are built. Nothing is built for them now, and they are not
   tracked as deferred work.

How the plan layer is stored and synchronized (two nullable `session_items`
columns, `set_session_item_key` with optimistic concurrency on the item's own
`version`, one planning mutation kind) is specified in the spec (PS10–PS20)
and recorded for the version semantics in ADR-038's 2026-10-13 amendment.

## Consequences

- A team can fix the key and capo of a song for one service, and every member
  reading that plan sees it, offline included once synced.
- A temporary change never leaks into the next song or onto another member's
  screen.
- The session-wide transpose and capo carry-over of the 2026-04-01 spec ends.
  View mode, instrument, zoom and the other reader state keep their behavior.
- Read-only members and the library reader get temporary changes only.
- The value belongs to the session item: the same song in two sessions can
  have two keys, and removing and re-adding a song loses its key.
- No new sync domain: the plan layer rides on planning's pull, outbox,
  purge and pending-work count.

## Rejected Alternatives

- **Per-user saved values on a personal layer (the 2026-10-01 default).**
  Replaced by the user's choice of shared values; kept as the extension point
  above.
- **Auto-saving `±` to the current scope.** A single tap on stage would change
  the key on every member's screen.
- **A reader action that writes the song base.** The base is song content
  with its own editor, conflict handling and capability; the reader stays a
  reader.
- **Storing a delta over the base.** A later base edit would silently move
  every plan's key.
- **A `(plan_id, song_id)` key for the plan layer.** It needs its own table
  and cascades, and cannot give a song two keys in two sessions.
