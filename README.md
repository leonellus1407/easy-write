<div align="center">

<img src="docs/icon.png" width="120" height="120" alt="Easy Write app icon">

# Easy Write on Mac

### Translate anything on your clipboard, in one keystroke — 100% on-device.

Copy text anywhere, press `⇧⌃Z`, and a popover opens at the menu bar with the translation already
streaming in. Pick the source and target language, swap them, edit the text and watch it retranslate.
Powered entirely by Apple's **on-device** engines — the Apple Intelligence model by default, or
Apple Translate when you want plainer, steadier wording.
**No accounts. No API keys. No cloud. No permissions.** Your text never leaves your Mac.

A free, open-source **DeepL / Google Translate alternative** for macOS — built for people who
write and read in more than one language.

![macOS 26.4+](https://img.shields.io/badge/macOS-26.4%2B-black?logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![100% on-device](https://img.shields.io/badge/AI-100%25%20on--device-2ea44f)
![No account](https://img.shields.io/badge/account-not%20required-2ea44f)
![No permissions](https://img.shields.io/badge/permissions-none-2ea44f)
![License: MIT](https://img.shields.io/badge/License-MIT-blue)
![PRs welcome](https://img.shields.io/badge/PRs-welcome-ff69b4)

**[🧠 How it works](HOW_IT_WORKS.md) · [⬇️ Install](#-install-build-from-source) · [🆚 How it compares](#-how-it-compares) · [🐛 Report a bug / request a feature](../../issues)**

</div>

---

![Easy Write popover translation walkthrough](docs/demo.gif)

## Why Easy Write?

If you write emails, messages, or docs in a language that isn't your first, you're stuck in a loop:
copy → open DeepL/Google Translate → wait for a browser tab → read → copy back.

Two things go wrong with the existing options:

- 🌐 **Cloud translators** (DeepL, Google Translate) mean sign-ups, monthly limits, and your private
  text leaving your machine. The "translate in any app" desktop tools are mostly the same — cloud
  behind a popup.
- 🧩 **Local LLM tools** get privacy right but make you install Ollama, download a model, or paste in
  an OpenAI API key first.

**Easy Write uses the AI already built into macOS 26** — so it's private *and* zero-setup. The
default engine is the on-device language model, and because that's a language model rather than a
dictionary, you can teach it your own vocabulary.

## What you get

- ⚡ **One keystroke** — copy anywhere, press `⇧⌃Z`, read the translation. Or click the menu-bar icon
- 🔀 **Two engines, one radio button apart** — Apple Intelligence follows your style guide and writes word by word; Apple Translate is steadier on long sentences and runs without Apple Intelligence
- 🌊 **Streams as it writes** — on Apple Intelligence the first words appear in about a quarter of a second, not after the whole answer
- 🔁 **Both directions** — source and target dropdowns with a swap button; source defaults to auto-detect
- ✏️ **Editable** — fix the text in the left pane and it retranslates on its own. ⌘A, ⌘C, ⌘X, ⌘V and ⌘Z all work there, and the pane has the keyboard the moment the popover opens
- ⏱️ **A stopwatch on every translation** — the footer counts up in hundredths while the engine works, then holds the time it took. A repeat comes out of memory and says "Cached" instead
- 🌍 **13 languages** — German, French, Spanish, Italian, Portuguese, Dutch, Turkish, Polish, Russian, English, Japanese, Chinese, Arabic
- 🧠 **Personal style & glossary** — teach it your preferred terms so the output sounds like *you* (Apple Intelligence only; Apple Translate takes no instructions)
- 🖱️ **Right-click the icon** for the settings menu — version, Preferences, launch at login, quit. Left-click still opens the translator
- 🔓 **No permissions at all** — nothing to grant, nothing to explain to your IT department
- 🔒 **100% local** — no account, no API key, no telemetry, zero network code
- 🪶 **Tiny & native** — about 1,500 lines of Swift, no Dock clutter, launches at login

## 🆚 How it compares

The honest version: these tools are good — Easy Write just occupies a different corner (free, private,
zero-setup, zero-permission).

| | **Easy Write** | DeepL | Google Translate | Apple Translate | Ollama-based tools |
|---|:---:|:---:|:---:|:---:|:---:|
| Runs on-device / private | ✅ | ❌ cloud | ❌ cloud | ✅ | ✅ |
| No account or API key | ✅ | ❌ | ⚠️ | ✅ | ⚠️ needs setup |
| Requires no permission | ✅ | ✅ | ✅ | ✅ | varies |
| One keystroke from any app | ✅ | ⚠️ app only | ❌ | ⚠️ some | varies |
| Your own glossary and tone | ✅ | Pro only | ❌ | ❌ | ✅ |
| Setup | just the app | account | — | built-in | install Ollama + model |
| Open source | ✅ | ❌ | ❌ | ❌ | ✅ |
| Price | **Free** | Free / Pro | Free | Free | Free |

The Apple Translate column is the app Apple ships. Its engine is also one of Easy Write's two, so
you can have that translation quality from the clipboard, in any app, with your own shortcut.

## Requirements

- **macOS 26.4 or later**, **Apple Silicon**
- **Apple Intelligence enabled** — System Settings → *Apple Intelligence & Siri*. Only the default
  engine needs it; pick Apple Translate in Preferences and it translates without it

## ⬇️ Install (build from source)

```bash
git clone https://github.com/onekapisch/easy-write.git
cd easy-write
./setup-signing.sh      # optional, once: a stable self-signed identity instead of an ad-hoc one
./build.sh              # compile + bundle + sign  →  EasyWrite.app
cp -R EasyWrite.app /Applications/
open /Applications/EasyWrite.app
```

There is **nothing to grant** — no permission dialog appears. Copy some text and press `⇧⌃Z`.

## Usage

| Shortcut | Action |
|:---:|---|
| `⇧⌃Z` | Open the translator on whatever is on your clipboard (press again to close) |

Clicking the menu-bar icon does the same thing, and right-clicking it opens the settings menu. Inside
the popover: pick the two languages, press the swap button to reverse them, edit the left pane to
retranslate, or press **Retranslate** to force a fresh run. The footer times each run and says
"Cached" when the answer came from memory. **Copy** puts the result on your clipboard — that is the
only time Easy Write writes to it.

Choose the engine, rebind the shortcut, add a personal style guide, and choose whether private
clipboard content is read in **Preferences** (menu-bar icon → gear → *Preferences…*). With Apple
Translate selected, Preferences also lists every language, whether its pack is already on your Mac,
and a **Download** button when it isn't.

## 🔒 Privacy & security

Nothing leaves your Mac. Both engines run locally; there is **no network code, no analytics, no
accounts**, and **no permission is requested at all**. Easy Write reads your clipboard and never
writes to it, except when you press **Copy** — that is one call site in the source, and a test keeps
it that way. Text copied from a password manager is skipped by default. Don't take our word for any
of it: the whole app is about 1,500 lines of Swift. Read it.

One thing does reach the network, and it is macOS doing it rather than the app: picking a language
Apple Translate hasn't downloaded yet makes the system offer to fetch the pack. It asks you first,
and translating with a pack you already have is entirely offline.

See [SECURITY.md](SECURITY.md) for the full data-flow and how to report a vulnerability.

## 🧠 How it works

See **[HOW_IT_WORKS.md](HOW_IT_WORKS.md)** — the on-device LLM integration, the permissive-guardrails
gotcha (Apple's default safety filter blocks ordinary translations!), how prewarming a session cuts
the first token from 2.4 s to 0.25 s, how two very different engines end up behind one protocol, and
why the app needs no permission at all.

## Roadmap

Long-text handling · more languages · a notarized prebuilt download. Ideas and PRs welcome — open an
[issue](../../issues).

## FAQ

**Is it really free?** Yes — free and open source (MIT). No account, no subscription, no upsell.

**Does it send my data anywhere?** No. There is zero network code, and your text is translated on
your Mac by either engine. The one thing that can touch the network is macOS downloading an Apple
Translate language pack, which it asks you about and fetches itself.

**What permissions does it need?** None. It reads the clipboard, which needs no permission, and
registers a global shortcut, which also needs none.

**Can it replace my selected text in place, like version 1?** No. That needed Accessibility
permission and synthetic keystrokes, which is exactly what 2.0 removed. Press **Copy** and paste.

**Will it read a password I copied?** Not by default. Password managers mark what they copy as
private, and Easy Write skips it — you get an empty popover. There's a checkbox in Preferences if you
want it to read everything.

**Why not the Mac App Store?** Distribution is build-from-source for now; a notarized download may
come later.

**"Apple Intelligence isn't available."** First, requires Apple Silicon + macOS 26.4 with Apple
Intelligence enabled (System Settings → *Apple Intelligence & Siri*). If it's already enabled and you
still see this, the model is most likely **still downloading in the background** — that happens the
first time you turn Apple Intelligence on and can take a while. Wait until Settings shows it's ready
(needs free storage + a network connection), then try again. The app tells you which of these it is.
Or don't wait: switch the engine to Apple Translate in Preferences and translate without it.

**Which engine should I pick?** Start with Apple Intelligence, the default. It's the only one that
reads your style guide, so it's the one that can sound like you, and it writes the answer word by
word. Switch to Apple Translate when a sentence comes back with an odd or invented term, when you
want the answer faster, or when Apple Intelligence isn't available on your Mac. Neither wins
everywhere, which is why it's a setting rather than a replacement.

**How is this different from Apple's built-in Translate?** Apple's right-click Translate works on a
selection inside apps that support it, and you can't give it a glossary or a house style. Easy Write
works from the clipboard in any app, on one shortcut. Pick the Apple Intelligence engine and every
translation goes through your own style guide; pick Apple Translate and you get that same engine, but
reachable from anywhere rather than only where an app supports it.

## Contributing

PRs and issues welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Good first contributions: more
languages, long-text handling, more tests.

## License

[MIT](LICENSE) © onekapisch

---

<div align="center">

⭐ **If Easy Write saves you a trip to a translation site, star the repo — it genuinely helps other people find it.**

Made with Swift + Apple's on-device intelligence · No cloud, no accounts, no tracking.

</div>
