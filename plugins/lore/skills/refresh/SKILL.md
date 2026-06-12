---
description: Keep a small lore-managed block at the top of CLAUDE.md fresh as the repo evolves. First run sets a baseline; later runs only re-derive what git shows changed. Use when the SessionStart hook reports drift, after a dependency bump or major refactor, or whenever the user wants CLAUDE.md re-blessed against the current HEAD.
when_to_use: First-run bootstrap (no state file) or incremental refresh (state file + drift detected). Manages a small section of CLAUDE.md — stack identifiers, commands, version pins, last-refresh metadata. Never touches content outside the markers.
argument-hint: "[force]"
allowed-tools: Read Write Edit Glob Grep Bash(bash *) Bash(git *) Bash(jq *) Bash(date *) Bash(mkdir *) Bash(cat *) Bash(ls *) Bash(head *) Bash(wc *) Bash(grep *) Bash(sed *) Bash(awk *) Bash(find *) Bash(test *) Bash(echo *)
---

# /lore:refresh — keep CLAUDE.md fresh against drift

lore is small on purpose. Its only job is to keep a tiny block at the top of `CLAUDE.md` synced with what's actually in the repo, and to notice when that block has gone stale. Architecture, conventions, and prose stay human-curated below.

Arguments passed by the user: "$ARGUMENTS" (if this contains `force`, see Force mode).

## Live drift context

A bundled recon script ran before you saw this skill. Use its output instead of re-running its commands. It includes the current UTC date/time, the lore version, the state file, git facts, and either bootstrap context (manifest excerpts) or refresh context (what changed since the last refresh).

!`bash "${CLAUDE_SKILL_DIR}/scripts/recon.sh"`

## Decide which mode

Look at the live output above before doing anything.

- `=== state file ===` shows `NO_STATE` → **bootstrap mode**.
- State file present, zero commits + no changed watch files → **no-op mode**: update `lastRefreshDate` in the state file (use the `iso:` value from the recon output) and tell the user "Nothing has changed since the last refresh." Two sentences max.
- State file present, drift detected → **refresh mode**.
- `$ARGUMENTS` contains `force` → **force mode**: follow refresh mode but re-derive every field from scratch, and recreate the managed block even if the markers were deleted. Preserve user customizations in the state file (`driftThresholds`, `watchFiles`, `disabled`).

## Bootstrap mode

Lightweight onboard. The recon output inlines manifest excerpts — usually you need zero additional file reads. Read a file only if the excerpts are genuinely insufficient.

1. **Stack identifiers**. From the manifest excerpts, pick the primary stack:
   - JS/TS: name, package manager (`packageManager` field or lockfile present), runtime pin (`engines.node` / `.nvmrc`).
   - Python: project name, Python version pin (`requires-python` / `.python-version`).
   - Rust: crate name, `rust-toolchain.toml` pin.
   - Go: module path, `go` directive version.
   - Other / mixed: the dominant manifest, same idea.

2. **Commands**. From the same excerpts (npm scripts, Make targets, justfile recipes), pick at most 5 that matter: install, build, test, lint, dev/run.

3. **Write the lore-managed block** at the top of CLAUDE.md.

   - If `CLAUDE.md` exists with `<!-- BEGIN lore-managed` and `<!-- END lore-managed -->` markers: replace everything between (and including) the markers.
   - If `CLAUDE.md` exists without lore markers: prepend the managed block (plus one blank line) at the top. Leave all existing content untouched.
   - If `CLAUDE.md` does not exist: create it with the managed block followed by `<!-- Add project-specific instructions below this line. -->` so humans know where to write.
   - If `.claude/CLAUDE.md` exists instead of root-level `CLAUDE.md`, edit that file instead.

   Block format (fill `lore-version` from the recon `=== lore version ===` output, `last-refreshed` from the recon `date:` value, `last-sha` from the recon `head12:` value):

   ```markdown
   <!-- BEGIN lore-managed: do not edit between these markers. Run /lore:refresh to update. -->
   <!-- lore-version: <from recon> -->
   <!-- last-refreshed: YYYY-MM-DD -->
   <!-- last-sha: <head12 from recon, or none> -->

   ## Project
   <name>

   ## Stack
   - <language> <version pin if any>
   - <package manager> (if relevant)
   - <framework> (only if obvious from the manifest)

   ## Commands
   - Install: `...`
   - Build: `...`   (omit if not applicable)
   - Test: `...`
   - Lint: `...`    (omit if not applicable)
   - Dev: `...`     (omit if not applicable)

   <!-- END lore-managed -->
   ```

   Hard rules:
   - Never include a section or field you couldn't confidently determine. Empty rows are worse than missing ones.
   - Never touch content outside the markers.
   - Block stays small: under 40 lines.

4. **Write the state file** at `.claude/lore-state.json` (create `.claude/` if needed). Use the recon `iso:` value for the date and the full HEAD SHA:

   ```json
   {
     "version": 1,
     "loreVersion": "<from recon>",
     "lastRefreshSha": "<full git head sha, or null outside git>",
     "lastRefreshDate": "<iso from recon, format YYYY-MM-DDTHH:MM:SSZ>",
     "repoRoot": "<git root or cwd>",
     "repoRemote": "<git remote origin url, or null>"
   }
   ```

   Do NOT write `watchFiles` or `driftThresholds` — when absent, lore uses built-in defaults that improve with plugin updates. Users add those keys (and `"disabled": true`) only to override; the README documents them.

   Then ensure `.claude/lore-state.json` is gitignored. If `.gitignore` does not already cover it (or all of `.claude/`), append:

   ```

   # lore (per-machine staleness baseline)
   .claude/lore-state.json
   ```

5. **One-line summary**. Example: `Bootstrapped lore for <name> (<stack>). Wrote a managed block to CLAUDE.md and recorded the baseline at <sha12>. Use /init if you want Claude Code to fill out the rest of CLAUDE.md.`

## Refresh mode

State file exists. Be conservative — keep what's still accurate, change only what the change set since `lastRefreshSha` actually affects.

The recon output shows the existing managed block, the commit count, and which watched files changed.

1. **Re-derive only what the changes could affect.**
   - Manifest/lockfile changed → re-check Stack + Commands. Update only fields whose values actually changed.
   - No manifest/config changes → nothing in the block body needs to change; skip to step 3.
   - New top-level manifest appeared (e.g., monorepo grew) → consider adding a Stack line; usually safer to leave alone unless it's the new primary.
   - Recon says `force-rederive` (baseline commit missing) or `$ARGUMENTS` contains `force` → treat every field as potentially stale and re-derive all of them.

2. **Update the managed block**, replacing the content between (and including) the existing markers. Always update `lore-version`, `last-refreshed`, and `last-sha` from the recon output, even if no other field changed. **Never touch content outside the markers.**

   If the markers are missing (someone deleted them): in force mode, recreate the block at the top of the file; otherwise do not silently recreate — tell the user the markers were removed and ask whether to re-insert (re-running with `/lore:refresh force` is the documented path).

3. **Update the state file**: set `lastRefreshSha` to the current full HEAD SHA, `lastRefreshDate` to the recon `iso:` value, `loreVersion` to the recon version. Preserve every other field exactly (including any `driftThresholds`, `watchFiles`, `disabled` the user added). Read the existing JSON first, then write the updated version.

4. **One-line summary**. Example: `Refreshed (18 commits since last refresh). Updated CLAUDE.md Commands (new "test:e2e" script). State bumped to <sha12>.` If nothing in the block body changed: `Refreshed metadata only — managed block fields unchanged. State bumped to <sha12>.` If the recon shows uncommitted changes to a watched manifest, mention it: the block reflects HEAD, not the working tree.

## Edge cases

- **Not a git repo**: bootstrap works without a SHA (write `null`, and `none` in the block comment). Refresh falls back to date-only drift. The recon script handles detection; you just consume its output.
- **CLAUDE.md is a symlink** (e.g., to AGENTS.md): if the target lives inside this repo, edit the target. If outside, write to `.claude/CLAUDE.md` instead and explain in the final summary.

## What NOT to do

- Do not run linters, tests, builds, or installers. Read scripts; do not execute them.
- Do not commit anything.
- Do not enlarge the managed block. Stack + Commands + metadata is the entire scope. Architecture and conventions belong below the managed block, written by the human or by Claude on demand.
- Do not produce long reports. The file changes are the report; the chat summary is one line.
