# Documentation debt

## TL;DR

- Parking list for `.md` edits that are known-needed but deliberately deferred.
- The prompt and the popover are still being tuned; docs get one pass at the end, not one per experiment.
- Nothing here blocks the build, the tests, or the app.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| When to edit the docs | Once the behaviour settles | Avoids rewriting the same lines each round |
| Where pending edits live | This file | One place to look before the final pass |
| What still gets edited immediately | Statements that became false | A wrong doc is worse than a missing one |
| Measured facts vs wording | Record measurements as they land | They stay true whatever the prompt ends up saying |

## Changes

- [ ] `README.md` — "What you get" omits the translation stopwatch, the right-click settings menu, and the editing shortcuts in the text pane
- [ ] `README.md` — the demo image was removed because it showed v1's in-place replacement; a new recording of the popover is needed
- [ ] `promo/easy-write-promo.html` — still animates "Replaced in place"; outside both specs' scope, needs new artwork
- [ ] `docs/requirements/1_popup-translator.md` — `Status` stays `In Progress` until the shortcut recorder, the claimed-hot-key case, and the model-unavailable and timeout paths are exercised
- [ ] `docs/requirements/2_clipboard-read-only-invariant.md` — same, and the pasteboard-read indicator question under `Unresolved`
- [ ] Pull request #4 body — its instruction-length table implies shortening the instruction bought latency; measurement says it bought nothing
- [ ] Open question: whether the prompt benchmark harness belongs in the repo rather than in `/tmp`

## Details

<details>
<summary>Known gaps that are code, not documentation</summary>

- A clipboard of a few thousand characters fails with "The translation didn't finish. Try again."
  The real cause is the model's 4096-token context being exceeded, and the message should say so.
  Pre-existing: v1 had the same ceiling.
- Register drift (dropping "Please", switching to informal address), gender agreement, and invention
  on longer sentences survive every instruction variant tried. The style guide is the lever;
  whether the app should ship a default one is undecided.

</details>

<details>
<summary>Why the docs are not edited per experiment</summary>

Each prompt round changes what is true about the instruction — its length, its wording, what it fixes.
Three documents describe it (`docs/AI_Overview.md`, `docs/requirements/1_popup-translator.md`,
`docs/conventions/testing/README.md`), so a round of tuning costs three edits that the next round may
undo. Measured facts are the exception and are written down as soon as they are established, because
they hold regardless of the final wording: the closing line must name the target language, instruction
length does not affect latency, and greedy decoding is deterministic.

</details>
