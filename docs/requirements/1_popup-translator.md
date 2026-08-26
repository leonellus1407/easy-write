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
- `Sources/EasyWrite/TranslationCache.swift` — in-memory LRU of the last twenty results

Rewritten:

- `Sources/EasyWrite/LLMTranslator.swift` — drop `Register`, stream the response, reuse a prewarmed session, shorten the instruction
- `Sources/EasyWrite/AppDelegate.swift` — reduces to status item, one hot-key, `togglePopup()`, login item, and the gear actions

Trimmed:

- `Sources/EasyWrite/Store.swift` — add `sourceCode`, drop `previewBeforeReplace`, collapse `defaultShortcuts` to one entry
- `Sources/EasyWrite/Languages.swift` — drop `formal` and `informal`, add the `auto` sentinel and a `sources` list
- `Sources/EasyWrite/PreferencesController.swift` — one recorder row, keep the style guide, drop the language picker and preview toggle

Deleted:

- `Sources/EasyWrite/Replacer.swift` — the only user of `CGEvent`; nothing drives the keyboard any more
- `Sources/EasyWrite/ReaderPanel.swift` — superseded by the popover

Documentation and packaging:

- `SECURITY.md` — the permissions table loses its only row; the data-flow section stops describing paste-back
- `README.md`, `HOW_IT_WORKS.md`, `docs/AI_Overview.md` — product description, file map, and flow rewritten
- `docs/conventions/testing/README.md` — the manual smoke test is rewritten around the popover
- `.cursor/rules/project-conventions.mdc` — the clipboard-swap and Accessibility rules no longer describe the app
- `Info.plist` — version bump to 2.0, build 4
- `CHANGELOG.md` — release entry

`Package.swift` is untouched. SwiftPM globs `Sources/EasyWrite`, so the four new
files need no manifest edit, and Carbon is still required for the global
hot-key.

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
it; if it is closed, open it, re-read the clipboard, and translate.

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

### Functional Requirements

- [ ] Pressing `⇧⌃Z` opens the popover at the status icon; pressing it again closes it
- [ ] Clicking the status icon does exactly what the hot-key does
- [ ] Opening the popover fills the left pane from the clipboard and starts translating without further input
- [ ] The right pane fills progressively while the model generates
- [ ] Source and target are dropdowns; source offers `Auto-detect` and defaults to it
- [ ] The swap button exchanges the two languages, keeps the input text, and retranslates
- [ ] Editing the left pane retranslates after a short pause, cancelling the previous run
- [ ] Re-requesting a translation already in the cache fills the right pane with no model call
- [ ] Every result, cached or fresh, has a retranslate button that forces a new run
- [ ] The shortcut is rebindable in Preferences and persists across relaunch

### Edge Cases & Error Handling

- [ ] Empty or whitespace-only clipboard → popover opens with empty panes, no model call, no beep loop
- [ ] Clipboard holds no text representation (image, file) → left pane stays empty, no crash
- [ ] Model unavailable → the specific explanatory message from `LLMTranslator.Unavailable`, shown in the popover rather than a modal
- [ ] Model times out → the popover shows a failed state and stays responsive; the timeout is never retried
- [ ] Source and target set to the same language → still translates, no special case
- [ ] Popover reopened while a translation is running → the previous task is cancelled, not queued
- [ ] Unknown or removed stored language code → `Languages.named(_:)` falls back to the first entry
- [ ] Hot-key already claimed by another app → registration fails silently, as today; the status icon still works

### User Experience

- [ ] All strings are English, sentence case, typographic punctuation, no emoji
- [ ] The popover is anchored to the status icon and clamped on screen by AppKit
- [ ] The popover takes focus, so Escape closes it and the text panes are usable from the keyboard
- [ ] Clicking outside dismisses it (`behavior = .transient`)
- [ ] Progress is visible in the popover; the status icon still swaps while a translation runs

### Privacy Impact

- [ ] No network code added (`URLSession`, sockets, or otherwise)
- [ ] No third-party dependency added to `Package.swift`
- [ ] No analytics, telemetry, or crash reporting
- [ ] No `print` / `os_log`
- [ ] The translation cache is in memory only and is never written to `UserDefaults` or disk
- [ ] The clipboard is only ever read, never overwritten, except when the user presses Copy
- [ ] No permission is requested at all; the Accessibility prompt and check are removed
- [ ] `SECURITY.md` is updated, because its current statements about `⌘C`/`⌘V`, clipboard restore, and Accessibility become false

## Development Information

### Testing Strategy

This repo has **no test target and no CI** — see
[`docs/conventions/testing/README.md`](../conventions/testing/README.md).

1. **Compile**: `swift build` warning-free, then `swift build -c release`.
2. **Manual verification**: `./build.sh && open EasyWrite.app` on macOS 26+ /
   Apple Silicon with Apple Intelligence enabled.
3. **Automated**: none. The new logic worth testing is `TranslationCache`
   eviction and key equality, which is pure — but a test target does not exist,
   and adding one is its own declared piece of work.

Manual steps specific to this feature:

| # | Step | Expected |
|---|---|---|
| 1 | Launch | Icon in the menu bar, no Dock icon, **no Accessibility prompt** |
| 2 | Copy a sentence, press `⇧⌃Z` | Popover opens at the icon; left pane holds the sentence; the right pane starts filling within about a second |
| 3 | Press `⇧⌃Z` again | Popover closes |
| 4 | Click the status icon | Same behaviour as step 2 |
| 5 | Change the target language | Retranslates into the new language |
| 6 | Set an explicit source, press swap | Languages exchange, input text unchanged, retranslates |
| 7 | With source on `Auto-detect` | Swap button is disabled |
| 8 | Close the popover, reopen with the same clipboard | Result appears instantly, with no generation delay |
| 9 | Press retranslate on that cached result | A fresh run visibly streams again |
| 10 | Edit the left pane | Retranslates once after the pause, not once per keystroke |
| 11 | Copy an image, press `⇧⌃Z` | Empty left pane, no crash |
| 12 | Gear → Preferences, rebind the shortcut | The new combination opens the popover; the old one does not |
| 13 | Preferences → add a style-guide line, retranslate | Output reflects the instruction |
| 14 | Gear → Launch at Login, twice | State tracks; no error dialog |
| 15 | Quit and relaunch | Languages and shortcut survive; the cache does not |

The existing smoke test in `docs/conventions/testing/README.md` describes the
register modes, the preview dialog, read mode, and the clipboard restore paths.
All of those disappear, so that section is rewritten rather than re-run, and its
long "why step 8 is scoped" note is dropped along with `Replacer`.

**This spec was written on Linux. Nothing in it has been compiled or run.** Every
claim about current behaviour is read from the source at the cited lines, not
reproduced. The build and the manual table above must be executed on a supported
Mac before this is considered done.

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
  Swift file at fifty added lines per PR. The work is split into four small
  focused files to keep each as low as possible, but `TranslatorView.swift` and
  `TranslatorModel.swift` will each land near ninety lines. A popover with two
  panes, two pickers and four actions does not compress below that without
  splitting it into files that no longer name a thing.
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

- Floating result surface hosted from AppKit: `Sources/EasyWrite/ReaderPanel.swift` (the closest precedent, and the thing being replaced)
- Global hot-key registration and teardown: `Sources/EasyWrite/HotKey.swift`
- On-device model access with timeout and retry: `Sources/EasyWrite/LLMTranslator.swift`

### External Resources

- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [streamResponse(to:options:)](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/streamresponse(to:options:))
- [NSPopover](https://developer.apple.com/documentation/appkit/nspopover)
- [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

---

**Created**: 2026-08-26
**Status**: Planning
