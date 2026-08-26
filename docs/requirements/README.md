# Feature Specifications

Specifications for **new** features and major changes to Easy Write. Fixes,
cleanups, and refactors of existing code go to
[`docs/plans/`](../plans/README.md) instead.

This directory holds only this README and the template until the first spec is
written.

## Purpose

A specification serves as:

- **Technical specification** for implementing the feature
- **Acceptance criteria** for deciding when it is done
- **Design record** for why it was built this way
- **Reference** for whoever touches the code next

## When to write one

Write a spec when:

- The feature adds a new user-visible capability (a mode, a surface, a setting).
- It touches more than one file, or introduces a new type.
- It adds or changes a persisted setting or a hot-key.
- It affects a permission, the clipboard, or anything covered by `SECURITY.md`.
- It needs a decision someone could reasonably disagree with.

Do **not** write one for:

- A bug fix (use a plan, or just fix it)
- Adding a language to `Languages.swift`
- Copy or wording changes
- Documentation updates
- Trivial refactoring

## Naming

`{NUMBER}_{descriptive-kebab-case-name}.md`

- ✅ `1_translation-history.md`
- ✅ `2_preview-for-every-mode.md`
- ✅ `3_long-text-chunking.md`
- ❌ `feature1.md` — no descriptive name
- ❌ `NewFeature.md` — not kebab-case, no number
- ❌ `translation_history.md` — no number, underscores instead of dashes

`0_TEMPLATE.md` keeps number `0` so it sorts to the top. Real specs start at `1`.

## Using the template

1. Check the existing files to find the next number.
2. Copy [`0_TEMPLATE.md`](0_TEMPLATE.md) to `{N}_{feature-name}.md`.
3. Fill in every section; delete the ones that genuinely do not apply rather
   than leaving placeholder text.
4. Replace `{Feature Name}` and `{Date}`.
5. Update **Status** as the work progresses.

## Workflow

### Planning

1. Read the existing code the feature touches — the whole file, not a fragment.
2. Confirm the feature is compatible with the invariants in
   [`docs/plans/README.md`](../plans/README.md#cross-cutting-invariants). A
   feature that needs network access or a new permission is a conversation, not
   a spec.
3. Determine the next sequential number.
4. Write the spec.
5. Review it for completeness before writing any code.

### Implementation

1. Follow the technical specification.
2. Check off acceptance criteria as they are met.
3. Refer back to the spec for design decisions rather than re-deciding.
4. Update the spec if a requirement genuinely changes.

### Completion

1. Verify every acceptance criterion, including the manual checks.
2. Set **Status** to `Completed`.
3. Add the `CHANGELOG.md` entry — see
   [`RELEASE_NOTES_GUIDE.md`](../conventions/RELEASE_NOTES_GUIDE.md).

## Tips

- **Be specific**: name real files, types, and settings keys.
- **Be practical**: quote patterns that already exist in the codebase.
- **Be thorough**: cover edge cases, failure modes, and the privacy impact.
- **Be concise**: this app is small; a spec longer than the feature is a smell.
- **Reference, don't duplicate**: link to the conventions instead of restating
  them.

## Related documents

- [`0_TEMPLATE.md`](0_TEMPLATE.md) — the template, with every section explained
- [`docs/plans/README.md`](../plans/README.md) — plans for existing code
- [`docs/conventions/CODING_CONVENTIONS.md`](../conventions/CODING_CONVENTIONS.md) — style and patterns
- [`HOW_IT_WORKS.md`](../../HOW_IT_WORKS.md) — architecture tour
