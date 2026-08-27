# EasyWrite — Repository Overview

This document exists so that an AI agent can understand what this repository is, how it is
organised, and how its pieces fit together *before* reading any source code. It describes
architecture, responsibilities, and intent rather than implementation details, so it should stay
accurate as the code evolves. When you need specifics — exact key codes, timeouts, prompt wording —
go to the file named here for that concern and read it directly.

## What the product is

Easy Write is a native macOS menu-bar utility that translates whatever text is on the clipboard and
shows the result in a popover anchored to its status-bar icon. It runs as a background agent: no Dock
icon, no main window, one global keyboard shortcut.

The problem it solves is the copy-paste round trip to a web translator. Translation is performed
on-device by one of two engines the user picks between: Apple's foundation model, which is part of
Apple Intelligence and is the default, or Apple's dedicated translation framework. This is a defining
property of the project, not an implementation detail: there is no network code anywhere in the app,
no accounts, no API keys, and no server component. Contributions are expected to preserve that.

One thing does reach the network, and the distinction matters enough to state rather than gloss:
choosing a language pair the translation framework has not downloaded makes *macOS* offer to fetch a
language pack. The system asks the user, downloads it, and shares it system-wide. The app still
contains no network code, and translating with an installed pack is entirely offline.

Two invariants shape almost every design decision in the app, and both are stronger than they look:

- **The app requests no permission at all.** It reads the clipboard and registers a global hot-key,
  neither of which needs one. Anything that would need a permission — reading a selection out of
  another app, pasting into one — is out of scope by construction.
- **The clipboard is read and never written, except in the single path behind the popover's Copy
  button.** That is one function in `Clipboard.swift`, and a unit test scans `Sources/` to keep it
  that way. It is a promise verified by counting call sites rather than by reasoning about control
  flow.

## Core user-facing flows

**Translate the clipboard.** The user copies text anywhere, then presses the shortcut or clicks the
status icon. A popover opens at the menu bar, its left pane filled from the clipboard, and the
translation streams into the right pane as the model produces it. Pressing the shortcut again, or
clicking outside, closes it.

**Adjust and retranslate.** Source and target language are dropdowns, with a swap button between them
that keeps the input text. The source list includes an auto-detect sentinel and defaults to it; the
swap button is disabled while auto-detect is chosen, because there is no concrete language to move
into the target slot. Editing the left pane retranslates after a short pause. A retranslate button
forces a fresh run even when a cached answer exists.

**Copy out.** A copy button puts the translation on the clipboard. This is the only thing in the app
that writes the clipboard.

**Configuration.** A gear menu inside the popover holds the app version, Preferences, a launch-at-login
toggle and Quit. The Preferences window holds the engine choice, a free-text personal style guide, the
rebindable shortcut, and a checkbox controlling whether clipboard content that its source marked
private is read at all. With the translation framework selected it also lists every supported
language, whether its pack is installed, and a control that downloads one that is not.

**Choosing an engine.** The two are good at different things, so the choice is the user's rather than
the app's, and Preferences states the trade instead of leaving it to be discovered. The model reads
instructions, so it is the only one that can honour a style guide, and it writes its answer word by
word. The translation framework takes no instructions at all and answers in one piece, but it is
steadier on long sentences and runs on a Mac where Apple Intelligence is off. Neither is a
replacement for the other, which is why nothing falls back automatically.

**Status feedback.** Progress lives in the popover: a spinner while the model runs, and a failure
message in the right-hand pane when something goes wrong. The status icon also changes while a
translation is running. There are no beeps and no modal dialogs on the translation path.

## Repository layout

This is a Swift Package Manager package with three targets and no Xcode project: a plain library
(`EasyWriteCore`) holding the pure value logic, the executable (`EasyWrite`) holding everything that
touches AppKit or the model, and a test target covering the library. `Package.swift` declares them,
the minimum macOS platform, the Swift language mode, and the one framework that must be linked
explicitly (Carbon).

The split exists for testability: `EasyWriteCore` imports neither AppKit nor FoundationModels, so its
tests run without a running `NSApplication` and without Apple Intelligence. Put new pure logic there;
put anything with a UI or a model call in `EasyWrite`.

The application bundle is assembled by a shell script rather than by a build system: `build.sh`
compiles the executable and hand-builds the `.app` directory structure around it. `Info.plist` at
the repository root is the bundle's property list, maintained by hand and copied in by the script.
`setup-signing.sh` is a one-time developer setup step for code signing. `test.sh` runs the unit
tests, working around the fact that swift-testing is not on SwiftPM's search path when only the
Command Line Tools are installed. `make-icon.swift` is a standalone script that renders the app
artwork; the finished `AppIcon.icns` is committed, and the script is not part of the build.

The remaining top-level Markdown files are the human-facing documentation: a user-oriented README,
an architecture tour, contribution guidelines, a security and privacy statement, and a changelog.
`docs/` holds this document, the images referenced by the README, and a documentation tree of
conventions, feature specifications, and plans; `promo/` holds a marketing page, and `.github/`
holds issue templates. There is no CI workflow.

## Runtime architecture

### Startup

The entry point creates the application object, installs the app delegate, and sets the activation
policy that suppresses the Dock icon — which, together with the agent flag in `Info.plist`, is what
makes this a menu-bar-only app.

The delegate performs all wiring on launch: it subscribes to settings changes, builds the status item
and wires its button straight to the popover toggle, registers the global hot-key, registers the app
as a login item on first run only, and warms up the language model so the first translation is not
slow. It deliberately assigns no menu to the status item: a menu would swallow the click that has to
reach the button's action.

### From hot-key press to translated text

1. The hot-key fires, or the status button is clicked. Both call the same toggle.
2. If the popover is open it closes. Otherwise the popover model is asked to open, and the popover is
   shown anchored to the status button. Unlike anything else the app puts on screen, the popover
   activates the app and takes keyboard focus, because the user types in it.
3. Opening reads the clipboard — but only if the clipboard changed since the last read, so an edit the
   user made in the left pane survives closing and reopening. A read that finds nothing usable leaves
   the panes empty and calls no model.
4. The model consults its in-memory cache. A hit fills the right pane with no model call at all.
5. Otherwise it asks the translator for a stream and renders each snapshot as it arrives. Every
   snapshot is the whole translation so far, so rendering is an assignment rather than an append.
6. On completion the result is cached and a fresh session is warmed for next time.

Only one request is ever live. Each new request cancels the previous task and carries a generation
number, so a superseded run cannot write over a newer one's state when its cancellation finally
surfaces.

### Reading and writing the clipboard

`Clipboard` is the app's entire pasteboard surface: one function that reads and one that writes.
Reading is selective. Password managers mark what they copy with `org.nspasteboard.ConcealedType`,
and applications that put something on the clipboard momentarily mark it
`org.nspasteboard.TransientType`. By default either marker is treated as "nothing to translate", which
is the same state as an image on the clipboard: empty panes, no model call, nothing cached. A
Preferences checkbox turns that off. These markers are a developer convention rather than an Apple
API, so a typo in the type string would silently disable the check — there is no compiler help.

Writing happens in exactly one place, behind the copy button. The model records the change count
afterwards so its own write is not mistaken for new clipboard content on the next open.

### The translation path

A single protocol is what keeps two very different engines from becoming a branch in five places.
It declares three things — why the engine cannot run at all, a prewarm, and a translate call that
returns a stream of cumulative snapshots — and the popover model consumes only that. The setting is
resolved to an engine in exactly one place, by an exhaustive switch, so a third engine would be a
compile error there rather than a silent fallback. If a conditional on the engine name appears
anywhere else, the abstraction is in the wrong shape.

The stream shape fits both because one engine yields many snapshots and the other yields exactly one.
The engine is also part of the cache key, since the two word the same sentence differently and
switching between them must never be answered out of the other's cache.

#### The model engine

Each request builds an instruction from the source and target language, an optional per-language note
carried by the language table, and the user's optional style guide, which is appended last and told to
take precedence. The instruction also frames the user's text as content to be translated rather than
as a request to answer, which is what keeps the model from replying to a clipboard that happens to be
a question.

Two measured facts about that instruction are worth knowing before editing it. **Its last line must
name the target language.** Ending on a bare "output only the translation" makes the model echo the
source text back untranslated — four of eight benchmark phrases, against none once the language is
named again at the end. And **length costs almost nothing**: going from 36 words to 200 did not move
the time to first token, so shortening it is not a latency lever.

Two things make it fast. Streaming, so the user reads the first words instead of waiting for the whole
answer; and genuine session reuse, which matters most. A session can be warmed ahead of time, but only
for one specific instruction string, and a session is stateful — its transcript grows if it is reused
across turns. So exactly one warm session is kept, spent on the next translation, and rebuilt
afterwards. Measured on an M-series Mac that is the difference between a first token at 2.4 seconds
and at 0.25 seconds.

Decoding is greedy, and **the reason is accuracy rather than decode cost**. Measured over eight
phrases sampled three times each and scored on whether the facts that must survive a translation did,
greedy passed 18 of 24 runs while every sampled alternative landed between 8 and 14, and none of them
was faster. There is usually one right continuation in a translation, so on a model this size
sampling mostly finds worse ones. Determinism follows for free, and it is what makes the cache
trustworthy — but it also means a re-run on unchanged input is identical, so the retranslate button
cannot offer a better alternative. It is for retrying after a failure and for picking up a style guide
edited while the popover was open.

Two forms of resilience are built in. Generation races a timeout so a stalled model can never wedge
the app, and a transient failure is retried once — but only while nothing has been emitted yet, since
retrying mid-stream would duplicate words already on screen, and a timeout or cancellation is never
retried at all. A response-token cap exists purely to stop a runaway generation; it truncates hard
rather than shortening gracefully, so it is set far above what a translation needs.

The component also exposes *why* the model is unavailable, distinguishing an ineligible device,
Apple Intelligence being switched off, and the model still downloading in the background. That
distinction matters in practice: the last case is common right after a user first enables Apple
Intelligence, and a generic "turn it on" message is actively misleading there. The reason is shown in
the popover, not in a dialog.

#### The translation-framework engine

Simpler in almost every way, and awkward in four. Its session demands a concrete source language that
is already installed, so auto-detect has to be resolved before a session exists — an on-device
recogniser does that, and the engine says it could not identify the text rather than guessing. Its
session type is not sendable, so unlike the model's it stays on the main actor. It ignores the style
guide and the per-language note because there is nowhere to put them, though both stay in the cache
key. And its prewarm loads a language pair rather than warming a prompt prefix, declining to fetch a
pack that is not installed so that prewarming never downloads anything unasked.

A pack that is missing cannot be downloaded from plain code at all: the only initializer refuses a
pair that is not installed, which is precisely the case where a download is wanted. A SwiftUI overlay
is the documented way in, so the download lives in the Preferences language list rather than in the
engine, and the framework reports per session whether the system will even accept the request.

Availability here is not a property of the engine but of the pair, so it is reported per translation
instead of up front. Every framework error is mapped to its own sentence naming the pair and the next
step — download it, pick an explicit source, or switch engines — because a single "try again" line
would hide which of those the user is actually facing.

### Settings and preferences

`Store` is the single source of truth for user settings, all of which live in user defaults. It is
an observable object so the SwiftUI preferences screen can bind to it directly, and it exposes a
change callback that the app delegate uses to re-register the hot-key when its binding changes.
Settings that affect neither the hot-key nor anything cached do not trigger that callback, since they
are read fresh when they are needed. (The delegate keeps one first-run bookkeeping flag of its own
outside the store; user-visible settings should go in the store.)

The shortcut is stored as a map from action name to key combination, serialised as a blob and merged
over the built-in defaults on load, so an action added in a later version gets a default binding
rather than nothing — and entries left behind by an older version decode harmlessly and are simply
never looked up. `PreferencesController` owns the single preferences window and the shortcut recorder,
which captures the next key press while the window is focused, rejects combinations without a
modifier, and lets Escape cancel.

## Source map

| File | Responsibility |
|---|---|
| `EasyWrite/main.swift` | Process entry point; installs the delegate and configures the app as a dock-less agent |
| `EasyWrite/AppDelegate.swift` | Status item, the single hot-key, the popover toggle, the right-click settings menu, the login item |
| `EasyWrite/MainMenu.swift` | The invisible main menu, which is what makes the editing key equivalents work at all |
| `EasyWrite/TranslatorPanel.swift` | The popover itself: anchoring, focus, and transient dismissal |
| `EasyWrite/TranslatorView.swift` | The popover's SwiftUI content: language row, swap, two panes, gear menu, footer actions |
| `EasyWrite/TranslatorModel.swift` | Popover state: debounce, cancellation, cache lookup, phase, which engine runs, and what the swap button means |
| `EasyWrite/Clipboard.swift` | The whole pasteboard surface: one read, one write, and the private-content policy |
| `EasyWrite/TranslationEngine.swift` | The protocol both engines satisfy, and the two error types they have in common |
| `EasyWrite/LLMTranslator.swift` | On-device model access: availability reporting, instruction construction, streaming, prewarming, timeout and retry |
| `EasyWrite/AppleTranslator.swift` | Translation-framework access: one session per turn, prewarming a pair, timeout and explicit cancellation |
| `EasyWrite/LanguagePacks.swift` | Language detection, pair availability, and the wording of every translation-framework failure |
| `EasyWrite/LanguagePackList.swift` | The Preferences language list, its per-language status, and the one route to a pack download |
| `EasyWrite/HotKey.swift` | Global hot-key registration and dispatch, via Carbon, so the shortcut fires from any app |
| `EasyWrite/Store.swift` | Persisted user settings and change notification |
| `EasyWrite/PreferencesController.swift` | Preferences window, its SwiftUI form, and the shortcut recorder |
| `EasyWrite/KeyDisplay.swift` | Translation between key codes, modifier representations, and human-readable shortcut labels |
| `EasyWriteCore/Engine.swift` | Which engines exist, the copy that explains each in Preferences, and the fallback for an unrecognised value |
| `EasyWriteCore/Languages.swift` | The supported-language table, the auto-detect sentinel, the per-language note, and lookup |
| `EasyWriteCore/TranslationCache.swift` | In-memory, capped, least-recently-used store of finished translations |

Rules of thumb for locating a concern: anything about *what happens when* belongs to the app delegate
or the popover model; anything about *the clipboard* belongs to `Clipboard`; anything about *what the
model is told* belongs to `LLMTranslator`; anything about *whether a language pair can run* belongs to
`LanguagePacks`; anything *remembered between launches* belongs to `Store`; anything *pure* belongs in
`EasyWriteCore` where it can be tested.

## Platform requirements and dependencies

There are no third-party dependencies. The app builds against system frameworks only: AppKit and
SwiftUI for the interface, FoundationModels for the on-device model, Translation for the second
engine, NaturalLanguage for detecting the source language it needs, ServiceManagement for the login
item, and Carbon for global hot-keys. Only Carbon needs a linker entry; the rest link from `import`
alone.

The minimum macOS version is declared in two places that must agree: the platform requirement in
`Package.swift` and the minimum-system key in `Info.plist`. It is a recent major release *and* a point
release above the one FoundationModels needs, because the translation framework's higher-quality
strategy is gated later than the rest of the framework. Raising it further is a product decision, not
a technical one, and it costs every user on the versions it skips.

Beyond the OS version, running the app meaningfully requires Apple Silicon. The default engine also
needs Apple Intelligence enabled with its model finished downloading; without that the popover still
opens and explains why it will not translate, and switching engines is a working way out.

The app requires **no permission at all** and ships no entitlements. It is not sandboxed.

Note that the project can only be built and run on macOS. If you are working in a checkout on
another platform, you can read and edit the code but cannot compile or verify it.

## Building, running, and packaging

```bash
./setup-signing.sh   # optional, one time per machine
./build.sh           # compile, bundle, sign
./test.sh            # unit tests
open EasyWrite.app
```

`build.sh` performs a release build with `swift build -c release`, then constructs the application
bundle by hand: it creates the bundle directory structure, copies the compiled executable and the
property list into place, copies the icon if present, and code-signs the result. There is no
separate packaging step and no installer; installing means copying the produced bundle into
`/Applications`.

If the stable self-signed identity created by `setup-signing.sh` is present, `build.sh` signs with it;
otherwise it falls back to ad-hoc signing, whose signature changes on every build. That used to cost
the user their Accessibility grant on every rebuild; with no permission to lose the stakes are lower,
but a stable identity is still the better default.

## Vocabulary

Understanding these terms will make the code read correctly:

- **Popover** — the app's only surface, an `NSPopover` anchored to the status-bar button. It takes
  focus deliberately, and dismisses itself when the user clicks elsewhere.
- **Source and target language** — what the text is in, and what it should become. Both persist.
- **Auto-detect** — a sentinel language used only as a source, telling the model to work out the
  language itself. It never appears in the target list, and it disables the swap button.
- **Snapshot** — one element of a streamed response, carrying the whole translation produced so far
  rather than the newest fragment.
- **Phase** — whether the popover is idle, translating, or showing a failure. It drives the spinner,
  the status icon, and what the right-hand pane displays.
- **Generation** — a counter identifying the current request, so a cancelled one cannot write state
  after a newer one has started.
- **Warm session** — a model session prewarmed for one specific instruction string, spent on the next
  translation and rebuilt afterwards. The other engine's equivalent is warmed for one language pair.
- **Engine** — which translator produces the text: the Apple Intelligence model or the translation
  framework. One global setting, applied to every translation, and part of the cache key.
- **Language pack** — the data the translation framework needs for one language. Downloaded by macOS
  on request, shared with every app on the machine, and irrelevant to the model engine.
- **Style guide** — the user's free-text personal instructions, appended to every model instruction so
  the output sounds like them. It is one global string, so it can express tone and preference but not
  a per-language glossary, and the other engine ignores it entirely.
- **Language note** — optional per-language guidance stored alongside a language entry and appended
  to the model instruction only when that language is the target. This is the language-scoped lever
  the style guide is not, and it is where a standing hint such as a dialect or register convention
  belongs.
- **Private clipboard content** — text whose source marked it with the nspasteboard concealed or
  transient type. Skipped by default.
- **Availability / unavailable reason** — whether an engine can run at all and why not. The model
  reports it up front; the translation framework cannot, because what is missing is a language pack
  and that depends on the pair, so it is reported per translation instead.

## Constraints, gotchas, and design decisions

**The clipboard is the interface, and that is a deliberate trade.** The app does not read the user's
selection and cannot see what is on screen; it only knows what was copied. That is what lets it need
no permission and work identically in every application, and it is why the popover shows the result
instead of putting it back where the text came from. Do not reintroduce a synthetic keystroke to make
some later convenience work — it would bring back a permission the app no longer asks for.

**A status item with a menu cannot have a button action.** Assigning `statusItem.menu` swallows the
click, so the popover would never open from the icon. The item therefore keeps no menu; the right-click
settings menu is assigned for the length of one programmatic click and cleared again.

**A transient popover fights its own toggle.** AppKit dismisses it on the very click that then reaches
the status button, so a naive toggle closes and immediately reopens it. The panel therefore refuses an
open that arrives within a moment of a close.

**The popover has to be pushed clear of the menu bar.** A status item is inset inside the bar, so
anchoring to the button leaves the popover overlapping it and dimming the icons beside it. The panel
measures where the content landed and drops the window by the overshoot, which is exact where guessing
at the popover's chrome is not. Do not try to fix it by moving the positioning rect instead: AppKit
ignores a rect that falls entirely outside the positioning view and shows nothing at all. The popover
also does not animate, because an animation would animate to the frame AppKit chose rather than the
corrected one.

**The app is `LSUIElement`.** It has no Dock icon and is usually not frontmost, so the popover must
activate the app before it can take keyboard focus, and the text pane asks for focus on every open so
the editing shortcuts have something to act on.

**An accessory app still needs a main menu.** It shows none, but `NSApp.mainMenu` is what turns ⌘C,
⌘V, ⌘X, ⌘Z and ⌘Q into working key equivalents. ⌘A is the trap when diagnosing this: `NSTextView`
binds it natively, so Select All keeps working even when the menu is missing entirely and everything
else is dead.

**Model sessions are stateful.** Reusing one across turns grows its transcript, which slows later
requests and leaves earlier text in context. Prewarming is per-instruction, so a session warmed for
one language pair is useless for another.

**The default guardrails had to be relaxed.** The on-device model's default safety filter
false-flags ordinary text when the task is translation, so the app opts into the permissive
content-transformation mode Apple provides for exactly this class of task. Reverting that will make
routine, harmless translations start failing.

**Prompt injection is anticipated.** The text being translated is untrusted input that is fed to a
language model, so the instruction explicitly frames it as content, not as a request. Changes to
the instruction text should preserve that framing, however much they shorten it.

**Greedy decoding can loop on nonsense.** On input the model cannot make sense of, greedy decoding
will repeat a phrase until the response-token cap stops it. That cap is the guard; do not remove it,
and do not reach for sampling to fix the looping — sampling was measured and is worse on every phrase
that matters.

**The model's word choice is not a prompt problem.** On longer sentences it sometimes picks an odd
term or invents one, and register drift and gender agreement go wrong the same way. Measured on a
supported Mac, the same sentence fails the same way under a 110-word instruction and a 36-word one,
under greedy and low-temperature sampling alike, and whether or not the source language is named — so
reaching for the instruction text is wasted effort, and lengthening it without measuring first is
worse than wasted. Three levers do exist, and they are not interchangeable:

- **The style guide** pins a term for this user, and that does work. But it is a single global string
  appended to every instruction, while the target language is chosen per translation out of thirteen,
  so a term mapping written into it is wrong for the other twelve. It cannot carry a glossary.
- **The language note** is the language-scoped mechanism, applied only when its language is the
  target — as Arabic's dialect note already is. Standing per-language guidance belongs there.
- **The other engine** does not invent terms at all, at the price of never using the user's.

Both the note and the style guide are appended *after* the instruction's closing line, which is the
one position measurement says must keep naming the target language. Arabic's instruction therefore
ends with its dialect note rather than with "Output only the Arabic translation" — a known wrinkle
rather than an oversight.

**Two engines, one protocol, and no automatic fallback.** A failure reports its reason and stops,
because the user chose the engine and silently answering with the other one would make the setting a
lie. The protocol is what keeps the choice from becoming a conditional in five places: it is resolved
once per run, by an exhaustive switch. A conditional on the engine anywhere else means the
abstraction is in the wrong shape.

**Hot-key registration failures are silent.** If the combination is already claimed by another
application, registration fails and the shortcut simply does nothing; nothing warns the user. When the
binding changes, all registrations are torn down and rebuilt from stored settings.

**Adding a language is intentionally cheap, but only for one engine.** Languages live in a single
static table where each entry carries its code, display name, and an optional instruction note.
Adding a row is the whole change for the model, and an unrecognised stored target code falls back to
the first entry. The translation framework covers its own set of languages, which is not this table,
so a new row may be listed as unsupported there — that is reported, not hidden.

**Almost everything is main-actor isolated.** The UI, the settings store, both engines, the popover
model, and the clipboard namespace all run on the main actor. The exceptions are deliberate: the
low-level hot-key callback, which hops to the main queue before invoking anything, and the streaming
helper inside the model translator, which is `nonisolated static` so it can consume the response
stream off the main actor. That helper is safe only because the model's session type is
`@unchecked Sendable`; the translation framework's session is not sendable at all, so the same pattern
would be wrong there. Keep new code on the main actor unless there is a reason not to.

**Automated coverage is narrow on purpose.** `EasyWriteCore` is unit tested, and one test enforces the
single-pasteboard-write invariant by scanning the sources. Everything else — the popover, the hot-key,
both engines — is verified by hand on a supported Mac. Neither engine is unit-testable: one needs
Apple Intelligence, the other needs installed language packs. See
[`conventions/testing/README.md`](conventions/testing/README.md).
