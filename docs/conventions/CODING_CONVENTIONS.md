# Coding Conventions — Easy Write

> **Documentation Maintenance Rule**: Each piece of information should exist in exactly ONE document. Avoid duplication across .md files. When updating documentation, modify only the authoritative source and reference it from other documents.

## Documentation Structure

- **docs/conventions/CODING_CONVENTIONS.md** (this file) — code style, naming, concurrency, settings, error handling
- **README.md** — product overview, install, usage
- **HOW_IT_WORKS.md** — architecture tour: the on-device engine, streaming and prewarming, the clipboard rule, hot-keys, signing
- **docs/AI_Overview.md** — orientation for AI agents
- **docs/conventions/testing/README.md** — testing guide: what the suite covers, and the much larger part it does not
- **docs/conventions/AI_WORKFLOW.md** — workflow and guardrails for AI agents
- **docs/conventions/RELEASE_NOTES_GUIDE.md** — how to write a release entry
- **SECURITY.md** — data flow and permissions
- **docs/requirements/** — feature specifications
- **docs/plans/** — cleanup, fix, and refactor plans for existing code

## Table of Contents

- [General Principles](#general-principles)
- [Swift Code Standards](#swift-code-standards)
- [Concurrency](#concurrency)
- [Naming Conventions](#naming-conventions)
- [File Organization](#file-organization)
- [Settings & Persistence](#settings--persistence)
- [AppKit and SwiftUI](#appkit-and-swiftui)
- [Error Handling & User Feedback](#error-handling--user-feedback)
- [Documentation & Comments](#documentation--comments)
- [Testing](#testing)
- [Git Workflow](#git-workflow)
- [Security & Privacy Conventions](#security--privacy-conventions)
- [Performance Conventions](#performance-conventions)
- [Versioning & Release](#versioning--release)
- [Quick Reference Checklist](#quick-reference-checklist)

---

## General Principles

### 1. Code Philosophy

- **Clarity over cleverness**: the app is small enough for a stranger to audit in one sitting. Keep it that way.
- **Small surface**: the whole app is a dozen files under `Sources/`. Prefer extending an existing type over adding a new one.
- **No dependencies**: `Package.swift` declares no `dependencies:`. Standard library and Apple frameworks only.
- **Private by default**: privacy is the product. A change that adds a network call, a log of user text, a permission request, or a third-party SDK is out of scope regardless of how useful it is.
- **Fail softly**: a failed translation says why, in the popover. It never crashes, and never touches the user's clipboard.

### 2. Language & Encoding

- **Charset**: UTF-8. Source files contain typographic characters (`’ “ ” – ⌥⌘`) and non-Latin script in language notes; that is expected.
- **All text is English** — code, comments, docs, commit messages, and user-facing strings. Other scripts appear only inside per-language model instructions (for example the Modern Standard Arabic note in `Languages.swift`).
- **User-facing strings** are sentence case with typographic punctuation, written as full sentences, and live inline at the point of use. There is no localization catalogue.
- **No emoji in app strings.** Emoji belong in the README and shell script output, not in the UI.

---

## Swift Code Standards

### 1. File Structure

```swift
import AppKit          // 1. imports, Apple frameworks only
import SwiftUI

/// 2. doc comment stating why the type exists
@MainActor
final class Thing {
    static let shared = Thing()     // 3. static members
    private var state: State?       // 4. stored properties
    private init() { }              // 5. init

    // MARK: Section                // 6. grouped members
    func doThing() { }              // 7. internal API

    private func helper() { }       // 8. private helpers last
}

struct ThingView: View { }          // 9. small satellite types may follow
```

### 2. Indentation & Formatting

- **4 spaces**, never tabs.
- **Braces** on the same line: `if condition {`, `func f() {`, `} else {`.
- **Line length**: wrap around 100–110 columns. A long user-facing string may run over rather than be split awkwardly; multi-line strings use `"""` or `+` continuation aligned under the opening quote.
- **Numeric literals**: underscore separators for anything long — `20_000_000_000`, `400_000_000`, `120_000`.
- **Single-line bodies** are fine for trivial members and keep the file scannable:

```swift
@objc func menuQuit() { NSApp.terminate(nil) }
static func keyLabel(_ code: UInt32) -> String { keyNames[code] ?? "·" }
var canSwap: Bool { sourceCode != Languages.auto.code }
```

### 3. Types

| Use | For | Examples |
|---|---|---|
| `final class` | reference types with identity or AppKit lifetime | `AppDelegate`, `Store`, `LLMTranslator`, `TranslatorPanel` |
| `struct` | values | `Lang`, `Store.Shortcut`, `TranslationCache.Key`, `TimeoutError` |
| `enum` (no cases) | static-only namespaces | `KeyDisplay`, `Languages`, `Clipboard` |
| `enum` (cases) | closed sets, especially where each case carries user-facing copy | `TranslatorModel.Phase`, `LLMTranslator.Unavailable` |

Classes are `final` unless something actually subclasses them. Singletons are `static let shared` with a `private init()`.

Keep user-facing copy next to the case that produces it, as `Unavailable.message` does — one switch, no string table drifting out of sync with the cases.

---

## Concurrency

### 1. Main-actor by default

Every class that owns app state or the lifetime of an AppKit object is `@MainActor final class`: `AppDelegate`, `Store`, `LLMTranslator`, `TranslatorPanel`, `TranslatorModel`, `TranslationCache`, `PreferencesController`, `Recorder`.

The rule is about isolating mutable state, not about turning every SwiftUI-adjacent type into a class. Two categories sit outside it deliberately, and converting them would be wrong:

- **SwiftUI views** — `PreferencesView` and `TranslatorView` are `struct`s, as views must be. SwiftUI already isolates a `View` body to the main actor, so they get the guarantee without the annotation, even though both touch SwiftUI and both hold an observable object.
- **Static-only namespaces and value types** — `KeyDisplay`, `Languages`, `Lang`, `Store.Shortcut`. They carry no mutable state, so they need no isolation, even where they take an AppKit type as a parameter. (`Clipboard` is a namespace too, but it is `@MainActor` because it touches `NSPasteboard`.)

Among the state-owning classes, the single exception is `HotKeyCenter`. It is registered from a Carbon C callback that fires on an unspecified context, so it is a plain `final class` and hops back before calling app code:

```swift
DispatchQueue.main.async { HotKeyCenter.shared.fire(id) }
```

Do not add more exceptions. If a helper is genuinely pure, or has to run off the main actor, mark it `nonisolated static func` (see `LLMTranslator.clean` and `LLMTranslator.stream`) rather than making the whole type non-isolated.

### 2. Entry point

`main.swift` is top-level code, so it wraps its work in `MainActor.assumeIsolated { … }` before building the `NSApplication`.

### 3. Async work

Start async work with `Task { … }` from the main actor. Where a user can trigger the same work again before the first one finishes, **cancel and supersede** rather than queueing or refusing — and carry a generation number so the cancelled run cannot write state after the newer one has started:

```swift
task?.cancel()
generation += 1
let mine = generation
task = Task { [weak self] in
    guard let self, !Task.isCancelled else { return }
    await self.run(mine)          // every state write inside re-checks `mine == generation`
}
```

The check is needed because cancellation surfaces asynchronously: without it, a superseded request's failure path would overwrite the phase a newer request has already set. Where overlap is genuinely impossible rather than merely undesirable, a plain flag is still fine; do not reach for a lock.

### 4. Timeouts and retries

Anything that calls the on-device model races a timeout, so a stall can never wedge the app:

```swift
try await withThrowingTaskGroup(of: String.self) { group in
    group.addTask { /* real work */ }
    group.addTask { try await Task.sleep(nanoseconds: 20_000_000_000); throw TimeoutError() }
    defer { group.cancelAll() }
    return try await group.next()!
}
```

Transient errors retry once with a short backoff. A `TimeoutError` or a `CancellationError` is rethrown immediately — never retried. When the call streams, the retry is additionally conditional on nothing having been emitted yet: retrying mid-stream would duplicate the words already on screen.

### 5. Delayed UI and closures

Use `DispatchQueue.main.asyncAfter` for a short UI delay, or `Task.sleep(for:)` inside a cancellable `Task` when the delay is part of async work that a later action should supersede — that is what makes the popover's typing debounce cancel cleanly. Escaping closures that outlive the call capture `[weak self]` and `guard let self else { return }`.

### 6. Language mode

The package uses the Swift 6 tools version with `.swiftLanguageMode(.v5)`. Strict Swift 6 concurrency checking is therefore not enforced by the compiler — the isolation discipline above is what keeps the app correct. Do not flip the language mode as a side effect of another change; that is its own piece of work.

---

## Naming Conventions

### 1. Types

- **UpperCamelCase**: `LLMTranslator`, `HotKeyCenter`, `TranslatorPanel`.
- **Descriptive suffixes** already in use:
  - `*Controller`: owns a window or UI lifecycle (`PreferencesController`)
  - `*Panel` / `*View` / `*Model`: AppKit container, SwiftUI view, and the observable state behind them (`TranslatorPanel`, `TranslatorView`, `TranslatorModel`)
  - `*Center`: process-wide registry (`HotKeyCenter`)
  - `*Cache`: bounded in-memory store (`TranslationCache`)
  - `*Translator`, `*Recorder`: agent nouns for the thing that performs the action

### 2. Members

- **lowerCamelCase** for properties and methods.
- **Action verbs** on methods: `translate`, `register`, `prewarm`, `retranslate`, `swap`, `read`, `write`, `show`, `close`, `toggle`.
- **Booleans** read as assertions: `isAvailable`, `isTranslating`, `canSwap`, `installed`, `ignoresPrivateClipboard`.
- **`@objc` action targets** are named for what they do: `togglePopup`, `toggleLaunchAtLogin`.
- **Private helpers** are `private func` and sit below the API they serve.

### 3. Local names

Short names are acceptable when the scope is a few lines and the type is obvious — `d` for the `UserDefaults` handle, `sc` for a shortcut, `pb` for the pasteboard, `vf` for a visible frame. Anything that outlives a short scope, or whose meaning is not obvious from its type, gets a full name.

### 4. Parameters

Use argument labels that make the call site read as a sentence:

```swift
func translate(_ text: String, from source: Lang, to target: Lang,
               styleGuide: String) -> AsyncThrowingStream<String, Error>

static func read(ignoringPrivateContent ignorePrivate: Bool) -> String?
func toggle(relativeTo button: NSStatusBarButton, willShow: () -> Void)
```

---

## File Organization

### 1. Directory Structure

```
Package.swift              # SPM manifest — core library, executable, test target; Carbon linked
Info.plist                 # bundle metadata: version, LSUIElement, min OS
build.sh                   # release build → EasyWrite.app → codesign
test.sh                    # unit tests (wraps `swift test`)
setup-signing.sh           # one-time stable self-signed identity
make-icon.swift            # throwaway script that renders AppIcon artwork
Sources/EasyWriteCore/     # pure logic: no AppKit, no FoundationModels, unit tested
Sources/EasyWrite/         # everything with a UI or a model call
Tests/EasyWriteCoreTests/  # the suite
docs/                      # documentation and README images
.github/ISSUE_TEMPLATE/    # bug report + feature request forms
```

For the responsibility of each source file, see the file map in [HOW_IT_WORKS.md](../../HOW_IT_WORKS.md). Do not duplicate that table here.

### 2. File Naming

- Swift files are UpperCamelCase, named after the primary type: `TranslatorPanel.swift` → `final class TranslatorPanel`.
- `main.swift` is the one lowercase exception; SwiftPM requires that name for top-level code.

### 3. One Primary Type Per File

Each file holds one primary type. A small satellite that only exists to serve it may share the file:

- `PreferencesController.swift` — `Recorder`, `PreferencesController`, `PreferencesView`
- `Languages.swift` — `Lang`, `Languages`
- `Clipboard.swift` — `Clipboard`, and the `NSPasteboard.PasteboardType` markers it checks

Split the file when the satellite grows its own reason to exist. `TranslatorPanel`, `TranslatorView` and `TranslatorModel` are three files rather than one for exactly that reason: a popover is a container, a layout, and a state machine, and each is legible alone.

### 4. Adding Files and Frameworks

**This is not like a manifest-driven project.** SwiftPM globs both source directories, so:

1. Create the `.swift` file in `Sources/EasyWriteCore/` if it is pure logic, or `Sources/EasyWrite/` if it touches AppKit or the model.
2. That's it — no manifest edit, no include list, no import registration.

A type in `EasyWriteCore` that the app uses must be `public`, and the app file that uses it needs `import EasyWriteCore`.

A new **system framework** does need a manifest change:

```swift
linkerSettings: [
    .linkedFramework("Carbon")     // add the new framework here
]
```

Most Apple frameworks (AppKit, SwiftUI, Foundation, FoundationModels, ServiceManagement) link automatically from `import` alone. Carbon is listed explicitly because the hot-key API needs it.

---

## Settings & Persistence

`Store` is the single source of truth for user settings. It is an `ObservableObject` so the SwiftUI preferences form binds to it directly, and it owns the only `UserDefaults` handle in the app.

### 1. The pattern

```swift
@Published private var shortcuts: [String: Shortcut] {
    didSet { saveShortcuts(); onChange?() }
}
```

- `@Published` so SwiftUI updates.
- `didSet` writes through to `UserDefaults` immediately — there is no explicit save step.
- `onChange?()` is called when the hot-key registrations depend on the value. `AppDelegate` installs that hook in `applicationDidFinishLaunching` and responds by re-registering.
- Omit `onChange?()` for settings nothing needs to react to — `styleGuide` and the language codes are read when they are needed, and the popover reacts to its own edits.

### 2. Reading settings

```swift
// GOOD
let sc = Store.shared.shortcut(for: "translate")
Store.shared.targetCode = code

// BAD — bypasses persistence and the change hook
UserDefaults.standard.set(code, forKey: "targetLanguageCode")
```

The one pre-existing exception is the `didInitLoginItem` first-run flag in `AppDelegate`, which is process bookkeeping rather than a user setting. Do not add more.

### 3. Defaults and upgrades

Provide a default for every key at read time, and **merge** decoded collections over the defaults so a version that adds an action does not lose it for existing users:

```swift
var merged = Store.defaultShortcuts
for (k, v) in decoded { merged[k] = v }
shortcuts = merged
```

Complex values are stored as JSON via `Codable` (`[String: Shortcut]`). Keys are string literals used at the point of read and write.

### 4. Adding a setting

1. Add the `@Published` property with its `didSet` to `Store`.
2. Add a default in `init`. A setting that should default to `true` reads `d.object(forKey:) as? Bool ?? true`, because `d.bool(forKey:)` cannot tell "off" from "absent".
3. Add the control to `PreferencesView`, or to the popover if the user changes it often.

### 5. Adding a shortcut action

Three places, all of which must agree on the action key string:

1. `Store.defaultShortcuts` — the default key code and Carbon modifier mask.
2. `AppDelegate.registerHotKeys()` — the registration line.
3. `PreferencesView.actions` — the row in the recorder list.

Modifier masks are Carbon values from `KeyDisplay` (`cmd` 256, `option` 2048, `control` 4096, `shift` 512); `4608` is `⇧⌃`.

### 6. Adding a language

`Sources/EasyWriteCore/Languages.swift` only. Add a `Lang` with its code and English name. Use `note:` for per-language model guidance, as Arabic does for Modern Standard Arabic. `Languages.all` is the target list; `Languages.auto` is a source-only sentinel and must never appear in it.

---

## AppKit and SwiftUI

The app mixes both deliberately:

- **AppKit** owns the shell: `NSStatusItem`, `NSPopover`, `NSAlert`, `NSWindow`, `NSPasteboard`.
- **SwiftUI** owns rich content, hosted via `NSHostingController`: the popover and the preferences form.

New UI goes in SwiftUI. Menu-bar chrome, dialogs, and anything positioned in screen coordinates stay AppKit.

Because the app is `LSUIElement` with `.accessory` activation policy, it has no Dock icon and is usually not the active app. That has consequences to respect:

- Anything that needs keyboard focus must call `NSApp.activate(ignoringOtherApps: true)` first. The popover does, because the user types in it.
- `statusItem.menu` must stay `nil`. Assigning a menu swallows the click that has to reach the button's action, and the popover would never open from the icon.
- A transient `NSPopover` is dismissed by AppKit on the same click that then reaches the status button, so a toggle has to refuse an open that arrives immediately after a close.
- Anchor a popover with `show(relativeTo:of:preferredEdge:)` and let AppKit clamp it; position and clamp a plain window yourself against `NSScreen.visibleFrame`.

---

## Error Handling & User Feedback

### 1. No crashing

There is no `try!` and no `fatalError` in `Sources/EasyWrite/`. Keep it that way. The single force-unwrap (`try await group.next()!` on a non-empty task group) is safe by construction.

### 2. Choose the response by who can fix it

| Situation | Response | Example |
|---|---|---|
| Failure while the popover is open | a message in the right-hand pane | model error, timeout, empty result, Apple Intelligence unavailable |
| Nothing to act on | nothing at all — empty panes, no model call | clipboard empty, holds an image, or is marked private |
| User can fix it, and no popover is open | `NSAlert` with a specific explanation | Launch-at-Login failure |
| Best-effort side effect | `try?`, no UI | `SMAppService.mainApp.register()` on first run |

The popover is the app's voice. Because it is on screen whenever a translation runs, a failure has somewhere to be explained, which is why there are no beeps on the translation path and no modal dialogs.

### 3. Specific messages beat generic ones

`LLMTranslator.Unavailable` exists because "enable Apple Intelligence" is wrong advice for a user who already enabled it and is waiting on a model download. Map each framework reason to its own message, and add `@unknown default` so a future OS reason falls back gracefully rather than silently misreporting.

### 4. Custom errors

Small and local: `struct TimeoutError: Error {}` inside the type that throws it. Do not build an app-wide error enum for four call sites.

---

## Documentation & Comments

### 1. Doc comments

`///` on types and non-obvious methods, stating the contract or the reason the thing exists:

```swift
/// Single source of truth for user settings. ObservableObject so SwiftUI prefs bind to it.

/// Nil means there is nothing to translate: no text at all, or — when the user leaves the
/// setting on — text whose source marked it as private or momentary.

/// Cumulative snapshots of the translation: every element is the whole text produced so far.
```

There is no required tag block (no `@date`, no mandatory `@param`). A sentence that a reader could not have derived from the signature is the bar.

### 2. Inline comments

Comment only what the code cannot say for itself:

```swift
// ✅ decodes a magic number
.init(keyCode: 6, modifiers: 4608),  // ⇧⌃Z
try await Task.sleep(nanoseconds: 20_000_000_000)    // 20s

// ✅ records a platform constraint
// Assigning a menu would swallow the click that has to reach the button's action.

// ✅ explains a product decision that the code alone doesn't justify
// Our own write must not look like new clipboard content on the next open.

// ❌ narrates the next line
// set the busy icon
setIcon(busy: true)

// ❌ repeats the method name
// prewarm the model
prewarm()
```

**When to comment**: magic numbers (key codes, modifier masks, timeouts), platform gotchas and workarounds, product decisions that look arbitrary in code, and anything an auditor would otherwise have to reverse-engineer.

**When not to comment (rename or restructure instead)**: business logic, obvious operations, restatements of a name.

### 3. `// MARK:`

Group sections in larger types, as `AppDelegate` and `TranslatorModel` do: `// MARK: Status item`, `// MARK: Hot-keys`, `// MARK: Actions`, `// MARK: Translation`, `// MARK: Helpers`.

### 4. Documentation workflow

Each fact lives in exactly one document. Before adding a paragraph, find the authoritative home:

| Topic | Authoritative document |
|---|---|
| Product, install, usage | `README.md` |
| Architecture, per-file responsibilities | `HOW_IT_WORKS.md` |
| Data flow, permissions, threat model | `SECURITY.md` |
| Code style and patterns | this file |
| Testing | `docs/conventions/testing/README.md` |
| AI guardrails | `docs/conventions/AI_WORKFLOW.md` |
| Release entries | `docs/conventions/RELEASE_NOTES_GUIDE.md` |

Update the authoritative document and link to it from elsewhere. Never copy-paste between docs.

---

## Testing

See [testing/README.md](testing/README.md) for the full picture.

Short version:

- The gates are `swift build` (warning-free), `./test.sh`, and a manual smoke test on a supported Mac. There is no CI, so nobody runs the tests but you.
- The suite covers `EasyWriteCore` — language lookup and the translation cache — plus one test that scans the sources to prove only one function writes the pasteboard.
- `@MainActor` AppKit flows, the popover, the hot-key, and the on-device model are **not** covered and cannot be.
- Put new pure logic in `EasyWriteCore` so it can be tested, and be precise about what "tests pass" covers.

---

## Git Workflow

### 1. Branch Naming

```
main                  # primary branch
dev/<descriptive>     # working branches, e.g. dev/popup
```

### 2. Commit Messages

A capitalised English sentence describing the change. No prefix tag, no scope, no trailing period. From real history:

```
Add Arabic language (v1.1)
Show specific reason when Apple Intelligence is unavailable
Replace README demo with a premium animated walkthrough
Use app icon (not the banner) as README header — keep it simple
```

### 3. Ignored Files

Per `.gitignore`: `.build/`, `.swiftpm/`, `Package.resolved`, `EasyWrite.app/`, `*.app`, `.DS_Store`, `xcuserdata/`. Signing material lives in a keychain under `~/Library` and must never enter the repo.

---

## Security & Privacy Conventions

These are invariants, not preferences. `SECURITY.md` is the promise made to users; this section is how the code keeps it.

1. **No network code.** No `URLSession`, no sockets, no third-party SDK that could open one. The absence is verifiable by grep, and that is the point.
2. **No telemetry, analytics, or crash reporting.**
3. **No logging of user text.** There is no `print` or `os_log` in `Sources/`. Debug prints must not survive into a commit.
4. **No persistence of translated content.** The translation cache is in memory, capped at twenty entries, and dies with the process. Settings persist; content does not.
5. **Easy Write reads the pasteboard and never writes it, except in the single code path behind the popover's Copy button.** That path is `Clipboard.write`, and `Tests/EasyWriteCoreTests/PasteboardWriteGuardTests.swift` fails if a second one appears. Like the network rule, this is enforced by counting rather than by remembering.
6. **No permission at all.** There is no `CGEvent`, no Accessibility check, and no entitlement. The app reads the clipboard and registers a hot-key, neither of which needs a grant. Adding a feature that needs one is a product decision, not an implementation detail.
7. **Content its source marked private is not read.** The nspasteboard concealed and transient markers are honoured by default, so a copied password produces empty panes rather than a translation, and never reaches the cache.
8. **No new dependencies.** Every added package is code the user can no longer audit in one sitting.

---

## Performance Conventions

- **Prewarm the model, and actually use the warm session.** A session is warmed for one instruction string; keep exactly one, spend it on the next translation, and rebuild it afterwards. Measured on an M-series Mac this is a first token at 0.25 s instead of 2.4 s, and it is the single biggest lever in the app.
- **Stream anything the user waits on.** Each snapshot carries the whole translation so far, so the first words appear immediately.
- **Cap the wait.** 20 s timeout on model calls; one retry for a transient error, and only while nothing has been emitted.
- **Cap the output.** `maximumResponseTokens` stops a runaway generation. It truncates hard rather than shortening gracefully, so set it far above what the task needs.
- **Debounce typing and cancel the previous request.** An edit costs one run, not one per keystroke.
- **Cache what is deterministic.** Greedy sampling makes a repeat safe to answer from memory.

---

## Versioning & Release

- `CFBundleShortVersionString` in `Info.plist` is the user-visible version and must match the newest `CHANGELOG.md` heading. The popover's gear menu reads it from the bundle at runtime.
- `CFBundleVersion` is a monotonically increasing build number.
- Every user-visible change gets a `CHANGELOG.md` entry — see [RELEASE_NOTES_GUIDE.md](RELEASE_NOTES_GUIDE.md).
- Distribution is build-from-source (`./build.sh`); a notarized download may follow.

---

## Quick Reference Checklist

Before committing, verify:

- [ ] `swift build` succeeds with no new warnings
- [ ] `swift build -c release` succeeds (what `./build.sh` runs)
- [ ] `./test.sh` passes
- [ ] Manually verified on a supported Mac — see [testing/README.md](testing/README.md)
- [ ] 4-space indentation, no tabs, no trailing whitespace
- [ ] No `URLSession`, sockets, analytics, or new package dependencies
- [ ] No `print` / `os_log`, and no debug code left behind
- [ ] New settings go through `Store`, with a default and a merge-safe decode
- [ ] New pure logic went into `EasyWriteCore` with a test, or there is a stated reason it could not
- [ ] AppKit / SwiftUI state changes are on the main actor; escaping closures use `[weak self]`
- [ ] No `try!` or `fatalError`; failures explain themselves, never crash
- [ ] Still exactly one pasteboard write, still no permission requested, still no `CGEvent`
- [ ] User-facing strings are English, sentence case, typographic punctuation
- [ ] `Info.plist` versions and `CHANGELOG.md` updated if the change is user-visible
- [ ] Commit message is a capitalised sentence with no prefix tag

---

## Additional Resources

- [README.md](../../README.md) — product overview
- [HOW_IT_WORKS.md](../../HOW_IT_WORKS.md) — architecture tour and file map
- [SECURITY.md](../../SECURITY.md) — data flow and permissions
- [CONTRIBUTING.md](../../CONTRIBUTING.md) — contributor-facing summary
- [AI_WORKFLOW.md](AI_WORKFLOW.md) — guardrails for AI agents
- [testing/README.md](testing/README.md) — testing guide
