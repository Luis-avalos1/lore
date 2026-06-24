#!/usr/bin/env bash
# Live context for /lore:refresh. Handles both bootstrap (no state file)
# and refresh (state file + drift). Read-only: this script never writes.
#
# In bootstrap mode it inlines short excerpts of the manifests it finds, so
# the model can usually fill the managed block without any extra file reads.

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || exit 0
# shellcheck source=../../../lib/common.sh
. "$SCRIPT_DIR/../../../lib/common.sh" 2>/dev/null || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || true

STATE=.claude/lore-state.json

# excerpt FILE LINES — print the first LINES lines of FILE, labeled.
excerpt() {
  [ -f "$1" ] || return 0
  echo "--- $1 (first $2 lines) ---"
  head -n "$2" "$1" 2>/dev/null
  echo
}

echo "=== now (UTC) ==="
echo "iso: $(now_iso)"
echo "date: $(today_utc)"
echo
echo "=== lore version ==="
lore_version
echo
echo "=== state file ($STATE) ==="
if [ -f "$STATE" ]; then
  cat "$STATE"
  echo
else
  echo "NO_STATE"
fi
echo
echo "=== git ==="
if in_git_repo; then
  echo "head: $(git rev-parse HEAD 2>/dev/null)"
  echo "head12: $(git rev-parse --short=12 HEAD 2>/dev/null)"
  echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  is_shallow_repo && echo "note: shallow clone"
  DIRTY=$(git status --short 2>/dev/null | head -15)
  if [ -n "$DIRTY" ]; then
    echo "--- uncommitted changes (working tree) ---"
    printf '%s\n' "$DIRTY"
  fi
else
  echo "(not a git repo)"
fi
echo

if [ ! -f "$STATE" ]; then
  # ---------- BOOTSTRAP CONTEXT ----------
  echo "=== bootstrap context (no state file yet) ==="
  echo
  echo "--- top-level ---"
  # shellcheck disable=SC2012  # display-only listing, never parsed
  ls -A1 2>/dev/null | head -40
  echo
  echo "--- manifests present ---"
  for f in \
    package.json pnpm-workspace.yaml pnpm-lock.yaml yarn.lock package-lock.json bun.lock bun.lockb turbo.json \
    pyproject.toml requirements.txt poetry.lock uv.lock Pipfile setup.py \
    Cargo.toml go.mod pom.xml \
    build.gradle build.gradle.kts settings.gradle settings.gradle.kts \
    Gemfile composer.json mix.exs deno.json \
    Dockerfile docker-compose.yml compose.yaml \
    Makefile justfile flake.nix CMakeLists.txt \
    .nvmrc .python-version .tool-versions mise.toml rust-toolchain.toml; do
    [ -f "$f" ] && echo "  $f"
  done
  echo
  echo "--- manifest excerpts ---"
  if [ -f package.json ]; then
    if have_jq; then
      echo "--- package.json (name/engines/packageManager/scripts) ---"
      jq '{name, version, packageManager, engines, scripts} | with_entries(select(.value != null))' package.json 2>/dev/null | head -40
      echo
    else
      excerpt package.json 40
    fi
  fi
  excerpt pyproject.toml 40
  excerpt Cargo.toml 20
  excerpt go.mod 10
  excerpt Gemfile 15
  excerpt composer.json 25
  excerpt mix.exs 20
  excerpt deno.json 25
  for f in .nvmrc .python-version .tool-versions rust-toolchain.toml; do
    if [ -f "$f" ]; then
      echo "--- $f ---"
      head -5 "$f" 2>/dev/null
      echo
    fi
  done
  if [ -f Makefile ]; then
    echo "--- Makefile targets ---"
    grep -E '^[A-Za-z0-9][A-Za-z0-9_.-]*:([^=]|$)' Makefile 2>/dev/null | cut -d: -f1 | head -12
    echo
  fi
  if [ -f justfile ]; then
    echo "--- justfile recipes ---"
    grep -E '^[A-Za-z0-9][A-Za-z0-9_-]*.*:' justfile 2>/dev/null | cut -d: -f1 | head -12
    echo
  fi
  echo "--- existing CLAUDE.md ---"
  CLAUDE_MD=$(find_claude_md)
  if [ -n "$CLAUDE_MD" ]; then
    LINES=$(wc -l <"$CLAUDE_MD" | tr -d ' ')
    echo "($CLAUDE_MD exists, $LINES lines)"
    if has_lore_block "$CLAUDE_MD"; then
      echo "(already has a lore-managed block — bootstrap will adopt it)"
    fi
  else
    echo "(no CLAUDE.md — bootstrap will create one with just the managed block)"
  fi
else
  # ---------- REFRESH (DRIFT) CONTEXT ----------
  LAST_SHA=$(state_str "$STATE" lastRefreshSha)
  echo "=== changes since lastRefreshSha ==="
  if ! in_git_repo; then
    echo "(not a git repo — date-based refresh only)"
  elif [ -z "$LAST_SHA" ]; then
    echo "(no lastRefreshSha — was bootstrapped outside a git repo)"
  elif ! sha_exists "$LAST_SHA"; then
    echo "lastRefreshSha not found in this clone (rebase, force-push, or shallow clone)."
    echo "Treat all watch files as potentially changed (force-rederive)."
  elif ! is_ancestor "$LAST_SHA"; then
    echo "lastRefreshSha exists but is no longer on this branch's history (rebase/squash/force-push)."
    echo "Treat all watch files as potentially changed (force-rederive)."
  else
    echo "commits: $(count_commits "$LAST_SHA")"
    echo "--- changed watch files ---"
    HITS=$(changed_watch_files "$STATE" "$LAST_SHA")
    if [ -n "$HITS" ]; then
      printf '%s\n' "$HITS"
    else
      echo "(none)"
    fi
    echo "--- changed files (repo-root-relative, first 100) ---"
    git diff --name-only "$LAST_SHA" HEAD 2>/dev/null | head -100
  fi
  echo
  echo "=== existing CLAUDE.md lore block ==="
  # Ask the writer what it would do, so this report and the actual edit can
  # never disagree. apply-block status reports create|insert|replace|malformed
  # and, for a well-formed block, its exact line range — never an open-ended
  # awk range that could slurp human prose past a missing END marker.
  CLAUDE_MD=$(find_claude_md)
  APPLY="$SCRIPT_DIR/../../../lib/apply-block.sh"
  if [ -z "$CLAUDE_MD" ]; then
    echo "(no CLAUDE.md found)"
  else
    ST=$(bash "$APPLY" status "$CLAUDE_MD" 2>/dev/null)
    printf '%s\n' "$ST"
    STATE=$(printf '%s\n' "$ST" | sed -n 's/^state: //p' | head -1)
    case "$STATE" in
      replace)
        RANGE=$(printf '%s\n' "$ST" | sed -n 's/^block: //p' | head -1)
        BN=${RANGE%-*}; EN=${RANGE#*-}
        echo "--- $CLAUDE_MD (current block) ---"
        [ -n "$BN" ] && [ -n "$EN" ] && sed -n "${BN},${EN}p" "$CLAUDE_MD" 2>/dev/null
        ;;
      insert)
        echo "($CLAUDE_MD exists but has no lore-managed block — refresh will insert one at the top)"
        ;;
      malformed)
        echo "WARNING: lore markers are malformed/duplicated. Do NOT edit this file."
        echo "Tell the user to fix the markers by hand; only /lore:refresh force may recreate the block, and only after the user confirms."
        ;;
    esac
  fi
fi

exit 0
