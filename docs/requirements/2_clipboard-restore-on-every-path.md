# Defect: Clipboard Is Not Restored on Non-Replacing Paths

## Overview

Easy Write borrows the user's clipboard to capture a selection, and gives it back
in exactly one place. Every other way out of a translation — read mode above
all, but also a cancelled preview, an unusable selection, an empty result, and a
failed or timed-out call — returns without restoring, leaving the copied
selection on the system clipboard indefinitely and destroying whatever the user
had there. Read mode (`⌥⌘E`) is the widest case: it never replaces anything, so
it never restores, ever. This document specifies the defect and the invariant
that should replace it. **It deliberately does not choose the fix** — the design
has real trade-offs around the asynchronous paste, and that decision is being
taken separately.

A note on where this file lives. [`README.md`](README.md) sends fixes to
[`docs/plans/`](../plans/README.md) and keeps this directory for new features.
This one is filed here by explicit request, because what is being specified is
not a patch but an invariant the product already claims to have: the
`0_TEMPLATE.md` privacy checklist demands it, `SECURITY.md` promises it to
users, and the code does not honour it. The eventual code change still deserves
a plan of its own.

**Everything below is read from the source at the cited lines on a Linux
machine. Nothing here was reproduced.** The package targets macOS 26+ / Apple
Silicon and cannot be built or run here. Confirming the reproduction on a
supported Mac is the first task for whoever picks this up — see
[`docs/plans/README.md`](../plans/README.md#evidence) on the difference between
"reproduced" and "read from the code".

## Technical Specification

### Observed Behaviour

`Replacer` holds one snapshot of the pasteboard in a stored property:

```swift
private var saved: [NSPasteboardItem] = []
```

It is assigned in exactly one place — `Replacer.copySelection()` at
`Sources/EasyWrite/Replacer.swift:15`, before the synthetic ⌘C — and written
back in exactly one place, inside `Replacer.replaceSelection(with:)` at
`Sources/EasyWrite/Replacer.swift:36-41`:

```swift
let restore = saved
DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
    guard let self else { return }
    self.pasteboard.clearContents()
    if !restore.isEmpty { self.pasteboard.writeObjects(restore) }
}
```

`replaceSelection(with:)` has two callers, both in `AppDelegate`: the
replace-immediately path at `Sources/EasyWrite/AppDelegate.swift:226`, and the
**Replace** button of the preview dialog at
`Sources/EasyWrite/AppDelegate.swift:254`. `saved` is never cleared, and no
other code path restores it. Every other exit from
`AppDelegate.translate(register:toEnglish:)` therefore ends with the captured
selection sitting on the clipboard.

Two consequences are worth stating separately, because neither is obvious from
the exit-path table alone:

- **The loss is permanent, not temporary.** Because `saved` is only ever
  reassigned by the next `copySelection()`, the following run snapshots the
  *leaked selection* rather than the user's original content. One non-restoring
  exit is enough to destroy the original for good.
- **The loss is silent.** There is no beep, no icon change, and no dialog that
  distinguishes "the app gave your clipboard back" from "the app kept it". The
  user discovers it at the next ⌘V.

### Reproduction — Read Mode (the widest case)

Read mode never pastes and therefore has no restoring path at all. This is not
an edge case; it is what read mode does on every single run.

1. On macOS 26+ / Apple Silicon with Apple Intelligence enabled, build and
   launch the app: `./build.sh && open EasyWrite.app`. Grant Accessibility when
   prompted.
2. In TextEdit, type `CLIPBOARD-SENTINEL-1`, select it, and press ⌘C. This is
   the content the app promises to give back.
3. Open a web page in Safari containing text in a foreign language.
4. Select a sentence of it and press `⌥⌘E` (Read → English).
5. The floating reader panel appears near the cursor with the English text.
   Dismiss it with **Done**, or let it auto-dismiss after ~30 s
   (`Sources/EasyWrite/ReaderPanel.swift:47-50`).
6. Click into TextEdit and press ⌘V.

**Expected:** `CLIPBOARD-SENTINEL-1` is pasted.
**Actual (read from the code):** the foreign sentence from step 4 is pasted.
`CLIPBOARD-SENTINEL-1` is gone and cannot be recovered from the app.

Step 5 is deliberately written to cover both dismissals: neither **Done** nor
the auto-dismiss restores anything, because nothing in `ReaderPanel` or in the
read branch at `Sources/EasyWrite/AppDelegate.swift:217-219` touches the
snapshot.

### Exit Paths and What the Clipboard Holds Afterwards

Complete enumeration of every return from
`AppDelegate.translate(register:toEnglish:)`. "Restored" means the user's
pre-translation clipboard is back.

| # | Exit path | Code | Clipboard afterwards | Restored |
|---|---|---|---|---|
| 1 | Aborted before the capture — another translation in flight, Accessibility missing, or the model unavailable | `AppDelegate.swift:179-184` | Untouched; the snapshot is never taken | n/a |
| 2 | Nothing selected, so ⌘C is a no-op | `AppDelegate.swift:191`, `Replacer.swift:20-26` | Untouched; `changeCount` never moves and `copySelection()` returns `nil` | n/a — benign |
| 3 | Selection copies no string representation (an image in Preview, a file in Finder) | `Replacer.swift:22-24` | Holds whatever the target app put there; `changeCount` moved but `string(forType:)` was `nil`, so `copySelection()` still returns `nil` | **No** |
| 4 | Target app answers ⌘C after the ~0.6 s poll window | `Replacer.swift:20-26` | Holds the selection, written after the poll gave up | **No** |
| 5 | Selection is whitespace only | `AppDelegate.swift:191-194` | Holds the selection | **No** |
| 6 | Model returns an empty or whitespace-only result | `AppDelegate.swift:213-215` | Holds the selection | **No** |
| 7 | Translation throws — failure, timeout, or cancellation | `AppDelegate.swift:229-231` | Holds the selection | **No** |
| 8 | Read mode (`⌥⌘E`) — panel dismissed with **Done** or after ~30 s | `AppDelegate.swift:217-219` | Holds the selection | **No** |
| 9 | Read mode — panel dismissed with **Copy** | `ReaderPanel.swift:15-20` | Holds the English translation | Deliberate |
| 10 | Preview dialog → **Cancel** | `AppDelegate.swift:250-257` | Holds the selection | **No** |
| 11 | Preview dialog → **Copy** | `AppDelegate.swift:255-256`, `263-267` | Holds the translation | Deliberate |
| 12 | Preview dialog → **Replace** | `AppDelegate.swift:252-254` | Original content, ~0.35 s after the paste | Yes |
| 13 | Preview off, translation replaces the selection | `AppDelegate.swift:226` | Original content, ~0.35 s after the paste | Yes |

Two of the thirteen restore. Two more (rows 9 and 11) end with the clipboard
holding something the user explicitly asked for, which is correct and must stay
that way. Two never reach the pasteboard at all. The remaining **seven lose the
user's content**.

Rows 3 and 4 extend the exit-path note already in
[`docs/conventions/testing/README.md`](../conventions/testing/README.md). That
note is right that pressing a shortcut with genuinely nothing selected is
benign, but a `nil` return from `copySelection()` is a broader condition than
that one scenario: it means "no usable text was captured", which is not the same
as "the pasteboard was left alone". In rows 3 and 4 the pasteboard *was*
overwritten and the app then walked away from it. Row 4 also means the
template's own edge-case requirement — *"Target application is slow or handles
copy unusually → fails visibly, clipboard intact"*, at
[`0_TEMPLATE.md`](0_TEMPLATE.md) line 123 — is unmet today: it fails visibly,
but the clipboard is not intact.

### Why It Matters

**It contradicts the published security promise.** `SECURITY.md` tells users, in
the data-flow section:

> Your **clipboard is snapshotted before** a swap and **restored after**, so
> Easy Write doesn't clobber what you had copied.

Read literally, "before a swap" is narrow enough that read mode might be argued
outside it, since read mode performs no swap. That defence does not survive
contact with the sentence's own justification — *"so Easy Write doesn't clobber
what you had copied"* — which is unconditional, and it does not survive contact
with a user, who will not model "the app took my clipboard and kept it" as
compliant. Read mode snapshots the clipboard and then overwrites it, which is
the whole of the promise except the last step.

**It breaks a cross-cutting invariant.** [`docs/plans/README.md`](../plans/README.md#cross-cutting-invariants)
lists among the invariants that any work touching the clipboard must preserve:

> | The clipboard is snapshotted before a swap and restored after | The user's clipboard is borrowed, never taken |

Today the clipboard is taken. [`CODING_CONVENTIONS.md`](../conventions/CODING_CONVENTIONS.md)
states the same rule as security convention 5 — *"**Clipboard is borrowed, not
taken.** Snapshot every pasteboard item and type before a swap, restore
afterwards"* — and its commit checklist widens it past the word "swap" to
*"Clipboard snapshot/restore preserved on any path that touches the
pasteboard"*. The requirements template makes it a non-negotiable privacy gate:
*"Clipboard snapshot-and-restore preserved on every path that touches the
pasteboard"*, at [`0_TEMPLATE.md`](0_TEMPLATE.md) line 141. That box cannot
honestly be ticked by anybody today, on any feature, which quietly devalues the
checklist itself.

**The privacy cost is real, not theoretical.** The app's strongest claim is that
user text lives in memory for one translation and is never persisted. Leaving
the captured selection on the system pasteboard hands that text to every
application on the Mac, and to clipboard-history utilities — Raycast, Alfred,
Paste, Maccy — which exist precisely to write clipboard contents to disk. The
app does not persist the text; it arranges for something else to. Read mode
makes this worst: it is the mode used on text the user cannot edit, which is
typically somebody else's content in an email, a document, or a web page.

**The collateral damage compounds.** As noted above, the original clipboard is
lost permanently after the first non-restoring exit. A user who reads three
paragraphs with `⌥⌘E` has had their clipboard replaced three times and will
never get the original back.

### Desired Behaviour

Stated as an invariant, not an implementation:

> **A translate action either leaves the pasteboard exactly as it found it, or
> leaves on it only what the user explicitly asked to be there. There is no
> third outcome.**

Two corollaries follow, and both are testable:

1. The intermediate values the app writes to the pasteboard — the captured
   selection written by the target app's ⌘C, and the translation written by
   `replaceSelection(with:)` at `Sources/EasyWrite/Replacer.swift:32-33` — are
   never the final state of the pasteboard. They are transport, not results.
2. "What the user explicitly asked to be there" means exactly the two **Copy**
   buttons (rows 9 and 11 above). Nothing else may claim that exemption, and a
   restore must never fire after one of them and undo it.

An empty original clipboard is a real state, not a missing one: if the user had
nothing copied, the invariant is satisfied by an empty pasteboard, not by
leaving the selection on it. The current code already gets this right —
`clearContents()` at `Sources/EasyWrite/Replacer.swift:39` runs unconditionally
and only `writeObjects` is guarded by `!restore.isEmpty` — and a fix must not
regress it into "skip the restore when the snapshot is empty".

### Components Affected

No file is changed by this document. These are the files a fix will be in play
across, so that the eventual plan starts from a real list:

- `Sources/EasyWrite/Replacer.swift` — owns `saved` and the only restore; the
  restore has to move, or gain a second entry point
- `Sources/EasyWrite/AppDelegate.swift` — owns every exit path in the table,
  including every guard that aborts after the capture has already happened
- `Sources/EasyWrite/ReaderPanel.swift` — read mode's surface; its **Copy**
  button is one of the two legitimate exemptions and must keep working
- `docs/conventions/testing/README.md` — smoke-test step 8 was narrowed to the
  replacing paths and must be widened again; the "Why step 8 is scoped" section
  (lines 193-222) is deleted when the fix lands
- `SECURITY.md` — no change if the fix lands, since the fix makes its existing
  statement true; a change only if the decision goes the other way (see
  Privacy Impact)
- `CHANGELOG.md` and `Info.plist` — the fix is user-visible and needs a release
  entry and a version bump

`Package.swift` is untouched under every option considered here.

### Settings & Persistence Changes

**None.** No new key, no change to `Store`, no migration, and nothing new
written to `UserDefaults`. The snapshot is an in-memory array of
`NSPasteboardItem` (`Sources/EasyWrite/Replacer.swift:9`) that dies with the
process, and it must stay that way — persisting a clipboard snapshot across
launches would be a far larger privacy regression than the defect it fixes.

Existing users see no upgrade behaviour on first launch after the fix, because
there is no stored state involved.

### Design Considerations for the Fix

The template's `Implementation Details` section is replaced here, because
choosing the implementation is explicitly deferred. What follows is what the
implementer needs to know before choosing, in the order it will bite.

#### The restore must move to a point every path passes through

Placing the restore inside `replaceSelection(with:)` is what caused this defect:
the restore is reachable only from the operation that happens to paste. Two
shapes are available.

- **A `defer` in `translate`, immediately after a successful capture.** The
  release then belongs to the same scope as the acquisition, and a future exit
  path inherits it instead of having to remember it. This is the property that
  matters: the bug is not that seven paths forgot to call restore, it is that
  restoring was opt-in.
- **An explicit release step owned by the caller** — a `replacer.release()`
  paired with `copySelection()` at each exit. Symmetric and easy to read, but it
  reintroduces exactly the failure mode above, since the eighth exit path added
  next year has to opt in again.

Note that a `defer` placed in the `Task` at
`Sources/EasyWrite/AppDelegate.swift:207-232` covers the preview dialog
correctly: `alert.runModal()` blocks, so the modal has already returned by the
time the scope exits. It does *not* naturally cover the pasting paths, for the
next reason.

#### The paste is asynchronous, and restoring too early is a worse bug

`replaceSelection(with:)` posts ⌘V and assumes it landed
(`Sources/EasyWrite/Replacer.swift:35`); there is no completion signal.
[`docs/AI_Overview.md`](../AI_Overview.md#constraints-gotchas-and-design-decisions)
records both that "the app pastes and assumes the paste landed" and that
delaying the restore until the paste has been consumed is load-bearing timing.
The 0.35 s in `Sources/EasyWrite/Replacer.swift:37` is that delay, and it is why
the restore lives where it does.

Restoring before the target app has read the pasteboard means the target pastes
the user's *old clipboard* into their document instead of the translation. That
is strictly worse than the current defect: it silently writes wrong text into
the user's work, rather than silently losing something they can see is missing.
Any fix must keep a delayed restore on the two pasting paths, while not
inheriting that delay on the eleven paths that never paste.

#### Read mode can restore immediately — and so, arguably, can everything else

Read mode never pastes, so the pasteboard is free the moment `copySelection()`
returns the text. It does not need to wait for the model, the panel, or the
dismissal.

Generalising that observation produces a second design, and it is the more
interesting one:

- **Restore on exit.** Keep one snapshot for the whole run and give it back at
  the end. Minimal change, but the user's clipboard stays hostage for the entire
  translation — potentially several seconds of model time plus however long a
  dialog or panel is on screen.
- **Restore straight after the capture, and re-borrow at paste time.** The
  clipboard is held for the ~0.6 s of the capture poll, released, and then
  borrowed again for the ~0.35 s around the paste. The leak window becomes
  bounded by construction rather than by remembering to close it, and read mode
  gets the correct behaviour for free because it simply never takes the second
  borrow.

The second design also fixes a latent bug in the current one. `saved` is
captured before the model call, and restored after the paste. If the user copies
something new while the translation is running — entirely normal during a
multi-second call — the restore overwrites their new content with a stale
snapshot. Re-snapshotting immediately before the paste would preserve it. This
is read from the code, not reproduced.

#### The two Copy buttons must survive the fix

Both are the user deliberately claiming the clipboard, and both are currently
correct:

- `ReaderPanel`'s **Copy** (`Sources/EasyWrite/ReaderPanel.swift:15-20`) writes
  the English text and closes the panel.
- The preview dialog's **Copy** (`Sources/EasyWrite/AppDelegate.swift:255-256`,
  via `copyToClipboard` at lines 263-267) writes the translation.

Neither is the defect, and neither may be "fixed". The ordering hazard is
specific and easy to get wrong in each case:

- In the **preview dialog**, `runModal()` returns *before* the surrounding scope
  exits, so a `defer`-based restore fires *after* `copyToClipboard(text)` and
  wipes the translation the user just asked for. The release must become a no-op
  once the user has claimed the clipboard.
- In **read mode**, the panel is non-modal and appears immediately
  (`orderFrontRegardless()` at `Sources/EasyWrite/ReaderPanel.swift:44`), so the
  user can press **Copy** within milliseconds. A restore scheduled on a delay
  would land afterwards and wipe it. This is the concrete reason read mode wants
  an immediate restore rather than a delayed one — it is not merely an
  optimisation.

#### A second run can start while a restore is pending

`busy` makes translation single-flight (`Sources/EasyWrite/AppDelegate.swift:12`,
`179`, `208`), but `defer { busy = false }` runs when the `Task` scope exits,
which on the replacing path is as soon as `replaceSelection(with:)` returns —
about 0.35 s *before* its restore fires. A second hot-key press inside that
window calls `copySelection()`, which snapshots a pasteboard that currently
holds the translation and then polls `changeCount`; the first run's pending
restore changes `changeCount` mid-poll. Whatever design is chosen has to state
what happens when a new run begins while a release is outstanding — cancel it,
await it, or make it idempotent. Read from the code; the window is narrow and
requires a deliberate double-trigger, so treat it as a design constraint rather
than a reported bug.

#### Smaller points, worth one line each

- `writeObjects` returns a discardable `Bool` that nothing checks
  (`Sources/EasyWrite/Replacer.swift:40`). If the restore becomes an invariant,
  silently dropping its failure is worth reconsidering — though the honest
  failure mode in this app is a beep, not a dialog.
- `saved` is never cleared after a successful restore. Nothing depends on that
  today because every run re-snapshots first, but a design that restores more
  than once per run must not assume a stale `saved` is safe to replay.
- `presentResult(_:allowReplace:)` is only ever called with `allowReplace: true`
  (`Sources/EasyWrite/AppDelegate.swift:222`), so its Copy/Done branch at lines
  258-260 is currently unreachable — read mode uses `ReaderPanel` instead. Do
  not spend effort restoring a path no one runs, and do not delete it as part of
  this work either.
- The diff budget in [`AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md#3-diff-size-budget)
  is 50 added lines per Swift file. Every option sketched here fits comfortably;
  if a proposal does not, that is a signal the design has grown a component.

### Code Patterns to Follow

The scope-bound release already exists in this codebase, guarding the busy flag
in `AppDelegate.translate(register:toEnglish:)`. A clipboard release wants the
same shape and the same guarantee:

```swift
// Async work from the main actor, with a reentrancy guard
busy = true
setIcon(busy: true)
Task { @MainActor in
    defer { busy = false }
    // every exit below inherits the release
}
```

The existing delayed restore is the pattern for the pasting paths, and the
reason it cannot simply be hoisted:

```swift
// Restore only after the target app has had time to consume the paste
let restore = saved
DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
    guard let self else { return }
    self.pasteboard.clearContents()
    if !restore.isEmpty { self.pasteboard.writeObjects(restore) }
}
```

And the snapshot itself is already correct — it preserves every representation
of every item, not just plain text, so a restore does not silently degrade rich
content into a string. It should not be simplified while the restore is being
moved:

```swift
for item in pasteboard.pasteboardItems ?? [] {
    let copy = NSPasteboardItem()
    for type in item.types {
        if let data = item.data(forType: type) { copy.setData(data, forType: type) }
    }
    items.append(copy)
}
```

## Acceptance Criteria

### Functional Requirements

- [ ] Read mode (`⌥⌘E`) leaves the clipboard holding the user's original content, on every dismissal — **Done** and the ~30 s auto-dismiss alike
- [ ] The preview dialog's **Cancel** leaves the clipboard holding the user's original content
- [ ] The replacing paths still paste the translation, and still restore afterwards — no regression on rows 12 and 13
- [ ] The reader panel's **Copy** leaves the English text on the clipboard and it stays there; no delayed restore overwrites it
- [ ] The preview dialog's **Copy** leaves the translation on the clipboard and it stays there
- [ ] The `0_TEMPLATE.md` privacy line *"Clipboard snapshot-and-restore preserved on every path that touches the pasteboard"* can be ticked honestly for the first time
- [ ] Smoke-test step 8 in [`docs/conventions/testing/README.md`](../conventions/testing/README.md) is widened back to every exit path, and the "Why step 8 is scoped" section is deleted rather than edited

### Edge Cases & Error Handling

- [ ] Empty or whitespace-only selection → single beep, no dialog, no crash, **clipboard intact**
- [ ] Model returns an empty result → icon flashes, clipboard intact
- [ ] Model times out or fails → icon flashes, app stays responsive, clipboard intact
- [ ] Target application is slow or handles copy unusually → fails visibly, clipboard intact (table row 4; the template already requires this and it is not met today)
- [ ] Selection has no string representation — an image in Preview, a file in Finder → beep, clipboard intact (table row 3)
- [ ] Nothing selected at all → beep, clipboard untouched, and the restore does not write an empty snapshot over content it never took (table row 2)
- [ ] User had nothing on the clipboard beforehand → it is empty afterwards, not holding the selection
- [ ] User had rich content — styled text, an image, a file promise — on the clipboard → every representation comes back, not just the plain-text one
- [ ] User copies something new *during* a translation → the newer content survives, or the behaviour is a documented decision rather than an accident
- [ ] Two translations triggered in quick succession → neither leaves a selection or a translation stranded on the clipboard
- [ ] Accessibility permission missing, model unavailable, or a translation already running → aborts before the capture, clipboard never touched

### User Experience

- [ ] No new user-facing string is required; if one is added it is English, sentence case, typographic punctuation, no emoji
- [ ] Feedback for a failure is unchanged — beep plus a flashed status icon, no new dialog
- [ ] The reader panel still does not steal focus, and still auto-dismisses
- [ ] The restore is invisible: the user never sees a flicker of the wrong content in a paste
- [ ] Nothing about the fix lengthens the perceived time between the hot-key and the result

### Privacy Impact

Non-negotiable. Every box must be checked, or the fix does not ship:

- [ ] No network code added (`URLSession`, sockets, or otherwise)
- [ ] No third-party dependency added to `Package.swift`
- [ ] No analytics, telemetry, or crash reporting
- [ ] No `print` / `os_log`, and no persistence of translated text
- [ ] Clipboard snapshot-and-restore preserved on every path that touches the pasteboard — **this is the entire point of the work**
- [ ] The snapshot itself stays in memory and is never written to `UserDefaults` or disk
- [ ] No permission requested beyond Accessibility
- [ ] Statements in `SECURITY.md` remain true

That last box is the one that needs a decision rather than a tick. It is
**false today** for read mode and for the six other non-restoring paths.
There are two ways to make it true:

1. **Fix the code**, so the existing sentence in `SECURITY.md` becomes accurate.
   This is the resolution this document assumes, and no edit to `SECURITY.md` is
   then needed.
2. **Narrow the promise**, rewriting `SECURITY.md` to say the clipboard is
   restored only when the translation is pasted back. This is a product
   decision, not an implementation detail, and it would also require amending
   the invariant in `docs/plans/README.md` and security convention 5 in
   `CODING_CONVENTIONS.md`. It should not be chosen by whoever happens to pick
   up the code.

## Out of Scope

- **The code change itself.** No file under `Sources/` is modified by this
  document, and no option in "Design Considerations" is selected here.
- Choosing between restore-on-exit and restore-after-capture. The trade-offs are
  laid out; the decision is the implementer's, with the user's agreement.
- Any rewording of `SECURITY.md`, `docs/plans/README.md`, or
  `CODING_CONVENTIONS.md` — see option 2 above; a change to any of them is a
  separate, deliberate decision.
- Editing [`docs/conventions/testing/README.md`](../conventions/testing/README.md).
  Widening step 8 is an acceptance criterion of the fix, not of this spec; the
  current narrowing is accurate for the current code and must stay until the
  behaviour changes.
- The two **Copy** buttons' semantics. They are correct and are only mentioned
  so a fix does not break them.
- The unreachable `allowReplace: false` branch of `presentResult`.
- Adding a test target. Nothing in this defect is unit-testable — it is
  pasteboard and Accessibility behaviour, which
  [`testing/README.md`](../conventions/testing/README.md) explicitly excludes
  from unit tests.
- The popup-translator rewrite specified in
  `docs/requirements/1_popup-translator.md`. If that ships, it deletes
  `Replacer.swift` and stops writing to the clipboard entirely, which dissolves
  this defect rather than fixing it. The two are alternatives, not dependencies,
  and this one is worth doing on its own because it is small and the rewrite is
  not.

## Development Information

### Testing Strategy

This repo has **no test target and no CI** — see
[`docs/conventions/testing/README.md`](../conventions/testing/README.md).

1. **Compile**: `swift build` warning-free, then `swift build -c release`.
2. **Manual verification**: `./build.sh && open EasyWrite.app` on macOS 26+ /
   Apple Silicon with Apple Intelligence enabled, after `./setup-signing.sh` has
   been run once.
3. **Automated**: none is possible. The behaviour is `NSPasteboard` plus
   synthetic `CGEvent`s against a live target application, which
   [`testing/README.md`](../conventions/testing/README.md) rules out of unit
   tests by convention ("No Accessibility, no pasteboard").

Manual steps specific to this defect. Every row starts by copying the sentinel
string `CLIPBOARD-SENTINEL-1` in TextEdit, so "sentinel returns" always means
the same thing. These rows are written to slot into the standard smoke test in
place of its current single step 8.

| # | Step | Expected |
|---|---|---|
| 8a | Copy the sentinel; select foreign text in Safari; `⌥⌘E`; dismiss with **Done**; ⌘V into TextEdit | Sentinel returns |
| 8b | Same, but let the panel auto-dismiss after ~30 s | Sentinel returns |
| 8c | Same, but press **Copy** in the panel | The English text is on the clipboard and stays there for at least 5 s |
| 8d | Copy the sentinel; enable "Preview before replacing"; translate; press **Cancel** | Sentinel returns |
| 8e | Same, but press **Copy** | The translation is on the clipboard and stays there for at least 5 s |
| 8f | Same, but press **Replace** | Translation pastes into the original app; sentinel returns within about a second |
| 8g | Copy the sentinel; preview off; translate with `⌥⌘T` | Selection is replaced; sentinel returns within about a second |
| 8h | Copy the sentinel; select only spaces; `⌥⌘T` | Beep; sentinel intact |
| 8i | Copy the sentinel; select an image in Preview; `⌥⌘T` | Beep; sentinel intact |
| 8j | Copy the sentinel; press `⌥⌘T` with nothing selected | Beep; sentinel intact |
| 8k | Copy the sentinel; turn off Apple Intelligence to force a failure; `⌥⌘T` | Icon flashes; sentinel intact |
| 8l | Copy the sentinel; start a translation of a long selection; copy `SENTINEL-2` while it runs; let it finish | `SENTINEL-2` survives, or the observed behaviour is recorded as a decision |
| 8m | Copy rich content — styled text or an image — then run 8a | Every representation returns, not only plain text |
| 8n | Empty the clipboard (`pbcopy < /dev/null`); run 8a | Clipboard is empty afterwards, not holding the selection |
| 8o | Press `⌥⌘T` twice within about half a second | Neither a selection nor a translation is stranded on the clipboard |

When the fix lands, the "Why step 8 is scoped to a replacing translation"
section of [`docs/conventions/testing/README.md`](../conventions/testing/README.md)
(lines 193-222) is deleted along with its exit-path table, because it documents
behaviour that will no longer exist.

**This spec was written on Linux. Nothing in it has been compiled, run, or
reproduced.** Every claim about current behaviour is read from the source at the
cited lines. Reproducing the defect on a supported Mac — step 8a is enough — is
the first task of the fix, per
[`AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md#5-reproduce-before-you-fix).

### Code Examples from Existing Features

- Scope-bound release that every exit path inherits: `defer { busy = false }` in `AppDelegate.translate(register:toEnglish:)`
- Delayed side effect after a synthetic keystroke: `Replacer.replaceSelection(with:)`
- Full-fidelity pasteboard capture across every representation: `Replacer.snapshot()`
- Modal dialog with actions, and re-activating the previous app: `AppDelegate.presentResult`
- Non-activating floating popup with auto-dismiss: `ReaderPanel.show(_:at:)`

### Considerations

#### Privacy & security

- The clipboard is the one place this app leaves user content outside its own
  process. Everything else — the selection, the translation — lives in memory
  for one call. That asymmetry is why this is a privacy defect and not a
  polish item.
- Do not "fix" it by clearing the pasteboard instead of restoring it. An empty
  clipboard is not what the user had, and destroying their content quietly is
  the same class of bug in a different direction.
- Do not add a setting for it. A promise with an off switch is not a promise,
  and the privacy checklist admits no per-user exemption.
- The permission surface does not move. Nothing here needs anything beyond the
  existing Accessibility grant.

#### Performance

- The `usleep` waits in `Replacer` and the 0.35 s restore delay are load-bearing
  ([`AI_Overview.md`](../AI_Overview.md#constraints-gotchas-and-design-decisions),
  [`CODING_CONVENTIONS.md`](../conventions/CODING_CONVENTIONS.md)). Do not
  shorten them to make a restore land sooner.
- Restoring after the capture rather than at the end of the run shortens the
  window in which the user's clipboard is unavailable from seconds to
  milliseconds. That is a user-visible improvement, not just tidiness.
- The snapshot copies every representation of every item, so a large clipboard —
  a big image, a long styled document — costs real memory for the duration of
  the borrow. Shortening the borrow shortens that too.

#### Maintainability

- Diff budget: ≤50 added lines per Swift file
  ([`AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md#3-diff-size-budget)). Every
  design considered here fits.
- Classify the new control flow, per
  [`AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md#4-invariants-and-if-checks).
  A guard that skips the restore because the user pressed **Copy** is an
  *invariant* check and should say which invariant, in the method name or a
  `///` comment. It is not a "just in case".
- Keep the restore in one place. The defect exists because it was in one place
  that only two callers could reach; the fix is one place every caller reaches,
  not seven call sites that each remember.
- `@MainActor` throughout, as today. No new type is needed for any option here.

#### Known Gotchas

- The paste is fire-and-forget: there is no signal that the target app consumed
  the pasteboard, only the 0.35 s guess.
- `changeCount` is the only capture signal, and it moves for reasons other than
  the app's own ⌘C — including the app's own pending restore.
- A `nil` from `copySelection()` does not mean the pasteboard is untouched. This
  is the trap that rows 3 and 4 of the exit-path table document.
- Ad-hoc signing loses the Accessibility grant on every rebuild — run
  `./setup-signing.sh` once before iterating on anything that drives the
  keyboard.
- Clipboard-history utilities running on the test machine will make the manual
  steps confusing, because they re-post content. Disable them for the smoke
  test.
- Builds and runs on macOS 26+ / Apple Silicon only.

## References

### Related Documentation

- [Security & privacy](../../SECURITY.md) — the promise this defect breaks
- [Plans](../plans/README.md) — the cross-cutting invariant table, and the evidence rules this document follows
- [Coding conventions](../conventions/CODING_CONVENTIONS.md) — security convention 5 and the commit checklist
- [AI workflow](../conventions/AI_WORKFLOW.md) — reproduce-before-you-fix, the diff budget, and the PR checklist item "Is the clipboard snapshot/restore path still intact?"
- [Testing guide](../conventions/testing/README.md) — smoke-test step 8 and the scoping note this document supersedes
- [Release notes guide](../conventions/RELEASE_NOTES_GUIDE.md) — the changelog entry the fix will need
- [Architecture tour](../../HOW_IT_WORKS.md) — the capture-and-replace flow
- [Repository overview](../AI_Overview.md) — why the timing is load-bearing

### Existing Similar Features

- Pasteboard capture, restore, and synthetic keystrokes: `Sources/EasyWrite/Replacer.swift`
- Every exit path in the table: `AppDelegate.translate(register:toEnglish:)` and `AppDelegate.presentResult(_:allowReplace:)`
- The read-mode surface and its **Copy** button: `Sources/EasyWrite/ReaderPanel.swift`

### External Resources

- [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)
- [NSPasteboardItem](https://developer.apple.com/documentation/appkit/nspasteboarditem)
- [changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)
- [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)

---

**Created**: 2026-08-26
**Status**: Planning
