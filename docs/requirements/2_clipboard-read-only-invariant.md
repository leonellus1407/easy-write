# Feature: Clipboard Read-Only Invariant

> **Sequenced after [`1_popup-translator.md`](1_popup-translator.md) and dependent
> on it.** Every item below assumes `Replacer.swift` is already deleted and the app
> no longer writes the pasteboard. None of it can be done first.

## Overview

After the popup translator ships, Easy Write reads the clipboard and never writes
it — except in the one path behind the popover's **Copy** button. Two things are
still missing at that point, and this document specifies them: five documents
state the clipboard rule as repo law and all five describe the *old* mechanism,
and nothing says what the popover declines to read.

**The v1.x defect this file originally described is resolved by deletion, not by a
fix.** v1.x borrowed the pasteboard for a synthetic ⌘C and gave it back from
exactly one place, so most ways out of a translation stranded the user's selection
on the clipboard. `1_popup-translator.md` deletes
`Sources/EasyWrite/Replacer.swift` — *"the only user of `CGEvent`; nothing drives
the keyboard any more"* — along with `ReaderPanel.swift`, the register modes, the
preview dialog, and read mode. The snapshot, the ⌘C, the ⌘V, the 0.35 s delayed
restore and every exit path that leaked are all gone. There is nothing left to
fix, and the analysis of it has been removed from this file rather than kept as
history.

What survives is much smaller, and it is not nothing. The popup spec asserts the
new behaviour as an acceptance checkbox on its own pull request — *"The clipboard
is only ever read, never overwritten, except when the user presses Copy"* — and a
ticked checkbox on a merged PR is not a standing guarantee for the codebase
afterwards. This file stays under `docs/requirements/` rather than moving to
[`docs/plans/`](../plans/README.md) because it keeps the `2_` number already in
use, and because it specifies a standing guarantee and a new read policy rather
than a patch.

## Technical Specification

### Components Affected

Documentation — five files that state the clipboard rule as repo law and are
**not** in the popup spec's own documentation list:

- `docs/requirements/0_TEMPLATE.md` (line 141) — the non-negotiable privacy gate
  *"Clipboard snapshot-and-restore preserved on every path that touches the
  pasteboard"*. The most consequential of the five, because the template is
  copied into every future spec: left alone, it propagates a mandatory checkbox
  about a mechanism that no longer exists.
- `docs/plans/README.md` (line 25) — the cross-cutting invariant *"The clipboard
  is snapshotted before a swap and restored after"*, which every plan touching
  the clipboard must preserve.
- `docs/conventions/CODING_CONVENTIONS.md` (lines 482, 520) — security convention
  5, *"Clipboard is borrowed, not taken. Snapshot every pasteboard item and type
  before a swap, restore afterwards"*, and the matching pre-commit checklist item.
- `docs/conventions/AI_WORKFLOW.md` (lines 67, 167) — the PR checklist question
  *"Is the clipboard snapshot/restore path still intact?"* and the section 6
  prohibition *"Remove the clipboard snapshot/restore around a swap"*, which read
  literally forbids the popup translator's own change.
- `.cursor/rules/swift-code-standards.mdc` (line 74) — *"The clipboard is
  snapshotted before a swap and restored after."*

Code:

- The popover's clipboard read. `1_popup-translator.md` does not pin down which
  type performs it — only that `togglePopup()` re-reads on open. Wherever it
  lands, `TranslatorModel` or the `AppDelegate` toggle, it must be a single
  function, so the read policy in Step 3 has one place to live.
- `.github/workflows/ci.yml` — one added step, **if** the workflow in flight on
  `ci/add-tests-and-workflow` has landed by then. If it has not, the guard is a
  checklist line instead and this part drops.

Already scheduled elsewhere, and therefore deliberately **not** in scope here:
`SECURITY.md`, `README.md`, `HOW_IT_WORKS.md`, `docs/AI_Overview.md`,
`docs/conventions/testing/README.md` and `.cursor/rules/project-conventions.mdc`
are all listed in `1_popup-translator.md`, which also carries the acceptance
criterion *"`SECURITY.md` is updated, because its current statements about
`⌘C`/`⌘V`, clipboard restore, and Accessibility become false"*. Re-specifying
them here would duplicate work that already has an owner.

### Settings & Persistence Changes

**None.** No new key, no change to `Store`, no migration, nothing new in
`UserDefaults`. An existing user sees no upgrade behaviour, because no stored
state is involved.

### Implementation Details

#### Step 1: State the invariant where it is repo law

Replace the snapshot-and-restore wording in all five documents with the guarantee
the code will then actually keep:

> **Easy Write reads the pasteboard and never writes it, except in the single code
> path behind the popover's Copy button.**

This is a stronger promise than the one it replaces, and a far cheaper one to
check. The v1.x rule required reasoning about control flow across every exit of a
long method, which is why it stayed quietly false. The new rule is a count of call
sites.

The same five documents carry equally stale Accessibility statements, because v2
requests no permission at all. Those lines sit next to these ones — fix both in
the same pass, or record why not.

#### Step 2: Make it mechanically checkable

`CODING_CONVENTIONS.md` argues that the absence of network code *"is verifiable by
grep, and that is the point"*. That now applies here too. The pasteboard-writing
API is a closed list — `clearContents`, `writeObjects`, `setString`, `setData`,
`setPropertyList`, `declareTypes`, `prepareForNewContents` — so one `rg` over
`Sources/`, asserting a single matching call site, enforces the invariant outright
instead of asking a reviewer to remember it.

The check needs no Swift toolchain, so it does not have to wait on the macOS
build: it can be its own cheap job in `ci.yml` and report independently of
whether the compile succeeded.

#### Step 3: Decide what the popover refuses to read

`1_popup-translator.md` specifies *when* the clipboard is read (on every open) and
what happens when it holds nothing usable (empty panes, no model call; an image
leaves the left pane empty). It does not specify what the popover declines to read
when a string *is* available.

Password managers mark a copied credential with `org.nspasteboard.ConcealedType`,
and applications that put something on the pasteboard momentarily mark it
`org.nspasteboard.TransientType`. Under the popup design as written, copying a
password and then pressing `⇧⌃Z` seeds the left pane with it, renders it on
screen, sends it to the on-device model, and stores it in the twenty-entry cache
for the life of the process.

Nothing leaves the Mac, so this is not an exfiltration bug. It is the same
judgement the popup spec already makes in keeping the cache in memory: the app
should not surface content whose source explicitly asked tools not to read it.

**Recommendation:** treat either marker as "no usable text". That state is already
specified — empty panes, no model call — so the behaviour is indistinguishable
from the image case and costs a few lines in the read function. Seeding it anyway,
on the grounds that the user pressed the hot-key deliberately, is defensible; if
that is chosen it should be chosen explicitly and written down here rather than
arrived at by omission. Either way a concealed read must never reach the cache.

### Code Patterns to Follow

The markers are plain type strings with an empty payload, so the check is a type
lookup rather than a data read:

```swift
extension NSPasteboard.PasteboardType {
    /// nspasteboard.org convention: the source declared this payload sensitive.
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    /// nspasteboard.org convention: the source will replace this payload within seconds.
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}
```

## Acceptance Criteria

### Functional Requirements

- [ ] All five documents state the read-only invariant; none still describes snapshot-and-restore
- [ ] A spec written from `0_TEMPLATE.md` after v2 can complete its privacy checklist truthfully
- [ ] Exactly one code path under `Sources/` writes the pasteboard, and it is behind the popover's **Copy** button
- [ ] The grep guard fails a pull request that adds a second pasteboard write
- [ ] The Step 3 decision is recorded in this file with its reason, whichever way it goes

### Edge Cases & Error Handling

- [ ] Pasteboard marked `org.nspasteboard.ConcealedType` → per the Step 3 decision, and never cached
- [ ] Pasteboard marked `org.nspasteboard.TransientType` → same
- [ ] Marker present but no string representation → already the empty case; no new branch needed
- [ ] Marker present on a later open after an ordinary first open → the decision applies per read, not per session
- [ ] Copy button pressed → the pasteboard is written, and this is the one exemption, not a loophole

### User Experience

- [ ] Declining to read produces the same empty popover as an image: no new string, no dialog, no beep
- [ ] If a string is added anyway it is English, sentence case, typographic punctuation, no emoji

### Privacy Impact

Non-negotiable. Every box must be checked, or the work does not ship:

- [ ] No network code added (`URLSession`, sockets, or otherwise)
- [ ] No third-party dependency added to `Package.swift`
- [ ] No analytics, telemetry, or crash reporting
- [ ] No `print` / `os_log`, and no persistence of translated text
- [ ] The pasteboard is read and never written, outside the **Copy** path
- [ ] No permission is requested at all
- [ ] Statements in `SECURITY.md` remain true — v2 rewrites that file, and this work must not make the rewrite false again

## Out of Scope

- **The v1.x defect and its exit-path analysis.** Removed with `Replacer.swift`,
  and deliberately not retained here as history.
- `SECURITY.md`, `README.md`, `HOW_IT_WORKS.md`, `docs/AI_Overview.md`,
  `docs/conventions/testing/README.md`, `.cursor/rules/project-conventions.mdc` —
  all scheduled by `1_popup-translator.md`.
- The popover itself: streaming, the cache, the language row, the hot-key.
  `1_popup-translator.md` owns all of it.
- Whether reopening the popover should overwrite an edited left pane. A real
  ambiguity in the popup design, but a question about toggle semantics rather
  than about the clipboard; it belongs in `1_popup-translator.md`.
- Adding the test target or the CI workflow. In flight on
  `ci/add-tests-and-workflow`; this document only adds one step to a workflow that
  exists by then.

## Development Information

### Testing Strategy

1. **Compile**: `swift build` warning-free, then `swift build -c release`. The
   documentation edits need no build.
2. **Automated**: the grep guard from Step 2 *is* the test for the write
   invariant. The read policy is not unit-testable under this repo's own rule —
   [`testing/README.md`](../conventions/testing/README.md) forbids a unit test
   from touching `NSPasteboard.general`.
3. **Manual verification**: `./build.sh && open EasyWrite.app` on macOS 26+ /
   Apple Silicon.

| # | Step | Expected |
|---|---|---|
| 1 | Copy a password from a password manager, press `⇧⌃Z` | Per the Step 3 decision; with the recommendation, empty panes and no model call |
| 2 | Copy ordinary text, press `⇧⌃Z` | Normal behaviour, unchanged |
| 3 | Translate, press **Copy**, wait 5 s, ⌘V elsewhere | The translation pastes; nothing has overwritten it |
| 4 | Translate without pressing **Copy**, then ⌘V elsewhere | The pre-existing clipboard content pastes; the app wrote nothing |

**This document was written on Linux. Nothing in it has been compiled or run.**
The package is macOS 26+ / Apple Silicon only. Every claim about the current
repository is read from the files at the cited lines.

### Considerations

#### Privacy & security

- The clipboard was the one place v1.x left user content outside its own process.
  v2 removes that by construction. What replaces it as the risk is what the app
  *reads* into a visible pane and a cache — which is the whole reason Step 3
  exists.
- Do not reintroduce a pasteboard write to make some later convenience work.
  `1_popup-translator.md` gives the same warning about synthetic keystrokes; the
  guard in Step 2 is what turns both warnings into something a reviewer cannot
  miss.
- Do not add a setting for any of this. A promise with an off switch is not a
  promise.

#### Maintainability

- One read function, one write call site. The v1.x defect existed because the
  restore was reachable from only two of many exits; the lesson is a single
  owner, not more call sites that each remember.
- Diff budget: ≤50 added lines per Swift file
  ([`AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md#3-diff-size-budget)). The read
  guard is a handful of lines and nothing here approaches the limit.

#### Known Gotchas

- The `org.nspasteboard.*` markers are a developer convention (nspasteboard.org),
  honoured by clipboard managers such as Maccy and Yoink, **not** an Apple API.
  There is no compiler help: a typo in the type string silently disables the
  check.
- A `nil` string with a marker present and a `nil` string without one are
  different reasons for the same empty pane. Do not collapse them into one branch
  without saying so.
- Builds and runs on macOS 26+ / Apple Silicon only.

### Unresolved

- Whether macOS 26 surfaces any system indication — a notification, a prompt —
  when an application reads the general pasteboard without a paste gesture. This
  could not be checked from Linux, and it changes how visible the popover's
  read-on-open is to the user. Confirm on a supported Mac before calling this
  done.

## References

### Related Documentation

- [`1_popup-translator.md`](1_popup-translator.md) — the prerequisite; owns the popover and the documentation it rewrites
- [Security & privacy](../../SECURITY.md) — the promise, as v2 will restate it
- [Plans](../plans/README.md) — the cross-cutting invariant table amended in Step 1
- [Coding conventions](../conventions/CODING_CONVENTIONS.md) — security convention 5 and the pre-commit checklist
- [AI workflow](../conventions/AI_WORKFLOW.md) — the PR checklist and the section 6 prohibitions
- [Testing guide](../conventions/testing/README.md) — why the read policy gets no unit test

### External Resources

- [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)
- [nspasteboard.org](http://nspasteboard.org/) — the concealed, transient, and auto-generated markers

---

**Created**: 2026-08-26
**Status**: Planning
