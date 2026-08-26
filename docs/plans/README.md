# Plans

Plans for fixes, refactors, and infrastructure work on **code that already
exists**. Specifications for **new** features live in
[`docs/requirements/`](../requirements/README.md).

The writing rules for a plan are enforced by `.cursor/rules/plan-conventions.mdc`
and always apply, including in Plan mode. This file covers where plans live, how
they are named, and what a finished one looks like.

This directory holds only this README until the first plan is written.

---

## Cross-cutting invariants

Any plan that touches translation, the clipboard, or permissions must preserve
all of the following. If a plan needs to break one, that is not a detail in the
`Details` block — it is the headline decision, and it needs the user's explicit
agreement.

| Invariant | Why it exists |
|---|---|
| No network code, no dependencies, no telemetry | The privacy promise is the product, and it is only credible because it is verifiable by reading the source |
| The clipboard is snapshotted before a swap and restored after | The user's clipboard is borrowed, never taken |
| Translated text is never logged or persisted | Content lives in memory for one translation; only settings persist |
| Accessibility is the only permission requested | Anything more breaks the claim in `SECURITY.md` |
| A failure beeps or explains — it never crashes | The app runs unattended in the menu bar |
| Model calls are bounded by a timeout | A stalled request must not wedge the app |

A plan that adds a check *inside* the failure path when the real fix belongs at
the call site is solving the problem in the wrong place. Say so and move it.

---

## Status legend

Every item in a plan carries one of:

| Label | Meaning |
|---|---|
| `[DONE]` | in the code, on the working branch or on `main` |
| `[PENDING]` | agreed, not implemented yet |
| `[INVESTIGATION]` | needs diagnosis before a fix can be written |
| `[REJECTED]` | decided against, with the reason recorded |
| `[BACKLOG]` | deferred indefinitely |
| `[REVERTED]` | was done, then undone, with the reason recorded |

When a plan is finished, its file **stays** in this directory as a historical
record. Do not delete it.

---

## Naming

`{N}_{descriptive-kebab-case-name}.md` — `N` is an ID, not a priority.

- `1_reader-panel-focus-handling.md`
- `2_shortcut-recorder-edge-cases.md`

If a plan grows into several independent units of work, add a folder
`{N}_{short-name}/` beside it with one file per unit, and turn the original file
into an orchestrator. Names inside follow the same pattern, where `N` is the
bug or phase number. Never duplicate content between an orchestrator and a
sub-plan: each fact lives in one place.

---

## Structure of one plan

There is no rigid template (unlike [`requirements/0_TEMPLATE.md`](../requirements/0_TEMPLATE.md)),
but the required order is:

1. **TL;DR** — max 3 bullets.
2. **Decisions** — a table: Decision | Choice | Why (≤10 words).
3. **Changes** — a checklist, one line per file.
4. **Details** — long reasoning, inside a collapsible `<details>` block.

An orchestrator holds only the shared material: the status index, cross-cutting
principles, the order of work, and how the units group into PRs. A sub-plan
holds everything needed to implement one unit.

### Evidence

This app cannot be exercised on CI, and it has no test suite (see
[`docs/conventions/testing/README.md`](../conventions/testing/README.md)). So a
plan must be explicit about where each claim comes from:

- **"Reproduced"** means you ran the built app on a supported Mac and saw the
  behaviour. Record the exact steps and the observed result.
- **"Read from the code"** means exactly that. Cite the file and line:
  `Sources/EasyWrite/Replacer.swift:31`.

Mixing the two silently is the fastest way to ship a fix for a bug that was
never there.

---

## When to write a plan

Write one when the work is a fix, cleanup, or refactor of existing code **and**
at least one of these holds:

- It spans more than one file.
- It requires a decision someone could reasonably disagree with.
- It changes an invariant, a permission, or something the user can see.
- It will be done in several PRs.

Do **not** write one for a typo, a one-line fix with an obvious cause, a doc
change, or a rename with no behavioural effect. Just make the change.

---

## Related documents

- [`docs/requirements/README.md`](../requirements/README.md) — specs for new features
- [`docs/conventions/CODING_CONVENTIONS.md`](../conventions/CODING_CONVENTIONS.md) — style and patterns
- [`docs/conventions/AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md) — guardrails and the PR checklist
- [`docs/conventions/testing/README.md`](../conventions/testing/README.md) — how work is verified
