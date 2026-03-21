# AGENTS.md

## Purpose

This repository uses AI-assisted development, but the repository itself remains the canonical source of truth.

## Non-Negotiable Rules

1. Never keep critical architectural, product, workflow, testing, or authorization decisions only in chat, prompts, local notes, or tool-specific folders.
2. If an AI-assisted session makes a meaningful decision, update the appropriate repository document in the same change.
3. Superpowers workflows are allowed, but Superpowers must not contain exclusive project knowledge.
4. Documentation is part of implementation, not follow-up cleanup.
5. Authorization rules must be implemented in backend-enforced layers, not delegated to the Flutter UI.
6. TDD is the default implementation discipline for behavior changes.
7. Every mergeable change must leave the repository in a clearer state than before.

## Documentation Duties

Update these files whenever their subject changes:

- `README.md` for repository-level guidance
- `docs/product/vision.md` for product scope and principles
- `docs/domain/domain-model.md` for domain entities and relationships
- `docs/architecture/architecture.md` for system architecture and boundaries
- `docs/architecture/decisions/` for durable architectural decisions
- `docs/testing/testing-strategy.md` for testing rules
- `docs/workflows/` for engineering and AI workflows
- `docs/integrations/freeshow.md` for presentation integration boundaries

## Commit Expectations

- Prefer small, meaningful commits.
- Keep documentation changes with the code or schema changes they justify.
- Do not merge undocumented critical behavior.

## AI Workflow Summary

1. Update or create the spec in the repository.
2. Update or create the implementation plan in the repository.
3. Implement with tests first where behavior is introduced or changed.
4. Verify locally.
5. Update documentation.
6. Merge only with green CI.
