# Feature: Clipboard Read-Only Invariant

> **Sequenced after [`1_popup-translator.md`](1_popup-translator.md) and dependent
> on it.** Every item below assumes `Replacer.swift` is already deleted and the app
> no longer writes the pasteboard. None of it can be done first.

## Overview

After the popup translator ships, Easy Write reads the clipboard and never writes
it — except in the one path behind the popover's **Copy** button. Two things are
still missing at that point, and this document specifies them: five documents
state the clipboard rule as repo law, across nine separate locations, and every
one of them describes the *old* mechanism; and nothing says what the popover
declines to read.

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

## Questions Settled Before Implementation

Two gaps in [`1_popup-translator.md`](1_popup-translator.md) were recorded here
because this document depends on it. Both were decided by the user before any code
was written, and both are now closed:

- **An edited left pane survives a reopen.** The popover re-reads the clipboard
  only when the clipboard has changed since the last read, tracked by
  `NSPasteboard.changeCount`. Copying something new therefore replaces the pane,
  and reopening on an unchanged clipboard keeps whatever the user typed. The Copy
  button records the change count of its own write, so pressing Copy does not make
  the translation look like new clipboard content on the next open
  (`Sources/EasyWrite/TranslatorModel.swift:70` and `:92`).
- **`.cursor/rules/swift-code-standards.mdc` is covered here.** Step 1 covers the
  clipboard rule; the stale `ReaderPanel` example in the same file is fixed in the
  same pass, along with the other stale example types listed there.

## Technical Specification

### Components Affected

Documentation — **five files, nine locations** that state or exemplify the
snapshot-and-restore mechanism as repo law, and that are **not** in the popup
spec's own documentation list. The list below is exhaustive as of this branch,
established by grepping `docs/**`, `.cursor/**` and the root Markdown files for
the whole concept (snapshot, restore, borrowed, pasteboard, clipboard) rather
than for one phrasing:

- `docs/requirements/0_TEMPLATE.md`
  - **line 141** — the non-negotiable privacy gate *"Clipboard
    snapshot-and-restore preserved on every path that touches the pasteboard"*.
    The most consequential location of the nine, because the template is copied
    into every future spec: left alone, it propagates a mandatory checkbox about
    a mechanism that no longer exists.
  - **line 123** — the edge case *"Target application is slow or handles copy
    unusually → fails visibly, clipboard intact"*, which presumes a synthetic ⌘C
    against a target application.
- `docs/plans/README.md`
  - **line 25** — the cross-cutting invariant *"The clipboard is snapshotted
    before a swap and restored after | The user's clipboard is borrowed, never
    taken"*, which every plan touching the clipboard must preserve.
- `docs/conventions/CODING_CONVENTIONS.md`
  - **line 164** — the delayed-closure guidance *"Use
    `DispatchQueue.main.asyncAfter` for short UI delays (icon revert, clipboard
    restore)"*. The pattern itself stays correct; the second example stops
    naming anything real, since the clipboard restore was the 0.35 s
    `asyncAfter` inside `Replacer`. Replace the example, not the rule.
  - **line 482** — security convention 5, *"**Clipboard is borrowed, not taken.**
    Snapshot every pasteboard item and type before a swap, restore afterwards"*.
  - **line 520** — the matching pre-commit checklist item.
- `docs/conventions/AI_WORKFLOW.md`
  - **line 67** — the PR checklist question *"Is the clipboard snapshot/restore
    path still intact?"*
  - **line 167** — the section 6 prohibition *"Remove the clipboard
    snapshot/restore around a swap"*, which read literally forbids the popup
    translator's own change.
- `.cursor/rules/swift-code-standards.mdc`
  - **line 74** — *"The clipboard is snapshotted before a swap and restored
    after."*

Code:

- `Sources/EasyWrite/Clipboard.swift` — the app's entire pasteboard surface: one
  function that reads and one that writes, plus the two `NSPasteboard.PasteboardType`
  markers the read checks. `1_popup-translator.md` left the location open, asking
  only that the read be a single function; a file that holds both sides makes the
  invariant a claim about one file rather than about control flow.
- `Sources/EasyWrite/Store.swift` and `PreferencesController.swift` — the setting
  behind the Step 3 decision.
- `Tests/EasyWriteCoreTests/PasteboardWriteGuardTests.swift` — the guard from
  Step 2. The workflow in flight on `ci/add-tests-and-workflow` has **not** landed
  on `main`, so the guard is a test rather than a CI step: it runs under
  `./test.sh`, needs no runner, and fails by naming the offending function.

Already scheduled elsewhere, and therefore deliberately **not** in scope here:
`SECURITY.md`, `README.md`, `HOW_IT_WORKS.md`, `docs/AI_Overview.md`,
`docs/conventions/testing/README.md` and `.cursor/rules/project-conventions.mdc`
are all listed in [`1_popup-translator.md`](1_popup-translator.md), which also
carries the acceptance criterion *"`SECURITY.md` is updated, because its current
statements about `⌘C`/`⌘V`, clipboard restore, and Accessibility become false"*.
Re-specifying them here would duplicate work that already has an owner.

One caveat on that list: the upstream entry for
`docs/conventions/testing/README.md` is scoped to *"the manual smoke test is
rewritten around the popover"*, but section 2 of that file, *"Why the automatable
surface is small"* (lines 39-43), also cites `ReaderPanel` and `Replacer` posting
synthetic ⌘C/⌘V. Whoever rewrites the file should read all of it rather than only
the smoke test.

### Settings & Persistence Changes

One key, added by the Step 3 decision.

| Key | Type | Default | Triggers `onChange?()` | Why |
|---|---|---|---|---|
| `ignoresPrivateClipboard` | `Bool` | `true` | no | The read function checks it each time; nothing else depends on it |

The default is `true`, so a fresh install protects a copied password without being
asked. Because `UserDefaults.bool(forKey:)` cannot tell "off" from "absent", `Store`
reads it as `d.object(forKey:) as? Bool ?? true`. An existing user gets the
protective default on first launch after the update and can turn it off.

### Implementation Details

#### Step 1: State the invariant where it is repo law

Replace the snapshot-and-restore wording at all nine locations with the guarantee
the code will then actually keep:

> **Easy Write reads the pasteboard and never writes it, except in the single code
> path behind the popover's Copy button.**

This is a stronger promise than the one it replaces, and a far cheaper one to
check. The v1.x rule required reasoning about control flow across every exit of a
long method, which is why it stayed quietly false. The new rule is a count of call
sites.

`CODING_CONVENTIONS.md:164` is the one exception to that wording swap: it is a
concurrency pattern rather than a promise, so it keeps its rule and loses only its
second example.

The same five files carry two further classes of staleness on adjacent lines,
because v2 requests no permission at all and deletes two types. Fix them in the
same pass, or record why not:

- **Accessibility and `CGEvent`** — including the AppKit inventory at
  `CODING_CONVENTIONS.md:329`, which lists `CGEvent` as part of the shell.
- **Deleted types still cited as examples** — `Replacer` and `ReaderPanel` appear
  as illustrations at `CODING_CONVENTIONS.md:99`, `114`, `176`, `179`, `181`,
  `229`, `237`, `492`, at `AI_WORKFLOW.md:121`, at `0_TEMPLATE.md:177` and `198`,
  and at `plans/README.md:95`. One further file is affected by this class alone
  and by nothing else in this document: `docs/conventions/RELEASE_NOTES_GUIDE.md:24`
  names `ReaderPanel` in its list of type names.

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

[`1_popup-translator.md`](1_popup-translator.md) specifies *when* the clipboard is read (on every open) and
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

**Decision:** either marker means "no usable text", and a checkbox in Preferences
lets the user opt out. The checkbox is on by default, so the protective behaviour
is what everyone gets without choosing it, and the state is already specified —
empty panes, no model call — so declining is indistinguishable from the image case
and costs three lines in the read function.

The reason for making it a setting rather than a fixed rule is that the marker is
a convention, not a guarantee, and the app cannot tell a password from an
application being over-cautious with something the user genuinely wants
translated. A user who hits that has no other way out: the app would silently show
empty panes for text that is plainly on their clipboard. The escape hatch is one
checkbox, off the default path, and it cannot weaken the write invariant — that
one has no setting, because a promise with an off switch is not a promise.

A declined read reaches nothing: the input pane stays empty, so no key is ever
built and the cache is never consulted or written.

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

- [x] All nine locations listed under Components Affected state the read-only invariant, or lose their stale example; none still describes snapshot-and-restore
- [x] A repo-wide grep for the restore concept (snapshot, restore, borrowed, pasteboard, clipboard) across `docs/**`, `.cursor/**` and the root Markdown files returns no surviving description of the deleted mechanism
- [x] A spec written from `0_TEMPLATE.md` after v2 can complete its privacy checklist truthfully
- [x] Exactly one code path under `Sources/` writes the pasteboard, and it is behind the popover's **Copy** button
- [x] The guard fails a pull request that adds a second pasteboard write — demonstrated by adding a second write, watching the test fail and name it, then reverting
- [x] The Step 3 decision is recorded in this file with its reason

### Edge Cases & Error Handling

- [x] Pasteboard marked `org.nspasteboard.ConcealedType` → empty panes, no model call, nothing cached. Run on a supported Mac: with a concealed string on the pasteboard the app produced no translation and left the pasteboard untouched; with the setting off it translated normally
- [x] Pasteboard marked `org.nspasteboard.TransientType` → same, and it is the same call: one `availableType(from: [.concealed, .transient])` covers both markers, so there is no second branch to test
- [x] Marker present but no string representation → already the empty case; no new branch added
- [x] Marker present on a later open after an ordinary first open → the check lives in the read function, which runs per open, so the decision applies per read
- [x] Copy button pressed → the pasteboard is written, and this is the one exemption, not a loophole

### User Experience

- [x] Declining to read produces the same empty popover as an image: no new string, no dialog, no beep
- [x] The one new string, the Preferences checkbox and its caption, is English, sentence case, typographic punctuation, no emoji

### Privacy Impact

Non-negotiable. Every box must be checked, or the work does not ship:

- [x] No network code added (`URLSession`, sockets, or otherwise)
- [x] No third-party dependency added to `Package.swift`
- [x] No analytics, telemetry, or crash reporting
- [x] No `print` / `os_log`, and no persistence of translated text
- [x] The pasteboard is read and never written, outside the **Copy** path
- [x] No permission is requested at all
- [x] Statements in `SECURITY.md` remain true

## Out of Scope

- **The v1.x defect and its exit-path analysis.** Removed with `Replacer.swift`,
  and deliberately not retained here as history.
- `SECURITY.md`, `README.md`, `HOW_IT_WORKS.md`, `docs/AI_Overview.md`,
  `docs/conventions/testing/README.md`, `.cursor/rules/project-conventions.mdc` —
  all scheduled by [`1_popup-translator.md`](1_popup-translator.md).
- The popover itself: streaming, the cache, the language row, the hot-key.
  [`1_popup-translator.md`](1_popup-translator.md) owns all of it.
- The CI workflow. Still in flight on `ci/add-tests-and-workflow`; the guard here
  is a test, so it does not wait on a runner. When that branch lands, `swift test`
  in its workflow picks the guard up with no further change.

## Development Information

### Testing Strategy

1. **Compile**: `swift build` warning-free, then `swift build -c release`. The
   documentation edits need no build.
2. **Automated**: the guard from Step 2 *is* the test for the write invariant. The
   read policy is not unit-testable under this repo's own rule —
   [`testing/README.md`](../conventions/testing/README.md) forbids a unit test
   from touching `NSPasteboard.general` — so it was exercised by running the built
   app instead.
3. **Manual verification**: `./build.sh && open EasyWrite.app` on macOS 26+ /
   Apple Silicon.

| # | Step | Expected |
|---|---|---|
| 1 | Copy a password from a password manager, press `⇧⌃Z` | Empty panes and no model call |
| 2 | Uncheck "Ignore private clipboard content", repeat step 1 | It reads and translates normally |
| 3 | Copy ordinary text, press `⇧⌃Z` | Normal behaviour |
| 4 | Translate, press **Copy**, wait 5 s, ⌘V elsewhere | The translation pastes; nothing has overwritten it |
| 5 | Translate without pressing **Copy**, then ⌘V elsewhere | The pre-existing clipboard content pastes; the app wrote nothing |

### What was actually run

On macOS 26.5.2, Apple Silicon, Apple Intelligence available. `swift build` and
`swift build -c release` are warning-free and `./test.sh` passes.

Steps 1–5 above were run against the built bundle, driven from a temporary hook in
`applicationDidFinishLaunching` that opened the popover, waited, pressed Copy and
quit — because macOS denies this environment both synthetic keystrokes and screen
capture, so the popover cannot be driven by hand from here. The hook was removed
before committing. Observed: a concealed pasteboard produced no translation and no
write; the same pasteboard with the setting off produced a Russian translation;
ordinary text produced a correct translation; and a translation without pressing
Copy left the original clipboard text in place.

What that does **not** cover: that the popover is positioned and rendered
correctly, and that Escape and click-outside dismiss it. Those need a human on a
supported Mac.

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
- The write invariant has no setting, and must not gain one. The read policy does,
  for the reason recorded in Step 3 — a marker the app cannot verify is a different
  kind of rule from a call site it can count.

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
  when an application reads the general pasteboard without a paste gesture. No
  prompt appeared across the runs recorded above, and the app requests no
  permission, but those runs did not watch for a passive indicator such as a menu
  bar glyph. Worth a look during the manual pass.

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
**Status**: In Progress — implemented and verified as recorded above; the popover's
on-screen behaviour still needs a human on a supported Mac
