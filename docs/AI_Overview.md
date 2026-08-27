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

The problem it solves is the copy-paste round trip to a web translator. Translation is performed by
Apple's on-device foundation model, which is part of Apple Intelligence. This is a defining property
of the project, not an implementation detail: there is no network code anywhere in the app, no
accounts, no API keys, and no server component. Contributions are expected to preserve that.

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
toggle and Quit. The Preferences window holds a free-text personal style guide, the rebindable
shortcut, and a checkbox controlling whether clipboard content that its source marked private is read
at all.

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

`LLMTranslator` is the only component that talks to the model. It uses Apple's FoundationModels
framework — the on-device large language model — rather than a dedicated translation API, because a
user-supplied style guide can be expressed as an instruction to a language model but not to a
dictionary-style translator.

Each request builds an instruction from the source and target language, an optional per-language note
carried by the language table, and the user's optional style guide, which is appended last and told to
take precedence. The instruction also frames the user's text as content to be translated rather than
as a request to answer, which is what keeps the model from replying to a clipboard that happens to be
a question. It is deliberately short — a long instruction is tokens the model has to read before it
can start.

The public call returns a stream of cumulative snapshots. Three things make it fast: streaming, so the
user reads the first words instead of waiting for the whole answer; greedy sampling, which is the
cheapest decode path and makes the same input produce the same output, which is what makes the cache
trustworthy; and genuine session reuse. That last one matters most. A session can be warmed ahead of
time, but only for one specific instruction string, and a session is stateful — its transcript grows
if it is reused across turns. So exactly one warm session is kept, spent on the next translation, and
rebuilt afterwards. Measured on an M-series Mac that is the difference between a first token at 2.4
seconds and at 0.25 seconds.

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
| `EasyWrite/AppDelegate.swift` | Status item, the single hot-key, the popover toggle, the login item |
| `EasyWrite/TranslatorPanel.swift` | The popover itself: anchoring, focus, and transient dismissal |
| `EasyWrite/TranslatorView.swift` | The popover's SwiftUI content: language row, swap, two panes, gear menu, footer actions |
| `EasyWrite/TranslatorModel.swift` | Popover state: debounce, cancellation, cache lookup, phase, and what the swap button means |
| `EasyWrite/Clipboard.swift` | The whole pasteboard surface: one read, one write, and the private-content policy |
| `EasyWrite/LLMTranslator.swift` | On-device model access: availability reporting, instruction construction, streaming, prewarming, timeout and retry |
| `EasyWrite/HotKey.swift` | Global hot-key registration and dispatch, via Carbon, so the shortcut fires from any app |
| `EasyWrite/Store.swift` | Persisted user settings and change notification |
| `EasyWrite/PreferencesController.swift` | Preferences window, its SwiftUI form, and the shortcut recorder |
| `EasyWrite/KeyDisplay.swift` | Translation between key codes, modifier representations, and human-readable shortcut labels |
| `EasyWriteCore/Languages.swift` | The supported-language table, the auto-detect sentinel, and lookup |
| `EasyWriteCore/TranslationCache.swift` | In-memory, capped, least-recently-used store of finished translations |

Rules of thumb for locating a concern: anything about *what happens when* belongs to the app delegate
or the popover model; anything about *the clipboard* belongs to `Clipboard`; anything about *what the
model is told* belongs to `LLMTranslator`; anything *remembered between launches* belongs to `Store`;
anything *pure* belongs in `EasyWriteCore` where it can be tested.

## Platform requirements and dependencies

There are no third-party dependencies. The app builds against system frameworks only: AppKit and
SwiftUI for the interface, FoundationModels for the on-device model, ServiceManagement for the login
item, and Carbon for global hot-keys.

The minimum macOS version is declared in two places that must agree: the platform requirement in
`Package.swift` and the minimum-system key in `Info.plist`. It is a recent major release, because
FoundationModels requires it. Beyond the OS version, running the app meaningfully requires Apple
Silicon with Apple Intelligence enabled and its model finished downloading; without that the app
launches and the popover opens, but every translation is refused with an explanatory message.

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
  translation and rebuilt afterwards.
- **Style guide** — the user's free-text personal instructions and glossary, injected into every
  translation so the output sounds like them.
- **Language note** — optional per-language guidance stored alongside a language entry and appended
  to the model instruction, used where a language needs a standing hint such as a dialect choice.
- **Private clipboard content** — text whose source marked it with the nspasteboard concealed or
  transient type. Skipped by default.
- **Availability / unavailable reason** — the model's readiness state and the specific reason it is
  not usable, surfaced to the user as distinct messages.

## Constraints, gotchas, and design decisions

**The clipboard is the interface, and that is a deliberate trade.** The app does not read the user's
selection and cannot see what is on screen; it only knows what was copied. That is what lets it need
no permission and work identically in every application, and it is why the popover shows the result
instead of putting it back where the text came from. Do not reintroduce a synthetic keystroke to make
some later convenience work — it would bring back a permission the app no longer asks for.

**A status item with a menu cannot have a button action.** Assigning `statusItem.menu` swallows the
click, so the popover would never open from the icon. The gear menu inside the popover exists because
of this.

**A transient popover fights its own toggle.** AppKit dismisses it on the very click that then reaches
the status button, so a naive toggle closes and immediately reopens it. The panel therefore refuses an
open that arrives within a moment of a close.

**The app is `LSUIElement`.** It has no Dock icon and is usually not frontmost, so the popover must
activate the app before it can take keyboard focus.

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

**Greedy decoding can loop on nonsense.** Deterministic sampling is what makes the cache trustworthy,
but on input the model cannot make sense of, greedy decoding will repeat a phrase until the
response-token cap stops it. That cap is the guard; do not remove it.

**Hot-key registration failures are silent.** If the combination is already claimed by another
application, registration fails and the shortcut simply does nothing; nothing warns the user. When the
binding changes, all registrations are torn down and rebuilt from stored settings.

**Adding a language is intentionally cheap.** Languages live in a single static table where each
entry carries its code, display name, and an optional instruction note. Adding a row is the whole
change; an unrecognised stored target code falls back to the first entry.

**Almost everything is main-actor isolated.** The UI, the settings store, the translator, the popover
model, and the clipboard namespace all run on the main actor. The exceptions are deliberate: the
low-level hot-key callback, which hops to the main queue before invoking anything, and the streaming
helper inside the translator, which is `nonisolated static` so it can consume the response stream off
the main actor. Keep new code on the main actor unless there is a reason not to.

**Automated coverage is narrow on purpose.** `EasyWriteCore` is unit tested, and one test enforces the
single-pasteboard-write invariant by scanning the sources. Everything else — the popover, the hot-key,
the model — is verified by hand on a supported Mac. See
[`conventions/testing/README.md`](conventions/testing/README.md).
