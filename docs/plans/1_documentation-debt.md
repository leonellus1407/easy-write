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
- [ ] `docs/requirements/1_popup-translator.md` and `docs/AI_Overview.md` — both justify greedy sampling by determinism and decode cost; the real reason is accuracy, measured below
- [ ] `docs/AI_Overview.md` — states the style guide is the lever for word choice; it is global while the target language is per-translation, so it cannot carry a glossary
- [ ] `README.md`, `HOW_IT_WORKS.md`, `docs/AI_Overview.md` — all three describe one translation engine; 2.1 ships two, so the engine, the language packs and the 26.4 floor need a pass
- [ ] `docs/conventions/testing/README.md` — the eight-phrase benchmark now has two engines to record, and the suite count moved from nine tests to fourteen
- [ ] Open question: whether the prompt benchmark harness belongs in the repo rather than in `/tmp`

## Details

<details>
<summary>Measured: greedy sampling wins on accuracy, not just on cost</summary>

Eight phrases, three samples each, scored on whether the facts that must survive — times, places,
numbers, negation, modality, subject — actually did, and whether the output degenerated:

| Sampling | Passed | Avg | Distinct outputs of 24 runs |
|---|---|---|---|
| greedy | **18/24** | 0.80s | 8 (deterministic) |
| temperature 0.3 | 11/24 | 0.88s | 21 |
| temperature 0.7 | 9/24 | 0.61s | 24 |
| `.random(top: 20)` | 8/24 | 0.60s | 24 |
| `.random(probabilityThreshold: 0.9)` | 11/24 | 0.61s | 23 |
| `.random(top: 20)` + temperature 0.3 | 14/24 | 0.94s | 22 |

Quality falls as randomness rises, with no latency to show for it. Translation is not open-ended
generation: there is usually one right continuation, so on a model this size the greedy path is the
best path and sampling mostly finds worse ones — invented words ("Снежай"), swapped time references
(*yesterday* for *tomorrow*), dropped subjects, and one output that echoed the English with a Cyrillic
С spliced into it.

Consequence for the popover: `retranslate()` cannot offer a better alternative, because a re-run is
byte-identical. It stays useful for retrying after a timeout or an error, and for picking up a style
guide edited while the popover was open — a style-guide change does not re-trigger a run by itself.

</details>

<details>
<summary>Known gaps that are code, not documentation</summary>

- A clipboard of a few thousand characters fails with "The translation didn't finish. Try again."
  The real cause is the model's 4096-token context being exceeded, and the message should say so.
  Pre-existing: v1 had the same ceiling.
- Register drift (dropping "Please", switching to informal address), gender agreement, and invention
  on longer sentences survive every instruction variant and every sampling mode tried.
- The style guide cannot be the lever for these. It is one global string appended to every
  instruction, while the target language is chosen per translation out of thirteen, so a term
  mapping is wrong for twelve of them. `Lang.note` in `Sources/EasyWriteCore/Languages.swift` is the
  language-scoped mechanism — it is applied only when that language is the target, as Arabic already
  uses it — and is where per-language guidance such as register convention belongs.
- Both `Lang.note` and the style guide are appended *after* the instruction's closing line, which is
  the one position measurement says must keep naming the target language. Arabic's instruction
  therefore ends with its dialect note rather than with "Output only the Arabic translation."

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
