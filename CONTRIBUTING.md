# Contributing to Easy Write

Thanks for your interest! Easy Write is a small, focused native macOS app — contributions that keep it
that way are very welcome.

## Getting set up

```bash
./setup-signing.sh   # optional, once — a stable self-signed identity instead of an ad-hoc signature
./build.sh           # compile + bundle + sign
./test.sh            # unit tests
open EasyWrite.app
```

Requires macOS 26+ on Apple Silicon with Apple Intelligence enabled. See
[HOW_IT_WORKS.md](HOW_IT_WORKS.md) for an architecture tour before diving in.

## Good first contributions

- More target languages (add to `Languages.swift`)
- Better long-text handling
- More tests for the pure logic in `EasyWriteCore`
- VoiceOver and keyboard-navigation improvements in the popover

## Guidelines

- **Keep it private by default.** No network calls, analytics, or telemetry. On-device only.
- **Keep it small.** Prefer the standard library and system frameworks over dependencies.
- Match the existing style; run a release build (`swift build -c release`) before opening a PR.
- One focused change per PR, with a clear description of the user-facing effect.

## Reporting bugs

Open an issue with your macOS version, whether Apple Intelligence is enabled, the app you were using,
and steps to reproduce. Logs aren't collected (by design), so repro steps are gold.
