# Easy Write — Testing Guide

## Current state: there is no test suite

This is the honest starting point, and every plan, PR, and doc must be written
against it:

- `Package.swift` declares exactly one target — `.executableTarget(name: "EasyWrite")`.
- There is no `Tests/` directory and no `.testTarget`.
- `swift test` therefore runs nothing.
- There is no CI: `.github/` contains only issue templates, no workflows.
- There is no SwiftLint or swift-format configuration.

Do not write "tests pass" in a PR. Do not add a coverage claim. If a change
needs proof, either add the test target (section 3) or record a manual
reproduction (section 6).

---

## 1. What is verified today

| Gate | Command | What it catches |
|---|---|---|
| Compile | `swift build` | type errors, isolation mistakes, warnings |
| Release compile | `swift build -c release` | optimiser-only failures; what `./build.sh` runs |
| Bundle | `./build.sh` | plist/icon/codesign problems |
| Manual smoke test | see section 6 | everything else |

`swift build` must finish **warning-free**. With no linter and no tests, the
compiler is the only automated signal this repo has.

---

## 2. Why the automatable surface is small

Most of the app is not unit-testable, for reasons that are properties of the
app rather than gaps to be fixed:

- **It is `@MainActor` AppKit.** `AppDelegate`, `ReaderPanel`, and
  `PreferencesController` build menus, panels, and windows. Exercising them
  needs a running `NSApplication`, not a test process.
- **It drives other applications.** `Replacer` posts synthetic ⌘C/⌘V through
  `CGEvent` and reads the system pasteboard. That requires an Accessibility
  grant, a focused target app, and real timing.
- **The engine is hardware-bound and non-deterministic.** `LLMTranslator` calls
  Apple's on-device model, which needs Apple Silicon with Apple Intelligence
  enabled and returns different wording run to run.
- **Hot-keys are global OS state.** `HotKeyCenter` registers with Carbon
  system-wide; two test processes would fight over the same combination.

What *is* worth testing is the pure logic wrapped around all of that.

---

## 3. Adding a test target

Adding tests is a change to the package layout. Agree on it first — do not do it
as a side effect of another task.

### Preferred: extract a library target

Move the pure logic into a plain library, let both the executable and the tests
depend on it. This avoids linking a target that owns `main`, and it makes the
testable surface explicit.

```swift
targets: [
    .target(
        name: "EasyWriteCore",
        path: "Sources/EasyWriteCore"
    ),
    .executableTarget(
        name: "EasyWrite",
        dependencies: ["EasyWriteCore"],
        path: "Sources/EasyWrite",
        swiftSettings: [.swiftLanguageMode(.v5)],
        linkerSettings: [.linkedFramework("Carbon")]
    ),
    .testTarget(
        name: "EasyWriteCoreTests",
        dependencies: ["EasyWriteCore"],
        path: "Tests/EasyWriteCoreTests"
    )
]
```

### Quicker: depend on the executable directly

SwiftPM allows a test target to depend on an executable target. It works, but it
links the whole app — including its AppKit and FoundationModels imports — into
the test bundle, so it is the more fragile option.

```swift
.testTarget(
    name: "EasyWriteTests",
    dependencies: ["EasyWrite"],
    path: "Tests/EasyWriteTests"
)
```

Either way, remember the platform floor: tests build and run only on macOS 26+
with Apple Silicon.

---

## 4. What to test first

In priority order, with the change each one needs:

| Unit | Why it is worth a test | Change required |
|---|---|---|
| `KeyDisplay.string(keyCode:modifiers:)` | Pure mapping, easy to break when adding keys; wrong labels are user-visible | none — already `internal` and non-isolated |
| `KeyDisplay.carbonModifiers(from:)` | Bit-mask conversion between two APIs; silent if wrong | none |
| `Languages.named(_:)` | Falls back to the first language for an unknown code — a real upgrade path when a code is removed | none |
| `LLMTranslator.clean(_:)` | Strips surrounding quotes the model sometimes adds; edge cases (one quote, empty, quoted-inside) are exactly where it breaks | make it non-`private` |
| `Store` shortcut merge/decode | The upgrade path: a release that adds an action must not lose it for existing users | inject `UserDefaults` instead of reading `.standard` in `init` |

Everything above is deterministic, needs no permissions, and runs in
milliseconds. That is the bar for "worth automating" in this repo.

---

## 5. Conventions for new tests

- **Use Swift Testing** (`import Testing`, `@Test`, `#expect`) for new tests.
  It ships with the Swift 6 toolchain the package already requires. XCTest is
  acceptable if you need something Swift Testing lacks; do not mix styles inside
  one file.
- **Given/when/then as the display name**, mirroring how behaviour is described
  everywhere else in this repo:

```swift
@Test("given an unknown language code, when looked up, then it falls back to German")
func unknownLanguageCodeFallsBack() {
    #expect(Languages.named("xx").code == "de")
}
```

- **One behaviour per test.** No shared mutable state between tests; Swift
  Testing runs them in parallel by default.
- **Never call the model.** No test may depend on Apple Intelligence being
  enabled, on network access, or on wall-clock timing.
- **Never touch `UserDefaults.standard`.** Inject a
  `UserDefaults(suiteName:)` and call `removePersistentDomain(forName:)`
  afterwards, so a test run cannot corrupt the developer's real settings.
- **No Accessibility, no pasteboard.** A unit test must not post `CGEvent`s or
  write to `NSPasteboard.general`.
- **English** in names, comments, and failure messages.
- **Test the contract, not the implementation.** Assert on the returned string,
  not on how it was assembled.

Run them with:

```bash
swift test                                    # all
swift test --filter EasyWriteCoreTests        # one target
swift test --list-tests                       # enumerate
```

---

## 6. Manual smoke test

This is the real acceptance gate today. Run it on macOS 26+ / Apple Silicon with
Apple Intelligence enabled, after `./setup-signing.sh` has been run once.

```bash
./build.sh && open EasyWrite.app
```

| # | Step | Expected |
|---|---|---|
| 1 | Launch | Speech-bubble icon appears in the menu bar; **no** Dock icon |
| 2 | Open the menu | Header shows the version from `Info.plist`; all four actions list their current shortcuts |
| 3 | First launch only | Accessibility prompt appears; grant it in System Settings → Privacy & Security → Accessibility |
| 4 | Select "Can you send me the report tomorrow?" in TextEdit, press `⌥⌘T` | Selection is replaced in place with a formal translation in the target language; icon flashes a checkmark |
| 5 | Repeat with `⌥⌘I` | Informal forms (German *du*, French *tu*, …) instead of formal |
| 6 | Repeat with `⌥⌘P` | Translation that keeps the source's tone |
| 7 | Select foreign text on a web page in Safari, press `⌥⌘E` | Floating popup appears near the cursor with the English text; Safari keeps focus; Copy and Done work; it disappears on its own after ~30 s |
| 8 | Copy a distinctive string, then run any translation | After the swap, the original clipboard content is back |
| 9 | Press a shortcut with nothing selected | Single beep, no dialog, no crash |
| 10 | Preferences → change target language | Menu labels and pronoun hints update immediately |
| 11 | Preferences → rebind a shortcut, press Esc | Recording cancels, the old shortcut still works |
| 12 | Preferences → rebind a shortcut for real | The new combination works; the old one no longer does |
| 13 | Preferences → add a style-guide line, translate again | Output reflects the instruction |
| 14 | Enable "Preview before replacing", translate | Dialog with Replace / Copy / Cancel; Replace pastes into the original app |
| 15 | Toggle Launch at Login twice | Checkmark tracks the state; no error dialog |
| 16 | Quit and relaunch | Settings survive |

If a step cannot be run — wrong hardware, Apple Intelligence unavailable — say
so explicitly rather than skipping it silently.

---

## 7. What deliberately has no coverage

Stating these keeps anyone from assuming they are covered:

- The Accessibility permission flow and its TCC interaction.
- Code signing and whether the grant survives a rebuild.
- Launch at Login (`SMAppService`) registration.
- Translation quality for any language.
- Behaviour when the model is mid-download or the Mac is unsupported.

Each of these is verified by hand, or by a user reporting it.

---

## Related documents

- [CODING_CONVENTIONS.md](../CODING_CONVENTIONS.md) — style and patterns
- [AI_WORKFLOW.md](../AI_WORKFLOW.md) — guardrails, PR checklist, reproduce-before-fix
- [HOW_IT_WORKS.md](../../../HOW_IT_WORKS.md) — architecture tour
- [docs/AI_Overview.md](../../AI_Overview.md) — orientation for AI agents
