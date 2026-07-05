# Changelog

## 0.5.0

The "watch the whole file" release. lore is repositioned from a managed-block
watchdog to a drift watchdog for the entire `CLAUDE.md`: alongside the existing
managed-block signals, a deterministic scanner now flags stale human prose, and
a new `/lore:review` skill fixes it.

### Added

- **Prose dead-reference detection (`claude_md_dead_refs` in `lib/common.sh`).**
  A conservative, deterministic scanner reads the human prose and flags
  backticked tokens and Markdown link targets that look like repo paths whose
  parent directory exists but the path doesn't. It skips URLs, globs,
  placeholders, fenced code, build-output directories, and the managed block
  itself, and reports at most 5 — false positives cost more trust than a quiet
  miss. Shared by the hook, `/lore:status`, and `/lore:review`.
- **`/lore:review` — a model-driven review of `CLAUDE.md` prose.** Verifies each
  flagged dead reference, hunts other stale claims, proposes edits, and applies
  them to the prose only, never inside the managed markers.
- The SessionStart hook and `/lore:status` now surface dead prose references
  (the hook nudges toward `/lore:review`), combined into the existing one-line
  output.

### Changed

- **Repositioned as a drift watchdog for the whole `CLAUDE.md`.** The managed
  block is now one of two payloads lore watches; the prose is the other.
  `/lore:refresh` still owns the managed block and never touches prose;
  `/lore:review` owns the prose and never touches the managed block.

### Deferred

- **Stale-command detection.** Flagging a documented command that no longer
  exists can't be done reliably from prose alone — a script may live in a
  Makefile, justfile, tool alias, or shell function — so it was left out rather
  than spend the false-positive budget on guesses.

## 0.4.0

The "never corrupt your CLAUDE.md" release. The managed-block edit is now done
by a deterministic, byte-preserving writer instead of model prose, refresh is
user-triggered only, and the test suite grew golden byte comparisons plus
threshold-boundary and git-edge coverage.

### Added

- **`lib/apply-block.sh` — a deterministic managed-block writer.** It owns the
  `BEGIN`/`END` markers and performs an atomic, marker-bounded splice: only the
  bytes between the markers change, everything outside is preserved byte-for-byte
  (text, blank lines, LF/CRLF, trailing-newline state), and the write is atomic
  (temp file + rename). It refuses to write on unbalanced or duplicate markers
  (exit 3, nothing written), follows a symlinked `CLAUDE.md` to its target, and
  is idempotent. `/lore:refresh` now derives only the block body and pipes it to
  this writer instead of hand-editing the file.
- **Golden byte-comparison tests** for the writer (create/insert/replace,
  idempotency, exact LF and CRLF output, trailing-newline preservation, two-block
  and missing-`END` refusal, body-with-markers rejection, symlink write-through),
  plus threshold-boundary tests (commits 19/21, day 9/10, bootstrap 9/10) and git
  edge cases (shallow clone, detached HEAD, rewritten-but-present baseline). The
  suite grew from 35 to 66 tests, all re-run with `jq` removed.
- CI now runs `claude plugin validate --strict`, shellchecks the writer, and a
  `Makefile` provides `make test|validate|shellcheck|check`.
- `$schema` on `plugin.json` for editor validation.

### Changed

- **`/lore:refresh` is user-invocable only** (`disable-model-invocation: true`),
  so Claude can no longer autonomously rewrite `CLAUDE.md` at session start — the
  SessionStart hook prompts *you* to refresh. `/lore:status` stays
  model-invocable (it's read-only). This also drops the refresh description from
  always-on context.
- The recon scripts report a deterministic marker `state:`
  (`create`/`insert`/`replace`/`malformed`) from the writer instead of dumping an
  open-ended `awk` range, so a missing `END` marker no longer presents your prose
  as "the block" and `/lore:status` surfaces a malformed block.

### Fixed

- **`count_commits` no longer reports a rewritten baseline's whole history as
  drift.** After a rebase/squash/force-push, an old baseline SHA can survive in
  the object store while no longer being an ancestor of `HEAD`; `BASE..HEAD` then
  counted the entire rewritten history. A new `is_ancestor` guard makes the hook
  and recon emit an accurate "recompute the baseline" message instead.
- **The jq-free `state_num` now rejects non-integer thresholds like `jq` does.**
  A value such as `3.5`, `1e2`, or `"7x"` parsed to a wrong small number without
  `jq` while the `jq` path fell back to the default — the same committed state
  file behaved differently depending on whether `jq` was installed.
- **`to_epoch` keeps a timezone offset when stripping fractional seconds (BSD).**
  A timestamp like `...00.123+05:00` had its offset deleted along with the
  fraction and was misread as UTC.

The following were committed after 0.3.0 was tagged but never released under a
version, so they ship for the first time in 0.4.0:

- **The jq-free state-file readers respect JSON nesting.** A `"disabled": true`
  / `"watchFiles"` / `"driftThresholds"` nested inside another object no longer
  registers as a top-level key, and a threshold is read only from
  `driftThresholds.<key>` so a same-named key elsewhere can't shadow it (quoted
  integers like `"50"` parse like bare integers, matching `jq`).
- **`watchFiles` entries containing `,` or `]` no longer corrupt the list.** An
  entry like `app/[id]/page.tsx` used to drop itself and everything after it;
  entries are now read as whole quoted strings.
- **Bare `YYYY-MM-DD` dates parse at midnight UTC on BSD/macOS.** `date -j` had
  filled the missing time-of-day from the current clock, making `days_since`
  off by up to a day; a numeric timezone offset is now honored.

## 0.3.0 — 2026-06-11

The "actually honor the knobs" release. The hook, the skills, and the docs
now agree with each other, and a test suite + CI keep it that way.

### Fixed

- **`driftThresholds` in the state file is now honored by the hook.** The
  README promised tunable thresholds; the hook had them hardcoded. Setting a
  threshold to `0` disables that signal.
- **Custom `watchFiles` in the state file is now honored by the hook** (it
  previously used a hardcoded list that could disagree with the state file
  and with `/lore:status`). An explicit empty array disables watch checking.
- **`"lastRefreshSha": null` no longer produces a false "history has been
  rewritten" nudge.** The jq-free JSON fallback parser echoed the whole line
  for null values; it now extracts quoted strings only.
- **Repos bootstrapped outside git now get the date-based staleness nudge.**
  An early exit skipped the day check whenever the SHA was missing.
- **Monorepo subdirectory projects are checked correctly.** Watched files are
  now matched as git pathspecs relative to the project directory (previously
  only repo-root paths could ever match), and the commit count only counts
  commits touching the project directory.
- Date parsing tolerates fractional seconds and bare dates on BSD/macOS date.
- Removed the README claim that HTML comment markers cost "zero context
  tokens" — Claude Code does not strip comments from CLAUDE.md. The markers
  are just small.

### Changed

- One shared library (`plugins/lore/lib/common.sh`) now backs the hook and
  both recon scripts, so `/lore:status` reports exactly what the hook checks.
- Drift signals are combined into a single nudge line (commits, watched
  files, days) instead of first-match-wins.
- The default watch list dropped `README.md`/`ARCHITECTURE.md` (they never
  feed the managed block, so they only caused churn) and gained modern
  manifests and version pins: `bun.lock`, `deno.lock`, `uv.lock`,
  `setup.py`, `rust-toolchain.toml`, `.nvmrc`, `.python-version`,
  `.tool-versions`, `mise.toml`, gradle version catalogs, `compose.yaml`,
  and more.
- New state files no longer freeze a copy of `watchFiles`/`driftThresholds`;
  when the keys are absent, built-in defaults apply (and improve with plugin
  updates). Existing state files keep working as written.
- The hook's nudge text now mentions how to opt out, and distinguishes a
  fresh clone (managed block present, per-machine baseline missing) from a
  repo lore has never seen.
- Shallow clones get accurate wording instead of "history was rewritten".
- The managed block and state file get their `lore-version` from
  `plugin.json` at refresh time (the skill had a stale hardcoded version).

### Added

- `/lore:refresh force` — re-derive every field and recreate the block even
  if the markers were deleted.
- More ways to silence the hook: per-repo `.claude/lore-disabled`,
  `"disabled": true` in the state file, and the `LORE_DISABLE` env var, in
  addition to the existing global `~/.claude/lore-disabled`.
- `/lore:status` now reports the effective thresholds and whether they come
  from the state file or defaults.
- Bootstrap recon inlines manifest excerpts (package.json scripts, pyproject,
  go.mod, Makefile targets, version-pin files), so bootstrapping usually
  needs zero extra file reads.
- Test suite (`tests/run.sh`, dependency-free bash) covering the hook and
  recon scripts, including the no-jq fallback parsers, run in CI on Linux
  and macOS (system bash 3.2) plus shellcheck.

## 0.2.2 and earlier

Initial staleness-watchdog scope: SessionStart drift hook, `/lore:refresh`,
`/lore:status`.
