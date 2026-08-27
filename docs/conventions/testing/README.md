# Easy Write — Testing Guide

## Current state: a small suite, no CI

This is the honest starting point, and every plan, PR, and doc must be written against it:

- `Package.swift` declares three targets: the `EasyWriteCore` library, the `EasyWrite` executable, and
  the `EasyWriteCoreTests` test target.
- Fourteen tests exist, all covering `EasyWriteCore` or the source tree itself. They run in
  milliseconds, need no permissions, and never call either engine.
- Everything with a UI, a hot-key, or a translation call has **no automated coverage at all**.
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
| Unit tests | `./test.sh` | language lookup, engine resolution, cache behaviour, the single-pasteboard-write invariant |
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
- **Both engines are hardware-bound.** `LLMTranslator` calls Apple's on-device model, which needs
  Apple Silicon with Apple Intelligence enabled. Greedy sampling makes it repeatable for the same
  input, but it is still a several-second call to a model that a future OS update will reword.
  `AppleTranslator` needs an installed language pack for the pair, which is machine state a test
  cannot create and must not download.
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

Remember the platform floor: tests build and run only on macOS 26.4+ with Apple Silicon.

---

## 4. What is covered, and what to cover next

Covered today:

| Unit | What the test protects |
|---|---|
| `Languages.named(_:)` | Falls back to the first language for a code this build no longer ships, and every language resolves to its own entry |
| `Languages.auto` / `sources` | The auto-detect sentinel can be a source and can never become a target |
| `Engine.named(_:)` | A fresh install and a value written by a later build both resolve to Apple Intelligence, and every raw value survives a round trip — renaming one would silently reset the user's choice on upgrade |
| `Engine.title` / `caption` | Every engine says what it is and what the choice costs, and no two share a title |
| `TranslationCache` | A repeat hits; the style guide, both language codes, the engine and the text are all part of the key; overflow evicts the least recently used entry; a read refreshes recency; remove forces a fresh run |
| Pasteboard writes | Exactly one function under `Sources/` calls a pasteboard-writing API, and it is `Clipboard.write` |

The engine in the cache key is the one that is easiest to lose in a refactor and the most visible when
lost: the two engines word the same sentence differently, so dropping it would answer a switched
engine with the other one's result.

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

This is still the real acceptance gate. Run it on macOS 26.4+ / Apple Silicon with Apple Intelligence
enabled — steps 25 to 27 also need at least one Apple Translate language pack.

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
| 14 | Copy a password from a password manager, press `⇧⌃Z` | Empty panes and no engine call. Uncheck "Ignore private clipboard content" in Preferences and it reads normally |
| 15 | Translate, press **Copy**, wait five seconds, then paste elsewhere | The translation pastes; nothing has overwritten it |
| 16 | Translate **without** pressing Copy, then paste elsewhere | The text you originally copied pastes — the app wrote nothing |
| 17 | Press Escape with the popover focused, and click outside it | Both close it |
| 18 | Look at the menu bar with the popover open | The bar and every icon beside ours stay fully visible and undimmed — the popover starts below the bar |
| 19 | Without clicking anything, type | The left pane already has the keyboard |
| 20 | In the left pane press ⌘A, ⌘C, ⌘X, ⌘V, ⌘Z | All behave as in any text field. ⌘A is not proof on its own: `NSTextView` binds it natively and works even when the main menu is missing |
| 21 | Watch the footer during a translation | A stopwatch counts up in hundredths, then holds the final time. A cached result says "Cached" instead |
| 22 | Right-click the menu-bar icon | The settings menu opens — version, Preferences…, Launch at login, Quit — and the popover closes if it was open |
| 23 | Gear → Preferences, rebind the shortcut | The new combination opens the popover; the old one does not |
| 24 | Preferences → add a style-guide line, then Retranslate | Output reflects the instruction |
| 25 | Preferences → switch the engine to Apple Translate, reopen on the same text | That engine's own wording, arriving in one piece rather than streaming — never the model's cached answer |
| 26 | With Apple Translate selected, read the language list | Every language, its pack status against the current target, and a Download button wherever a pack is missing |
| 27 | Switch back to Apple Intelligence and reopen | The model's own answer returns, and the style guide applies to it again |
| 28 | Gear → Launch at login, twice | The checkmark tracks the state; no error dialog |
| 29 | Press ⌘Q with the popover focused | The app quits |
| 30 | Quit and relaunch | Languages, shortcut, engine and style guide survive; the cache does not — the first translation runs again |

### Driving this from a script

Most of the table can be automated on a Mac that has granted the terminal **Accessibility** and
**Screen Recording**, which is how the rows above were checked: `osascript -e 'tell application
"System Events" to key code 6 using {shift down, control down}'` for the hot-key, a short `CGEvent`
helper for clicks, `screencapture -x -R x,y,w,h` to look at the result, and
`CGWindowListCopyWindowInfo` filtered by owner to assert the popover's frame against
`NSScreen.visibleFrame`.

Two traps are worth knowing before trusting such a run:

- **`keystroke "c" using command down` does not fire menu key equivalents.** Use the low-level form,
  `key code 8 using {command down}`. A ⌘C test that silently does nothing looks exactly like the bug
  it is meant to catch.
- **Assert against a sentinel, not the previous value.** Copying text that the clipboard already held
  proves nothing. Put a known string on the clipboard first and check it was replaced.

If a step cannot be run — wrong hardware, Apple Intelligence unavailable, no password manager
installed — say so explicitly rather than skipping it silently.

---

## 7. What deliberately has no coverage

Stating these keeps anyone from assuming they are covered:

- The popover: anchoring, focus, Escape, transient dismissal, and the toggle.
- The hot-key: registration, rebinding, and the silent failure when another app owns the combination.
- Streaming: that snapshots arrive progressively, and that the timeout and the single retry behave.
- The clipboard read policy at runtime, including the nspasteboard markers.
- The editing key equivalents, and therefore whether the main menu is installed at all.
- Code signing, and Launch at Login (`SMAppService`) registration.
- Translation quality for any language.
- Behaviour when the model is mid-download or the Mac is unsupported.

Each of these is verified by hand, or by a user reporting it.

## 8. Translation quality is not a bug report about the prompt

The on-device model is small. On longer sentences it sometimes chooses an odd word for a term, or
invents one outright. Before changing the instruction text in response, measure — a throwaway script
against `FoundationModels` costs a minute and settles it. The one time this was done, the same sentence
failed identically under the v1 110-word instruction, a 36-word one, greedy sampling and
temperature 0.1, and with the source language named or auto-detected. Only pinning the term in the
user's style guide fixed it.

So: reproduce with a script, compare variants, and only then touch the instruction. A prompt change that
fixes one sentence and breaks another is the normal outcome, and without measurements you will not know
that is what happened.

Four things that measuring has already settled, so nobody spends the minute twice:

- **The instruction's last line must name the target language.** Ending on a bare "output only the
  translation" makes the model echo the source text back untranslated — four of eight phrases.
- **Instruction length does not cost latency.** 36 words and 200 words gave the same time to first
  token. Shorten for clarity, not for speed.
- **Greedy decoding is genuinely deterministic**, six identical runs across different prewarm timings.
  So if the app disagrees with your script, the *instruction differs* — check the style guide, which is
  appended to it, before suspecting the model.
- **Sampling is worse, and not faster.** Eight phrases, three samples each, scored on whether the
  facts that must survive — times, places, numbers, negation, modality, subject — actually did, and
  on whether the output degenerated:

| Sampling | Passed | Avg | Distinct outputs of 24 runs |
|---|---|---|---|
| greedy | **18/24** | 0.80 s | 8 (deterministic) |
| temperature 0.3 | 11/24 | 0.88 s | 21 |
| temperature 0.7 | 9/24 | 0.61 s | 24 |
| `.random(top: 20)` | 8/24 | 0.60 s | 24 |
| `.random(probabilityThreshold: 0.9)` | 11/24 | 0.61 s | 23 |
| `.random(top: 20)` + temperature 0.3 | 14/24 | 0.94 s | 22 |

Quality falls as randomness rises with no latency to show for it, because translation is not
open-ended generation: there is usually one right continuation, so sampling mostly finds worse ones —
invented words, *yesterday* for *tomorrow*, dropped subjects, and one output that echoed the English
with a Cyrillic С spliced into it. Greedy stays.

### The eight-phrase benchmark

One phrase per failure mode: a time reference ("See you tomorrow at the office."), a question ("Can
you send me the report tomorrow?"), a number ("The two invoices are attached."), a negation with "yet"
("Please don't send the revised version yet."), modality ("She may arrive after lunch."), a place and
past tense ("We discussed it with the legal team in London."), a request ("Could we tighten the second
section?"), and a domain term ("Please find the invoice in the appendix.").

**Record both engines.** Since 2.1 there are two, and they fail differently: the model invents terms
and drifts in register, while Apple Translate is steady but cannot be told anything. A result that
names only one engine does not say which of those you were looking at. The known spot check, into
Russian: on the question phrase the model produced an ungrammatical sentence in 2.0 s and Apple
Translate a correct one in 0.8 s; with a term pinned in the style guide, only the model used it.

---

## Related documents

- [CODING_CONVENTIONS.md](../CODING_CONVENTIONS.md) — style and patterns
- [AI_WORKFLOW.md](../AI_WORKFLOW.md) — guardrails, PR checklist, reproduce-before-fix
- [HOW_IT_WORKS.md](../../../HOW_IT_WORKS.md) — architecture tour
- [docs/AI_Overview.md](../../AI_Overview.md) — orientation for AI agents
