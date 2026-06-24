---
description: Refresh lore's managed block at the top of CLAUDE.md — stack, commands, version pins, and last-refresh metadata — against the current HEAD. First run bootstraps a baseline; later runs re-derive only what git shows changed.
when_to_use: Run when the SessionStart hook reports drift, after a dependency bump or major refactor, or to re-bless CLAUDE.md against HEAD. Bootstrap (no state file) or incremental refresh (state file + drift). Never touches content outside the markers.
argument-hint: "[force]"
disable-model-invocation: true
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

The recon `=== existing CLAUDE.md lore block ===` section reports a `state:` of `create`, `insert`, `replace`, or `malformed`. **If it says `malformed`** (unbalanced or duplicate markers), STOP — do not edit CLAUDE.md. Tell the user to fix the markers by hand; the writer will refuse anyway.

## Bootstrap mode

Lightweight onboard. The recon output inlines manifest excerpts — usually you need zero additional file reads. Read a file only if the excerpts are genuinely insufficient.

1. **Stack identifiers**. From the manifest excerpts, pick the primary stack:
   - JS/TS: name, package manager (`packageManager` field or lockfile present), runtime pin (`engines.node` / `.nvmrc`).
   - Python: project name, Python version pin (`requires-python` / `.python-version`).
   - Rust: crate name, `rust-toolchain.toml` pin.
   - Go: module path, `go` directive version.
   - Other / mixed: the dominant manifest, same idea.

2. **Commands**. From the same excerpts (npm scripts, Make targets, justfile recipes), pick at most 5 that matter: install, build, test, lint, dev/run.

3. **Write the block with the bundled writer.** Do NOT hand-edit CLAUDE.md. Pipe the block *body* (the metadata comments and the sections — but NOT the `BEGIN`/`END` marker lines, which the writer adds) to `apply-block.sh`:

   ```bash
   bash "${CLAUDE_SKILL_DIR}/../../lib/apply-block.sh" apply CLAUDE.md <<'LORE_BODY'
   <!-- lore-version: <recon "=== lore version ===" output> -->
   <!-- last-refreshed: <recon date: value, YYYY-MM-DD> -->
   <!-- last-sha: <recon head12: value, or none outside git> -->

   ## Project
   <name>

   ## Stack
   - <language> <version pin if any>
   - <package manager> (if relevant)
   - <framework> (only if obvious from the manifest)

   ## Commands
   - Install: `...`
   - Test: `...`
   - Build: `...`   (omit if not applicable)
   - Lint: `...`    (omit if not applicable)
   - Dev: `...`     (omit if not applicable)
   LORE_BODY
   ```

   The writer owns the markers and performs an atomic, byte-preserving splice — you supply only the body. It creates CLAUDE.md if missing, prepends the block (plus one blank line) if the file has no markers, or replaces an existing block in place; content outside the markers is left untouched. Target the path recon reported — root `CLAUDE.md`, or `.claude/CLAUDE.md` if that is the one that exists. **If the writer exits non-zero** (malformed/duplicate markers), STOP and tell the user — do not retry or hand-edit.

   Hard rules:
   - Never include a section or field you couldn't confidently determine. Empty rows are worse than missing ones.
   - The body must NOT contain `BEGIN`/`END` marker lines — the writer adds them, and a body that includes them is rejected.
   - Block stays small: under 40 lines. Architecture and prose belong below it, written by the human.

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

2. **Write the updated block** with the bundled writer — the same `apply-block.sh apply` command as bootstrap step 3. Re-emit the full body: keep fields that are still accurate, change only what the change set affects, and always refresh `lore-version`, `last-refreshed`, and `last-sha` from the recon output even if nothing else changed. The writer replaces the block in place and preserves every byte outside the markers. Branch on the recon `state:`:

   - `replace` → normal in-place update.
   - `insert` (markers were deleted) → in non-force mode, do NOT recreate silently: tell the user the markers were removed and that `/lore:refresh force` will re-insert them. In force mode, run the writer (it prepends a fresh block).
   - `malformed` (unbalanced/duplicate markers) → STOP. Do not edit. Tell the user to fix the markers by hand; the writer refuses this state even in force mode.

3. **Update the state file**: set `lastRefreshSha` to the current full HEAD SHA, `lastRefreshDate` to the recon `iso:` value, `loreVersion` to the recon version. Preserve every other field exactly (including any `driftThresholds`, `watchFiles`, `disabled` the user added). Read the existing JSON first, then write the updated version.

4. **One-line summary**. Example: `Refreshed (18 commits since last refresh). Updated CLAUDE.md Commands (new "test:e2e" script). State bumped to <sha12>.` If nothing in the block body changed: `Refreshed metadata only — managed block fields unchanged. State bumped to <sha12>.` If the recon shows uncommitted changes to a watched manifest, mention it: the block reflects HEAD, not the working tree.

## Edge cases

- **Not a git repo**: bootstrap works without a SHA (write `null`, and `none` in the block comment). Refresh falls back to date-only drift. The recon script handles detection; you just consume its output.
- **CLAUDE.md is a symlink** (e.g., to AGENTS.md): the writer follows the link and edits the target in place, keeping the symlink intact — you don't need to resolve it. If the target lives outside the repo and you'd rather keep lore's block local, point the writer at `.claude/CLAUDE.md` instead and say so in the summary.
- **CRLF or unusual whitespace**: the writer preserves the file's existing line endings and trailing-newline state. Do not try to normalize anything.

## What NOT to do

- Do not run linters, tests, builds, or installers. Read scripts; do not execute them.
- Do not commit anything.
- Do not enlarge the managed block. Stack + Commands + metadata is the entire scope. Architecture and conventions belong below the managed block, written by the human or by Claude on demand.
- Do not produce long reports. The file changes are the report; the chat summary is one line.
