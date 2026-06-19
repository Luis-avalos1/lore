# Changelog

## Unreleased

The "jq and the fallback finally agree" release. The sed/grep parsers used
when `jq` is absent now match jq's JSON scoping, so a repo behaves the same
whether or not `jq` is installed.

### Fixed

- **The jq-free state-file readers now respect JSON nesting.** Previously they
  scanned the whole file, so a key nested inside another object leaked into a
  top-level check on machines without `jq`:
  - A `"disabled": true` (or `"watchFiles"`/`"driftThresholds"`) nested inside
    some other object no longer registers as a top-level key, so it can't
    silence nudges or flip the watch/threshold source.
  - Drift thresholds are read only from `driftThresholds.<key>`; a same-named
    key elsewhere in the file can no longer shadow them. Thresholds written as
    quoted integers (`"50"`) now parse like bare integers, matching `jq`.
- **`watchFiles` entries containing `,` or `]` no longer corrupt the list.**
  The jq-free parser split on commas and stopped at the first `]`, so an entry
  like `app/[id]/page.tsx` dropped itself and every entry after it (disabling
  watching entirely). Entries are now read as whole quoted strings.
- **Bare `YYYY-MM-DD` dates parse at midnight UTC on BSD/macOS.** `date -j`
  filled the missing time-of-day from the current clock, making `days_since`
  off by up to a day and nondeterministic; a numeric timezone offset
  (`+05:00`/`-05:00`) is now honored instead of silently dropped.

### Added

- Tests covering the nested-key, shadowed-threshold, quoted-threshold, and
  `]`-in-`watchFiles` cases (all exercised in the no-jq pass).

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
