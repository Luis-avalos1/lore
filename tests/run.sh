#!/usr/bin/env bash
# lore test suite.
#
# Pure bash (3.2-compatible) + git + standard unix tools. No frameworks.
# Builds throwaway git repos under a tempdir and asserts on what the
# SessionStart hook and the two skill recon scripts print.
#
#   bash tests/run.sh
#
# If jq is installed, the whole suite re-runs a second time with jq removed
# from PATH, so both the jq and the sed/grep fallback code paths are covered.
# Output is TAP-ish: "ok N - name" / "not ok N - name". Exits non-zero on
# any failure.

set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK="$ROOT/plugins/lore/hooks/check-state.sh"
REFRESH_RECON="$ROOT/plugins/lore/skills/refresh/scripts/recon.sh"
STATUS_RECON="$ROOT/plugins/lore/skills/status/scripts/recon.sh"
PLUGIN_JSON="$ROOT/plugins/lore/.claude-plugin/plugin.json"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/lore-tests.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# Isolate from the developer's real environment: their ~/.claude/lore-disabled,
# git config (signing, hooks), and any enclosing git repo must not leak in.
HOME="$TMP/home"
export HOME
mkdir -p "$HOME/.claude"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=lore-tests GIT_AUTHOR_EMAIL=t@t
export GIT_COMMITTER_NAME=lore-tests GIT_COMMITTER_EMAIL=t@t
export GIT_CEILING_DIRECTORIES="$TMP"
unset CLAUDE_PROJECT_DIR LORE_DISABLE 2>/dev/null || true

OLD_DATE="1999-01-02T03:04:05Z"
NOW_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BOGUS_SHA="0123456789abcdef0123456789abcdef01234567"

TESTS=0
FAILS=0
CURRENT=""
OUT=""
RC=0

t_start() { TESTS=$((TESTS + 1)); CURRENT="$1"; }
t_pass() { echo "ok $TESTS - $CURRENT"; }
t_fail() {
  FAILS=$((FAILS + 1))
  echo "not ok $TESTS - $CURRENT: $1"
  if [ -n "${2:-}" ]; then
    printf '%s\n' "$2" | sed 's/^/    # /'
  fi
}

# run_script SCRIPT DIR — run SCRIPT with DIR as the project dir; capture
# stdout in OUT and the exit code in RC.
run_script() {
  OUT=$(cd "$2" 2>/dev/null && CLAUDE_PROJECT_DIR="$2" "$BASH" "$1" 2>/dev/null)
  RC=$?
}

# expect_out NAME SCRIPT DIR SUBSTRING... — script exits 0 and stdout
# contains every SUBSTRING.
expect_out() {
  t_start "$1"
  local script="$2" dir="$3" e
  shift 3
  run_script "$script" "$dir"
  if [ "$RC" -ne 0 ]; then
    t_fail "exit code $RC" "$OUT"
    return
  fi
  for e in "$@"; do
    case "$OUT" in
      *"$e"*) ;;
      *)
        t_fail "output missing '$e'" "$OUT"
        return
        ;;
    esac
  done
  t_pass
}

# expect_silent NAME SCRIPT DIR — script exits 0 and prints nothing.
expect_silent() {
  t_start "$1"
  run_script "$2" "$3"
  if [ "$RC" -ne 0 ]; then
    t_fail "exit code $RC" "$OUT"
    return
  fi
  if [ -n "$OUT" ]; then
    t_fail "expected silence" "$OUT"
    return
  fi
  t_pass
}

# expect_not_out NAME SCRIPT DIR SUBSTRING — exits 0, stdout does NOT contain.
expect_not_out() {
  t_start "$1"
  run_script "$2" "$3"
  if [ "$RC" -ne 0 ]; then
    t_fail "exit code $RC" "$OUT"
    return
  fi
  case "$OUT" in
    *"$4"*) t_fail "output unexpectedly contains '$4'" "$OUT" ;;
    *) t_pass ;;
  esac
}

# ---------- fixture helpers ----------

mkrepo() { # DIR — git repo with one seed commit
  mkdir -p "$1"
  (
    cd "$1" || exit 1
    git init -q -b main 2>/dev/null || git init -q
    echo seed >seed.txt
    git add -A
    git commit -qm seed
  ) >/dev/null 2>&1
}

addcommits() { # DIR N [FILE] — N commits appending to FILE (default churn.txt)
  local d="$1" n="$2" f="${3:-churn.txt}" i=1
  (
    cd "$d" || exit 1
    while [ "$i" -le "$n" ]; do
      echo "line $i" >>"$f"
      git add -A
      git commit -qm "c$i"
      i=$((i + 1))
    done
  ) >/dev/null 2>&1
}

commitfile() { # DIR FILE CONTENT — write FILE and commit it
  (
    cd "$1" || exit 1
    mkdir -p "$(dirname "$2")"
    printf '%s\n' "$3" >"$2"
    git add -A
    git commit -qm "edit $2"
  ) >/dev/null 2>&1
}

hsha() { git -C "$1" rev-parse HEAD 2>/dev/null; }

# wstate DIR FRAGMENT... — write .claude/lore-state.json from JSON fragments
wstate() {
  local d="$1" body="" part
  shift
  for part in "$@"; do
    body="${body:+$body,
  }$part"
  done
  mkdir -p "$d/.claude"
  printf '{\n  %s\n}\n' "$body" >"$d/.claude/lore-state.json"
}

claude_md_with_block() { # DIR — write a CLAUDE.md containing a lore block
  cat >"$1/CLAUDE.md" <<'EOF'
<!-- BEGIN lore-managed: do not edit between these markers. Run /lore:refresh to update. -->
<!-- lore-version: 0.0.0 -->
<!-- last-refreshed: 2020-01-01 -->
<!-- last-sha: deadbeefdead -->

## Project
fixture

<!-- END lore-managed -->

Human notes live below.
EOF
}

# =================================================================
# Hook: silence in non-candidate directories
# =================================================================

D="$TMP/plain"
mkdir -p "$D"
expect_silent "hook: silent in a non-git dir without state" "$HOOK" "$D"

D="$TMP/young"
mkrepo "$D"
addcommits "$D" 3
expect_silent "hook: silent in a young repo (below bootstrap minimum)" "$HOOK" "$D"

# =================================================================
# Hook: bootstrap nudges (branch B)
# =================================================================

D="$TMP/boot-no-md"
mkrepo "$D"
commitfile "$D" package.json '{"name":"boot"}'
addcommits "$D" 11
expect_out "hook: bootstrap nudge suggests /init when no CLAUDE.md" \
  "$HOOK" "$D" "no CLAUDE.md yet" "/init" "/lore:refresh"

D="$TMP/boot-md"
mkrepo "$D"
commitfile "$D" package.json '{"name":"boot"}'
addcommits "$D" 11
echo "# notes" >"$D/CLAUDE.md"
expect_out "hook: bootstrap nudge when CLAUDE.md exists without baseline" \
  "$HOOK" "$D" "no baseline" "/lore:refresh" "lore-disabled"

D="$TMP/boot-clone"
mkrepo "$D"
commitfile "$D" package.json '{"name":"boot"}'
addcommits "$D" 11
claude_md_with_block "$D"
expect_out "hook: fresh-clone nudge when block exists but state is missing" \
  "$HOOK" "$D" "fresh clone" "/lore:refresh"

D="$TMP/boot-no-manifest"
mkrepo "$D"
addcommits "$D" 11
expect_silent "hook: no bootstrap nudge without a project manifest" "$HOOK" "$D"

# =================================================================
# Hook: drift detection (branch A)
# =================================================================

D="$TMP/fresh"
mkrepo "$D"
commitfile "$D" package.json '{"name":"fresh"}'
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$(hsha "$D")\"" "\"lastRefreshDate\": \"$NOW_DATE\""
expect_silent "hook: silent when state is fresh" "$HOOK" "$D"

D="$TMP/commit-drift"
mkrepo "$D"
SHA=$(hsha "$D")
addcommits "$D" 20
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$NOW_DATE\""
expect_out "hook: nudges after 20 commits (default threshold)" \
  "$HOOK" "$D" "drift since last refresh" "20 commits" "/lore:refresh"

D="$TMP/custom-thresh"
mkrepo "$D"
SHA=$(hsha "$D")
addcommits "$D" 25
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$NOW_DATE\"" \
  '"driftThresholds": {"commits": 50, "days": 60}'
expect_silent "hook: honors a custom commit threshold from the state file" "$HOOK" "$D"

D="$TMP/watch-drift"
mkrepo "$D"
commitfile "$D" package.json '{"name":"w"}'
SHA=$(hsha "$D")
addcommits "$D" 2
commitfile "$D" package.json '{"name":"w","version":"2.0.0"}'
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$NOW_DATE\""
expect_out "hook: a watched-file change fires below the commit threshold" \
  "$HOOK" "$D" "watched files changed" "package.json"

D="$TMP/custom-watch"
mkrepo "$D"
commitfile "$D" package.json '{"name":"cw"}'
commitfile "$D" custom.cfg 'v=1'
SHA=$(hsha "$D")
commitfile "$D" package.json '{"name":"cw","version":"9"}'
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$NOW_DATE\"" \
  '"watchFiles": ["custom.cfg"]'
expect_silent "hook: custom watchFiles list excludes default entries" "$HOOK" "$D"
commitfile "$D" custom.cfg 'v=2'
expect_out "hook: custom watchFiles entry fires when it changes" \
  "$HOOK" "$D" "watched files changed" "custom.cfg"

D="$TMP/null-sha"
mkdir -p "$D"
wstate "$D" '"version": 1' '"lastRefreshSha": null' "\"lastRefreshDate\": \"$OLD_DATE\""
expect_out "hook: null SHA outside git still gets the date-based nudge" \
  "$HOOK" "$D" "days" "/lore:refresh"
expect_not_out "hook: null SHA is not misread as rewritten history" \
  "$HOOK" "$D" "rewritten"

D="$TMP/millis-date"
mkrepo "$D"
wstate "$D" '"version": 1' '"lastRefreshSha": null' '"lastRefreshDate": "2020-01-01T00:00:00.123Z"'
expect_out "hook: parses dates with fractional seconds" "$HOOK" "$D" "days"

D="$TMP/rewritten"
mkrepo "$D"
addcommits "$D" 2
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$BOGUS_SHA\"" "\"lastRefreshDate\": \"$NOW_DATE\""
expect_out "hook: missing baseline commit reports rewritten history" \
  "$HOOK" "$D" "rewritten" "/lore:refresh"

D="$TMP/zero-thresh"
mkrepo "$D"
commitfile "$D" package.json '{"name":"z"}'
SHA=$(hsha "$D")
addcommits "$D" 30
commitfile "$D" package.json '{"name":"z","version":"2"}'
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$OLD_DATE\"" \
  '"driftThresholds": {"commits": 0, "days": 0}' '"watchFiles": []'
expect_silent "hook: zero thresholds and empty watchFiles disable all signals" "$HOOK" "$D"

D="$TMP/day-thresh"
mkrepo "$D"
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$(hsha "$D")\"" "\"lastRefreshDate\": \"$OLD_DATE\"" \
  '"driftThresholds": {"commits": 20, "days": 99999}'
expect_silent "hook: honors a custom day threshold" "$HOOK" "$D"

D="$TMP/malformed"
mkdir -p "$D/.claude"
echo '{{{ not json' >"$D/.claude/lore-state.json"
expect_silent "hook: malformed state file fails silent" "$HOOK" "$D"

# =================================================================
# Hook: monorepo subdirectory project
# =================================================================

D="$TMP/mono"
mkrepo "$D"
commitfile "$D" apps/web/package.json '{"name":"web"}'
SUB="$D/apps/web"
SHA=$(hsha "$D")
wstate "$SUB" '"version": 1' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$NOW_DATE\"" \
  '"driftThresholds": {"commits": 5, "days": 60}'
addcommits "$D" 6 rootchurn.txt
expect_silent "hook: commits outside the project subdir don't count as drift" "$HOOK" "$SUB"
commitfile "$D" apps/web/package.json '{"name":"web","version":"2"}'
expect_out "hook: watched-file change inside the project subdir fires" \
  "$HOOK" "$SUB" "watched files changed" "package.json"

# =================================================================
# Hook: disable switches
# =================================================================

D="$TMP/disabled-state"
mkrepo "$D"
SHA=$(hsha "$D")
addcommits "$D" 30
wstate "$D" '"version": 1' '"disabled": true' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$OLD_DATE\""
expect_silent "hook: \"disabled\": true in the state file silences nudges" "$HOOK" "$D"

D="$TMP/disabled-repo"
mkrepo "$D"
SHA=$(hsha "$D")
addcommits "$D" 30
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$OLD_DATE\""
touch "$D/.claude/lore-disabled"
expect_silent "hook: per-repo .claude/lore-disabled marker silences nudges" "$HOOK" "$D"

D="$TMP/disabled-global"
mkrepo "$D"
SHA=$(hsha "$D")
addcommits "$D" 30
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$OLD_DATE\""
touch "$HOME/.claude/lore-disabled"
expect_silent "hook: global ~/.claude/lore-disabled silences nudges" "$HOOK" "$D"
rm -f "$HOME/.claude/lore-disabled"

t_start "hook: LORE_DISABLE env var silences nudges"
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$D" LORE_DISABLE=1 "$BASH" "$HOOK" 2>/dev/null)
RC=$?
if [ "$RC" -ne 0 ]; then
  t_fail "exit code $RC" "$OUT"
elif [ -n "$OUT" ]; then
  t_fail "expected silence" "$OUT"
else
  t_pass
fi

# =================================================================
# Refresh recon
# =================================================================

PLUGIN_VERSION=$(sed -n -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$PLUGIN_JSON" | head -1)

D="$TMP/recon-boot"
mkrepo "$D"
commitfile "$D" package.json '{"name":"recon-demo","scripts":{"test":"jest"}}'
expect_out "refresh recon: bootstrap mode inlines manifest excerpts" \
  "$REFRESH_RECON" "$D" "NO_STATE" "bootstrap context" "package.json" "recon-demo" "jest" \
  "=== now (UTC) ===" "$PLUGIN_VERSION" "no CLAUDE.md"

D="$TMP/recon-drift"
mkrepo "$D"
commitfile "$D" package.json '{"name":"rd"}'
SHA=$(hsha "$D")
commitfile "$D" package.json '{"name":"rd","version":"3"}'
claude_md_with_block "$D"
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$NOW_DATE\""
expect_out "refresh recon: drift mode reports commits, watch hits, and the block" \
  "$REFRESH_RECON" "$D" "commits: " "changed watch files" "package.json" \
  "BEGIN lore-managed" "## Project"

D="$TMP/recon-rewritten"
mkrepo "$D"
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$BOGUS_SHA\"" "\"lastRefreshDate\": \"$NOW_DATE\""
expect_out "refresh recon: unreachable SHA asks for force-rederive" \
  "$REFRESH_RECON" "$D" "force-rederive"

# =================================================================
# Status recon
# =================================================================

D="$TMP/status-none"
mkdir -p "$D"
expect_out "status recon: reports NO_STATE" "$STATUS_RECON" "$D" "NO_STATE" "(no CLAUDE.md)"

D="$TMP/status-drift"
mkrepo "$D"
commitfile "$D" package.json '{"name":"sd"}'
SHA=$(hsha "$D")
commitfile "$D" package.json '{"name":"sd","version":"2"}'
claude_md_with_block "$D"
wstate "$D" '"version": 1' "\"lastRefreshSha\": \"$SHA\"" "\"lastRefreshDate\": \"$NOW_DATE\""
expect_out "status recon: reports thresholds, commits, watch hits, block" \
  "$STATUS_RECON" "$D" "thresholds: 20 commits / 60 days" \
  "commits since last refresh: " "watch files changed: package.json" \
  "has lore-managed block" "last-refreshed"

D="$TMP/status-nongit"
mkdir -p "$D"
wstate "$D" '"version": 1' '"lastRefreshSha": null' "\"lastRefreshDate\": \"$OLD_DATE\""
expect_out "status recon: date-only drift outside git" \
  "$STATUS_RECON" "$D" "date only" "days since last refresh"

# =================================================================
# Summary + no-jq re-run
# =================================================================

echo
echo "# $TESTS tests, $FAILS failures (jq $(command -v jq >/dev/null 2>&1 && echo present || echo absent))"

if [ "$FAILS" -ne 0 ]; then
  exit 1
fi

# Re-run the whole suite with jq removed from PATH so the sed/grep fallback
# parsers get the same coverage. Only the outer run does this.
if [ -z "${LORE_TEST_NOJQ:-}" ] && command -v jq >/dev/null 2>&1; then
  SHIM="$TMP/nojq-bin"
  mkdir -p "$SHIM"
  for t in sh env git date grep sed awk head tail tr sort wc ls cat printf \
    dirname basename mktemp rm rmdir mkdir cp mv touch xargs uname find \
    cut paste chmod ln true false id; do
    p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$SHIM/$t" 2>/dev/null
  done
  ln -sf "$BASH" "$SHIM/bash"
  echo
  echo "# re-running suite with jq removed from PATH"
  PATH="$SHIM" LORE_TEST_NOJQ=1 "$BASH" "$0"
  exit $?
fi

exit 0
