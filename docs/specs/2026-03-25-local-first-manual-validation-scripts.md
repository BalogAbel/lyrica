# Local-First Manual Validation Scripts Spec

## Goal

Add repository-owned scripts for repeatable manual validation of the local-first authenticated song-reading slice so developers can reliably walk through online, offline, refresh-failed, and explicit sign-out scenarios without reconstructing the workflow from chat or memory.

## Scope

- Add repository scripts for:
  - preparing the local validation environment
  - resetting the validation state
  - running the app against the current local Supabase instance without resetting state on every launch
  - switching the backend offline for manual validation
  - bringing the backend back online
  - printing a manual checklist of expected outcomes
- Keep the scripts aligned with repository wrapper expectations such as `./scripts/supabase.sh`.
- Document the workflow in repository docs.
- Add automated shell coverage for the script contract.

## Non-Goals

- No new product behavior in Flutter.
- No GUI/browser automation of the reader flow.
- No replacement of the existing `./scripts/verify.sh` quality gate.
- No direct unmanaged Supabase CLI usage outside the repository wrapper.

## Core Rules

- Setup and reset scripts must provision the documented demo user after database reset.
- The app-run script for manual validation must not reset the database automatically, because offline relaunch validation depends on preserving the previously fetched cache.
- The app-run script must support offline relaunch after the backend is stopped by reusing the last known local Supabase `dart-define` values captured while the backend was online.
- Offline and online transition scripts must use repository-owned Supabase wrapper commands.
- The checklist script must describe the expected manual observations for:
  - online launch
  - offline relaunch from cache on native Flutter targets
  - refresh failure while cached data remains visible
  - explicit sign-out removing cached authenticated access
- The manual validation workflow must state that browser-based offline relaunch is diagnostic only for this slice, while native Flutter targets are the required acceptance path.
- The manual validation workflow must also distinguish native manual offline-relaunch acceptance from the automated persistent-cache reopen proof in `./scripts/verify.sh`.

## Success Criteria

- A developer can prepare the environment with a single setup command.
- A developer can relaunch the app without losing validation state.
- A developer can switch backend connectivity off and on through scripts.
- The repository documents the manual validation flow alongside the scripts.
