---
description: Keep a small lore-managed block at the top of CLAUDE.md fresh as the repo evolves. First run sets a baseline; later runs only re-derive what git shows changed. Use when the SessionStart hook reports drift, after a dependency bump or major refactor, or whenever the user wants CLAUDE.md re-blessed against the current HEAD.
when_to_use: First-run bootstrap (no state file) or incremental refresh (state file + drift detected). Manages a small section of CLAUDE.md — stack identifiers, commands, version pins, last-refresh metadata. Never touches content outside the markers.
allowed-tools: Bash(bash *) Bash(git *) Bash(jq *) Bash(mkdir *) Bash(ls *) Bash(cat *) Bash(test *) Bash(wc *) Bash(date *) Bash(grep *) Bash(find *) Bash(echo *) Bash(sed *) Bash(awk *) Read Write Edit Glob Grep
disable-model-invocation: false
---

# /lore:refresh — keep CLAUDE.md fresh against drift

lore is small on purpose. Its only job is to keep a tiny block at the top of `CLAUDE.md` synced with what's actually in the repo, and to notice when that block has gone stale. Architecture, conventions, and prose stay human-curated below.

This skill has two modes, picked automatically based on whether a state file exists:

- **Bootstrap** (`.claude/lore-state.json` does not exist): light reconnaissance, write a small lore-managed block at the top of CLAUDE.md, write the state file at the current SHA. Bootstrap is intentionally lean — use `/init` first if you want a full Claude Code-generated CLAUDE.md; lore only manages the small block.
- **Refresh** (state file exists, repo has drifted): re-derive only the fields the change set affects, update the managed block in place, bump the state file SHA.

## Live drift context

A bundled recon script runs before you see this skill. Use its output instead of re-running its commands.

!`bash "${CLAUDE_SKILL_DIR}/scripts/recon.sh"`

## Decide which mode

Look at the live output above before doing anything.

- `=== state file ===` shows `NO_STATE` → **bootstrap mode**, jump to Bootstrap below.
- State file present, zero commits + no changed watch files → **no-op mode**, just bump `lastRefreshDate` and tell the user "Nothing has changed since the last refresh." Two sentences max.
- State file present, drift detected → **refresh mode**, jump to Refresh below.

## Bootstrap mode

Lightweight onboard. Aim for under 5 file reads total.

1. **Stack identifiers**. From the manifest list in the recon output, pick the primary one:
   - JS/TS: Read `package.json` → name, package manager (`packageManager` field or lockfile signal), runtime pin (`engines.node` or `.nvmrc`).
   - Python: Read `pyproject.toml` or `requirements.txt` → project name, Python version pin.
   - Rust: Read `Cargo.toml` → name, rust-toolchain pin.
   - Go: Read `go.mod` → module path, go version.
   - Other / mixed: pick the dominant manifest, do the same.

2. **Commands**. From the same manifest, extract user-facing scripts (npm scripts, Make targets, justfile, poetry scripts). Pick at most 5 that matter: install, build, test, lint, dev/run.

3. **Write the lore-managed block** at the top of CLAUDE.md.

   - If `CLAUDE.md` exists with `<!-- BEGIN lore-managed` and `<!-- END lore-managed -->` markers: replace the content between (and including) those markers via `Edit`.
   - If `CLAUDE.md` exists without lore markers: use `Edit` to **prepend** the new managed block (plus one blank line) at the top of the file. Leave all existing content untouched.
   - If `CLAUDE.md` does not exist: create it with the managed block followed by a comment line `<!-- Add project-specific instructions below this line. -->` so humans know where to write.
   - If `.claude/CLAUDE.md` exists instead of root-level `CLAUDE.md`, edit that file instead.

   Block format:

   ```markdown
   <!-- BEGIN lore-managed: do not edit between these markers. Run /lore:refresh to update. -->
   <!-- lore-version: 0.2.0 -->
   <!-- last-refreshed: YYYY-MM-DD -->
   <!-- last-sha: <git head sha> -->

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
   - Block stays small. Aim for under 40 lines.

4. **Write the state file** at `.claude/lore-state.json` (create `.claude/` if needed). Schema:

   ```json
   {
     "version": 1,
     "loreVersion": "0.2.0",
     "lastRefreshSha": "<git head sha or null>",
     "lastRefreshDate": "<ISO 8601 UTC>",
     "repoRoot": "<git root or cwd>",
     "repoRemote": "<git remote origin url or null>",
     "watchFiles": [
       "package.json", "pnpm-lock.yaml", "yarn.lock", "package-lock.json",
       "pyproject.toml", "requirements.txt", "poetry.lock",
       "Cargo.toml", "Cargo.lock",
       "go.mod", "go.sum",
       "README.md", "ARCHITECTURE.md",
       "Dockerfile", "docker-compose.yml",
       "Makefile", "justfile"
     ],
     "driftThresholds": { "commits": 20, "days": 60 }
   }
   ```

   Then ensure `.claude/lore-state.json` is gitignored. If `.gitignore` does not already cover it (or all of `.claude/`), append a section:

   ```
   
   # lore
   .claude/lore-state.json
   ```

5. **One-line summary**. Example: `Bootstrapped lore for <name> (<stack>). Wrote a managed block to CLAUDE.md and recorded the baseline at <sha[:8]>. Use /init if you want Claude Code to fill out the rest of CLAUDE.md.`

## Refresh mode

State file exists. Be conservative — keep what's still accurate, change only what the change set since `lastRefreshSha` actually affects.

Use the recon output to see:
- The existing lore-managed block (so you know the current values)
- What files changed since `lastRefreshSha`

Then:

1. **Re-derive only what the changes could affect.**
   - Manifest/lockfile changed → re-check Stack + Commands. Update only fields whose values actually changed.
   - No manifest/config changes → likely nothing in the managed block needs to change. Skip to step 3.
   - New top-level manifest appeared (e.g., monorepo grew) → consider adding a Stack line; usually safer to leave alone unless it's the new primary.

2. **Update the managed block** via `Edit`, replacing the content between the existing `<!-- BEGIN lore-managed` and `<!-- END lore-managed -->` markers. Always update `last-refreshed` and `last-sha` even if no fields changed. **Never touch content outside the markers.**

   If the markers are missing (someone deleted them), do not silently recreate them. Tell the user the markers were removed and ask whether to re-insert.

3. **Update the state file**: bump `lastRefreshSha` to current HEAD, `lastRefreshDate` to now. Preserve all other fields. Read the existing JSON first, then write the updated version.

4. **One-line summary**. Example: `Refreshed (18 commits since last refresh). Updated CLAUDE.md Commands (new "test:e2e" script). State bumped to <sha[:8]>.` If nothing in the block changed, say so: `Refreshed metadata only — managed block fields unchanged. State bumped to <sha[:8]>.`

## Edge cases

- **Not a git repo**: bootstrap works without a SHA (use `null`). Refresh falls back to date-only drift checks. The recon script handles this; you just consume its output.
- **`lastRefreshSha` not reachable** (history rewritten): refresh in "force-rederive" mode — treat all watch files as potentially changed.
- **CLAUDE.md is a symlink** (e.g., to AGENTS.md): if the target lives inside this repo, edit the target. If outside, write to `.claude/CLAUDE.md` instead and explain in the final summary.

## What NOT to do

- Do not run linters, tests, builds, or installers. Read scripts; do not execute them.
- Do not commit anything.
- Do not enlarge the managed block. Stack + Commands + metadata is the entire scope. Architecture and conventions belong below the managed block, written by the human or by Claude on demand.
- Do not produce long reports. The file changes are the report; the chat summary is one line.
