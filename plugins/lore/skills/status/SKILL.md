---
description: Show what lore knows about this repository and whether it has drifted since the last learn or refresh. Use when the user asks "what does lore know", "is lore up to date", or to inspect the lore state file and memory inventory.
when_to_use: Quick read-only inspection. Reports last-learn date, current drift (commits, watch files), and the inventory of memory topic files. Does not modify anything.
allowed-tools: Bash(git *) Bash(jq *) Bash(ls *) Bash(cat *) Bash(test *) Bash(wc *) Bash(date *) Bash(stat *) Read
disable-model-invocation: false
---

# /lore:status — what does lore know?

This is a **read-only** status report. Do not write any files. Do not modify CLAUDE.md, the memory directory, or the state file. Just gather the facts and present them concisely.

## Live status

```!
set -u
echo "=== state ==="
if test -f .claude/lore-state.json; then
  echo "(state file present)"
  cat .claude/lore-state.json
else
  echo "NO_STATE — lore has not learned this repo. Run /lore:learn."
fi
echo
echo "=== drift ==="
if test -f .claude/lore-state.json; then
  LAST_SHA="$(jq -r '.lastLearnedSha // empty' .claude/lore-state.json 2>/dev/null)"
  LAST_DATE="$(jq -r '.lastLearnedDate // empty' .claude/lore-state.json 2>/dev/null)"
  if [ -n "$LAST_SHA" ] && git cat-file -e "$LAST_SHA" 2>/dev/null; then
    COMMITS="$(git rev-list --count "$LAST_SHA"..HEAD 2>/dev/null)"
    echo "commits since last learn: $COMMITS"
    if [ "$COMMITS" != "0" ]; then
      echo "--- changed files (truncated) ---"
      git diff --name-only "$LAST_SHA"..HEAD 2>/dev/null | head -30
      echo "--- watch files in change set ---"
      jq -r '.watchFiles[]' .claude/lore-state.json 2>/dev/null | while read -r wf; do
        git diff --name-only "$LAST_SHA"..HEAD 2>/dev/null | grep -Fx "$wf" && echo "    (watched)"
      done
    fi
  elif [ -n "$LAST_SHA" ]; then
    echo "lastLearnedSha not reachable (rebase/squash). Drift cannot be computed precisely."
  else
    echo "(not a git repo — drift based on date only)"
  fi
  echo
  if [ -n "$LAST_DATE" ]; then
    NOW_EPOCH=$(date -u +%s)
    # Try GNU then BSD date parsing
    LAST_EPOCH=$(date -u -d "$LAST_DATE" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_DATE" +%s 2>/dev/null || echo "")
    if [ -n "$LAST_EPOCH" ]; then
      DAYS=$(( (NOW_EPOCH - LAST_EPOCH) / 86400 ))
      echo "days since last learn: $DAYS"
    fi
  fi
fi
echo
echo "=== claude.md ==="
for f in CLAUDE.md .claude/CLAUDE.md; do
  if test -f "$f"; then
    if grep -q "BEGIN lore-managed" "$f"; then
      echo "$f: has lore-managed block"
      grep -E "^<!-- (lore-version|last-learned|last-sha):" "$f"
    else
      echo "$f: present, no lore-managed block"
    fi
  fi
done
echo
echo "=== memory ==="
if test -f .claude/lore-state.json; then
  MEM="$(jq -r '.memoryDir // empty' .claude/lore-state.json 2>/dev/null)"
  if [ -n "$MEM" ] && test -d "$MEM"; then
    echo "dir: $MEM"
    ls -lh "$MEM" 2>/dev/null | awk 'NR>1 {print "  " $9, "(" $5 ")"}' | head -20
  else
    echo "(memory dir not found at $MEM)"
  fi
fi
```

## How to present this

Look at the live output above and answer in a tight format. No headers, no tables — three or four short lines.

If `NO_STATE`:
> No lore state yet for this repo. Run `/lore:learn` to seed CLAUDE.md and memory.

If state exists, no drift:
> Lore last learned <DATE> at <SHA[:8]>. No drift detected. Memory has <N> files at `<memoryDir>`.

If state exists, drift detected:
> Lore last learned <DATE> at <SHA[:8]>. Drifted: <X> commits, <Y> watch files changed. Run `/lore:refresh` to catch up.

Add a fourth line ONLY if something looks off (e.g., CLAUDE.md exists but lore block is gone; state file references a missing memory dir). One sentence each.

## Do not

- Do not write any files.
- Do not run git commands beyond the ones already in the live context above. The context contains everything needed.
- Do not produce a long report. The user wants a glance, not a deep dive — they'll run `/lore:refresh` if they want details.
