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

| Command         | What it does                                                                                              |
| :-------------- | :-------------------------------------------------------------------------------------------------------- |
| `/lore:refresh` | First run: writes a small managed block at the top of `CLAUDE.md` (stack, commands) and records a baseline. Later runs: only re-derives what git shows changed. |
| `/lore:status`  | Read-only. Reports last-refresh date and current drift. Won't touch anything.                             |

The **SessionStart hook** runs silently every time Claude Code starts. It only prints a message when:

- You're in a repo with a lore baseline and the repo has **drifted** — ≥20 commits since last refresh, a watched manifest (`package.json`, `Cargo.toml`, `go.mod`, lockfiles, `Makefile`, etc.) changed, ≥60 days passed, or history was rewritten. → Suggests `/lore:refresh`.
- You're in a "real" repo (git, ≥10 commits, has a manifest) that lore **hasn't bootstrapped yet**. → Suggests `/lore:refresh` to bootstrap.

In every other case the hook is silent. The check is a small shell script — zero model tokens, zero context cost when nothing fires.

## What the managed block looks like

A short block at the top of your `CLAUDE.md`, wrapped in HTML comments. Those comments are stripped before Claude reads `CLAUDE.md`, so the markers cost zero context tokens — they only exist so lore can find the block to rewrite it.

```markdown
<!-- BEGIN lore-managed: do not edit between these markers. Run /lore:refresh to update. -->
<!-- lore-version: 0.2.0 -->
<!-- last-refreshed: 2026-05-27 -->
<!-- last-sha: 9a7c1d4 -->

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

Schema: last-refreshed SHA, last-refreshed date, the list of watched files, drift thresholds. The hook reads this to decide whether to nudge. lore adds `.claude/lore-state.json` to `.gitignore` on first run (the state is per-machine; sharing it with teammates would just cause refresh churn).

## Disable the hook

If you want the skills but not the SessionStart notifications:

```sh
touch ~/.claude/lore-disabled
```

The hook checks this file first and exits silently if present. To re-enable, `rm ~/.claude/lore-disabled`.

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
- **Per-machine state.** `.claude/lore-state.json` is gitignored. Each contributor maintains their own refresh cadence. The managed block in `CLAUDE.md` is committed so the *content* travels; only the staleness baseline is local.
- **Heuristic drift thresholds.** Commits ≥20, days ≥60, or a watched-file change triggers a nudge. These are sensible defaults, not science. The thresholds are fields in the state file if you want to tune them per-repo.
- **Platform absorption risk.** Anthropic ships memory and onboarding features quickly. A native "CLAUDE.md is stale" notification is the kind of thing Claude Code could grow on its own. If it does, the right move is to drop lore. The plugin is small enough that switching costs are nil.

## Tune the thresholds

Edit `.claude/lore-state.json` directly:

```json
{
  "driftThresholds": {
    "commits": 50,
    "days": 90
  }
}
```

The hook reads these on every session start. No reinstall needed.

## Versioning

Semver on the `version` field in `plugins/lore/.claude-plugin/plugin.json`. Marketplace consumers see updates only when that field is bumped. Tagging is done with `claude plugin tag` from the repo.

## License

MIT. See [LICENSE](LICENSE).

## Contributing

Issues and PRs at [github.com/Luis-avalos1/lore](https://github.com/Luis-avalos1/lore). Test locally:

```sh
claude --plugin-dir ./plugins/lore
```

Then `/reload-plugins` to pick up edits without restarting.
