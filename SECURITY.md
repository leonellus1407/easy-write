# Security & Privacy

Easy Write is designed to be private by default. This document explains exactly what it does, what
permissions it needs and why, and how to report a security issue.

## Data flow (there isn't much)

- **Translation runs entirely on-device** using Apple's Foundation Models framework. There is **no
  network code** in this app — nothing is uploaded, logged, or sent to any server.
- **No accounts, no API keys, no telemetry, no analytics.**
- When you open the translator, Easy Write reads the text on your clipboard, shows it in the left
  pane, and sends it to the on-device model. Nothing is written back to your clipboard unless you
  press **Copy**.
- **Easy Write reads the pasteboard and never writes it, except in the single code path behind the
  popover's Copy button.** That is one call site in the source, so you can check it by reading rather
  than by taking our word for it.
- If the app that put something on your clipboard marked it as private or temporary — password
  managers do this — Easy Write leaves the panes empty and calls no model at all. You can turn that
  off in Preferences; it is on by default.
- The last twenty translations are kept **in memory** so reopening the popover on unchanged text is
  instant. They are never written to disk, and they are gone when you quit.

## Permissions

**None.** Easy Write asks for nothing: no Accessibility, no network, no full-disk access, no
microphone or camera, no contacts. It reads the clipboard, which needs no permission on macOS, and it
registers a global hot-key, which also needs none.

Earlier versions replaced your selected text in place, which required Accessibility so the app could
post synthetic ⌘C and ⌘V keystrokes into other applications. Version 2.0 shows the translation in its
own popover instead, so that permission — and the code behind it — is gone.

## Why it's not on the Mac App Store

Easy Write is distributed as build-from-source (and possibly a notarized download later). Because you
build it yourself, you can audit every line first — it's a few hundred lines of Swift.

## Reporting a vulnerability

If you find a security issue, please **do not open a public issue**. Instead, open a
[GitHub security advisory](../../security/advisories/new) or email the maintainer. You'll get a
response as quickly as possible, and credit if you'd like it.
