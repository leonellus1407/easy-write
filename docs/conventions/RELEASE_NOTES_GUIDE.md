# How to Write Release Notes

This guide describes how to turn the changes on a branch into a release entry.

## Output artifacts

| Artifact | Where it lives | Audience |
|---|---|---|
| `CHANGELOG.md` | repo root, committed | Everyone — users reading the repo, and contributors |
| GitHub Release body | github.com, not in the repo | Users skimming the releases page |

There is no separate `docs/release-notes/` directory: `CHANGELOG.md` **is** the
release-note artifact, and duplicating it under `docs/` would break the
one-fact-one-place rule. The GitHub Release body is a shortened copy of the
newest `CHANGELOG.md` section, so it is written from the same source.

## Golden rule — behavior, not implementation

An entry describes what a **user** does or sees differently. It never describes
which types were touched or how the code is arranged.

### Forbidden content

- **Type names** — `LLMTranslator`, `HotKeyCenter`, `TranslatorPanel`
- **Method or property names** — `translate(_:from:to:styleGuide:)`, `copyOutput()`
- **File names or paths** — `Sources/EasyWrite/Store.swift`
- **UserDefaults keys or other code tokens** — `ignoresPrivateClipboard`, `keyCode: 6`
- **Internal mechanics** — "moved to a task group", "extracted a helper",
  "switched from a closure to a delegate"

### Forbidden entries

- **Pure refactors** — anything with no observable effect must not appear at all.
  Splitting a type, renaming a helper, tightening isolation, reordering members.
- **Repository housekeeping** — README edits, doc changes, CI, `.gitignore`,
  promo assets. The changelog is about the app, not the repository.

### The one allowed exception: a `Notes` section

Technical facts that genuinely change how a user should think about the app may
go in a `### Notes` block at the end of an entry. The 1.0 entry does this for
the permissive-guardrails mode and the self-signed identity: both explain
observable behaviour (translations are not falsely blocked; the Accessibility
grant survives rebuilds), so they earn their place. A framework name mentioned
purely because it is what you used does not.

### Rewriting examples

| Don't write | Write instead |
|---|---|
| Added `note:` field to the `Lang` struct | Arabic now produces Modern Standard Arabic rather than mixed dialect |
| Wrapped the model call in `withThrowingTaskGroup` | A stalled translation no longer leaves the app stuck; it times out and lets you retry |
| Reused the prewarmed `LanguageModelSession` | The first words of a translation now appear in a quarter of a second instead of two |
| Extracted `EasyWriteCore` and added a test target | (omit — repository housekeeping) |
| Reads `SystemLanguageModel.availability` and maps each reason | The app now tells you *why* Apple Intelligence isn't available — unsupported Mac, turned off, or still downloading |
| Bumped `CFBundleVersion` to 3 | (omit — build bookkeeping) |

## Step-by-step process

### 1. Identify the changes

Compare only the commits the branch introduced since it diverged from `main`.
The two commands need different ranges to agree on that:

```bash
git log --oneline main..HEAD     # two dots: commits on HEAD and not on main
git diff main...HEAD --stat      # three dots: diff against the merge base
```

For `git log`, three dots means the *symmetric difference*, so `main...HEAD`
also lists commits that exist only on `main` — someone else's work, not yours to
write up. For `git diff`, three dots means "compare against the merge base",
which is exactly what excludes later changes on `main`. Keep two dots for the
commit list and three for the diff.

Then read the diff of the files that can actually change behaviour:

```bash
git diff main...HEAD -- Sources/ Package.swift Info.plist build.sh setup-signing.sh
```

If the branch is already merged, fall back to the merge commit:

```bash
git show --stat <merge_commit_sha>
git diff <merge_commit_sha>^1..<merge_commit_sha> -- Sources/ Package.swift Info.plist
```

### 2. Review the diff

Only application behaviour counts. Exclude `README.md`, `docs/`, `promo/`,
`.github/`, and `.gitignore` from the analysis.

### 3. Translate each change into observable behavior

For each non-trivial hunk, ask: *what would a user notice differently?* If the
answer is "nothing", it is an internal change and must not appear.

Otherwise write it in plain language, with no code identifiers.

### 4. Write the `CHANGELOG.md` entry

Newest entry at the top, directly under the file's intro line.

```markdown
## [1.2] — 2026-08-30

### Added
- **Short bold title.** One or two sentences on what you can now do, and why it
  matters. Mention the shortcut if there is one.

### Changed
- **Short bold title.** What behaves differently now.

### Fixed
- **Short bold title.** What used to go wrong, and what happens instead. Say
  which case it affected, so a user can tell whether it was their case.

### Notes
- Technical facts that change how a user should think about the app.
```

Rules:

- Heading format: `## [<short version>] — <YYYY-MM-DD>`, using an em dash. The
  version must match `CFBundleShortVersionString` in `Info.plist`.
- Sections in this order, omitting empty ones: `Added`, `Changed`, `Fixed`,
  `Notes`.
- Every bullet starts with a **bold title sentence**, then the explanation.
  `Fixed` bullets may skip the bold title when the fix is a single sentence.
- Write full sentences. An entry that explains *why* the old behaviour was wrong
  is more useful than one that only names the fix.
- Be honest about limitations. The 1.1 Arabic entry says on-device translation
  "can occasionally slip on more complex sentences" — keep that tone.
- A first release opens with a one-line celebration and closes with the
  requirements line, as 1.0 does.

### 5. Bump the version

A release entry is not done until:

- `CFBundleShortVersionString` in `Info.plist` matches the new heading.
- `CFBundleVersion` is incremented.
- If the README refers to behaviour introduced by this release, the README is
  updated in the same PR. (The README owner does this; do not edit it as a
  drive-by.)

### 6. Write the GitHub Release body

Shorten the new `CHANGELOG.md` section to its headline items, keep the same
wording, and link back to the changelog for the full text. Do not invent items
that are not in the changelog.

## Checklist

- [ ] Changes identified from the branch diff against `main` (or the merge commit)
- [ ] Only `Sources/`, `Package.swift`, `Info.plist`, and the build scripts reviewed
- [ ] Each change classified: user-visible (keep) vs internal (drop)
- [ ] No type, method, file, or key names anywhere in the entry
- [ ] No refactors, doc changes, or repo housekeeping listed
- [ ] Sections in order, empty sections omitted
- [ ] Heading version matches `CFBundleShortVersionString`
- [ ] `CFBundleVersion` incremented
- [ ] GitHub Release body derived from the changelog, not written separately
