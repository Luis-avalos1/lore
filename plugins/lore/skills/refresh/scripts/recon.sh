#!/usr/bin/env bash
# Live context for /lore:refresh. Handles both bootstrap (no state file)
# and refresh (state file + drift). Read-only. No writes.

set -u

STATE=.claude/lore-state.json

echo "=== state file ==="
if [ -f "$STATE" ]; then
  cat "$STATE"
else
  echo "NO_STATE"
fi
echo
echo "=== current HEAD ==="
if git rev-parse HEAD >/dev/null 2>&1; then
  git rev-parse HEAD
  git rev-parse --abbrev-ref HEAD
else
  echo "(not a git repo)"
fi
echo

if [ ! -f "$STATE" ]; then
  # ---------- BOOTSTRAP CONTEXT ----------
  echo "=== bootstrap context (no state file yet) ==="
  echo
  echo "--- top-level ---"
  ls -A1 2>/dev/null | head -30
  echo
  echo "--- manifests present ---"
  for f in \
    package.json pnpm-workspace.yaml turbo.json \
    pyproject.toml requirements.txt poetry.lock Pipfile \
    Cargo.toml go.mod pom.xml \
    build.gradle build.gradle.kts \
    Gemfile composer.json mix.exs deno.json \
    Dockerfile docker-compose.yml \
    Makefile justfile \
    .nvmrc .python-version rust-toolchain.toml; do
    [ -f "$f" ] && echo "  $f"
  done
  echo
  echo "--- existing CLAUDE.md ---"
  for cm in CLAUDE.md .claude/CLAUDE.md; do
    if [ -f "$cm" ]; then
      lines=$(wc -l < "$cm" | tr -d ' ')
      echo "($cm exists, $lines lines)"
      if grep -q "BEGIN lore-managed" "$cm" 2>/dev/null; then
        echo "(already has a lore-managed block — bootstrap will adopt it)"
      fi
      break
    fi
  done
  if [ ! -f CLAUDE.md ] && [ ! -f .claude/CLAUDE.md ]; then
    echo "(no CLAUDE.md — bootstrap will create one with just the managed block)"
  fi
else
  # ---------- REFRESH (DRIFT) CONTEXT ----------
  echo "=== changes since lastRefreshSha ==="
  if command -v jq >/dev/null 2>&1; then
    LAST_SHA=$(jq -r '.lastRefreshSha // empty' "$STATE" 2>/dev/null)
  else
    LAST_SHA=$(grep -E '"lastRefreshSha"[[:space:]]*:' "$STATE" 2>/dev/null \
      | head -1 \
      | sed -E 's/.*"lastRefreshSha"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  fi

  if [ -n "$LAST_SHA" ] && git cat-file -e "$LAST_SHA" 2>/dev/null; then
    echo "commits: $(git rev-list --count "$LAST_SHA"..HEAD 2>/dev/null)"
    echo "--- changed files ---"
    git diff --name-only "$LAST_SHA"..HEAD 2>/dev/null | head -100
    if command -v jq >/dev/null 2>&1; then
      echo "--- changed watch files ---"
      jq -r '.watchFiles[]' "$STATE" 2>/dev/null | while IFS= read -r wf; do
        if git diff --name-only "$LAST_SHA"..HEAD 2>/dev/null | grep -Fxq "$wf"; then
          echo "  $wf (watched)"
        fi
      done
    fi
  elif [ -n "$LAST_SHA" ]; then
    echo "lastRefreshSha not reachable from current branch (rebase/squash?). Falling back to working-tree status."
    git status --short 2>/dev/null | head -50
  else
    echo "(no lastRefreshSha — was bootstrapped outside a git repo)"
  fi
  echo
  echo "=== existing CLAUDE.md lore block ==="
  found=0
  for f in CLAUDE.md .claude/CLAUDE.md; do
    if [ -f "$f" ]; then
      block=$(awk '/<!-- BEGIN lore-managed/,/<!-- END lore-managed/' "$f" 2>/dev/null)
      if [ -n "$block" ]; then
        echo "--- $f ---"
        printf '%s\n' "$block"
        found=1
        break
      fi
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "(no lore-managed block found in CLAUDE.md — may have been removed)"
  fi
fi

exit 0
