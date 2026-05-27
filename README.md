# lore

> Persistent repo knowledge for Claude Code. Learn a repo once, remember it forever, refresh it when things drift.

`lore` is a Claude Code plugin that gets Claude oriented in a codebase without it having to grep around to rediscover the same things every session. It learns your repo, writes a managed section into `CLAUDE.md`, seeds per-project memory, and quietly watches for drift in the background.

The point isn't fewer tokens in context — `CLAUDE.md` is sent every turn, so those tokens never go away. The point is **fewer exploratory tool calls**. Claude already knows your build commands, your test runner, where the entry point lives, what your conventions look like. It doesn't have to figure it out again next session.

## Install

```sh
/plugin marketplace add Luis-avalos1/lore
/plugin install lore@lore
```

That's it. Restart Claude Code (or run `/reload-plugins`) and lore is live.

## Use it

Three skills, all namespaced under `lore`:

| Command         | What it does                                                                          |
| :-------------- | :------------------------------------------------------------------------------------ |
| `/lore:learn`   | First-time onboard. Analyzes the repo, writes a managed block to `CLAUDE.md`, seeds memory files. Run this once per repo. |
| `/lore:refresh` | Incremental update. Only re-derives what git shows changed. Cheaper than `learn`.    |
| `/lore:status`  | Read-only inspection. Reports drift, memory inventory, last-learned date.            |

Plus a `SessionStart` hook that runs silently in the background. It only speaks up when:

- You're in a repo lore already knows and the repo has **drifted** (≥20 commits since last learn, a watched manifest file changed, or ≥60 days passed) → suggests `/lore:refresh`.
- You're in a "real" repo (git, ≥10 commits, has a package manifest) that lore **hasn't seen yet** → suggests `/lore:learn`.

In every other case it's silent. The check costs zero model tokens — it's a shell script, not a Claude call.

## What it writes

### `CLAUDE.md` (in your repo)

A managed block at the top, between HTML comment markers. The markers are stripped before Claude reads `CLAUDE.md`, so they don't waste any context — they only exist so `/lore:refresh` knows what's safe to rewrite.

```markdown
<!-- BEGIN lore-managed: do not edit between these markers. Run /lore:refresh to update. -->
<!-- lore-version: 0.1.0 -->
<!-- last-learned: 2026-05-27 -->
<!-- last-sha: 9a7c1d4 -->

# Project: …
## Stack
## Commands
## Layout
## Conventions

<!-- END lore-managed -->
```

Anything you write outside those markers is left untouched. lore never deletes human-authored content.

### `.claude/lore-state.json` (in your repo, gitignored)

Tiny state file: last-learned SHA, last-learned date, watch-file list, drift thresholds. The hook reads this to decide whether to nudge.

### Per-project memory

Claude Code already maintains a per-repo auto-memory directory at `~/.claude/projects/<encoded-path>/memory/`. lore writes topic files there:

```
MEMORY.md             # index
lore-architecture.md  # system shape, module boundaries
lore-gotchas.md       # landmines (grows over time)
lore-history.md       # dated log of learns/refreshes
```

`MEMORY.md` is loaded into every session (first 200 lines). The topic files are loaded on-demand when Claude needs them.

## Design notes

**Why a plugin and not just a `SKILL.md` you drop into `~/.claude/skills/`?**
Plugins are versioned, installable in one command, updatable in one command, and bundle the hook with the skills. The skills are namespaced (`/lore:learn` instead of `/learn`) so they can't conflict with anything else you have installed.

**Why an HTML-comment marker block in `CLAUDE.md`?**
HTML comments are stripped before `CLAUDE.md` is injected into Claude's context — so the markers cost zero tokens during normal use, but the Read tool still sees them, which is what `/lore:refresh` needs to find the section. Best of both worlds.

**Why a hook that's silent by default?**
Auto-running analysis on every session start would burn tokens for users who just wanted to read one file. Instead the hook does a cheap shell-only staleness check and only suggests action when the check actually fires. Zero cost when there's nothing to say.

**Why memory + `CLAUDE.md`, not one or the other?**
`CLAUDE.md` is for **facts** that every session needs (stack, commands, layout). Memory is for **history and observations** that accumulate over time (gotchas seen in past sessions, what was last refactored, decisions made). Both live alongside each other; lore writes to both during a learn/refresh.

## Limitations

- **Memory is per-machine.** The auto-memory directory at `~/.claude/projects/…` isn't synced. If you want history across machines, sync `~/.claude/` via your dotfiles. CLAUDE.md is in the repo so it travels naturally.
- **Heuristic onboarding suggestion.** The hook decides "should I suggest `/lore:learn` here?" with simple rules (git repo, ≥10 commits, has a manifest). It will miss exotic project layouts. Run `/lore:learn` manually any time.
- **Single-language detection.** The learn skill picks the primary language/manifest and works from there. Polyglot monorepos work but the generated CLAUDE.md may favor whichever workspace lore reads first.
- **Not for ephemeral scratch repos.** The hook explicitly skips repos with <10 commits and no manifest, so scratch directories don't get nagged.

## Disable the hook

If you want lore's skills but not the SessionStart suggestions:

```sh
touch ~/.claude/lore-disabled
```

The hook checks for this file first and exits silently if it exists. To re-enable, `rm ~/.claude/lore-disabled`.

## Uninstall

```sh
/plugin uninstall lore@lore
/plugin marketplace remove lore
```

What's left behind after uninstall:

- `CLAUDE.md` lore-managed block (delete by hand if you don't want it).
- `.claude/lore-state.json` (`rm` it).
- `~/.claude/projects/<encoded>/memory/lore-*.md` (delete to free space, or keep as a personal log).

lore intentionally does *not* hook into the uninstall flow to clean these up — they're your files, in your repo and your home dir.

## Update

```sh
/plugin marketplace update lore
/plugin update lore@lore
```

Or enable auto-update in `/plugin` → Marketplaces → lore → Enable auto-update.

## Versioning

Semver against the `version` field in `plugins/lore/.claude-plugin/plugin.json`. Marketplace consumers only see a new version when that field is bumped, regardless of how many commits land in between. Release tagging is done with `claude plugin tag` from the repo.

## License

MIT. See [LICENSE](LICENSE).

## Contributing

Issues and PRs welcome at [github.com/Luis-avalos1/lore](https://github.com/Luis-avalos1/lore). Test changes locally with:

```sh
claude --plugin-dir ./plugins/lore
```

Then run `/reload-plugins` after edits to pick them up without restarting.
