# AI Workflow — guide for AI agents

> **Purpose.** Easy Write's value proposition is auditability: ten Swift files, no
> dependencies, no network code, and a privacy promise a user can verify by
> reading the source. That property is easy to destroy one convenient addition at
> a time. This document is the process that protects it. It is required reading
> for every AI agent working in this repository.
>
> **Language rule for the repo:** every file — docs, README, code comments,
> shell scripts, commit messages, and user-facing strings — is written in
> English. Other scripts appear only inside per-language model instructions
> (for example the Modern Standard Arabic note in `Languages.swift`).

Treat this document as read-first for every AI session. If the instructions here
conflict with fresh facts about the codebase, stop and ask — do not "fill in the
blanks" by guessing.

---

## 1. Read-first before any work

Every new AI session must read the following **before** the first code edit:

1. `README.md` — what the product is and how a user runs it.
2. `HOW_IT_WORKS.md` — architecture: the on-device engine, the in-place swap,
   hot-keys, and the code-signing trick.
3. `docs/AI_Overview.md` — orientation for AI agents.
4. `docs/conventions/CODING_CONVENTIONS.md` — style, naming, concurrency,
   settings, error handling, prohibitions.
5. `docs/conventions/testing/README.md` — how work is actually verified, and
   why there is no test suite yet.
6. **This document** (`docs/conventions/AI_WORKFLOW.md`).
7. `SECURITY.md` — when touching the clipboard, permissions, or anything that
   could move data.
8. The relevant plan under `docs/plans/` (when working from a plan).
9. The feature spec under `docs/requirements/` (when one exists for the feature
   you touch).

"Read" means actually loading the file into context, not skimming. If a document
is large, hold a summary in working memory so you can answer "what does the doc
say about X?" later in the session.

Also read the actual Swift file you are about to change, end to end. It is under
200 lines. There is no excuse for patching a function you have only seen a
fragment of.

---

## 2. PR checklist

This repository has no `.github/PULL_REQUEST_TEMPLATE.md`. Walk this list
yourself before opening a PR or asking for review:

- Which invariant am I introducing or preserving?
- Does the change add any network call, dependency, log of user text, or
  persisted content? (If yes: stop — see section 6.)
- Did I `rg` for every caller of the API I changed?
- Has every new `if` been classified (invariant / workaround / dead branch)?
- Is the diff ≤ 50 added lines in every changed file?
- Does `swift build` finish with no new warnings?
- Does `swift build -c release` succeed?
- Did I run the manual smoke test from
  [`testing/README.md`](testing/README.md) on a supported Mac — or state
  plainly that I could not?
- Is the clipboard snapshot/restore path still intact?
- Does the PR description say what a **user** will observe differently?

"No answer" to any item means stop and resolve, not "commit and move on".

---

## 3. Diff-size budget

| Level | Threshold | Action |
|---|---|---|
| Soft | +50 added lines in one file per commit | Justify in the PR description. |
| Hard | +50 added lines in one file across the whole PR | Do not breach without explicit agreement (a reviewer comment, or an explicit "yes, splitting is impossible because…"). |

The budget is tight on purpose. The whole app is ten files; a 200-line addition
to one of them is a new component wearing a trench coat. Split it into its own
file — SwiftPM picks it up with no manifest edit.

---

## 4. Invariants and `if` checks

For every new `if` / `switch` / `guard` / early return, classify it explicitly
(in code, the PR description, or the commit message):

- **Invariant.** The condition protects a system invariant. Then:
  - State the invariant explicitly — in the method name, a `///` doc comment,
    or a test.
  - The code should read as documentation of what you expect never to happen.
  - Example: `guard !busy else { return }` guards single-flight translation.

- **Workaround.** The condition works around a platform bug or limitation in
  AppKit, Carbon, Foundation Models, or TCC. Then:
  - Comment `// workaround: <reason>`, with the observable symptom.
  - Existing examples worth imitating: `.privateState` on the event source,
    `.permissiveContentTransformations` on the model, the `usleep` pauses in
    `Replacer`.

- **Dead branch.** The condition guards against something that "shouldn't
  happen but just in case". Then:
  - Comment `// dead: <reason>`, or delete it.
  - Do not add a silent `return` that hides a bug. In this app the honest
    failure mode is `NSSound.beep()` plus a flashed icon — visible, harmless,
    and reportable.

"Just-in-case `if`" is an anti-pattern. Every such check masks a bug elsewhere.

---

## 5. Reproduce before you fix

There is no automated regression net (see
[`testing/README.md`](testing/README.md)), so the burden of proof is on you:

1. Reproduce the bug manually on a supported Mac and write down the exact
   steps and the observed wrong behaviour.
2. Change the production code.
3. Re-run the same steps and record the corrected behaviour.
4. Put both, verbatim, in the PR description or the plan's `Details` block.

If the fixed logic is pure (formatting, lookup, parsing, merging), add a real
test instead — and add the test target if it does not exist yet, as a separate,
declared piece of work.

If you cannot run the app (wrong hardware, no Apple Intelligence), say so
explicitly. Claiming "verified" for something you reasoned about rather than ran
is the single most damaging thing you can do in this repository.

---

## 6. What you must NOT change without an explicit instruction

An AI agent must not, on its own initiative:

- Add **any network code** — `URLSession`, sockets, a "just for update checks"
  ping, a cloud fallback for the translator.
- Add **any third-party dependency** to `Package.swift`.
- Add analytics, telemetry, crash reporting, or logging of user text
  (`print`, `os_log`, an on-disk translation history).
- Persist translated content anywhere.
- Remove or weaken `.permissiveContentTransformations`; the default guardrails
  false-flag ordinary text for translation.
- Remove the clipboard snapshot/restore around a swap.
- Rewrite the architecture — SwiftUI `App` lifecycle, an actor-based redesign,
  a new dependency-injection layer.
- Flip `.swiftLanguageMode(.v5)` to Swift 6 mode, change the minimum macOS
  version, or restructure the package targets.
- Change conventions: 4 spaces → tabs, English → another language,
  main-actor-by-default → ad-hoc queues.
- Touch `setup-signing.sh` or the signing logic in `build.sh` — a stable
  identity is what keeps the user's Accessibility grant alive across rebuilds.
- Edit `Info.plist` bundle identity (`CFBundleIdentifier`, `LSUIElement`) —
  changing it silently invalidates existing users' Accessibility grant.
- Add an entitlement or request a permission beyond Accessibility.

These prohibitions can only be lifted by an explicit instruction from the user in
the current session.

---

## 7. Local commands

### Build

```bash
swift build                 # debug; the everyday gate
swift build -c release      # what build.sh compiles
swift package clean         # or: rm -rf .build
```

`swift build` must finish **warning-free**. Warnings are the closest thing this
repo has to static analysis — do not let them accumulate.

### Bundle and run

```bash
./setup-signing.sh          # one-time: stable self-signed identity
./build.sh                  # release build → EasyWrite.app → codesign
open EasyWrite.app
```

`./build.sh` signs with the "Easy Write Self-Signed" identity when it exists and
falls back to ad-hoc signing otherwise. Ad-hoc builds lose the Accessibility
grant on every rebuild, so run `setup-signing.sh` once before iterating on
anything that drives the keyboard.

### Tests

```bash
swift test                  # currently runs nothing — there is no test target
```

See [`testing/README.md`](testing/README.md) before writing any.

### Static analysis and formatting

There is **no** SwiftLint, swift-format, or CI configuration in this repository.
Do not claim a lint gate that does not exist, and do not add one as a side effect
of another change — introducing a linter reformats the whole codebase and is its
own PR.

### Platform constraint

The app builds and runs only on macOS 26+ with Apple Silicon. On any other
machine you can read and edit the code but cannot compile or verify it. Say so
rather than implying you built it.

---

## 8. When to stop and ask

An AI agent must **stop and report to the user**, rather than deciding on their
behalf, when:

- The request requires one of the "forbidden" items in section 6.
- The build fails in an unexpected place and the cause is not obvious after a
  few minutes of investigation.
- A plan in `docs/plans/` contradicts the current state of the code.
- An architectural choice is required — new type versus method on an existing
  one, AppKit versus SwiftUI for a new surface, a new persisted setting versus
  deriving the value.
- The change would alter what the user sees or what permission they must grant.
- The diff-size budget is breached and splitting is not obviously possible.
- You cannot verify the change on real hardware.

"Stop" means: list the blocker explicitly in the final summary, and do not start
the next phase of the plan.

---

## 9. Related documents

- [`README.md`](../../README.md) — product overview.
- [`HOW_IT_WORKS.md`](../../HOW_IT_WORKS.md) — architecture tour.
- [`SECURITY.md`](../../SECURITY.md) — data flow and permissions.
- [`docs/AI_Overview.md`](../AI_Overview.md) — orientation for AI agents.
- [`CODING_CONVENTIONS.md`](CODING_CONVENTIONS.md) — style and patterns.
- [`testing/README.md`](testing/README.md) — verification.
- [`RELEASE_NOTES_GUIDE.md`](RELEASE_NOTES_GUIDE.md) — changelog entries.
- [`docs/plans/README.md`](../plans/README.md) — plan workflow.
- [`docs/requirements/README.md`](../requirements/README.md) — spec workflow.
