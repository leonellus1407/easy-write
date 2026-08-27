# Easy Write — Testing Guide

## Current state: a small suite, no CI

This is the honest starting point, and every plan, PR, and doc must be written against it:

- `Package.swift` declares three targets: the `EasyWriteCore` library, the `EasyWrite` executable, and
  the `EasyWriteCoreTests` test target.
- Nine tests exist, all covering `EasyWriteCore` or the source tree itself. They run in
  milliseconds, need no permissions, and never call the model.
- Everything with a UI, a hot-key, or a model call has **no automated coverage at all**.
- There is no CI: `.github/` contains only issue templates, no workflows. Nobody runs these tests
  except the person who typed the command.
- There is no SwiftLint or swift-format configuration.

So "the tests pass" is a much smaller claim than it sounds. Say what actually ran, and record a manual
reproduction (section 6) for anything the suite does not reach.

---

## 1. What is verified today

| Gate | Command | What it catches |
|---|---|---|
| Compile | `swift build` | type errors, isolation mistakes, warnings |
| Release compile | `swift build -c release` | optimiser-only failures; what `./build.sh` runs |
| Unit tests | `./test.sh` | language lookup, cache behaviour, the single-pasteboard-write invariant |
| Bundle | `./build.sh` | plist/icon/codesign problems |
| Manual smoke test | see section 6 | everything else |

`swift build` must finish **warning-free**. With no linter and no CI, the compiler is still the
strongest automated signal this repo has.

### Why `./test.sh` and not `swift test`

Both work; use whichever runs. With full Xcode installed, `swift test` is enough. With only the
Command Line Tools, swift-testing ships as a framework that SwiftPM leaves off the search path and
`swift test` fails with `no such module 'Testing'`. `./test.sh` adds the framework and its rpaths, then
hands off to `swift test`, passing any extra arguments straight through:

```bash
./test.sh                                        # all
./test.sh --filter TranslationCacheTests         # one suite
./test.sh --list-tests                           # enumerate
```

---

## 2. Why the automatable surface is small

Most of the app is not unit-testable, for reasons that are properties of the app rather than gaps to
be fixed:

- **It is `@MainActor` AppKit.** `AppDelegate`, `TranslatorPanel`, and `PreferencesController` build a
  status item, a popover, and a window. Exercising them needs a running `NSApplication`, not a test
  process.
- **The engine is hardware-bound and non-deterministic.** `LLMTranslator` calls Apple's on-device
  model, which needs Apple Silicon with Apple Intelligence enabled. Greedy sampling makes it
  repeatable for the same input, but it is still a several-second call to a model that a future OS
  update will reword.
- **Hot-keys are global OS state.** `HotKeyCenter` registers with Carbon system-wide; two test
  processes would fight over the same combination.
- **The clipboard is shared, mutable, machine-wide state.** A test must not write to
  `NSPasteboard.general`, so the read policy in `Clipboard` cannot be exercised directly.

What *is* worth testing is the pure logic wrapped around all of that, plus — see section 4 — the
invariants that can be checked by reading the source rather than by running it.

---

## 3. The package layout that makes testing possible

`EasyWriteCore` is a plain library target holding the pure value logic, deliberately free of AppKit and
FoundationModels. Both the executable and the tests depend on it, which avoids linking a target that
owns `main` and makes the testable surface explicit:

```swift
targets: [
    .target(name: "EasyWriteCore", path: "Sources/EasyWriteCore", ...),
    .executableTarget(name: "EasyWrite", dependencies: ["EasyWriteCore"], ...),
    .testTarget(name: "EasyWriteCoreTests", dependencies: ["EasyWriteCore"], ...)
]
```

New pure logic goes in `EasyWriteCore` so it can be tested. Anything that imports AppKit or
FoundationModels stays in `EasyWrite`. Moving an existing type across that line is a change to the
package layout — agree on it first, rather than doing it as a side effect of another task.

Remember the platform floor: tests build and run only on macOS 26+ with Apple Silicon.

---

## 4. What is covered, and what to cover next

Covered today:

| Unit | What the test protects |
|---|---|
| `Languages.named(_:)` | Falls back to the first language for a code this build no longer ships, and every language resolves to its own entry |
| `Languages.auto` / `sources` | The auto-detect sentinel can be a source and can never become a target |
| `TranslationCache` | A repeat hits; the style guide, both language codes and the text are all part of the key; overflow evicts the least recently used entry; a read refreshes recency; remove forces a fresh run |
| Pasteboard writes | Exactly one function under `Sources/` calls a pasteboard-writing API, and it is `Clipboard.write` |

That last one is not a unit test in the usual sense: it scans the source tree for the closed list of
`NSPasteboard` writing calls (`clearContents`, `writeObjects`, `setString`, `setData`,
`setPropertyList`, `declareTypes`, `prepareForNewContents`) and asserts they all sit in one function.
It exists because the promise in [`SECURITY.md`](../../../SECURITY.md) is a count of call sites, and a
count is worth enforcing rather than remembering. When it fails it names the offending function.

Worth adding next, in priority order:

| Unit | Why it is worth a test | Change required |
|---|---|---|
| `KeyDisplay.string(keyCode:modifiers:)` | Pure mapping, easy to break when adding keys; wrong labels are user-visible | move to `EasyWriteCore` (it only needs `NSEvent.ModifierFlags` for one function) |
| `KeyDisplay.carbonModifiers(from:)` | Bit-mask conversion between two APIs; silent if wrong | same |
| `LLMTranslator.clean(_:)` | Strips surrounding quotes the model sometimes adds; edge cases (one quote, empty, quoted-inside) are exactly where it breaks | extract it into `EasyWriteCore` |
| `Store` shortcut merge/decode | The upgrade path: a release that renames an action must not lose the user's binding | inject `UserDefaults` instead of reading `.standard` in `init` |

Everything above is deterministic, needs no permissions, and runs in milliseconds. That is the bar for
"worth automating" in this repo.

---

## 5. Conventions for new tests

- **Use Swift Testing** (`import Testing`, `@Test`, `#expect`). It ships with the Swift 6 toolchain the
  package already requires. XCTest is acceptable if you need something Swift Testing lacks; do not mix
  styles inside one file.
- **Given/when/then as the display name**, mirroring how behaviour is described everywhere else in
  this repo:

```swift
@Test("given an unknown language code, when looked up, then it falls back to German")
func unknownLanguageCodeFallsBack() {
    #expect(Languages.named("xx").code == "de")
}
```

- **One behaviour per test.** No shared mutable state between tests; Swift Testing runs them in
  parallel by default.
- **Never call the model.** No test may depend on Apple Intelligence being enabled, on network access,
  or on wall-clock timing.
- **Never touch `UserDefaults.standard`.** Inject a `UserDefaults(suiteName:)` and call
  `removePersistentDomain(forName:)` afterwards, so a test run cannot corrupt the developer's real
  settings.
- **Never touch `NSPasteboard.general`.** A test must not read or write the developer's clipboard.
- **English** in names, comments, and failure messages.
- **Test the contract, not the implementation.** Assert on the returned string, not on how it was
  assembled.

---

## 6. Manual smoke test

This is still the real acceptance gate. Run it on macOS 26+ / Apple Silicon with Apple Intelligence
enabled.

```bash
./build.sh && open EasyWrite.app
```

| # | Step | Expected |
|---|---|---|
| 1 | Launch | Speech-bubble icon appears in the menu bar; **no** Dock icon; **no permission prompt of any kind** |
| 2 | Copy "Can you send me the report tomorrow?", press `⇧⌃Z` | Popover opens at the icon; left pane holds the sentence; the right pane starts filling within about a second |
| 3 | Press `⇧⌃Z` again | Popover closes |
| 4 | Click the status icon | Same as step 2; clicking it again closes it |
| 5 | Change the target language | Retranslates into the new language |
| 6 | Pick an explicit source language, press swap | The two languages exchange, the input text is unchanged, and it retranslates once |
| 7 | Set the source back to Auto-detect | The swap button is disabled |
| 8 | Close the popover and reopen it with the same clipboard | The result appears instantly, with no generation delay |
| 9 | Press **Retranslate** on that cached result | A fresh run visibly streams again |
| 10 | Edit the left pane | Retranslates once after a short pause, not once per keystroke |
| 11 | Edit the left pane, close the popover, reopen it | The edit is still there — the clipboard has not changed, so it is not re-read |
| 12 | Copy something new, reopen | The new clipboard text replaces the pane |
| 13 | Copy an image, press `⇧⌃Z` | Empty panes, no crash |
| 14 | Copy a password from a password manager, press `⇧⌃Z` | Empty panes and no model call. Uncheck "Ignore private clipboard content" in Preferences and it reads normally |
| 15 | Translate, press **Copy**, wait five seconds, then paste elsewhere | The translation pastes; nothing has overwritten it |
| 16 | Translate **without** pressing Copy, then paste elsewhere | The text you originally copied pastes — the app wrote nothing |
| 17 | Press Escape with the popover focused, and click outside it | Both close it |
| 18 | Gear → Preferences, rebind the shortcut | The new combination opens the popover; the old one does not |
| 19 | Preferences → add a style-guide line, then Retranslate | Output reflects the instruction |
| 20 | Gear → Launch at login, twice | The checkmark tracks the state; no error dialog |
| 21 | Quit and relaunch | Languages, shortcut and style guide survive; the cache does not — the first translation streams again |

If a step cannot be run — wrong hardware, Apple Intelligence unavailable, no password manager
installed — say so explicitly rather than skipping it silently.

---

## 7. What deliberately has no coverage

Stating these keeps anyone from assuming they are covered:

- The popover: anchoring, focus, Escape, transient dismissal, and the toggle.
- The hot-key: registration, rebinding, and the silent failure when another app owns the combination.
- Streaming: that snapshots arrive progressively, and that the timeout and the single retry behave.
- The clipboard read policy at runtime, including the nspasteboard markers.
- Code signing, and Launch at Login (`SMAppService`) registration.
- Translation quality for any language.
- Behaviour when the model is mid-download or the Mac is unsupported.

Each of these is verified by hand, or by a user reporting it.

---

## Related documents

- [CODING_CONVENTIONS.md](../CODING_CONVENTIONS.md) — style and patterns
- [AI_WORKFLOW.md](../AI_WORKFLOW.md) — guardrails, PR checklist, reproduce-before-fix
- [HOW_IT_WORKS.md](../../../HOW_IT_WORKS.md) — architecture tour
- [docs/AI_Overview.md](../../AI_Overview.md) — orientation for AI agents
