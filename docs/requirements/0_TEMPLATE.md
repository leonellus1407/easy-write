# Feature: {Feature Name}

## Overview

Brief description of the feature and its purpose. What can the user do afterwards
that they cannot do now, and why does it matter? One paragraph.

## Technical Specification

### Components Affected

List every file that will be created or modified, with one line on why:

- `Sources/EasyWrite/XyzPanel.swift` — new floating panel that presents ...
- `Sources/EasyWrite/AppDelegate.swift` — new menu item and hot-key registration for ...
- `Sources/EasyWrite/Store.swift` — new persisted setting `...`
- `Sources/EasyWrite/PreferencesController.swift` — control for the new setting
- `Sources/EasyWrite/Languages.swift` — new language row
- `Info.plist` — version bump
- `CHANGELOG.md` — release entry

Remember: a new `.swift` file in `Sources/EasyWrite/` needs **no** `Package.swift`
edit — SwiftPM globs the directory. Only a new **system framework** needs a
`linkerSettings` entry.

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

- Menu-bar changes in `AppDelegate.rebuildMenu()` (AppKit)
- Preferences changes in `PreferencesView` (SwiftUI)
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
// Async work from the main actor, with a reentrancy guard
guard !busy else { return }
busy = true
setIcon(busy: true)
Task { @MainActor in
    defer { busy = false }
    do {
        let result = try await llm.translate(text, toLanguageNamed: language, register: register)
        // ...
    } catch {
        NSSound.beep(); flashIcon("exclamationmark.bubble", revertAfter: 1.1)
    }
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

- [ ] Empty or whitespace-only selection → single beep, no dialog, no crash
- [ ] Model unavailable → the specific explanatory dialog, not a generic one
- [ ] Model times out → icon flashes, app stays responsive
- [ ] Accessibility permission missing → prompt, then abort cleanly
- [ ] Action triggered while one is already running → ignored, not queued
- [ ] Unknown or removed stored value → falls back to a sane default
- [ ] Target application is slow or handles copy unusually → fails visibly, clipboard intact

### User Experience

- [ ] All strings are English, sentence case, typographic punctuation, no emoji
- [ ] Menu labels show the current shortcut
- [ ] Feedback is visible without a Dock icon (status-bar icon change or beep)
- [ ] A window that needs focus activates the app; anything else does not steal focus
- [ ] Floating windows are clamped to the visible screen frame

### Privacy Impact

Non-negotiable. Every box must be checked, or the feature does not ship:

- [ ] No network code added (`URLSession`, sockets, or otherwise)
- [ ] No third-party dependency added to `Package.swift`
- [ ] No analytics, telemetry, or crash reporting
- [ ] No `print` / `os_log`, and no persistence of translated text
- [ ] Clipboard snapshot-and-restore preserved on every path that touches the pasteboard
- [ ] No permission requested beyond Accessibility
- [ ] Statements in `SECURITY.md` remain true (if not, that file must change too, and that is a separate decision)

## Development Information

### Testing Strategy

This repo has **no test target and no CI** — see
[`docs/conventions/testing/README.md`](../conventions/testing/README.md). State
honestly how the feature will be verified:

1. **Compile**: `swift build` warning-free, and `swift build -c release`.
2. **Manual verification**: `./build.sh && open EasyWrite.app`, then the steps
   below, run on macOS 26+ / Apple Silicon with Apple Intelligence enabled.
3. **Automated** (only if the feature adds pure logic — formatting, lookup,
   parsing, merging): note that a test target must be added first, and treat
   that as its own declared piece of work.

Manual steps specific to this feature:

| # | Step | Expected |
|---|---|---|
| 1 | ... | ... |
| 2 | ... | ... |

Also re-run the relevant rows of the standard smoke test if this feature touches
the translate path, the clipboard, hot-keys, or settings.

If you cannot run the app on suitable hardware, say so explicitly rather than
implying it was verified.

### Code Examples from Existing Features

Point at the closest existing implementation instead of inventing a pattern:

- Non-activating floating popup: `ReaderPanel.swift`
- Modal dialog with actions, and re-activating the previous app: `AppDelegate.presentResult`
- Reason-specific user-facing error copy: `LLMTranslator.Unavailable`
- Persisted collection with a merge-on-load upgrade path: `Store.shortcuts`
- Key capture with modifier validation and Escape to cancel: `Recorder`
- Pure static lookup table with a fallback: `Languages`

### Considerations

#### Privacy & security

- Untrusted input: the selection is fed to a language model, so any new
  instruction text must keep framing it as content, not as a request to answer.
- Never widen the permission surface. Accessibility is the only grant.
- Do not weaken `.permissiveContentTransformations`; the default guardrails
  false-flag ordinary text for translation.

#### Performance

- Keep the first-use path warm; do not undo `llm.prewarm()`.
- Bound every model call with a timeout.
- The short `usleep` waits in `Replacer` are load-bearing — do not lengthen or
  remove them without measuring.
- Dismiss transient UI automatically rather than leaving it on screen.

#### Maintainability

- Diff budget: ≤50 added lines per Swift file. A larger addition is a new file.
  (Swift sources only — see [`AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md#3-diff-size-budget).)
- One primary type per file, named after it.
- `@MainActor` for every class that owns app state or an AppKit object. SwiftUI
  views stay `struct`s.
- No `try!`, no `fatalError`.

#### Known Gotchas

- Changing `CFBundleIdentifier` or the signing identity invalidates the user's
  existing Accessibility grant.
- Ad-hoc signing loses the Accessibility grant on every rebuild — run
  `./setup-signing.sh` once before iterating on anything that drives the keyboard.
- Hot-key registration fails silently when a combination is already claimed by
  another app.
- The app is `LSUIElement`: there is no Dock icon and it is usually not frontmost,
  so a window that needs focus must call `NSApp.activate(ignoringOtherApps: true)`.
- Synthetic keystrokes need a `.privateState` event source so physically-held
  modifiers do not contaminate them.
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
