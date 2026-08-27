# AI Workflow — guide for AI agents

> **Purpose.** Easy Write's value proposition is auditability: a dozen Swift
> files, no dependencies, no network code, no permissions, and a privacy promise
> a user can verify by reading the source. That property is easy to destroy one
> convenient addition at a time. This document is the process that protects it.
> It is required reading for every AI agent working in this repository.
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
2. `HOW_IT_WORKS.md` — architecture: the on-device engine, streaming and
   prewarming, the clipboard rule, hot-keys, and the code-signing trick.
3. `docs/AI_Overview.md` — orientation for AI agents.
4. `docs/conventions/CODING_CONVENTIONS.md` — style, naming, concurrency,
   settings, error handling, prohibitions.
5. `docs/conventions/testing/README.md` — how work is actually verified, what
   the suite covers, and the much larger part it does not.
6. **This document** (`docs/conventions/AI_WORKFLOW.md`).
7. `SECURITY.md` — when touching the clipboard, permissions, the translation
   cache, or anything that could move data.
8. The relevant plan under `docs/plans/` (when working from a plan).
9. The feature spec under `docs/requirements/` (when one exists for the feature
   you touch).

"Read" means actually loading the file into context, not skimming. If a document
is large, hold a summary in working memory so you can answer "what does the doc
say about X?" later in the session.

Also read the actual Swift file you are about to change, end to end — not the
hunk your search matched. Every file under `Sources/` is small enough to fit in
context, so there is no excuse for patching a function you have only seen a
fragment of. Do not substitute an assumed file size for looking.

---

## 2. PR checklist

This repository has no `.github/PULL_REQUEST_TEMPLATE.md`. Walk this list
yourself before opening a PR or asking for review:

- Which invariant am I introducing or preserving?
- Does the change add any network call, dependency, log of user text, persisted
  content, or permission request? (If yes: stop — see section 6.)
- Did I `rg` for every caller of the API I changed?
- Has every new `if` been classified (invariant / workaround / dead branch)?
- Is the diff ≤ 50 added lines in every changed file under `Sources/`?
  (Section 3 — the budget covers Swift sources only.)
- Does `swift build` finish with no new warnings?
- Does `swift build -c release` succeed?
- Does `./test.sh` pass, and did new pure logic get a test?
- Did I run the manual smoke test from
  [`testing/README.md`](testing/README.md) on a supported Mac — or state
  plainly that I could not?
- Is there still exactly one pasteboard write, and still no permission request?
- Does the PR description say what a **user** will observe differently?

"No answer" to any item means stop and resolve, not "commit and move on".

---

## 3. Diff-size budget

**This budget applies to `Sources/**/*.swift` and to nothing else.**

| Level | Threshold | Action |
|---|---|---|
| Soft | +50 added lines in one Swift file per commit | Justify in the PR description. |
| Hard | +50 added lines in one Swift file across the whole PR | Do not breach without explicit agreement (a reviewer comment, or an explicit "yes, splitting is impossible because…"). |

The budget is tight on purpose. The whole app is a dozen files; a 200-line
addition to one of them is a new component wearing a trench coat. Split it into
its own file — SwiftPM picks it up with no manifest edit. The popover is the
worked example: it is three files, because a container, a layout and a state
machine are three things, and each is legible alone.

### Why documentation is out of scope

Markdown, the `.cursor/rules/*.mdc` files, and the shell scripts are not
governed by the numbers above. The argument for the limit is a code-structure
argument: an oversized Swift file is usually a type that wants extracting, and
SwiftPM makes extracting it free. Prose has no equivalent move — splitting a
convention document into 50-line fragments would scatter one topic across
several files and break the one-fact-one-place rule that
[`CODING_CONVENTIONS.md`](CODING_CONVENTIONS.md) opens with.

Be honest about the history here: the commit that introduced this document
added more than 50 lines to twelve of the thirteen files it created. Read as an
unscoped rule, the budget was breached the moment it was written. The constraint
that does apply to documentation is accuracy, not length — a doc is too long
when it repeats something that already has an owner elsewhere.

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
  AppKit, Carbon, or Foundation Models. Then:
  - Comment `// workaround: <reason>`, with the observable symptom.
  - Existing examples worth imitating: `.permissiveContentTransformations` on
    the model, and `TranslatorPanel`'s refusal to reopen right after AppKit
    dismissed the popover on the same click.

- **Dead branch.** The condition guards against something that "shouldn't
  happen but just in case". Then:
  - Comment `// dead: <reason>`, or delete it.
  - Do not add a silent `return` that hides a bug. In this app the honest
    failure mode is a message in the popover — visible, harmless, and
    reportable.

"Just-in-case `if`" is an anti-pattern. Every such check masks a bug elsewhere.

---

## 5. Reproduce before you fix

The automated net reaches only the pure logic (see
[`testing/README.md`](testing/README.md)), so for anything else the burden of
proof is on you:

1. Reproduce the bug manually on a supported Mac and write down the exact
   steps and the observed wrong behaviour.
2. Change the production code.
3. Re-run the same steps and record the corrected behaviour.
4. Put both, verbatim, in the PR description or the plan's `Details` block.

If the fixed logic is pure (formatting, lookup, parsing, merging), add a real
test instead. If it lives in `Sources/EasyWrite/` and cannot be tested there,
moving it into `EasyWriteCore` is a change to the package layout — declare it
rather than doing it silently.

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
- Add a second pasteboard write, or move the one that exists out of
  `Clipboard.write`.
- Reintroduce `CGEvent` or any other synthetic input, or add an Accessibility
  check. The app requests no permission, and that is a headline claim.
- Stop honouring the nspasteboard concealed and transient markers by default.
- Rewrite the architecture — SwiftUI `App` lifecycle, an actor-based redesign,
  a new dependency-injection layer.
- Flip `.swiftLanguageMode(.v5)` to Swift 6 mode, change the minimum macOS
  version, or restructure the package targets.
- Change conventions: 4 spaces → tabs, English → another language,
  main-actor-by-default → ad-hoc queues.
- Touch `setup-signing.sh` or the signing logic in `build.sh`.
- Edit `Info.plist` bundle identity (`CFBundleIdentifier`, `LSUIElement`).
- Add an entitlement or request any permission at all.

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
./setup-signing.sh          # optional, one-time: stable self-signed identity
./build.sh                  # release build → EasyWrite.app → codesign
open EasyWrite.app
```

`./build.sh` signs with the "Easy Write Self-Signed" identity when it exists and
falls back to ad-hoc signing otherwise, whose signature changes on every build.
With no permission to lose that no longer costs a grant, but a stable identity is
still the better default.

### Tests

```bash
./test.sh                   # the suite; wraps `swift test`
./test.sh --filter TranslationCacheTests
```

Use `./test.sh` rather than `swift test` directly: with only the Command Line
Tools installed, `swift test` cannot find the swift-testing framework. See
[`testing/README.md`](testing/README.md) before writing any tests, and be precise
about what passing them does and does not prove.

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
