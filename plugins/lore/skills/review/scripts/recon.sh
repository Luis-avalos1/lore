#!/usr/bin/env bash
# Live context for /lore:review — a model-driven audit of the HUMAN PROSE of
# CLAUDE.md for staleness. Read-only: this script never writes.
#
# It pre-computes cheap facts (which CLAUDE.md, its length, the exact line
# range of the lore-managed block that is OFF LIMITS, a deterministic dead-ref
# pre-scan, and repo context) and inlines the whole file, so the model can
# judge staleness and propose prose edits without extra reads.

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || exit 0
# shellcheck source=../../../lib/common.sh
. "$SCRIPT_DIR/../../../lib/common.sh" 2>/dev/null || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || true

echo "=== now / lore version ==="
echo "iso: $(now_iso)"
echo "date: $(today_utc)"
echo "lore-version: $(lore_version)"
echo

echo "=== claude.md ==="
CLAUDE_MD=$(find_claude_md)
if [ -z "$CLAUDE_MD" ]; then
  echo "(no CLAUDE.md — nothing to review; tell the user and stop)"
else
  LINES=$(wc -l <"$CLAUDE_MD" | tr -d ' ')
  echo "file: $CLAUDE_MD ($LINES lines)"
  APPLY="$SCRIPT_DIR/../../../lib/apply-block.sh"
  ST=$(bash "$APPLY" status "$CLAUDE_MD" 2>/dev/null)
  STATE=$(printf '%s\n' "$ST" | sed -n 's/^state: //p' | head -1)
  case "$STATE" in
    replace)
      RANGE=$(printf '%s\n' "$ST" | sed -n 's/^block: //p' | head -1)
      echo "managed block: lines $RANGE — DO NOT EDIT these (that is /lore:refresh territory)"
      ;;
    malformed)
      echo "managed block: MALFORMED markers — do not edit the file; tell the user to run /lore:refresh force"
      ;;
    *)
      echo "managed block: none — the whole file is human prose, all reviewable"
      ;;
  esac
fi
echo

echo "=== dead prose refs (deterministic pre-scan) ==="
if [ -n "$CLAUDE_MD" ] && type claude_md_dead_refs >/dev/null 2>&1; then
  DEAD=$(claude_md_dead_refs "$CLAUDE_MD")
  if [ -n "$DEAD" ]; then
    printf '%s\n' "$DEAD"
  else
    echo "(none detected)"
  fi
  echo "(pre-scan only — verify each, and look for staleness the scanner can't see)"
else
  echo "(none detected)"
fi
echo

echo "=== repo context ==="
echo "--- top-level ---"
# shellcheck disable=SC2012  # display-only listing, never parsed
ls -A1 2>/dev/null | head -40
echo
if in_git_repo; then
  echo "head: $(git rev-parse --short=12 HEAD 2>/dev/null)"
  echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "--- recent history ---"
  git log --oneline -15 2>/dev/null
else
  echo "(not a git repo)"
fi
echo

echo "=== full CLAUDE.md ==="
if [ -z "$CLAUDE_MD" ]; then
  echo "(no CLAUDE.md)"
else
  head -400 "$CLAUDE_MD" 2>/dev/null
  TOTAL=$(wc -l <"$CLAUDE_MD" | tr -d ' ')
  [ "${TOTAL:-0}" -gt 400 ] && echo "... (truncated at 400 lines; $TOTAL total — Read the rest before editing past line 400)"
fi

exit 0
