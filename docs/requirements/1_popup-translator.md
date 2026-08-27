# Feature: Popup Translator

## Overview

Easy Write becomes a translator rather than a rewriter. One hot-key (`⇧⌃Z` by
default) or a click on the status icon opens a popover anchored to the menu-bar
icon. The popover fills its left pane from the clipboard, translates into the
right pane immediately, and streams the result as the model produces it. Source
and target language are dropdowns with a swap button between them, and the last
twenty translations are held in memory so a repeat is instant. The register
modes (formal / informal / plain), the in-place replacement, the preview dialog
and the read-to-English popup are all removed. Because nothing is pasted back
any more, the app stops posting synthetic keystrokes and therefore stops needing
the Accessibility permission — it ends up requiring no permission at all.

## Technical Specification

### Components Affected

Created:

- `Sources/EasyWrite/TranslatorPanel.swift` — owns the `NSPopover` anchored to the status button; show, close, toggle
- `Sources/EasyWrite/TranslatorView.swift` — SwiftUI content: language row, swap button, two panes, footer actions
- `Sources/EasyWrite/TranslatorModel.swift` — observable state for the popover: text, languages, phase, debounce, swap, retranslate
- `Sources/EasyWrite/Clipboard.swift` — the app's whole pasteboard surface, one read and one write; owned by [`2_clipboard-read-only-invariant.md`](2_clipboard-read-only-invariant.md)
- `Sources/EasyWriteCore/TranslationCache.swift` — in-memory LRU of the last twenty results

Moved:

- `Sources/EasyWrite/Languages.swift` → `Sources/EasyWriteCore/Languages.swift`, made `public`

Rewritten:

- `Sources/EasyWrite/LLMTranslator.swift` — drop `Register`, stream the response, reuse a prewarmed session, shorten the instruction
- `Sources/EasyWrite/AppDelegate.swift` — reduces to status item, one hot-key, `togglePopup()`, login item, and the gear actions

Trimmed:

- `Sources/EasyWrite/Store.swift` — add `sourceCode`, drop `previewBeforeReplace`, collapse `defaultShortcuts` to one entry
- `Sources/EasyWriteCore/Languages.swift` — drop `formal` and `informal`, add the `auto` sentinel and a `sources` list
- `Sources/EasyWrite/PreferencesController.swift` — one recorder row, keep the style guide, drop the language picker and preview toggle

Deleted:

- `Sources/EasyWrite/Replacer.swift` — the only user of `CGEvent`; nothing drives the keyboard any more
- `Sources/EasyWrite/ReaderPanel.swift` — superseded by the popover

Documentation and packaging:

- `SECURITY.md` — the permissions table loses its only row; the data-flow section stops describing paste-back
- `README.md`, `HOW_IT_WORKS.md`, `docs/AI_Overview.md` — product description, file map, and flow rewritten
- `docs/conventions/testing/README.md` — rewritten: the manual smoke test around the popover, and the suite that now exists
- `.cursor/rules/project-conventions.mdc` — the clipboard-swap and Accessibility rules no longer describe the app
- `CONTRIBUTING.md` — the Accessibility note and the preview-dialog suggestion
- `Info.plist` — version bump to 2.0, build 4
- `CHANGELOG.md` — release entry

`Package.swift` gains an `EasyWriteCore` library and an `EasyWriteCoreTests` test
target, mirroring the layout in flight on `ci/add-tests-and-workflow` so the two
merge cleanly. That is the [testing guide](../conventions/testing/README.md)'s
preferred shape, and it is what lets `TranslationCache` — the one genuinely
testable piece of new logic — be tested at all. `test.sh` is added alongside
`build.sh`, because `swift test` cannot find swift-testing when only the Command
Line Tools are installed. New files inside either source directory still need no
manifest edit, and Carbon is still required for the global hot-key.

### Settings & Persistence Changes

| Key | Type | Default | Triggers `onChange?()` | Why |
|---|---|---|---|---|
| `sourceLanguageCode` | `String` | `"auto"` | no | The popover reads it directly; no menu or hot-key depends on it |
| `targetLanguageCode` | `String` | `"de"` | no | Unchanged key, but the menu no longer shows languages, so the hook is dropped |
| `shortcuts` | `[String: Shortcut]` (JSON) | one `"translate"` entry, key code 6, mask 4608 | yes | Hot-keys must be re-registered when rebound |
| `styleGuide` | `String` | `""` | no | Read at translation time, as today |
| `previewBeforeReplace` | — | removed | — | The preview dialog no longer exists |

Upgrade behaviour for an existing user: `Store.shortcuts` merges decoded values
over `defaultShortcuts` on load (`Sources/EasyWrite/Store.swift:31-38`), so the
stored `formal`, `informal`, `plain` and `english` entries decode harmlessly and
are then never looked up, while `shortcut(for: "translate")` falls through to the
new default. No migration code is needed. The abandoned `previewBeforeReplace`
key is simply never read again. A user who had rebound a shortcut gets the new
`⇧⌃Z` default for the one remaining action.

`⇧⌃Z` is key code 6 with Carbon modifier mask 4608 — control 4096 plus shift
512, per the table in `KeyDisplay`.

Translated text is **not** persisted. The cache lives in memory and dies with
the process.

### Implementation Details

#### Step 1: Data and settings

Add `sourceCode` to `Store` with the established `didSet` write-through and no
`onChange?()`. Remove `previewBeforeReplace`. Replace the four entries in
`defaultShortcuts` with a single `"translate"` entry.

In `Languages`, remove the `formal` and `informal` fields from `Lang` — they
existed only to build menu labels and register instructions, both of which are
going away. Add a sentinel and a second list:

```swift
static let auto = Lang(code: "auto", name: "Auto-detect")
static var sources: [Lang] { [auto] + all }
```

`Languages.all` stays the target list; `auto` never appears in it.

#### Step 2: Core logic

`LLMTranslator` loses `Register` and gains streaming. The public call returns an
`AsyncThrowingStream<String, Error>` of cumulative text so the view can render
each snapshot as it arrives.

Session reuse is the main latency fix. Today `prewarm()` stores a session at
`Sources/EasyWrite/LLMTranslator.swift:65-69` that `runOnce` never uses — line
100 builds a fresh `LanguageModelSession` on every call, so each translation
pays a cold start. Instead, cache one session per instruction string, prewarm it
at launch, when either language changes, and again once a turn completes.
Rebuild it rather than reuse it across turns, because sessions are stateful and
a growing transcript would slow later requests and leak earlier text into
context.

`TranslationCache` is a small `@MainActor` type holding an array of key/value
pairs, capped at twenty, evicting least-recently-used. The key is a `Hashable`
struct of the source text plus the source code, target code, and style guide, so
editing the style guide cannot serve a stale result.

`TranslatorModel` is the popover's `ObservableObject`. It holds the input text,
the output text, the two language codes, and a phase (`idle`, `translating`,
`failed`). It owns the debounce (about 300 ms after an edit), cancels the
in-flight `Task` before starting another, consults the cache before calling the
model, and writes the finished result back into the cache. `retranslate()`
evicts the entry first, so the button always produces a fresh run.

#### Step 3: User interface

`TranslatorPanel` owns an `NSPopover` with `behavior = .transient`, shown
`relativeTo:` the status item button so macOS positions and anchors it. The app
calls `NSApp.activate(ignoringOtherApps: true)` before showing it: unlike the
reader panel, this popover takes focus deliberately, because the user types in
it and nothing is being pasted back, so stealing focus costs nothing.

`TranslatorView` lays out a language row (source picker, swap button, target
picker, gear button), two equal panes below it — an editable `TextEditor` on the
left seeded from the clipboard, selectable streamed text on the right — and a
footer with retranslate and copy. The swap button is disabled while the source
is `Auto-detect`, since there is no concrete language to move into the target
slot. Swapping keeps the left-pane text exactly as it is, exchanges the two
codes, and retranslates.

The gear button holds Preferences, Launch at Login and Quit; `statusItem.menu`
becomes `nil` so that a click on the icon reaches the button action instead of
opening a menu (it is currently assigned at
`Sources/EasyWrite/AppDelegate.swift:108`). `rebuildMenu()` and its helper go
away with it.

`AppDelegate` also loses the frontmost-application tracking, the Accessibility
check, and the Accessibility Settings menu item.

#### Step 4: Hot-key wiring

Three places must agree on the action key string `"translate"`:

1. `Store.defaultShortcuts` — `.init(keyCode: 6, modifiers: 4608)`
2. `AppDelegate.registerHotKeys()` — `register("translate") { [weak self] in self?.togglePopup() }`
3. `PreferencesView.actions` — the single recorder row

The status button's action calls the same `togglePopup()`, so a click and the
hot-key are indistinguishable. Toggle semantics: if the popover is open, close
it; if it is closed, open it, read the clipboard, and translate.

The read on open is conditional on `NSPasteboard.changeCount` having moved since
the last read, so an edit the user made in the left pane survives a close and
reopen while a freshly copied string still replaces it. That decision, and the
reason for it, are recorded in
[`2_clipboard-read-only-invariant.md`](2_clipboard-read-only-invariant.md).

One AppKit detail the toggle has to survive: a `.transient` popover is dismissed by
AppKit on the very click that then reaches the status button, so a naive toggle
closes and immediately reopens it. `TranslatorPanel` refuses an open that arrives
within a moment of a close, which is what makes a second click mean "close".

### Code Patterns to Follow

```swift
// A new setting on Store: persist in didSet, notify only if the UI depends on it
@Published var sourceCode: String {
    didSet { d.set(sourceCode, forKey: "sourceLanguageCode") }
}
```

```swift
// Anything that can stall races a timeout; a timeout is never retried
try await withThrowingTaskGroup(of: String.self) { group in
    group.addTask { /* consume the response stream */ }
    group.addTask { try await Task.sleep(nanoseconds: 20_000_000_000); throw TimeoutError() }
    defer { group.cancelAll() }
    return try await group.next()!
}
```

```swift
// Streaming: each snapshot carries the aggregated text so far
for try await snapshot in session.streamResponse(to: prompt, options: options) {
    output = snapshot.content
}
```

## Acceptance Criteria

Boxes are ticked only where the behaviour was actually observed or is enforced by a
test. The ones left open are the interactive rows: see "What was actually run".

### Functional Requirements

- [x] Pressing `⇧⌃Z` opens the popover at the status icon; pressing it again closes it — the toggle path was run; the *key combination itself* reaching the app was not
- [ ] Clicking the status icon does exactly what the hot-key does — same code path, not clicked by hand
- [x] Opening the popover fills the left pane from the clipboard and starts translating without further input
- [x] The right pane fills progressively while the model generates — nine cumulative snapshots for a 330-character paragraph
- [x] Source and target are dropdowns; source offers `Auto-detect` and defaults to it
- [ ] The swap button exchanges the two languages, keeps the input text, and retranslates
- [ ] Editing the left pane retranslates after a short pause, cancelling the previous run
- [x] Re-requesting a translation already in the cache fills the right pane with no model call — cache behaviour is unit tested
- [ ] Every result, cached or fresh, has a retranslate button that forces a new run
- [ ] The shortcut is rebindable in Preferences and persists across relaunch

### Edge Cases & Error Handling

- [x] Empty or whitespace-only clipboard → popover opens with empty panes, no model call, no beep loop
- [x] Clipboard holds no text representation (image, file) → left pane stays empty, no crash — observed with a concealed marker, which takes the identical branch
- [ ] Model unavailable → the specific explanatory message from `LLMTranslator.Unavailable`, shown in the popover rather than a modal — Apple Intelligence was available on the test machine, so this path did not run
- [ ] Model times out → the popover shows a failed state and stays responsive; the timeout is never retried
- [x] Source and target set to the same language → still translates, no special case
- [x] Popover reopened while a translation is running → the previous task is cancelled, not queued
- [x] Unknown or removed stored language code → `Languages.named(_:)` falls back to the first entry — unit tested
- [ ] Hot-key already claimed by another app → registration fails silently, as today; the status icon still works

### User Experience

- [x] All strings are English, sentence case, typographic punctuation, no emoji
- [ ] The popover is anchored to the status icon and clamped on screen by AppKit
- [ ] The popover takes focus, so Escape closes it and the text panes are usable from the keyboard
- [ ] Clicking outside dismisses it (`behavior = .transient`)
- [ ] Progress is visible in the popover; the status icon still swaps while a translation runs

### Privacy Impact

- [x] No network code added (`URLSession`, sockets, or otherwise)
- [x] No third-party dependency added to `Package.swift`
- [x] No analytics, telemetry, or crash reporting
- [x] No `print` / `os_log`
- [x] The translation cache is in memory only and is never written to `UserDefaults` or disk
- [x] The clipboard is only ever read, never overwritten, except when the user presses Copy — enforced by `Tests/EasyWriteCoreTests/PasteboardWriteGuardTests.swift`, and observed: a completed translation left the original clipboard text in place
- [x] No permission is requested at all; the Accessibility prompt and check are removed — no `CGEvent` and no `AXIsProcessTrusted` remain under `Sources/`, and launching the app raised no prompt
- [x] `SECURITY.md` is updated, because its previous statements about `⌘C`/`⌘V`, clipboard restore, and Accessibility became false

## Development Information

### Testing Strategy

See [`docs/conventions/testing/README.md`](../conventions/testing/README.md).
There is still **no CI**.

1. **Compile**: `swift build` warning-free, then `swift build -c release`.
2. **Automated**: `./test.sh`. The new logic worth testing is `TranslationCache`
   eviction and key equality, which is pure, so the test target this spec adds
   covers it along with the language table and the single-pasteboard-write
   invariant. Nine tests; nothing that needs the model or a running app.
3. **Manual verification**: `./build.sh && open EasyWrite.app` on macOS 26+ /
   Apple Silicon with Apple Intelligence enabled.

The manual steps for this feature **are** the standard smoke test now, because the
popover is the whole app. They live in
[`testing/README.md`](../conventions/testing/README.md) rather than being repeated
here: launch with no permission prompt, open from the hot-key and from the icon,
change and swap languages, edit the left pane, reopen on a cached result, force a
retranslate, copy an image, rebind the shortcut, and relaunch.

That file previously described the register modes, the preview dialog, read mode,
and the clipboard restore paths. All of those disappear, so the section is rewritten
rather than re-run, and its long "why step 8 is scoped" note is dropped along with
`Replacer`.

### What was actually run

On macOS 26.5.2, Apple Silicon, Apple Intelligence available. `swift build` and
`swift build -c release` are warning-free; `./test.sh` passes nine tests; the guard
test was shown to fail by temporarily adding a second pasteboard write.

The app was launched from the built bundle and translated a real clipboard
end-to-end, driven from a temporary hook in `applicationDidFinishLaunching` that
opened the popover, waited for the stream, pressed Copy and quit. That hook was
removed before committing. Observed: an English sentence became a correct Russian
translation using the stored target language, and the copy button put it on the
clipboard.

Streaming and prewarming were measured separately against the FoundationModels API
with the same options and instruction this app uses: a 330-character paragraph
arrived in nine cumulative snapshots and finished in 2.5 s, and prewarming a session
moved the first snapshot from 2.36 s to 0.25 s.

**What could not be run here.** macOS denies this environment synthetic keystrokes
and screen capture, so nothing that needs a real key press, a click, or a look at
the screen was exercised: the hot-key combination itself, clicking the status icon,
the swap button, the debounce on typing, Escape and click-outside dismissal, the
gear menu, rebinding the shortcut, and whether the popover is positioned and
rendered correctly. The smoke test in
[`testing/README.md`](../conventions/testing/README.md) is the list to work through
on a Mac with those grants.

### Code Examples from Existing Features

- Reason-specific user-facing error copy: `LLMTranslator.Unavailable`
- Persisted collection with a merge-on-load upgrade path: `Store.shortcuts`
- Key capture with modifier validation and Escape to cancel: `Recorder`
- Pure static lookup table with a fallback: `Languages`
- SwiftUI hosted in an AppKit container: `PreferencesController.show()`

### Considerations

#### Privacy & security

- The instruction must keep framing the user's text as content rather than as a
  request to answer. Shortening it must not drop that sentence.
- Do not weaken `.permissiveContentTransformations`.
- The cache is the one new place user text lives beyond a single translation.
  Keeping it in memory, capped, and unwritten is what keeps the "translated text
  is never persisted" invariant true.
- The permission surface narrows to nothing. Do not reintroduce a synthetic
  keystroke to make some later convenience work.

#### Performance

Speed is the headline requirement, in rough order of effect:

- **Stream the result.** `streamResponse(to:options:)` yields snapshots whose
  `.content` is the aggregated text so far, so the user reads the first words
  instead of waiting for the whole answer.
- **Make prewarming real.** See Step 2: the current warm session is discarded
  unused, so every translation is a cold start today.
- **Shorten the instruction.** The current one runs about 110 words
  (`Sources/EasyWrite/LLMTranslator.swift:127-134`) and the register paragraph
  that dominates it is being deleted anyway. Target roughly 35 words: the text
  is content, not a request, and the output is the translation alone.
- **`GenerationOptions(sampling: .greedy)`.** The cheapest decode path, and
  determinism is what makes a cache trustworthy. `maximumResponseTokens` is a
  runaway guard only, scaled to input length — Apple's TN3193 warns it truncates
  hard rather than shortening gracefully.
- **Cache and debounce.** A repeat costs nothing; an edit costs one run, not one
  per keystroke.

Translation quality is protected by translating the clipboard as a single unit,
with no chunking and no reasoning step, so the output stays contextual without
the model deliberating.

Every model call is still bounded by a timeout. Stream consumption is raced
against a timeout task in the existing `withThrowingTaskGroup` shape. The
retry-once-on-transient-error rule is kept, but only fires when nothing has been
emitted yet — retrying mid-stream would duplicate output.

#### Maintainability

- **The diff budget is breached and this is the explicit agreement to do so.**
  [`AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md#3-diff-size-budget) caps a
  Swift file at fifty added lines per PR. The work is split into five small focused
  files to keep each as low as possible, and it still lands over: `TranslatorModel`
  at 165 lines, `TranslatorView` at 113, `TranslatorPanel` at 40 and `Clipboard` at
  33, against a rewritten `LLMTranslator` at 168. A popover with two panes, two
  pickers and four actions does not compress below that without splitting it into
  files that no longer name a thing. The three `Translator*` files and `Clipboard`
  are the split that *does* name things; going further would not.
- One primary type per file, named after it.
- `@MainActor` for every class that owns app state or an AppKit object;
  `TranslatorView` stays a `struct`.
- No `try!`, no `fatalError`.

#### Known Gotchas

- `statusItem.menu` must be `nil` for the button action to fire; assigning a
  menu swallows the click.
- The app is `LSUIElement`, so the popover needs
  `NSApp.activate(ignoringOtherApps: true)` before it can take keyboard focus.
- `LanguageModelSession` is stateful and its transcript grows across turns —
  rebuild per turn rather than reusing.
- Ad-hoc signing still changes the signature on every build. It no longer costs
  an Accessibility grant, since there is none, but `setup-signing.sh` and the
  signing logic in `build.sh` are left untouched here regardless.
- The package uses Swift 6 tools with `.swiftLanguageMode(.v5)`; strict Swift 6
  concurrency checking is not enforced by the compiler.
- Builds and runs on macOS 26+ / Apple Silicon only.

## References

### Related Documentation

- [Coding conventions](../conventions/CODING_CONVENTIONS.md) — style, naming, concurrency, settings
- [AI workflow](../conventions/AI_WORKFLOW.md) — guardrails and the PR checklist
- [Testing guide](../conventions/testing/README.md) — how work is verified
- [Release notes guide](../conventions/RELEASE_NOTES_GUIDE.md) — the changelog entry
- [Architecture tour](../../HOW_IT_WORKS.md) — how the pieces fit together
- [Repository overview](../AI_Overview.md) — orientation before reading code
- [Security & privacy](../../SECURITY.md) — the promise this feature changes

### Existing Similar Features

- SwiftUI hosted in an AppKit container: `PreferencesController.show()`
- Global hot-key registration and teardown: `Sources/EasyWrite/HotKey.swift`
- On-device model access with timeout and retry: `Sources/EasyWrite/LLMTranslator.swift`

### External Resources

- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [streamResponse(to:options:)](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/streamresponse(to:options:))
- [NSPopover](https://developer.apple.com/documentation/appkit/nspopover)
- [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

---

**Created**: 2026-08-26
**Status**: In Progress — implemented and verified as recorded above; the interactive
rows of the smoke test still need a human on a supported Mac
