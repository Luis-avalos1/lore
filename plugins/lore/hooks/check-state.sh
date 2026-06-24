#!/usr/bin/env bash
# lore — SessionStart hook
#
# Runs at session start. Stays silent unless there's something worth saying.
# Plain stdout from a SessionStart hook is added to Claude's context (the model
# reads it and surfaces it to the user), so every echo below is a drift nudge.
# /lore:refresh is user-invocable only (disable-model-invocation), so the nudge
# prompts the user to refresh rather than letting Claude rewrite CLAUDE.md on
# its own.
#
# This script never blocks the session: every exit path is 0.
#
# Ways to silence it:
#   - globally:   touch ~/.claude/lore-disabled
#   - per repo:   touch .claude/lore-disabled
#   - per repo:   set "disabled": true in .claude/lore-state.json
#   - env:        LORE_DISABLE=1
#   - per signal: set a driftThresholds value to 0 in the state file

set -u

[ -n "${LORE_DISABLE:-}" ] && exit 0
[ -f "${HOME:-/nonexistent}/.claude/lore-disabled" ] && exit 0

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || exit 0
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh" 2>/dev/null || exit 0

cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
[ -f .claude/lore-disabled ] && exit 0

STATE=.claude/lore-state.json
BOOTSTRAP_MIN_COMMITS=10

# =================================================================
# BRANCH A — state file exists: check drift, suggest /lore:refresh
# =================================================================
if [ -f "$STATE" ]; then
  state_true "$STATE" disabled && exit 0

  THRESH_COMMITS=$(state_num "$STATE" commits 20)
  THRESH_DAYS=$(state_num "$STATE" days 60)
  LAST_SHA=$(state_str "$STATE" lastRefreshSha)
  LAST_DATE=$(state_str "$STATE" lastRefreshDate)

  # Unreadable or corrupt state: give up silently rather than nagging.
  if [ -z "$LAST_SHA" ] && [ -z "$LAST_DATE" ]; then
    exit 0
  fi

  REASONS=""
  add_reason() { REASONS="${REASONS:+$REASONS; }$1"; }

  if [ -n "$LAST_SHA" ] && in_git_repo; then
    if ! sha_exists "$LAST_SHA"; then
      WHY="history was rewritten since the last refresh (rebase or force-push)"
      is_shallow_repo && WHY="the last-refresh commit isn't present in this shallow clone"
      echo "lore: $WHY. Run /lore:refresh to recompute the baseline."
      exit 0
    elif ! is_ancestor "$LAST_SHA"; then
      # The baseline object still exists but diverged from HEAD's history
      # (rebase/squash/force-push); a BASE..HEAD count would be meaningless.
      echo "lore: the last-refresh commit is no longer on this branch's history (rebase, squash, or force-push). Run /lore:refresh to recompute the baseline."
      exit 0
    fi

    COMMITS=$(count_commits "$LAST_SHA")
    if [ "$THRESH_COMMITS" -gt 0 ] && [ "${COMMITS:-0}" -ge "$THRESH_COMMITS" ]; then
      add_reason "$COMMITS commits"
    fi

    # Even a single commit to a watched manifest is high-signal.
    HITS=$(changed_watch_files "$STATE" "$LAST_SHA" | head -5 | join_commas)
    [ -n "$HITS" ] && add_reason "watched files changed: $HITS"
  fi

  # Time-based drift. Runs even without git or a SHA, so repos bootstrapped
  # outside version control still age out.
  if [ -n "$LAST_DATE" ] && [ "$THRESH_DAYS" -gt 0 ]; then
    DAYS=$(days_since "$LAST_DATE")
    if [ -n "$DAYS" ] && [ "$DAYS" -ge "$THRESH_DAYS" ]; then
      add_reason "$DAYS days"
    fi
  fi

  if [ -n "$REASONS" ]; then
    echo "lore: drift since last refresh ($REASONS). Run /lore:refresh to update the managed block in CLAUDE.md."
  fi
  exit 0
fi

# =================================================================
# BRANCH B — no state file: should we suggest /lore:refresh (bootstrap)?
# Only nudge for "real" software repos to avoid nagging in scratch dirs.
# =================================================================

in_git_repo || exit 0

# Must have some history (filter out brand-new throwaway repos).
COMMITS=$(git rev-list --count HEAD -- . 2>/dev/null || echo 0)
if [ "${COMMITS:-0}" -lt "$BOOTSTRAP_MIN_COMMITS" ]; then
  exit 0
fi

# Must look like a software project (at least one manifest).
HAS_MANIFEST=0
while IFS= read -r f; do
  if [ -n "$f" ] && [ -f "$f" ]; then
    HAS_MANIFEST=1
    break
  fi
done <<EOF
$LORE_MANIFEST_FILES
EOF
if [ "$HAS_MANIFEST" -ne 1 ]; then
  exit 0
fi

# All conditions met: nudge once per session. The model decides whether to act.
CLAUDE_MD=$(find_claude_md)
if has_lore_block "$CLAUDE_MD"; then
  echo "lore: $CLAUDE_MD has a lore-managed block but no local baseline (fresh clone? state is per-machine). Run /lore:refresh to rebuild it, or 'touch .claude/lore-disabled' to opt this repo out."
elif [ -n "$CLAUDE_MD" ]; then
  echo "lore: $CLAUDE_MD exists but lore has no baseline for this repo. Run /lore:refresh to bootstrap a managed block, or 'touch .claude/lore-disabled' to opt this repo out."
else
  echo "lore: no CLAUDE.md yet. Consider /init to generate one, then /lore:refresh to add lore's managed block. (Opt out: touch .claude/lore-disabled)"
fi
exit 0
