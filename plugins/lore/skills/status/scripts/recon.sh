#!/usr/bin/env bash
# Status snapshot for /lore:status. Read-only: this script never writes.
# Uses the same shared helpers as the SessionStart hook, so what status
# reports and what the hook nudges about can't disagree.

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || exit 0
# shellcheck source=../../../lib/common.sh
. "$SCRIPT_DIR/../../../lib/common.sh" 2>/dev/null || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || true

STATE=.claude/lore-state.json

echo "=== state ==="
if [ -f "$STATE" ]; then
  echo "(state file present)"
  cat "$STATE"
  echo
else
  echo "NO_STATE"
fi
echo
echo "=== drift ==="
if [ ! -f "$STATE" ]; then
  echo "(no state — run /lore:refresh to bootstrap)"
else
  if state_true "$STATE" disabled; then
    echo "note: nudges disabled for this repo (\"disabled\": true in state file)"
  fi
  THRESH_COMMITS=$(state_num "$STATE" commits 20)
  THRESH_DAYS=$(state_num "$STATE" days 60)
  THRESH_SRC="defaults"
  state_has_key "$STATE" driftThresholds && THRESH_SRC="from state file"
  echo "thresholds: ${THRESH_COMMITS} commits / ${THRESH_DAYS} days ($THRESH_SRC; 0 disables a signal)"

  LAST_SHA=$(state_str "$STATE" lastRefreshSha)
  LAST_DATE=$(state_str "$STATE" lastRefreshDate)

  if [ -n "$LAST_SHA" ] && in_git_repo; then
    if sha_exists "$LAST_SHA"; then
      COMMITS=$(count_commits "$LAST_SHA")
      echo "commits since last refresh: $COMMITS"
      HITS=$(changed_watch_files "$STATE" "$LAST_SHA" | join_commas)
      echo "watch files changed: ${HITS:-none}"
    elif is_shallow_repo; then
      echo "lastRefreshSha not present in this shallow clone. Drift cannot be computed precisely."
    else
      echo "lastRefreshSha not reachable (rebase/squash). Drift cannot be computed precisely."
    fi
  elif [ -n "$LAST_SHA" ]; then
    echo "(git unavailable — drift based on date only)"
  else
    echo "(not bootstrapped in a git repo — drift based on date only)"
  fi

  if [ -n "$LAST_DATE" ]; then
    DAYS=$(days_since "$LAST_DATE")
    [ -n "$DAYS" ] && echo "days since last refresh: $DAYS"
  fi
fi
echo
echo "=== claude.md ==="
APPLY="$SCRIPT_DIR/../../../lib/apply-block.sh"
FOUND_ANY=0
for f in CLAUDE.md .claude/CLAUDE.md; do
  if [ -f "$f" ]; then
    FOUND_ANY=1
    STATE=$(bash "$APPLY" status "$f" 2>/dev/null | sed -n 's/^state: //p' | head -1)
    if [ "$STATE" = malformed ]; then
      echo "$f: lore markers are MALFORMED (unbalanced or duplicated) — /lore:refresh force needed"
    elif has_lore_block "$f"; then
      echo "$f: has lore-managed block"
      grep -E '^<!-- (lore-version|last-refreshed|last-sha):' "$f" 2>/dev/null
    else
      echo "$f: present, no lore-managed block"
    fi
  fi
done
if [ "$FOUND_ANY" -eq 0 ]; then
  echo "(no CLAUDE.md)"
fi
exit 0
