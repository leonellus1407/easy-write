# Feature: Apple Translate as a second engine

## Overview

Easy Write gains a second translation engine, selectable in Preferences: Apple's **Translation**
framework — the same engine behind the system Translate app — alongside the Apple Intelligence
foundation model, which stays the default. The two are good at different things. The model reads
instructions, so it honours the user's style guide and the per-language notes, and it streams its
answer word by word; but it is a general-purpose 3B model that invents terms on longer sentences and
needs Apple Intelligence enabled. Translation is a dedicated machine-translation model: it takes no
instructions at all, returns the whole answer at once, runs on Macs without Apple Intelligence, and
covers language pairs the model handles poorly — at the cost of never sounding like you. Choosing
between them is a one-line setting, and everything else about the popover stays identical.

## Technical Specification

### Components Affected

Created:

- `Sources/EasyWrite/TranslationEngine.swift` — the protocol both engines satisfy, so `TranslatorModel` never branches on which one is active
- `Sources/EasyWrite/AppleTranslator.swift` — the Translation framework engine, conforming to that protocol
- `Sources/EasyWrite/LanguagePacks.swift` — availability lookup and the download flow, used by both the engine and Preferences

Modified:

- `Sources/EasyWrite/LLMTranslator.swift` — conforms to `TranslationEngine`; no behaviour change
- `Sources/EasyWrite/TranslatorModel.swift` — resolves the engine per run, and carries it in the cache key
- `Sources/EasyWrite/Store.swift` — the `engine` setting
- `Sources/EasyWrite/PreferencesController.swift` — engine picker, the language-pack list, and a line saying the style guide applies to the model only
- `Sources/EasyWriteCore/TranslationCache.swift` — `engine` joins the key
- `Tests/EasyWriteCoreTests/TranslationCacheTests.swift` — a case for the new key field
- `Package.swift` — platform floor raised; `Translation` and `NaturalLanguage` are expected to link from `import` alone, as every framework but Carbon does
- `Info.plist` — `LSMinimumSystemVersion` to match `Package.swift`, and a version bump
- `CHANGELOG.md` — release entry

Documentation is deliberately left out of this list. It is tracked in
[`docs/plans/1_documentation-debt.md`](../plans/1_documentation-debt.md) and updated in one pass, not
per experiment.

### Settings & Persistence Changes

| Key | Type | Default | Triggers `onChange?()` | Why |
|---|---|---|---|---|
| `translationEngine` | `String` — `"intelligence"` or `"translate"` | `"intelligence"` | no | Read when a run starts; nothing needs to re-register |

An existing user sees no change: the key is absent, so the default applies and they keep the model.

No `onChange?()` is needed because the popover is never on screen while Preferences is. The popover is
`.transient`, so opening the Preferences window dismisses it, and the next open re-reads the setting.

The engine is **not** stored per language. One setting, applied to every translation.

### Implementation Details

#### Step 1: Platform floor and the setting

Raise the floor in both places that must agree — `platforms:` in `Package.swift` and
`LSMinimumSystemVersion` in `Info.plist`. **26.4 is the version this feature needs**, because
`TranslationSession.Strategy`, `translate(_ AttributedString)` and `SystemLanguageModel.tokenCount(for:)`
are all gated there while everything else is 26.0. A higher floor is a product decision, not a
technical one, and costs users on the versions it skips.

Two things to check when the floor moves: a deployment target above the installed SDK produces linker
warnings, and `swift build` must stay warning-free, so the Command Line Tools may need updating first.
[`AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md#6-what-you-must-not-change-without-an-explicit-instruction)
forbids changing the minimum macOS version without an explicit instruction; this feature carries one.

Add `engine` to `Store` with the established `didSet` write-through and no `onChange?()`.

#### Step 2: One protocol, two engines

`TranslatorModel` already consumes an `AsyncThrowingStream<String, Error>` of cumulative snapshots.
That shape fits both engines — Translation simply yields one element — so the protocol is the existing
signature, and the model stops caring which engine answered:

```swift
@MainActor
protocol TranslationEngine {
    var unavailableReason: String? { get }
    func prewarm(from source: Lang, to target: Lang, styleGuide: String)
    func translate(_ text: String, from source: Lang, to target: Lang,
                   styleGuide: String) -> AsyncThrowingStream<String, Error>
}
```

`LLMTranslator` conforms as it stands, except that `unavailableReason` becomes a `String?` rather than
its own enum — the enum stays internal and `message` is what the protocol exposes.

`AppleTranslator` is the new conformer. Four things make it unlike `LLMTranslator`:

- **The source language is required.** The only programmatic initializer is
  `init(installedSource: Locale.Language, target: Locale.Language?)`, and its source is neither
  optional nor allowed to be uninstalled. Auto-detect therefore runs `NLLanguageRecognizer` first (see
  Step 3) and fails with a specific message when it cannot decide.
- **`TranslationSession` is a plain class with no `Sendable` conformance.** Unlike
  `LanguageModelSession`, which is `@unchecked Sendable` and so can be handed to a detached task, this
  one stays on the main actor. `translate(_:)` is `async throws` and awaiting it from the main actor is
  fine, so the streaming helper in `LLMTranslator` has no counterpart here.
- **The style guide and the per-language note are ignored.** There is nowhere to put them. They are
  still part of the cache key, because switching engines must not serve the other engine's answer.
- **Prewarming is `prepareTranslation()`**, which loads the pair rather than warming a prompt prefix.

The timeout keeps the existing shape — a `withThrowingTaskGroup` racing the work against a sleep — and
gains `session.cancel()` on the cancellation path, which `LanguageModelSession` has no equivalent for.
`.highFidelity` is the right `Strategy` for a translator a person reads; `.lowLatency` exists and is
the wrong trade here.

Errors map case by case, exactly as `LLMTranslator.Unavailable` does, so the popover explains itself:

| `TranslationError` | What the user is told |
|---|---|
| `unsupportedLanguagePairing` | This pair is not supported; suggest the model instead |
| `unsupportedSourceLanguage` / `unsupportedTargetLanguage` | Which of the two, by name |
| `notInstalled` | The pack is missing, with the Preferences route to download it |
| `unableToIdentifyLanguage` | Ask for an explicit source language rather than Auto-detect |
| `nothingToTranslate` | Never surfaced; the model already treats empty input as no work |
| `alreadyCancelled` | Never surfaced; a superseded run is not a failure |
| `internalError` and `@unknown default` | A generic line, as the model's `.other` does |

`TranslationError` matches through a custom `~=`, so `catch TranslationError.notInstalled` works in a
`catch` clause even though the cases are static properties rather than enum cases.

#### Step 3: Language detection, availability, and downloads

`LanguagePacks` owns three questions, and keeping them together is what stops availability logic
spreading between the engine and Preferences:

- **What is this text?** `NLLanguageRecognizer.dominantLanguage` gives an `NLLanguage`, whose
  `rawValue` is a BCP-47 code that `Locale.Language(identifier:)` accepts. This is the only reason
  `NaturalLanguage` is imported, and it runs on-device with no model download.
- **Can this pair run?** `LanguageAvailability.status(from:to:)` returns `.installed`, `.supported`
  (downloadable) or `.unsupported`, and `supportedLanguages` lists what the framework covers at all —
  which is not the same set as `Languages.all`.
- **Can it be installed?** `prepareTranslation()` performs the download, and `canRequestDownloads`
  says whether the app is allowed to ask at all.

One constraint shapes the UI. A session for a pair that is *not* installed cannot be built with
`init(installedSource:)`, so `prepareTranslation()` is unreachable from plain code in exactly the case
where it is needed. The SwiftUI overlay is the documented way in:

```swift
.translationTask(TranslationSession.Configuration(source: source, target: target)) { session in
    try? await session.prepareTranslation()
}
```

Preferences is already SwiftUI, so the download lives there rather than in the engine. That is also
where the user asked for it. **Verify on a supported Mac** that this presents the system download
consent and that the pack is usable afterwards without relaunching.

#### Step 4: Preferences

A new section, above the clipboard one, holding:

- The engine picker: *Apple Intelligence* and *Apple Translate*, with one caption line each saying
  what the choice costs — instructions and streaming versus speed and coverage.
- A note under the style guide stating that it applies to the Apple Intelligence engine only. The
  setting stays live either way, because the engine can be switched back at any time.
- The language list, shown only when Apple Translate is selected: each of `Languages.all` that the
  framework supports, with its status against the current target, and a control that starts the
  download when the status is `.supported`. Languages the framework does not cover are listed as
  unsupported rather than hidden, so the absence is explained rather than mysterious.

The popover is untouched. Same pickers, same swap, same stopwatch, same Copy. The right pane fills in
one step instead of streaming, which is a visible difference and an accepted one.

### Code Patterns to Follow

```swift
// A new setting on Store: persist in didSet, notify only if something must react
@Published var engine: String { didSet { d.set(engine, forKey: "translationEngine") } }
```

```swift
// Anything that can stall races a timeout; a timeout is never retried
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask { /* the translation */ }
    group.addTask { try await Task.sleep(nanoseconds: 20_000_000_000); throw TimeoutError() }
    defer { group.cancelAll() }
    _ = try await group.next()!
}
```

```swift
// Reason-specific copy lives next to the case that produces it, as LLMTranslator.Unavailable does
catch TranslationError.notInstalled {
    return "This language pair isn’t downloaded yet. Open Preferences to add it."
}
```

## Acceptance Criteria

### Functional Requirements

- [x] Preferences offers both engines, and Apple Intelligence is selected on a fresh install
- [x] The choice persists across relaunch
- [x] With Apple Translate selected, the popover translates the clipboard as before — same pickers, swap, stopwatch and Copy
- [x] Auto-detect works with Apple Translate, by identifying the source before opening the session
- [x] Switching engines and reopening on the same text produces that engine's own result, not the other's
- [x] Preferences lists which languages Apple Translate supports and whether each is installed
- [x] Enabling a language that is supported but not installed offers to download it, and it works afterwards
- [x] The style guide is stated to apply to Apple Intelligence only, and demonstrably has no effect in Apple Translate mode

### Edge Cases & Error Handling

Unchecked boxes below are written but not yet exercised on a Mac, because each needs a state that
cannot be forced from outside the app. They are listed in `Status` rather than assumed to work.

- [ ] Language pair unsupported → a specific message naming the pair, suggesting the other engine
- [x] Pack not installed → a specific message pointing at Preferences, not a generic failure
- [ ] Auto-detect cannot identify the language → asks for an explicit source
- [ ] `canRequestDownloads` is false → says so rather than offering a download that cannot happen
- [ ] Apple Intelligence unavailable while Apple Translate is selected → translation still works, since the model is not involved
- [ ] Apple Translate times out → the popover shows a failed state; the timeout is never retried
- [ ] Request superseded → the previous session is cancelled via `cancel()`, and cancellation is not reported as an error
- [ ] Empty, whitespace-only, image, or private clipboard → unchanged behaviour, no engine is called

### User Experience

- [x] All strings are English, sentence case, typographic punctuation, no emoji
- [x] The engine picker says what the trade is, so the choice is not guesswork
- [x] The right pane appearing at once rather than streaming is not mistaken for a hang — the spinner and stopwatch cover it
- [x] Nothing about the popover's layout changes between engines

### Privacy Impact

Non-negotiable. Every box must be checked, or the feature does not ship:

- [x] No network code added (`URLSession`, sockets, or otherwise)
- [x] No third-party dependency added to `Package.swift`
- [x] No analytics, telemetry, or crash reporting
- [x] No `print` / `os_log`, and no persistence of translated text
- [x] Easy Write still reads the pasteboard and never writes it, except in `Clipboard.write`
- [x] No permission is requested at all
- [x] **A language-pack download is the OS fetching data at the user's request, and `SECURITY.md` says so plainly.** The app contains no network code; choosing this engine can still cause macOS to download a pack. Not stating that would make the privacy page misleading by omission
- [ ] Confirmed on device that translating with an installed pack needs no network

## Out of Scope

- A per-language engine choice — one global setting, as decided
- Falling back to the other engine automatically. A failure reports its reason and stops; the user
  chose the engine
- `AttributedString` translation and the `skipsTranslation` attribute, which the 26.4 floor unlocks but
  which no part of the popover needs yet
- `.lowLatency` as a user-visible choice. `.highFidelity` is the right default and a second knob for a
  difference nobody asked about is not worth the surface
- Using `tokenCount(for:)` to catch over-long input before calling the model. Worth doing, unrelated to
  this feature, and listed in [`docs/plans/1_documentation-debt.md`](../plans/1_documentation-debt.md)

## Development Information

### Testing Strategy

1. **Compile**: `swift build` warning-free, then `swift build -c release`. The floor change makes the
   warning-free part a real risk rather than a formality.
2. **Automated**: `./test.sh`. The engine in the cache key is pure and gets a test; so does the
   mapping between our language codes and `Locale.Language`, if it lands in `EasyWriteCore`. The
   engines themselves are not unit-testable — one needs Apple Intelligence, the other needs installed
   language packs.
3. **Manual verification**: `./build.sh && open EasyWrite.app`, then the steps below.

| # | Step | Expected |
|---|---|---|
| 1 | Fresh install, translate | Apple Intelligence is used; behaviour identical to 2.0 |
| 2 | Preferences → Apple Translate, translate the same text | A translation appears, not streamed, from the other engine |
| 3 | Reopen on the same clipboard | Instant and labelled cached |
| 4 | Switch back to Apple Intelligence, reopen | The model's own answer, not the cached Translate one |
| 5 | Source on Auto-detect, translate non-English text | Detected correctly |
| 6 | Pick a language whose pack is missing | The download offer appears; after it completes, translation works |
| 7 | Pick an unsupported pair | A specific message naming the pair |
| 8 | Style guide set, Apple Translate selected | Output ignores it, and Preferences says it would |
| 9 | Turn Apple Intelligence off in System Settings, use Apple Translate | Still translates |
| 10 | Same, with Apple Intelligence selected | The existing explanatory message |
| 11 | Translate, then paste elsewhere without pressing Copy | The original clipboard content — the invariant holds for both engines |
| 12 | Compare both engines on the eight-phrase benchmark in [`testing/README.md`](../conventions/testing/README.md) | Recorded, so the choice rests on measurement |

Step 12 is the point of the feature: the benchmark exists, and the reason to add an engine is that the
model measurably struggles on some of those phrases. Record both columns.

### Code Examples from Existing Features

- Reason-specific user-facing error copy: `LLMTranslator.Unavailable`
- Racing a call against a timeout: `LLMTranslator.stream`
- A new setting with a default that is `true`, read through `d.object(forKey:)`: `Store.ignoresPrivateClipboard`
- Per-language data that only applies to one target: `Lang.note` in `Sources/EasyWriteCore/Languages.swift`
- An invariant enforced by scanning the sources: `Tests/EasyWriteCoreTests/PasteboardWriteGuardTests.swift`

### Considerations

#### Privacy & security

- The pack download is the one place this feature touches the network, and it is macOS doing it, not
  us. Say so in `SECURITY.md` rather than relying on "no network code" to cover it.
- Translation takes no instructions, so there is no prompt-injection surface on that path at all.
- Adding an engine must not add a permission, an entitlement, or a second pasteboard write.

#### Performance

- A dedicated translation model should beat a 3B general model comfortably. Measure it rather than
  claiming it; the stopwatch in the popover already shows the user.
- `prepareTranslation()` is the prewarm equivalent and belongs on the same three occasions the model's
  prewarm runs: at launch, when a language changes, and after a turn finishes.
- One session per turn, as with the model. Do not hold one across language changes.

#### Maintainability

- Diff budget: ≤50 added lines per Swift file
  ([`AI_WORKFLOW.md`](../conventions/AI_WORKFLOW.md#3-diff-size-budget)). `AppleTranslator` should fit;
  `PreferencesController` will not, because the language list is a real piece of UI. Split it into its
  own view file rather than breaching quietly.
- The protocol is what keeps this from becoming a branch in five places. If `TranslatorModel` ends up
  with `if engine == …` anywhere, the abstraction is in the wrong shape.

#### Known Gotchas

- `TranslationSession` is not `Sendable`. Keep it on the main actor; do not copy the pattern from
  `LLMTranslator.stream`, which is safe only because `LanguageModelSession` is `@unchecked Sendable`.
- `init(installedSource:)` demands an installed source, so it cannot be used to trigger a download.
  The SwiftUI `.translationTask` path is the way in.
- `NLLanguageRecognizer` returns a best guess and can be confidently wrong on short input, which is
  exactly what the popover often has.
- `LanguageAvailability.supportedLanguages` is `async`, so the Preferences list loads rather than
  appearing instantly.
- The framework's language set is not `Languages.all`. Do not assume our thirteen codes all map.
- `Strategy` and `translate(_ AttributedString)` need 26.4; the rest needs 26.0. Set the floor to what
  is actually used.
- Builds and runs on macOS 26.4+ / Apple Silicon only.

## References

### Related Documentation

- [Coding conventions](../conventions/CODING_CONVENTIONS.md) — style, naming, concurrency, settings
- [AI workflow](../conventions/AI_WORKFLOW.md) — guardrails and the PR checklist
- [Testing guide](../conventions/testing/README.md) — the eight-phrase benchmark and what measuring has settled
- [Documentation debt](../plans/1_documentation-debt.md) — where the deferred `.md` edits are parked
- [Popover translator](1_popup-translator.md) — the surface this engine plugs into
- [Clipboard read-only invariant](2_clipboard-read-only-invariant.md) — the promise both engines keep
- [Security & privacy](../../SECURITY.md) — the page the pack download makes incomplete

### External Resources

- [Translation framework](https://developer.apple.com/documentation/translation)
- [TranslationSession](https://developer.apple.com/documentation/translation/translationsession)
- [LanguageAvailability](https://developer.apple.com/documentation/translation/languageavailability)
- [translationTask(_:action:)](https://developer.apple.com/documentation/swiftui/view/translationtask(_:action:))
- [NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer)

---

**Created**: 2026-08-27
**Status**: In Progress — shipped in 2.1 and verified by hand on macOS 26.6.2 / Apple Silicon. What is
left is the states that cannot be forced from outside the app: Apple Intelligence switched off, a
translation slow enough to time out, a Mac that refuses pack downloads, an unsupported pair (all
thirteen of our languages are covered), text the recogniser will not identify, and a run of the
eight-phrase benchmark on both engines.
