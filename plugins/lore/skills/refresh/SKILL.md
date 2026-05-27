---
description: Incrementally update the lore-managed CLAUDE.md block and memory files based on what has changed since the last /lore:learn or /lore:refresh. Use when the SessionStart hook reports drift, after a major refactor, or whenever the user asks lore to update what it knows. Cheaper than re-learning from scratch — only re-reads files that git shows changed.
when_to_use: When a lore state file already exists and the repo has drifted (new commits, modified manifests, new dependencies). Reads the existing lore-managed block and only re-derives what the change set could plausibly affect. If no state file exists, defer to /lore:learn.
allowed-tools: Bash(git *) Bash(jq *) Bash(mkdir *) Bash(ls *) Bash(cat *) Bash(test *) Bash(wc *) Bash(date *) Bash(grep *) Bash(find *) Bash(echo *) Read Write Edit Glob Grep
disable-model-invocation: false
---

# /lore:refresh — incrementally update what lore knows

You are running a *refresh*, not a fresh onboard. Your job is to be conservative: keep what's still accurate, change only what the change set since `lastLearnedSha` actually affects. This is much cheaper than `/lore:learn` because you only touch the files git tells you matter.

If there is no `.claude/lore-state.json`, abort and tell the user to run `/lore:learn` instead.

## Live drift context

```!
echo "=== state file ==="
if test -f .claude/lore-state.json; then
  cat .claude/lore-state.json
else
  echo "NO_STATE"
fi
echo
echo "=== current HEAD ==="
git rev-parse HEAD 2>/dev/null || echo "(not a git repo)"
git rev-parse --abbrev-ref HEAD 2>/dev/null
echo
echo "=== changes since lastLearnedSha ==="
LAST_SHA="$(jq -r '.lastLearnedSha // empty' .claude/lore-state.json 2>/dev/null)"
if [ -n "$LAST_SHA" ] && git cat-file -e "$LAST_SHA" 2>/dev/null; then
  echo "commits: $(git rev-list --count "$LAST_SHA"..HEAD 2>/dev/null)"
  echo "--- changed files ---"
  git diff --name-only "$LAST_SHA"..HEAD 2>/dev/null | head -100
  echo "--- changed watch files ---"
  jq -r '.watchFiles[]' .claude/lore-state.json 2>/dev/null | while read -r wf; do
    git diff --name-only "$LAST_SHA"..HEAD 2>/dev/null | grep -Fx "$wf" && echo "    ^ watch file changed"
  done
elif [ -n "$LAST_SHA" ]; then
  echo "lastLearnedSha not reachable from current branch (rebase/squash?). Falling back to full diff vs working tree."
  git status --short 2>/dev/null | head -50
else
  echo "(no lastLearnedSha — was learned outside a git repo)"
fi
echo
echo "=== existing CLAUDE.md lore block ==="
if test -f CLAUDE.md; then
  awk '/<!-- BEGIN lore-managed/,/<!-- END lore-managed/' CLAUDE.md
elif test -f .claude/CLAUDE.md; then
  awk '/<!-- BEGIN lore-managed/,/<!-- END lore-managed/' .claude/CLAUDE.md
else
  echo "(no CLAUDE.md found — run /lore:learn first)"
fi
echo
echo "=== memory dir contents ==="
MEM="$(jq -r '.memoryDir // empty' .claude/lore-state.json 2>/dev/null)"
[ -n "$MEM" ] && ls -1 "$MEM" 2>/dev/null || echo "(memory dir missing — refresh will recreate)"
```

## Decide what to update

Read the live context above before doing anything. Three possibilities:

1. **No state file** (`NO_STATE` in the output above) → stop. Tell the user: "No lore state for this repo yet. Run `/lore:learn` first." Don't write anything.

2. **No drift** (zero commits since lastLearnedSha *and* zero watch files changed) → don't touch CLAUDE.md or memory files. Just bump `lastLearnedDate` in the state file (so the staleness clock resets) and tell the user "Nothing has changed since last learn." Two-sentence reply max.

3. **Drift detected** → proceed with phases below. Re-derive only what the change set affects:
   - Manifest/lockfile changed → re-derive **Stack** and **Commands** sections of the CLAUDE.md block
   - README changed → re-derive the project purpose line (if you had one)
   - New top-level directory created → update **Layout**
   - Many source-file changes but no manifest changes → likely no CLAUDE.md change needed; just append to `lore-history.md`
   - `.eslintrc*`, `.prettierrc*`, `rustfmt.toml`, etc. changed → re-derive **Conventions**

Be precise about scope. If only `src/feature-x/foo.ts` changed, you probably don't need to touch CLAUDE.md at all. The point of refresh is to *avoid* re-reading the whole repo.

## Phase 1 — Targeted reconnaissance

Only do the reconnaissance steps relevant to what changed. Examples:

- If `package.json` changed: Read `package.json`, diff the `scripts` and primary deps against the existing CLAUDE.md block. Update only if the user-facing commands or stack actually changed (a new transitive dep is not a stack change).
- If `pyproject.toml` changed: same, but for Python tooling and entry points.
- If a new top-level dir appeared: Glob inside it once to see what's there. Update the Layout section.
- If a CI config changed: usually no CLAUDE.md change — but worth a one-line note in `lore-history.md`.

Use Read sparingly. Use Glob and Grep first.

## Phase 2 — Update the CLAUDE.md lore block

Locate the existing block by its `<!-- BEGIN lore-managed` … `<!-- END lore-managed -->` markers. Use Edit (not Write) to replace only the content between (and including) those markers.

When you write the new block:

- Update the `last-learned:` and `last-sha:` HTML comments to today's date and the current HEAD.
- Keep field values you didn't verify this run *if* you still believe them. The principle: changes from your reconnaissance overwrite; otherwise carry forward.
- If the block is missing entirely (someone deleted it), do not recreate it from scratch here — tell the user to run `/lore:learn`.

Hard rule: **never touch content outside the markers.** The user may have hand-edited the rest of CLAUDE.md since last learn.

## Phase 3 — Update memory

The memory directory is at the `memoryDir` field in the state file. Three updates, in this order:

1. **`lore-history.md`** — append a new dated entry summarizing this refresh. Format:

   ```markdown
   ## YYYY-MM-DD — refresh
   - From: <oldSha[:8]> → To: <newSha[:8]> (<N> commits)
   - Changed manifests: ...
   - CLAUDE.md updated sections: <Stack | Commands | Layout | Conventions | none>
   - Notes: <anything you observed that doesn't belong in CLAUDE.md>
   ```

2. **`lore-architecture.md`** — only edit if architectural surface changed (new top-level package, new service, removed module). Otherwise leave alone.

3. **`lore-gotchas.md`** — only edit if you observed something specifically worth flagging (e.g., a comment in a changed file that warns "do not edit without reading X", or a TODO marked "BLOCKED:"). Don't manufacture gotchas.

4. **`MEMORY.md`** — only touch if you added a brand-new topic file (then add a line to the index). Otherwise leave alone.

## Phase 4 — Update the state file

Rewrite `.claude/lore-state.json` with:
- `lastLearnedSha`: current HEAD (or null if not git)
- `lastLearnedDate`: now (ISO 8601 UTC)
- Everything else: preserved from the existing state file

Use Read to load the existing JSON, then Write to overwrite with the updated version (preserving fields you didn't change, especially `repoRoot`, `repoRemote`, `memoryDir`, `watchFiles`, `driftThresholds`).

## Phase 5 — Final summary

One or two sentences. State what you changed and what you left alone. Example:

> Refreshed (18 commits since last learn). Updated CLAUDE.md Commands section (new `pnpm typecheck` script) and appended to lore-history. Architecture and gotchas unchanged.

## Edge cases

- **lastLearnedSha unreachable** (rebased/squashed): fall back to comparing working-tree state against the existing CLAUDE.md block. Treat all watch files as potentially changed.
- **Repo no longer a git repo** (e.g., user deleted `.git`): warn in the summary; refresh using mtime + content comparison only.
- **State file references a memory dir that doesn't exist**: recreate the dir and the standard files (MEMORY.md, lore-architecture.md, lore-gotchas.md, lore-history.md), then proceed.
- **CLAUDE.md exists but lore block is gone**: tell the user the lore block was removed; ask whether to re-insert it (don't do it automatically — they may have removed it on purpose).

## What NOT to do

- Do not re-do the full Phase-1 reconnaissance from `/lore:learn`. That's wasteful.
- Do not rewrite memory files that didn't change.
- Do not run any commands beyond what you need for reconnaissance.
- Do not silently change watchFiles or driftThresholds. Those are state-file fields, not part of refresh.
