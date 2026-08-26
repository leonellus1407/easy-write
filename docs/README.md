# Easy Write — Documentation Index

Guide to the `docs/` tree, grouped by purpose. Documentation aimed at users lives
at the repository root; everything here is for people (and agents) working on the
code.

## Start here

- [AI_Overview.md](AI_Overview.md) — what this repository is, how it is organised,
  and how the pieces fit together. Written to be read *before* any source code,
  and deliberately free of line numbers and version-specific detail so it stays
  accurate. Read it first.

## Conventions (how-to)

How we write, verify, and release the code.

- [conventions/CODING_CONVENTIONS.md](conventions/CODING_CONVENTIONS.md) — Swift
  style, naming, file organisation, concurrency and main-actor rules, the `Store`
  settings pattern, error handling, comments, git workflow, and the pre-commit
  checklist.
- [conventions/AI_WORKFLOW.md](conventions/AI_WORKFLOW.md) — required reading for
  AI agents: what to read first, the PR checklist, the diff-size budget, how to
  classify a new `if`, reproduce-before-fix, what must never change without
  explicit instruction, and when to stop and ask.
- [conventions/testing/README.md](conventions/testing/README.md) — the testing
  guide. **This repo has no test target and no CI**; the doc explains what is
  verified today, why the automatable surface is small, how to add a test target,
  what to test first, and the manual smoke test that is the real acceptance gate.
- [conventions/RELEASE_NOTES_GUIDE.md](conventions/RELEASE_NOTES_GUIDE.md) — how
  to turn a branch into a `CHANGELOG.md` entry and a GitHub Release body:
  behaviour over implementation, what must never appear, and the version bump.

## Specs & plans

Two directories with two different jobs. Both currently hold only their README
(and the template), because no work items have been written yet.

- [requirements/](requirements/README.md) — specifications for **new** features.
  Start from [requirements/0_TEMPLATE.md](requirements/0_TEMPLATE.md).
- [plans/](plans/README.md) — plans for fixes, refactors, and cleanup of **code
  that already exists**, plus the cross-cutting invariants any such plan must
  preserve.

The writing rules for both are enforced by the rules in `.cursor/rules/`.

## Images

Assets referenced by the root [README.md](../README.md) and by the repository's
GitHub social preview. They are not documentation; do not delete or overwrite
them when reorganising this tree.

| File | Used for |
|---|---|
| `demo.gif` | The animated walkthrough embedded in the README |
| `icon.png` | The app icon shown in the README header |
| `social-preview.jpg` | The GitHub repository social preview card |

## Root documentation

Not part of this tree, but the authoritative source for their topics — link to
them rather than restating them here.

- [../README.md](../README.md) — product overview, requirements, install, usage
- [../HOW_IT_WORKS.md](../HOW_IT_WORKS.md) — architecture tour and per-file map
- [../SECURITY.md](../SECURITY.md) — data flow, permissions, reporting a vulnerability
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — contributor-facing setup and guidelines
- [../CHANGELOG.md](../CHANGELOG.md) — the release-note artifact for every version

## Notes on what is deliberately absent

- **No `docs/release-notes/`.** `CHANGELOG.md` at the repository root *is* the
  release-note artifact; a copy under `docs/` would duplicate it. The guide for
  writing entries lives in `conventions/`.
- **No database schema reference.** There is no database. The only persistence is
  `UserDefaults`, documented in
  [conventions/CODING_CONVENTIONS.md](conventions/CODING_CONVENTIONS.md#settings--persistence).
- **No test inventory.** There are no tests to inventory. When a test target
  exists, its inventory belongs in
  [conventions/testing/README.md](conventions/testing/README.md), not in a
  separate summary that would drift out of date.
