# Development Workflow

## Standard Flow

1. Capture the requirement or decision in repository docs.
2. Update or create a design/spec document in `docs/specs/` when the change is material.
3. Write an implementation plan in `docs/plans/`.
4. Implement with tests first where behavior is introduced.
5. Run local verification.
6. Update documentation and ADRs if the change affects durable knowledge.
7. Merge only with green CI.

## Commit Guidance

- Keep commits meaningful and reviewable.
- Pair schema changes with policy and documentation updates.
- Pair architecture changes with ADRs.
- Avoid tool-specific document locations for repository-critical knowledge.

## Definition Of Done

- Behavior implemented
- Tests added or updated
- Relevant docs updated
- CI expectations met
- No critical decision left only in chat or tools
