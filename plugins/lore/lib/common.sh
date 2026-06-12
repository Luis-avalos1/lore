# lore — shared helpers, sourced by the SessionStart hook and both skill
# recon scripts. Keeping the watch list, state-file readers, and git probes
# in one place is what guarantees the hook and the skills agree on what
# "drift" means.
#
# Constraints: bash 3.2 (stock macOS), standard unix tools only. jq is used
# when present; every reader has a jq-free fallback. Nothing here writes to
# disk. Functions print nothing on failure and never exit the caller.
# shellcheck shell=bash

# Default watch list: files whose change means the managed block (stack,
# commands, version pins) may be stale. Overridden per-repo by the
# "watchFiles" array in .claude/lore-state.json. Names are interpreted as
# git pathspecs relative to the project directory.
# shellcheck disable=SC2034  # consumed by the scripts that source this file
LORE_DEFAULT_WATCH_FILES='package.json
pnpm-lock.yaml
pnpm-workspace.yaml
yarn.lock
package-lock.json
bun.lock
bun.lockb
deno.json
deno.lock
pyproject.toml
requirements.txt
poetry.lock
uv.lock
Pipfile
setup.py
setup.cfg
Cargo.toml
Cargo.lock
rust-toolchain.toml
go.mod
go.sum
pom.xml
build.gradle
build.gradle.kts
settings.gradle
settings.gradle.kts
gradle/libs.versions.toml
Gemfile
Gemfile.lock
composer.json
composer.lock
mix.exs
Dockerfile
docker-compose.yml
docker-compose.yaml
compose.yaml
Makefile
justfile
flake.nix
.nvmrc
.python-version
.tool-versions
mise.toml'

# Manifests that mark a directory as a "real" software project (used by the
# bootstrap nudge to avoid nagging in scratch directories).
# shellcheck disable=SC2034  # consumed by the scripts that source this file
LORE_MANIFEST_FILES='package.json
pyproject.toml
requirements.txt
setup.py
Cargo.toml
go.mod
pom.xml
build.gradle
build.gradle.kts
Gemfile
composer.json
mix.exs
deno.json
flake.nix
CMakeLists.txt
Makefile
justfile'

have_jq() { command -v jq >/dev/null 2>&1; }

in_git_repo() {
  command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# state_str FILE KEY — print a top-level string field, or nothing if the file
# or key is missing, or the value is null / not a string.
state_str() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  if have_jq; then
    jq -r --arg k "$key" '.[$k]? // empty | strings' "$file" 2>/dev/null
  else
    # sed -n + p: a "key": null line matches nothing and prints nothing
    # (a bare s/// without -n would echo the whole line back).
    sed -n -E "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" 2>/dev/null | head -1
  fi
}

# state_num FILE KEY DEFAULT — print a numeric field from driftThresholds,
# falling back to DEFAULT when the file/key is missing or the value is not a
# plain non-negative integer.
state_num() {
  local file="$1" key="$2" def="$3" v=""
  if [ -f "$file" ]; then
    if have_jq; then
      v=$(jq -r --arg k "$key" '.driftThresholds[$k]? // empty' "$file" 2>/dev/null)
    else
      v=$(sed -n -E "s/.*\"$key\"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" "$file" 2>/dev/null | head -1)
    fi
  fi
  case "$v" in
    ''|*[!0-9]*) v="$def" ;;
  esac
  printf '%s\n' "$v"
}

# state_has_key FILE KEY — succeed iff the key appears in the file at all.
# Used to tell "watchFiles": [] (watch nothing) apart from no watchFiles key
# (use the default list).
state_has_key() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  if have_jq; then
    [ "$(jq -r --arg k "$key" 'has($k)' "$file" 2>/dev/null)" = "true" ]
  else
    grep -E -q "\"$key\"[[:space:]]*:" "$file" 2>/dev/null
  fi
}

# state_true FILE KEY — succeed iff the file has "KEY": true at the top level.
state_true() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  if have_jq; then
    [ "$(jq -r --arg k "$key" '.[$k] == true' "$file" 2>/dev/null)" = "true" ]
  else
    grep -E -q "\"$key\"[[:space:]]*:[[:space:]]*true" "$file" 2>/dev/null
  fi
}

# state_watch_files FILE — print the watchFiles array, one entry per line.
# Prints nothing when the file/array is missing (callers fall back to
# LORE_DEFAULT_WATCH_FILES). The jq-free path assumes entries contain no
# commas or ']' — true for every real manifest filename.
state_watch_files() {
  local file="$1"
  [ -f "$file" ] || return 0
  if have_jq; then
    jq -r '.watchFiles[]? | strings' "$file" 2>/dev/null
  else
    tr -d '\n\r' <"$file" 2>/dev/null \
      | sed -n -E 's/.*"watchFiles"[[:space:]]*:[[:space:]]*\[([^]]*)\].*/\1/p' \
      | tr ',' '\n' \
      | sed -n -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/p'
  fi
}

# to_epoch ISO — parse an ISO-8601 UTC timestamp (or bare date) to epoch
# seconds. Tries GNU date, then BSD date against the common layouts lore
# writes. Prints nothing if unparseable.
to_epoch() {
  local iso="$1" s t fmt
  [ -n "$iso" ] || return 0
  if t=$(date -u -d "$iso" +%s 2>/dev/null); then
    printf '%s\n' "$t"
    return 0
  fi
  # BSD date: normalize away fractional seconds, zone suffixes.
  s="${iso%%.*}"
  s="${s%Z}"
  s="${s%%+*}"
  for fmt in '%Y-%m-%dT%H:%M:%S' '%Y-%m-%d %H:%M:%S' '%Y-%m-%d'; do
    if t=$(date -u -j -f "$fmt" "$s" +%s 2>/dev/null); then
      printf '%s\n' "$t"
      return 0
    fi
  done
  return 0
}

# days_since ISO — whole days between ISO and now; nothing if unparseable.
days_since() {
  local t_then t_now
  t_then=$(to_epoch "$1")
  [ -n "$t_then" ] || return 0
  t_now=$(date -u +%s)
  printf '%s\n' $(((t_now - t_then) / 86400))
}

# sha_exists SHA — does this commit object exist in the local object store?
sha_exists() {
  git rev-parse --quiet --verify "$1^{commit}" >/dev/null 2>&1
}

is_shallow_repo() {
  [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]
}

# count_commits BASE — commits since BASE that touch the current directory.
# The "-- ." pathspec keeps the count meaningful when the project is a
# subdirectory of a larger repo (monorepo package): unrelated commits
# elsewhere in the repo don't inflate drift.
count_commits() {
  git rev-list --count "$1"..HEAD -- . 2>/dev/null || echo 0
}

# changed_watch_files STATE_FILE BASE_SHA — watched files (from the state
# file, else the default list) that changed between BASE_SHA and HEAD, one
# per line. Watch entries are passed to git as pathspecs relative to the
# current directory, so this is both monorepo-correct (git diff output is
# repo-root-relative; pathspecs are cwd-relative) and a single git call.
changed_watch_files() {
  local state="$1" base="$2" list wf
  if state_has_key "$state" watchFiles; then
    list=$(state_watch_files "$state")
    [ -n "$list" ] || return 0 # explicit empty list: watching disabled
  else
    list="$LORE_DEFAULT_WATCH_FILES"
  fi
  set --
  while IFS= read -r wf; do
    [ -n "$wf" ] && set -- "$@" "$wf"
  done <<EOF
$list
EOF
  [ "$#" -gt 0 ] || return 0
  git diff --relative --name-only "$base" HEAD -- "$@" 2>/dev/null | sort -u
}

# join_commas — join stdin lines as "a, b, c".
join_commas() {
  local out="" line
  while IFS= read -r line; do
    [ -n "$line" ] && out="${out:+$out, }$line"
  done
  printf '%s\n' "$out"
}

# lore_version — the plugin's own version, read from plugin.json so scripts
# and docs can't drift from the manifest.
lore_version() {
  local lib_dir
  lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || return 0
  state_str "$lib_dir/../.claude-plugin/plugin.json" version
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
today_utc() { date -u +%Y-%m-%d; }

# find_claude_md — print the path of the CLAUDE.md lore should look at.
find_claude_md() {
  local f
  for f in CLAUDE.md .claude/CLAUDE.md; do
    if [ -f "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
}

# has_lore_block FILE — does FILE contain a lore-managed block?
has_lore_block() {
  [ -n "$1" ] && grep -q 'BEGIN lore-managed' "$1" 2>/dev/null
}
