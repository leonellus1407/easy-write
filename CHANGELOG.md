# Changelog

All notable changes to Easy Write are documented here.

## [2.1] — 2026-08-27

### Added
- **A second translator to choose from.** Preferences now offers Apple Translate — the engine behind
  the system Translate app — beside the Apple Intelligence model that Easy Write has always used. The
  model still wins when you want your own wording, because it is the only one that can read your
  style guide. Apple Translate is steadier on longer sentences, usually faster, and works on a Mac
  where Apple Intelligence is switched off or unavailable. Apple Intelligence stays selected unless
  you change it, so nothing moves under you.
- **A language list that says what is ready.** With Apple Translate selected, Preferences lists every
  language Easy Write offers, whether its pack is already on your Mac, and a Download button when it
  is not. Languages the engine does not cover are listed as unsupported rather than quietly left out.
- **Failures that name the problem.** A pair that has not been downloaded, a pair the engine cannot
  do at all, and text it could not identify each get their own explanation in the popover, with what
  to do about it — instead of one "try again" line covering everything.

### Changed
- **The style guide applies to Apple Intelligence only,** and Preferences now says so where you type
  it. Apple Translate takes no instructions of any kind. Your text is kept either way, so switching
  back costs you nothing.
- **Switching engines re-translates rather than repeating the other one's answer.** The two word the
  same sentence differently, and reopening on text you already translated shows the engine you are
  actually using.
- **With Apple Translate the translation appears in one piece** instead of arriving word by word. The
  spinner and the stopwatch cover the wait, and nothing else about the popover changes.
- **Easy Write now needs macOS 26.4,** up from 26.0. That is the version Apple Translate's
  higher-quality mode arrives in, and it is the mode worth having for text a person reads.

### Fixed
- **Opening Preferences now closes the translator popover.** It used to stay on screen, floating over
  the Preferences window. Clicking away from the popover, in any application, hides it too.

### Notes
- Choosing Apple Translate can make macOS download a language pack, which is the one moment anything
  in this workflow touches the network — and it is the system fetching it after asking you, not the
  app. Easy Write still contains no network code. Once a pack is on your Mac, translating with it is
  entirely offline. See [SECURITY.md](SECURITY.md).
- Neither engine is better at everything. On "Can you send me the report tomorrow?" into Russian, the
  model produced a broken sentence while Apple Translate got it right; on text where you have pinned
  your own terms, only the model can use them. That is why this is a setting and not a replacement.

## [2.0] — 2026-08-27

Easy Write is a translator now, not a rewriter. It reads what you copied and shows the translation in
its own popover, which means it no longer needs any permission at all.

### Added
- **A translator popover at the menu bar.** Copy text anywhere, press `⇧⌃Z` or click the menu-bar
  icon, and a popover opens with what you copied on the left and the translation on the right. Press
  the shortcut again, or click outside, to close it.
- **The translation appears as it is written.** The first words show up in about a quarter of a second
  instead of after the whole answer, so long text no longer feels like a wait.
- **Both directions, with a swap button.** Source and target are now separate dropdowns. The source
  defaults to auto-detect; choose a real language and the swap button reverses the pair, keeping your
  text and retranslating.
- **The text is editable.** Fix a typo or trim a sentence in the left pane and the translation updates
  on its own after a short pause — once, not once per keystroke.
- **Repeats are instant.** The last twenty translations are remembered while the app is running, so
  reopening the popover on text you already translated shows the result immediately. A retranslate
  button forces a fresh run whenever you want one. Nothing is written to disk, and the list is gone
  when you quit.
- **Copied passwords are skipped.** Password managers mark what they copy as private, and so do apps
  that put something on your clipboard for a moment. Easy Write now leaves the panes empty rather than
  translating it, and never remembers it. There is a checkbox in Preferences if you would rather it
  always read.
- **A stopwatch for each translation.** The footer counts up in hundredths of a second while the model
  works and then holds the time it took, so you can see what a translation actually costs. A result
  that came from memory says so instead.
- **The text pane is ready to type in.** It takes the keyboard as soon as the popover opens, and the
  standard editing shortcuts — ⌘A, ⌘C, ⌘X, ⌘V, ⌘Z — now work in it. ⌘Q quits.
- **Right-click the menu-bar icon** for the settings menu, the same one the gear button opens. Left-click
  still opens the translator.

### Changed
- **No permission is required any more, and none is requested.** Version 1 needed Accessibility so it
  could press ⌘C and ⌘V for you. Nothing is pasted back now, so that permission, its prompt, and the
  menu item pointing at System Settings are all gone. There is nothing left to grant.
- **Your clipboard is never touched unless you ask.** Easy Write reads it and writes to it only when
  you press Copy. Version 1 borrowed the clipboard for every translation and handed it back from only
  some of the paths out, which meant a translation that failed, timed out, or was cancelled could
  leave your copied text replaced. That cannot happen now, because nothing borrows it.
- **In-place replacement is gone.** The selection in the app you were using is no longer overwritten;
  press Copy in the popover and paste it yourself. This is what buys the permission-free install, and
  it is the trade to be aware of if version 1's replace-in-place was why you used it.
- **One shortcut instead of four.** `⇧⌃Z` opens the translator. The separate formal, informal, plain
  and read-to-English shortcuts are gone, along with the preview dialog and the reading popup. Pick
  your formality with a line in the style guide ("address me formally, use *Sie*") — it applies to
  every translation.
- **Preferences is smaller.** It now holds the style guide, the one shortcut, and the private-clipboard
  checkbox. The target language moved into the popover, where you change it more often.

### Notes
- Translation is deterministic: the same text and settings produce the same wording every time, which
  is what makes the instant repeats trustworthy. On input the model cannot make sense of — a random
  string rather than a sentence — that determinism shows up as a repeated phrase, cut off after a
  sensible length rather than running away.
- The on-device model is small, and on longer sentences it sometimes picks an odd word for a term or
  even invents one. This has not changed in this release — the same sentences went wrong the same way
  in 1.1.1. The **style guide** in Preferences is the fix: pin the term (`appendix = …`) and it is
  used from then on. Anything important is still worth reading before you send it.
- Your existing target language, style guide and login-item setting carry over. A shortcut you rebound
  in version 1 does not, since the actions it was bound to no longer exist; the new one starts at
  `⇧⌃Z` and is rebindable as before.

## [1.1.1] — 2026-07-14

### Fixed
- **Clearer "Apple Intelligence unavailable" message.** The app used to show a single generic
  "enable it in Settings" line for every reason the on-device model wasn't ready — even for users
  who *had* already enabled Apple Intelligence but whose model was still downloading. It now reads
  the actual reason and tells you which one it is: device not supported, Apple Intelligence turned
  off, or **model still downloading in the background** (the most common case right after enabling).

## [1.1] — 2026-07-13

### Added
- **Arabic** — added to the language list by user request. It's one of Apple's supported
  Foundation Models languages, tuned here to produce **Modern Standard Arabic (الفصحى)** rather than
  mixed dialect. Uses natural-register translation (no forced formal/informal split, since Arabic
  formality doesn't reduce to a single pronoun pair the way German *Sie/du* does — same treatment as
  English, Japanese, and Chinese). Strong on everyday messages; like any on-device translation it can
  occasionally slip on more complex sentences, so double-check anything important.

### Changed
- The translation prompt now explicitly emphasises subject/object direction (who does what to whom),
  improving accuracy across all languages.

## [1.0] — 2026-06-25

First public release. 🎉

### Added
- **In-place translation** — select text in any app, press a shortcut, and the selection is replaced
  with the translation.
- **Formal / informal register** — `⌥⌘T` formal (Sie/vous/usted…), `⌥⌘I` informal (du/tu/tú…),
  powered by Apple's on-device model.
- **Plain mode** (`⌥⌘P`) — translation that preserves the source's natural tone.
- **Read mode** (`⌥⌘E`) — translate incoming foreign text to English in a popup, for non-editable
  text like web pages, emails, and chats.
- **12 target languages**, switchable from the menu.
- **Personal style & glossary** — injected into every translation.
- **Custom shortcuts** with a built-in recorder.
- **Launch at login**, menu-bar-only (no Dock icon).
- **100% on-device** via Apple Foundation Models — no accounts, no API keys, no network.

### Notes
- Uses `permissiveContentTransformations` guardrails so ordinary text isn't false-flagged by the
  on-device model's default safety filter.
- Ships with a stable self-signed identity setup so the Accessibility grant persists across rebuilds.

Requires macOS 26+ on Apple Silicon with Apple Intelligence enabled.
