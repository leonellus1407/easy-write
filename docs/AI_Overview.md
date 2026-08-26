# EasyWrite — Repository Overview

This document exists so that an AI agent can understand what this repository is, how it is
organised, and how its pieces fit together *before* reading any source code. It describes
architecture, responsibilities, and intent rather than implementation details, so it should stay
accurate as the code evolves. When you need specifics — exact key codes, timeouts, prompt wording —
go to the file named here for that concern and read it directly.

## What the product is

Easy Write is a native macOS menu-bar utility that translates or rewrites the text you currently
have selected, in whatever application you are using, and puts the result straight back in place.
It runs as a background agent: no Dock icon, no main window, just a status-bar icon and a set of
global keyboard shortcuts.

The problem it solves is the copy-paste round trip to a web translator, plus the thing web
translators are bad at: **register**. Many languages distinguish formal and informal address
(German *Sie* / *du*, French *vous* / *tu*, and so on), and choosing wrong is socially costly. Easy
Write makes register a first-class choice — a different shortcut for formal, informal, or
tone-preserving translation.

Translation is performed by Apple's on-device foundation model, which is part of Apple
Intelligence. This is a defining property of the project, not an implementation detail: there is no
network code anywhere in the app, no accounts, no API keys, and no server component. Contributions
are expected to preserve that.

## Core user-facing flows

**Translate in place (write modes).** The user selects text in any app and presses one of three
shortcuts: formal, informal, or plain. The selection is replaced by the translation into the
currently chosen target language. The target language is picked once from the menu bar or
Preferences and applies to all three write modes.

**Read to English (read mode).** A fourth shortcut translates the selection *into English* and
shows it in a small floating popup near the pointer instead of replacing anything. This mode exists
because incoming foreign text — web pages, received mail, PDFs — is usually not editable, so
pasting back is impossible.

**Preview before replacing.** An optional setting makes the write modes show the translation in a
confirmation dialog first, from which the user can replace, copy, or cancel. Read mode always uses
its popup regardless of this setting.

**Configuration.** The menu-bar menu offers the four actions with their current shortcuts, a target
language submenu, the preview toggle, a launch-at-login toggle, a shortcut to the system
Accessibility settings pane, and Preferences. The Preferences window adds a free-text personal
style guide and lets the user rebind each shortcut by recording a key combination.

**Status feedback.** The menu-bar icon is the app's only progress indicator: it changes while a
translation is running and flashes briefly on success or failure. Failures along the translation
path are otherwise communicated with a system beep; the exception is an unavailable on-device
model, which gets an explanatory dialog.

## Repository layout

This is a Swift Package Manager package with a single executable target; there is no Xcode
project. `Package.swift` declares the target, the minimum macOS platform, the Swift language mode,
and the one framework that must be linked explicitly (Carbon). All application code lives in
`Sources/EasyWrite`.

The application bundle is assembled by a shell script rather than by a build system: `build.sh`
compiles the executable and hand-builds the `.app` directory structure around it. `Info.plist` at
the repository root is the bundle's property list, maintained by hand and copied in by the script.
`setup-signing.sh` is a one-time developer setup step for code signing. `make-icon.swift` is a
standalone script that renders the app artwork; the finished `AppIcon.icns` is committed, and the
script is not part of the build.

The remaining top-level Markdown files are the human-facing documentation: a user-oriented README,
an architecture tour, contribution guidelines, a security and privacy statement, and a changelog.
`docs/` holds this document, the images referenced by the README, and a documentation tree of
conventions, feature specifications, and plans; `promo/` holds a marketing page, and `.github/`
holds issue templates. There is no test target and no CI workflow.

## Runtime architecture

### Startup

The entry point creates the application object, installs the app delegate, and sets the activation
policy that suppresses the Dock icon — which, together with the agent flag in `Info.plist`, is what
makes this a menu-bar-only app.

The delegate performs all wiring on launch: it subscribes to settings changes, builds the status
item and its menu, registers the global hot-keys, starts observing which application is frontmost,
registers the app as a login item on first run only, requests Accessibility permission if it has
not been granted, and warms up the language model so the first translation is not slow.

### From hot-key press to replaced text

This is the central path and it lives almost entirely in the app delegate, which coordinates the
other components:

1. A global hot-key fires and is dispatched to the delegate's translate routine with the requested
   register (or the read-to-English flag).
2. The delegate refuses to start if a translation is already running, if Accessibility permission
   is missing, or if the on-device model reports itself unavailable — in the last case it shows a
   message explaining which of the possible reasons applies.
3. If Easy Write itself is frontmost (the action came from the menu), it re-activates the
   previously frontmost application first, because the next step drives the keyboard and needs the
   user's real target app to have focus.
4. `Replacer` obtains the current selection.
5. If nothing usable was captured, the flow aborts with a beep.
6. The delegate assembles the request — target language, register, any per-language note, the
   user's style guide — hands it to `LLMTranslator`, and awaits the result asynchronously while
   showing the busy icon.
7. On success, the result is either replaced in place via `Replacer`, shown in the preview dialog,
   or shown in the reader popup, depending on the mode and the preview setting.

Only one translation may be in flight at a time; the delegate guards the whole path with a busy
flag.

### Reading from and writing to other applications

Easy Write does not integrate with individual applications and does not read text through the
Accessibility object model. `Replacer` drives the keyboard instead: it snapshots the pasteboard,
synthesises a copy keystroke, waits for the pasteboard to change and reads the text out of it,
and later writes the translation to the pasteboard, synthesises a paste keystroke, and restores
the original pasteboard contents shortly afterwards. Posting synthetic keyboard events to other
processes is what requires the Accessibility permission.

Two subtleties in this component are deliberate and easy to break. The synthetic events are created
from a private event source so that modifier keys the user is still physically holding — from the
hot-key they just pressed — do not contaminate the synthesised keystroke. And the copy step waits
briefly before firing, for the same reason. The pasteboard snapshot preserves all representations
of each item, not just plain text, so restoring does not degrade what the user had copied.

### The translation path

`LLMTranslator` is the only component that talks to the model. It uses Apple's FoundationModels
framework — the on-device large language model — rather than a dedicated translation API,
precisely because register and a user-supplied style guide can be expressed as instructions to a
language model but not to a dictionary-style translator.

Each request builds an instruction string from four inputs: the target language, the requested
register (formal, informal, or "match the source"), an optional per-language note carried by the
language table, and the user's optional personal style guide, which is appended last and told to
take precedence. The instruction also frames the user's text as content to be translated rather
than as a request to answer, which is what keeps the model from replying to a selection that
happens to be a question or an instruction. Generation runs at low temperature, and the raw output
is cleaned up before use — chiefly by stripping surrounding quotes the model sometimes adds.

Two forms of resilience are built in. Each attempt races generation against a timeout so a stalled
model can never wedge the app, and a transient failure is retried once — but a timeout or a
cancellation is never retried. A session is prewarmed at launch to reduce first-use latency; each
translation still creates its own session, because the instruction text differs per request.

The component also exposes *why* the model is unavailable, distinguishing an ineligible device,
Apple Intelligence being switched off, and the model still downloading in the background. That
distinction matters in practice: the last case is common right after a user first enables Apple
Intelligence, and a generic "turn it on" message is actively misleading there.

### Settings and preferences

`Store` is the single source of truth for user settings, all of which live in user defaults. It is
an observable object so the SwiftUI preferences screen can bind to it directly, and it exposes a
change callback that the app delegate uses to re-register hot-keys and rebuild the menu when
something relevant changes. Settings that affect neither the menu nor the shortcuts do not trigger
that callback, since they are read fresh at translation time. (The delegate keeps one first-run
bookkeeping flag of its own outside the store; user-visible settings should go in the store.)

Shortcuts are stored as a map from action name to key combination, serialised as a blob and merged
over the built-in defaults on load, so an action added in a later version gets a default binding
rather than nothing. `PreferencesController` owns the single preferences window and the shortcut
recorder, which captures the next key press while the window is focused, rejects combinations
without a modifier, and lets Escape cancel.

## Source map

All files are in `Sources/EasyWrite`.

| File | Responsibility |
|---|---|
| `main.swift` | Process entry point; installs the delegate and configures the app as a dock-less agent |
| `AppDelegate.swift` | Central coordinator: status item and menu, hot-key wiring, the translate-to-replace/preview/popup flow, login item, Accessibility prompting, frontmost-app tracking |
| `HotKey.swift` | Global hot-key registration and dispatch, via Carbon, so shortcuts fire from any app |
| `Replacer.swift` | Reading the selection out of, and writing the result back into, the focused application, plus pasteboard save and restore |
| `LLMTranslator.swift` | On-device model access: availability reporting, instruction construction, timeout and retry, output cleanup |
| `Languages.swift` | The supported-language table and lookup |
| `Store.swift` | Persisted user settings and change notification |
| `PreferencesController.swift` | Preferences window, its SwiftUI form, and the shortcut recorder |
| `ReaderPanel.swift` | The non-activating floating popup used by read mode |
| `KeyDisplay.swift` | Translation between key codes, modifier representations, and human-readable shortcut labels |

Rules of thumb for locating a concern: anything about *what happens when* belongs to the app
delegate; anything about *how text moves between apps* belongs to `Replacer`; anything about *what
the model is told* belongs to `LLMTranslator`; anything *remembered between launches* belongs to
`Store`.

## Platform requirements and dependencies

There are no third-party dependencies. The app builds against system frameworks only: AppKit and
SwiftUI for the interface, FoundationModels for the on-device model, Core Graphics for synthesising
keyboard events, ApplicationServices for the Accessibility trust check, ServiceManagement for the
login item, and Carbon for global hot-keys.

The minimum macOS version is declared in two places that must agree: the platform requirement in
`Package.swift` and the minimum-system key in `Info.plist`. It is a recent major release, because
FoundationModels requires it. Beyond the OS version, running the app meaningfully requires Apple
Silicon with Apple Intelligence enabled and its model finished downloading; without that the app
launches and its menu works, but every translation is refused with an explanatory dialog.

The app requires exactly one permission: **Accessibility**, needed to post synthetic keystrokes
into other applications. It requests this at launch and re-checks before every translation. It is
not sandboxed and ships no entitlements, which is also why it cannot be distributed through the Mac
App Store.

Note that the project can only be built and run on macOS. If you are working in a checkout on
another platform, you can read and edit the code but cannot compile or verify it.

## Building, running, and packaging

Two scripts at the repository root cover the whole lifecycle:

```bash
./setup-signing.sh   # one time per machine
./build.sh           # compile, bundle, sign
open EasyWrite.app
```

`build.sh` performs a release build with `swift build -c release`, then constructs the application
bundle by hand: it creates the bundle directory structure, copies the compiled executable and the
property list into place, copies the icon if present, and code-signs the result. There is no
separate packaging step and no installer; installing means copying the produced bundle into
`/Applications`.

Signing has a real functional consequence. If the stable self-signed identity created by
`setup-signing.sh` is present, `build.sh` signs with it; otherwise it falls back to ad-hoc signing.
Ad-hoc signatures change on every build, and macOS ties the Accessibility grant to the signature,
so an ad-hoc build loses its permission on every rebuild — the permission toggle may still appear
enabled while the app is in fact untrusted. `setup-signing.sh` avoids this by generating a
self-signed code-signing certificate into a dedicated keychain with a known password, so signing
stays non-interactive and the identity is stable across rebuilds.

## Vocabulary

Understanding these terms will make the code read correctly:

- **Register** — the formality level of address (formal / informal / preserve the source's tone).
  It is the app's central concept and the reason for having three write shortcuts instead of one.
- **Write mode vs read mode** — write modes translate into the chosen target language and replace
  the selection; read mode translates into English and only displays the result.
- **Action** — a named, bindable command (the three write modes plus read mode). Actions are
  identified by short string keys, which are the keys used for stored shortcuts and for looking up
  shortcut labels in the menu.
- **Target language** — the single language write modes translate into, chosen by the user. Read
  mode ignores it.
- **Style guide** — the user's free-text personal instructions and glossary, injected into every
  translation so the output sounds like them.
- **Language note** — optional per-language guidance stored alongside a language entry and appended
  to the model instruction, used where a language needs a standing hint such as a dialect choice.
- **Preview** — showing the translation in a dialog before replacing, as opposed to replacing
  immediately.
- **Reader panel / HUD** — the floating, non-activating popup used by read mode.
- **Availability / unavailable reason** — the model's readiness state and the specific reason it is
  not usable, surfaced to the user as distinct messages.

## Constraints, gotchas, and design decisions

**Text transfer is pasteboard-mediated and therefore heuristic.** Because the selection is captured
by synthesising a copy keystroke and watching the pasteboard, the app cannot distinguish "the app
did not respond" from "the selection was empty", and it gives up after a short wait. Applications
that handle copy unusually, or are slow to respond, will fail this step. Replacement has the same
character: the app pastes and assumes the paste landed. This is a deliberate trade for working in
*every* app without per-app integration.

**Timing is load-bearing.** Several short waits exist for real reasons — letting physically held
modifiers release before synthesising a keystroke, letting a re-activated application take focus,
and delaying pasteboard restoration until the paste has been consumed. Removing or shortening them
tends to produce intermittent failures that are hard to reproduce. Some of these waits block the
main thread; that is a known simplicity trade-off, accepted because the durations are short.

**The default guardrails had to be relaxed.** The on-device model's default safety filter
false-flags ordinary text when the task is translation, so the app opts into the permissive
content-transformation mode Apple provides for exactly this class of task. Reverting that will make
routine, harmless translations start failing.

**Prompt injection is anticipated.** The text being translated is untrusted input that is fed to a
language model, so the instruction explicitly frames it as content, not as a request. Changes to
the instruction text should preserve that framing.

**Read mode is a separate presentation, not a separate engine.** It always shows the popup, because
the text it is used on is typically not editable. The popup is intentionally non-activating so it
does not steal focus from what the user is reading, and it dismisses itself after a while.

**The preview dialog activates the app.** Because a modal dialog brings Easy Write to the front, the
delegate must re-activate the user's previous application before pasting from the dialog. This is
why the app tracks the last frontmost application at all.

**Hot-key registration failures are silent.** If a combination is already claimed by another
application, registration fails and the shortcut simply does nothing; nothing warns the user. There
is likewise no validation preventing two actions from being bound to the same combination. When
shortcuts change, all registrations are torn down and rebuilt from stored settings rather than
patched individually.

**Adding a language is intentionally cheap.** Languages live in a single static table where each
entry carries its code, display name, optional formal and informal pronoun labels used for menu
labels, and an optional instruction note. Adding a row is the whole change; an unrecognised stored
language code falls back to the first entry.

**Almost everything is main-actor isolated.** The UI, the settings store, the translator, and the
text replacer all run on the main actor; the one exception is the low-level hot-key callback, which
hops to the main queue before invoking anything. Keep new code on the main actor unless there is a
reason not to.

**Privacy is a hard constraint, not a feature.** No network calls, no telemetry, no analytics, no
logging of user text. The absence of network code is a claim the project makes publicly and is
independently auditable because the codebase is small; adding a dependency or a network call would
break that promise.

**There are no automated tests.** Verification is manual, on a Mac meeting the requirements, and
the interesting failure modes — permission handling, cross-application text transfer, model
availability — are precisely the ones that cannot be tested in isolation. Treat changes to the
replacement and hot-key paths as needing hands-on checking.
