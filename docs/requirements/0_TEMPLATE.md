# Feature: {Feature Name}

## Overview

Brief description of the feature and its purpose. What can the user do afterwards
that they cannot do now, and why does it matter? One paragraph.

## Technical Specification

### Components Affected

List every file that will be created or modified, with one line on why:

- `Sources/EasyWrite/XyzPanel.swift` — new surface that presents ...
- `Sources/EasyWrite/AppDelegate.swift` — hot-key registration for ...
- `Sources/EasyWrite/Store.swift` — new persisted setting `...`
- `Sources/EasyWrite/PreferencesController.swift` — control for the new setting
- `Sources/EasyWriteCore/Languages.swift` — new language row
- `Tests/EasyWriteCoreTests/...Tests.swift` — cover the new pure logic
- `Info.plist` — version bump
- `CHANGELOG.md` — release entry

Remember: a new `.swift` file in `Sources/EasyWrite/` or `Sources/EasyWriteCore/`
needs **no** `Package.swift` edit — SwiftPM globs both directories. Only a new
**system framework** needs a `linkerSettings` entry. Pure logic belongs in
`EasyWriteCore`, where it can be tested; anything importing AppKit or
FoundationModels belongs in `EasyWrite`.

### Settings & Persistence Changes

If the feature stores anything, specify it here. There is no database; the only
persistence is `UserDefaults`, accessed exclusively through `Store`.

| Key | Type | Default | Triggers `onChange?()` | Why |
|---|---|---|---|---|
| `exampleSetting` | `Bool` | `false` | yes / no | ... |

State the upgrade behaviour: what an existing user sees on first launch after the
update. For a collection, say how it merges over the built-in defaults so an
added entry is not lost.

If the feature stores **nothing**, say so explicitly — that is a meaningful fact
in a privacy-first app.

### Implementation Details

#### Step 1: Data and settings

Add the `@Published` property to `Store` with its `didSet`, a default in `init`,
and `onChange?()` only if the menu or hot-keys depend on it.

#### Step 2: Core logic

Where the behaviour lives, and which existing type owns it. Prefer extending an
existing type over introducing one; if a new type is warranted, say which
existing responsibility it takes over.

#### Step 3: User interface

- Popover changes in `TranslatorView` (SwiftUI)
- Preferences changes in `PreferencesView` (SwiftUI)
- Status-item changes in `AppDelegate` (AppKit)
- Any new window or panel: state whether it takes focus, and why

#### Step 4: Hot-key wiring (if applicable)

Three places must agree on the action key string:

1. `Store.defaultShortcuts` — default key code and Carbon modifier mask
2. `AppDelegate.registerHotKeys()` — the `register("key") { … }` line
3. `PreferencesView.actions` — the recorder row

### Code Patterns to Follow

Quote the patterns this feature should imitate. Real examples from the codebase:

```swift
// A new setting on Store: persist in didSet, notify only if the UI depends on it
@Published var exampleSetting: Bool {
    didSet { d.set(exampleSetting, forKey: "exampleSetting"); onChange?() }
}
```

```swift
// Async work from the main actor: cancel the previous request rather than queueing another,
// and carry a generation number so a superseded run cannot write over a newer one's state
task?.cancel()
generation += 1
let mine = generation
task = Task { [weak self] in
    guard let self, !Task.isCancelled else { return }
    await self.run(mine)
}
```

```swift
// Anything that can stall races a timeout; a timeout is never retried
try await withThrowingTaskGroup(of: String.self) { group in
    group.addTask { /* real work */ }
    group.addTask { try await Task.sleep(nanoseconds: 20_000_000_000); throw TimeoutError() }
    defer { group.cancelAll() }
    return try await group.next()!
}
```

## Acceptance Criteria

### Functional Requirements

- [ ] User can perform action X from the menu bar
- [ ] User can perform action X from a keyboard shortcut
- [ ] The setting persists across relaunch
- [ ] The default behaviour for an existing user is unchanged unless they opt in

### Edge Cases & Error Handling

- [ ] Empty or whitespace-only text → empty panes, no model call, no crash
- [ ] Clipboard holds no text representation (image, file) → panes stay empty
- [ ] Clipboard marked concealed or transient → treated as nothing to translate, and never cached
- [ ] Model unavailable → the specific explanatory message, not a generic one
- [ ] Model times out → the popover shows a failed state and stays responsive; the timeout is never retried
- [ ] Action triggered while one is already running → the previous request is cancelled, not queued
- [ ] Unknown or removed stored value → falls back to a sane default
- [ ] Hot-key already claimed by another app → registration fails silently; the status icon still works

### User Experience

- [ ] All strings are English, sentence case, typographic punctuation, no emoji
- [ ] Preferences shows the current shortcut, and rebinding it persists
- [ ] Feedback is visible without a Dock icon (in the popover, or on the status-bar icon)
- [ ] A window that needs focus activates the app; anything else does not steal focus
- [ ] Popovers and floating windows are clamped to the visible screen frame

### Privacy Impact

Non-negotiable. Every box must be checked, or the feature does not ship:

- [ ] No network code added (`URLSession`, sockets, or otherwise)
- [ ] No third-party dependency added to `Package.swift`
- [ ] No analytics, telemetry, or crash reporting
- [ ] No `print` / `os_log`, and no persistence of translated text
- [ ] Easy Write still reads the pasteboard and never writes it, except in the single code path behind the popover's Copy button
- [ ] No permission is requested at all
- [ ] Statements in `SECURITY.md` remain true (if not, that file must change too, and that is a separate decision)

## Development Information

### Testing Strategy

There is a small test suite covering `EasyWriteCore` and **no CI** — see
[`docs/conventions/testing/README.md`](../conventions/testing/README.md). State
honestly how the feature will be verified:

1. **Compile**: `swift build` warning-free, and `swift build -c release`.
2. **Automated**: `./test.sh`. If the feature adds pure logic — formatting,
   lookup, parsing, merging — it goes in `EasyWriteCore` and it gets a test.
   If it does not, say so, and say why the logic could not go there.
3. **Manual verification**: `./build.sh && open EasyWrite.app`, then the steps
   below, run on macOS 26+ / Apple Silicon with Apple Intelligence enabled.

Manual steps specific to this feature:

| # | Step | Expected |
|---|---|---|
| 1 | ... | ... |
| 2 | ... | ... |

Also re-run the relevant rows of the standard smoke test if this feature touches
the translate path, the clipboard, the hot-key, or settings.

If you cannot run the app on suitable hardware, say so explicitly rather than
implying it was verified.

### Code Examples from Existing Features

Point at the closest existing implementation instead of inventing a pattern:

- Popover anchored to the status item, taking focus deliberately: `TranslatorPanel`
- SwiftUI hosted in an AppKit container: `PreferencesController.show()`
- Streaming a model response into a view: `LLMTranslator.translate` and `TranslatorModel.run`
- Reason-specific user-facing error copy: `LLMTranslator.Unavailable`
- Persisted collection with a merge-on-load upgrade path: `Store.shortcuts`
- Key capture with modifier validation and Escape to cancel: `Recorder`
- Pure static lookup table with a fallback: `Languages`
- An invariant enforced by scanning the sources: `Tests/EasyWriteCoreTests/PasteboardWriteGuardTests.swift`

### Considerations

#### Privacy & security

- Untrusted input: the clipboard text is fed to a language model, so any new
  instruction text must keep framing it as content, not as a request to answer.
- Never widen the permission surface. The app requests nothing, and that is a
  headline claim in `README.md` and `SECURITY.md`.
- Do not weaken `.permissiveContentTransformations`; the default guardrails
  false-flag ordinary text for translation.
- Do not add a second pasteboard write, and do not reintroduce a synthetic
  keystroke to make some later convenience work.

#### Performance

- Keep the first-use path warm; do not undo `prewarm()`. A warm session is the
  difference between a first token at 2.4 s and at 0.25 s, and it is warmed for
  one instruction string only.
- Bound every model call with a timeout.
- Stream anything the user waits on, rather than showing it all at once.
- Debounce anything driven by typing, and cancel the previous request instead of
  queueing another.

#### Maintainability

- Diff budget: ≤50 added lines per Swift file. A larger addition is a new file.
  (Swift sources only — see [`AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md#3-diff-size-budget).)
- One primary type per file, named after it.
- `@MainActor` for every class that owns app state or an AppKit object. SwiftUI
  views stay `struct`s.
- No `try!`, no `fatalError`.

#### Known Gotchas

- Assigning `statusItem.menu` swallows the click that has to reach the button's
  action, so the popover would never open from the icon.
- AppKit dismisses a transient popover on the same click that then reaches the
  status button, so a naive toggle closes and immediately reopens it.
- The app is `LSUIElement`: there is no Dock icon and it is usually not frontmost,
  so anything that needs keyboard focus must call
  `NSApp.activate(ignoringOtherApps: true)`.
- `LanguageModelSession` is stateful and its transcript grows across turns —
  rebuild it per turn rather than reusing one.
- The `org.nspasteboard.*` markers are a developer convention, not an Apple API.
  A typo in the type string silently disables the check.
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
- [Security & privacy](../../SECURITY.md) — the promise this feature must not break

### Existing Similar Features

- Feature X in `Sources/EasyWrite/....swift`
- Feature Y in `Sources/EasyWrite/....swift`

### External Resources

- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [AppKit](https://developer.apple.com/documentation/appkit)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [Swift Testing](https://developer.apple.com/documentation/testing)
- [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

---

**Created**: {Date}
**Status**: Planning | In Progress | Completed | On Hold
