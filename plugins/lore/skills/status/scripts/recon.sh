#!/usr/bin/env bash
# Status snapshot for /lore:status. Read-only. No writes.

set -u

STATE=.claude/lore-state.json

echo "=== state ==="
if [ -f "$STATE" ]; then
  echo "(state file present)"
  cat "$STATE"
else
  echo "NO_STATE"
fi
echo
echo "=== drift ==="
if [ ! -f "$STATE" ]; then
  echo "(no state — run /lore:refresh to bootstrap)"
else
  if command -v jq >/dev/null 2>&1; then
    LAST_SHA=$(jq -r '.lastRefreshSha // empty' "$STATE" 2>/dev/null)
    LAST_DATE=$(jq -r '.lastRefreshDate // empty' "$STATE" 2>/dev/null)
  else
    LAST_SHA=$(grep -E '"lastRefreshSha"[[:space:]]*:' "$STATE" 2>/dev/null \
      | head -1 \
      | sed -E 's/.*"lastRefreshSha"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
    LAST_DATE=$(grep -E '"lastRefreshDate"[[:space:]]*:' "$STATE" 2>/dev/null \
      | head -1 \
      | sed -E 's/.*"lastRefreshDate"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  fi

  if [ -n "$LAST_SHA" ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git cat-file -e "$LAST_SHA" 2>/dev/null; then
    COMMITS=$(git rev-list --count "$LAST_SHA"..HEAD 2>/dev/null || echo 0)
    echo "commits since last refresh: $COMMITS"
    if [ "${COMMITS:-0}" != "0" ]; then
      echo "--- changed files (truncated) ---"
      git diff --name-only "$LAST_SHA"..HEAD 2>/dev/null | head -30
    fi
  elif [ -n "$LAST_SHA" ]; then
    echo "lastRefreshSha not reachable (rebase/squash). Drift cannot be computed precisely."
  else
    echo "(not a git repo — drift based on date only)"
  fi
  echo
  if [ -n "$LAST_DATE" ]; then
    NOW=$(date -u +%s)
    THEN=$(date -u -d "$LAST_DATE" +%s 2>/dev/null \
      || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_DATE" +%s 2>/dev/null \
      || echo "")
    if [ -n "$THEN" ]; then
      DAYS=$(( (NOW - THEN) / 86400 ))
      echo "days since last refresh: $DAYS"
    fi
  fi
fi
echo
echo "=== claude.md ==="
found_any=0
for f in CLAUDE.md .claude/CLAUDE.md; do
  if [ -f "$f" ]; then
    found_any=1
    if grep -q "BEGIN lore-managed" "$f" 2>/dev/null; then
      echo "$f: has lore-managed block"
      grep -E "^<!-- (lore-version|last-refreshed|last-sha):" "$f"
    else
      echo "$f: present, no lore-managed block"
    fi
  fi
done
[ "$found_any" -eq 0 ] && echo "(no CLAUDE.md)"
