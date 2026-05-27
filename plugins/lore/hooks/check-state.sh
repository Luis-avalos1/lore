#!/usr/bin/env bash
# lore — SessionStart hook
#
# Runs at session start. Stays silent unless there's something worth saying.
# Anything printed to stdout is injected into Claude's context for this session
# (SessionStart hooks add stdout as context — see Claude Code hooks reference).
#
# This script never blocks the session: every exit is 0.
# To silence it entirely, create the file ~/.claude/lore-disabled.

set -u

# -------- escape hatch --------
if [ -f "$HOME/.claude/lore-disabled" ]; then
  exit 0
fi

# -------- where are we --------
CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE="$CWD/.claude/lore-state.json"
THRESH_COMMITS=20
THRESH_DAYS=60
BOOTSTRAP_MIN_COMMITS=10

# -------- tiny field reader (works with or without jq) --------
get_field() {
  local file="$1" key="$2"
  if [ ! -f "$file" ]; then return 0; fi
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null
  else
    grep -E "\"$key\"[[:space:]]*:" "$file" 2>/dev/null \
      | head -1 \
      | sed -E "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
  fi
}

# Portable epoch parse: tries GNU date, then BSD date.
to_epoch() {
  local iso="$1"
  date -u -d "$iso" +%s 2>/dev/null \
    || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null \
    || echo ""
}

cd "$CWD" 2>/dev/null || exit 0

# =================================================================
# BRANCH A — state file exists: check drift, suggest /lore:refresh
# =================================================================
if [ -f "$STATE" ]; then
  LAST_SHA=$(get_field "$STATE" lastRefreshSha)
  LAST_DATE=$(get_field "$STATE" lastRefreshDate)

  # If we can't read the SHA, give up silently rather than nagging.
  if [ -z "$LAST_SHA" ]; then
    exit 0
  fi

  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

    # Is the last-refreshed SHA still reachable from this branch?
    if ! git cat-file -e "$LAST_SHA" 2>/dev/null; then
      echo "lore: history has been rewritten since the last refresh (rebase or force-push). Run /lore:refresh to recompute the baseline."
      exit 0
    fi

    COMMITS=$(git rev-list --count "$LAST_SHA"..HEAD 2>/dev/null || echo 0)

    # Loud signal: many commits since last refresh.
    if [ "${COMMITS:-0}" -ge "$THRESH_COMMITS" ]; then
      echo "lore: $COMMITS commits since last refresh. Run /lore:refresh to update the managed block."
      exit 0
    fi

    # Even with few commits, a watched-file change is high-signal.
    WATCH_FILES="package.json pnpm-lock.yaml yarn.lock package-lock.json pyproject.toml requirements.txt poetry.lock Pipfile Cargo.toml Cargo.lock go.mod go.sum pom.xml build.gradle build.gradle.kts Gemfile Gemfile.lock composer.json composer.lock mix.exs deno.json bun.lockb README.md ARCHITECTURE.md Dockerfile docker-compose.yml docker-compose.yaml Makefile justfile flake.nix"
    CHANGED=$(git diff --name-only "$LAST_SHA"..HEAD 2>/dev/null || true)
    if [ -n "$CHANGED" ]; then
      for wf in $WATCH_FILES; do
        if printf '%s\n' "$CHANGED" | grep -Fxq "$wf"; then
          echo "lore: $wf changed since last refresh. Run /lore:refresh to update."
          exit 0
        fi
      done
    fi
  fi

  # Time-based drift (handles non-git repos and slow-moving repos).
  if [ -n "$LAST_DATE" ]; then
    NOW=$(date -u +%s)
    THEN=$(to_epoch "$LAST_DATE")
    if [ -n "$THEN" ]; then
      DAYS=$(( (NOW - THEN) / 86400 ))
      if [ "$DAYS" -ge "$THRESH_DAYS" ]; then
        echo "lore: $DAYS days since last refresh. Run /lore:refresh to update."
        exit 0
      fi
    fi
  fi

  # No drift worth mentioning. Silence is golden.
  exit 0
fi

# =================================================================
# BRANCH B — no state file: should we suggest /lore:refresh (bootstrap)?
# Only nudge for "real" software repos to avoid nagging in scratch dirs.
# =================================================================

# Must be inside a git repo.
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Must have some history (filter out brand-new throwaway repos).
COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo 0)
if [ "${COMMITS:-0}" -lt "$BOOTSTRAP_MIN_COMMITS" ]; then
  exit 0
fi

# Must look like a software project (at least one manifest).
HAS_MANIFEST=0
for f in package.json pyproject.toml requirements.txt Cargo.toml go.mod pom.xml build.gradle build.gradle.kts Gemfile composer.json mix.exs deno.json Makefile; do
  if [ -f "$f" ]; then
    HAS_MANIFEST=1
    break
  fi
done
if [ "$HAS_MANIFEST" -ne 1 ]; then
  exit 0
fi

# All conditions met: nudge once. The model decides whether to act.
if [ -f CLAUDE.md ] || [ -f .claude/CLAUDE.md ]; then
  echo "lore: CLAUDE.md exists but lore has no baseline for this repo. Run /lore:refresh to bootstrap a managed block."
else
  echo "lore: no CLAUDE.md yet. Consider /init to generate one, then /lore:refresh to bootstrap the managed block."
fi
exit 0
