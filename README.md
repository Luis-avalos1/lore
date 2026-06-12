# lore

> A staleness watchdog for `CLAUDE.md`. Tells you when your repo has drifted past what Claude Code remembers, and refreshes a small managed block so the basics stay current.

`lore` does one thing: it keeps the top of your `CLAUDE.md` honest. It manages a tiny block — stack identifiers, the install/build/test commands, last-refresh metadata — and pings you when too many commits or a lockfile change make that block stale. Everything else in `CLAUDE.md` stays under your control.

## Why a watchdog, not an onboarder?

Claude Code already has good built-ins for the heavy lifting:

- **`/init`** generates a starting `CLAUDE.md` from scratch.
- **Auto memory** (v2.1.59+) writes per-project notes automatically as Claude works.

What it doesn't have: anything that *notices* when your `CLAUDE.md` falls out of sync with the actual repo. You bump a major dependency, add a new test runner, restructure scripts — and the file sitting at the root quietly goes stale. Claude keeps reading it as truth.

That's the gap lore fills. Use `/init` to bootstrap `CLAUDE.md`, then let lore manage a small section of it and tell you when reality has moved.

## Install

```
/plugin marketplace add Luis-avalos1/lore
/plugin install lore@lore
```

Two commands, once. Reload (`/reload-plugins`) or restart Claude Code. Now `/lore:refresh` and `/lore:status` are available in every repo.

## Use it

Two skills, plus a silent hook:

| Command               | What it does                                                                                              |
| :-------------------- | :-------------------------------------------------------------------------------------------------------- |
| `/lore:refresh`       | First run: writes a small managed block at the top of `CLAUDE.md` (stack, commands) and records a baseline. Later runs: only re-derives what git shows changed. |
| `/lore:refresh force` | Re-derives every field from scratch and recreates the block even if the markers were deleted.             |
| `/lore:status`        | Read-only. Reports last-refresh date, current drift, and the effective thresholds. Won't touch anything.  |

The **SessionStart hook** runs silently every time Claude Code starts. It prints a single line only when:

- You're in a repo with a lore baseline and the repo has **drifted**: ≥20 commits touching the project since the last refresh, a watched manifest (`package.json`, `Cargo.toml`, `go.mod`, lockfiles, `Makefile`, version-pin files like `.nvmrc`, etc.) changed, ≥60 days passed, or the baseline commit no longer exists (history rewritten). All triggered signals are combined into one line. → Suggests `/lore:refresh`.
- You're in a "real" repo (git, ≥10 commits, has a manifest) that lore **hasn't bootstrapped yet**. → Suggests `/lore:refresh` (and `/init` first if there's no `CLAUDE.md` at all). If `CLAUDE.md` already has a lore block but the local baseline is missing, you probably just cloned — the nudge says so.

In every other case the hook is silent. The check is a small shell script — zero model tokens, zero context cost when nothing fires.

Monorepos: lore is scoped to the directory you opened. Watched files are matched relative to the project directory, and only commits touching that directory count toward drift — so a baseline in `apps/web` isn't spooked by churn in `apps/api`.

## What the managed block looks like

A short block at the top of your `CLAUDE.md`, wrapped in HTML comments. The markers exist so lore can find and rewrite its block without ever touching your content; they're two short comment lines, so they cost only a few context tokens.

```markdown
<!-- BEGIN lore-managed: do not edit between these markers. Run /lore:refresh to update. -->
<!-- lore-version: 0.3.0 -->
<!-- last-refreshed: 2026-06-11 -->
<!-- last-sha: 9a7c1d4e22b1 -->

## Project
acme-api

## Stack
- TypeScript 5.4, Node 22 (.nvmrc)
- pnpm

## Commands
- Install: `pnpm install`
- Test: `pnpm test`
- Lint: `pnpm lint`
- Dev: `pnpm dev`

<!-- END lore-managed -->

# Anything you (or `/init`) write below the markers is left alone forever.
```

That's the entire scope. Architecture, conventions, prose, project-specific gotchas — those stay outside the markers, written by you or by Claude when you ask.

## State file

lore stores a tiny state file in your repo:

```
.claude/lore-state.json
```

It records the last-refresh SHA and date. lore adds it to `.gitignore` on first run — the state is per-machine; sharing it with teammates would just cause refresh churn. The managed block in `CLAUDE.md` is committed, so the *content* travels; only the staleness baseline is local.

```json
{
  "version": 1,
  "loreVersion": "0.3.0",
  "lastRefreshSha": "9a7c1d4e22b1…",
  "lastRefreshDate": "2026-06-11T18:04:05Z",
  "repoRoot": "/path/to/repo",
  "repoRemote": "git@github.com:acme/api.git"
}
```

## Tune it

Add any of these optional keys to `.claude/lore-state.json` — the hook reads them on every session start, no reinstall needed. When a key is absent, lore uses built-in defaults (which improve as the plugin updates, another reason not to write them down unless you're overriding).

```json
{
  "driftThresholds": { "commits": 50, "days": 90 },
  "watchFiles": ["package.json", "deno.json", "infra/Dockerfile"],
  "disabled": true
}
```

- `driftThresholds` — defaults: 20 commits, 60 days. Set a value to `0` to disable that signal.
- `watchFiles` — replaces the default watch list. Entries are git pathspecs relative to the project directory. An empty array disables watch checking entirely.
- `disabled` — silences the hook for this repo while keeping the skills usable.

`/lore:status` shows the effective thresholds and whether they come from your state file or the defaults.

## Disable the hook

Pick whichever fits:

```sh
touch ~/.claude/lore-disabled     # everywhere, all repos
touch .claude/lore-disabled       # this repo only (also stops bootstrap nudges)
```

…or set `"disabled": true` in the state file (this repo, keeps the skills), or export `LORE_DISABLE=1` (e.g. for CI). To re-enable, remove whichever you added.

## Uninstall

```
/plugin uninstall lore@lore
/plugin marketplace remove lore
```

What's left behind:

- The lore-managed block in your `CLAUDE.md` (delete by hand if you don't want it).
- `.claude/lore-state.json` (`rm` it).

lore intentionally does not hook into uninstall to clean these up — they're your files.

## Limitations and honest caveats

- **lore is small on purpose.** It does not generate architecture overviews, list files, detect conventions, or seed a memory directory. Use `/init` for the broader bootstrap; lore only manages the small block at the top.
- **Per-machine state.** Each contributor maintains their own refresh cadence. On a fresh clone the hook will offer to rebuild the baseline once.
- **Heuristic drift thresholds.** Sensible defaults, not science — tune them per-repo as above.
- **Drift is measured against commits.** Uncommitted changes to a manifest don't trigger the hook; they'll count once committed. (`/lore:refresh` does surface uncommitted manifest edits in its summary.)
- **Platform absorption risk.** Anthropic ships memory and onboarding features quickly. A native "CLAUDE.md is stale" notification is the kind of thing Claude Code could grow on its own. If it does, the right move is to drop lore. The plugin is small enough that switching costs are nil.

## Versioning

Semver on the `version` field in `plugins/lore/.claude-plugin/plugin.json`. Marketplace consumers see updates only when that field is bumped. Tagging is done with `claude plugin tag` from the repo. See [CHANGELOG.md](CHANGELOG.md).

## Development

The hook and recon scripts are plain bash (3.2-compatible — stock macOS — with BSD and GNU userlands both supported; `jq` is used when present, never required). A dependency-free test suite covers drift detection, the disable switches, custom thresholds/watch lists, monorepo subdirectory projects, and the jq-free fallback parsers:

```sh
bash tests/run.sh        # or /bin/bash tests/run.sh for the bash-3.2 experience
claude plugin validate . # manifest + skill frontmatter validation
```

CI runs the suite on Linux and macOS plus shellcheck. Test a working copy of the plugin against a real repo with:

```sh
claude --plugin-dir ./plugins/lore
```

Then `/reload-plugins` to pick up edits without restarting.

## License

MIT. See [LICENSE](LICENSE).

## Contributing

Issues and PRs at [github.com/Luis-avalos1/lore](https://github.com/Luis-avalos1/lore).
