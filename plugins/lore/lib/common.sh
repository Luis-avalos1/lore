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

# _state_top_level FILE — print the state object's top-level members on a
# single line with nested objects/arrays elided, so the jq-free readers below
# can match root-level keys only (mirroring jq's top-level .key / has(.)).
# Assumes nesting at most one level deep and that top-level string values hold
# no braces/brackets — both true for the lore state schema (driftThresholds is
# an object of numbers; watchFiles an array of strings; the rest are scalars).
_state_top_level() {
  tr -d '\n\r' <"$1" 2>/dev/null \
    | sed -E 's/^[[:space:]]*\{//; s/\}[[:space:]]*$//; s/\{[^{}]*\}//g; s/\[[^][]*\]//g'
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
      # Mirror the jq path's .driftThresholds[$k] scope: isolate the
      # driftThresholds object first, then read the key inside it, so a
      # same-named key elsewhere in the file can't shadow it. Capture the whole
      # raw value token (up to the next comma) rather than just a leading digit
      # run, then trim trailing whitespace and any surrounding quotes. A
      # non-integer like 3.5 / 1e2 / "7x" / "30 " then fails the all-digits
      # guard below and falls back to the default — exactly as jq -r + the
      # guard would. A quoted integer ("50") still parses as 50.
      v=$(tr -d '\n\r' <"$file" 2>/dev/null \
        | sed -n -E 's/.*"driftThresholds"[[:space:]]*:[[:space:]]*\{([^}]*)\}.*/\1/p' \
        | sed -n -E "s/.*\"$key\"[[:space:]]*:[[:space:]]*([^,]*).*/\1/p" \
        | head -1)
      v="${v%"${v##*[![:space:]]}"}"          # trim trailing whitespace
      case "$v" in \"*\") v="${v#\"}"; v="${v%\"}" ;; esac  # strip surrounding quotes
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
    _state_top_level "$file" | grep -E -q "\"$key\"[[:space:]]*:"
  fi
}

# state_true FILE KEY — succeed iff the file has "KEY": true at the top level.
state_true() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  if have_jq; then
    [ "$(jq -r --arg k "$key" '.[$k] == true' "$file" 2>/dev/null)" = "true" ]
  else
    _state_top_level "$file" | grep -E -q "\"$key\"[[:space:]]*:[[:space:]]*true"
  fi
}

# state_watch_files FILE — print the watchFiles array, one entry per line.
# Prints nothing when the file/array is missing (callers fall back to
# LORE_DEFAULT_WATCH_FILES). The jq-free path handles entries containing ','
# or ']' (e.g. a "app/[id]/page.tsx" route glob); it assumes no entry contains
# a literal '"' or the two-char sequence ']' followed by ',' or '}'.
state_watch_files() {
  local file="$1"
  [ -f "$file" ] || return 0
  if have_jq; then
    jq -r '.watchFiles[]? | strings' "$file" 2>/dev/null
  else
    # Drop everything up to the array's opening '[', then cut at its closing
    # ']' (the one followed by ',' or '}' or end), then pull each quoted entry.
    # Reading quoted strings directly — rather than splitting on ',' — keeps
    # entries that themselves contain ',' or ']' intact.
    tr -d '\n\r' <"$file" 2>/dev/null \
      | sed -n -E 's/.*"watchFiles"[[:space:]]*:[[:space:]]*\[//p' \
      | sed -E 's/\][[:space:]]*[,}].*$//; s/\][[:space:]]*$//' \
      | grep -oE '"[^"]*"' \
      | sed -E 's/^"//; s/"$//'
  fi
}

# to_epoch ISO — parse an ISO-8601 UTC timestamp (or bare date) to epoch
# seconds. Tries GNU date, then BSD date against the common layouts lore
# writes. Prints nothing if unparseable.
to_epoch() {
  local iso="$1" s t fmt off sign oh om adj frac
  [ -n "$iso" ] || return 0
  if t=$(date -u -d "$iso" +%s 2>/dev/null); then
    printf '%s\n' "$t"
    return 0
  fi
  # BSD date has no -d; parse the layouts lore writes, in UTC. BSD `date -j`
  # ignores a trailing zone offset and fills a missing time-of-day from the
  # current clock, so normalize both by hand first to match GNU `date -d`.
  # Drop fractional seconds only, keeping any trailing Z or numeric offset — a
  # blunt "${iso%%.*}" would also delete a +05:00 offset that follows the dot.
  case "$iso" in
    *.*) s="${iso%%.*}"; frac="${iso#*.}"; s="$s${frac#"${frac%%[!0-9]*}"}" ;;
    *)   s="$iso" ;;
  esac
  off=""
  case "$s" in
    *Z) s="${s%Z}" ;;
    *+[0-9][0-9]:[0-9][0-9]) off="${s##*+}"; s="${s%+*}" ;;
    *-[0-9][0-9]:[0-9][0-9]) off="-${s##*-}"; s="${s%-*}" ;;
  esac
  case "$s" in
    *T*|*' '*) ;;                 # already carries a time-of-day
    *) s="${s}T00:00:00" ;;       # bare date: pin to midnight, not "now"
  esac
  for fmt in '%Y-%m-%dT%H:%M:%S' '%Y-%m-%d %H:%M:%S' '%Y-%m-%d'; do
    if t=$(date -u -j -f "$fmt" "$s" +%s 2>/dev/null); then
      if [ -n "$off" ]; then
        # off is +HH:MM or -HH:MM; convert to seconds and shift to true UTC.
        sign="${off%%[0-9]*}"; oh="${off#?}"; oh="${oh%%:*}"; om="${off##*:}"
        adj=$(( (10#$oh * 3600) + (10#$om * 60) ))
        if [ "$sign" = "-" ]; then t=$(( t + adj )); else t=$(( t - adj )); fi
      fi
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

# is_ancestor SHA — succeed iff SHA is an ancestor of HEAD, i.e. SHA..HEAD is a
# meaningful "commits since" range. Fails (so callers fall back to the
# rewritten-baseline path) when the baseline object still exists but no longer
# sits on HEAD's history after a rebase, squash, or force-push.
is_ancestor() {
  git merge-base --is-ancestor "$1" HEAD 2>/dev/null
}

# count_commits BASE — commits since BASE that touch the current directory.
# The "-- ." pathspec keeps the count meaningful when the project is a
# subdirectory of a larger repo (monorepo package): unrelated commits
# elsewhere in the repo don't inflate drift. Returns 0 when BASE is missing or
# not an ancestor of HEAD, so a rewritten-but-still-present baseline can't
# report the whole rewritten history as drift.
count_commits() {
  is_ancestor "$1" || { echo 0; return 0; }
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

# claude_md_dead_refs FILE — scan the human prose of a CLAUDE.md for repo-relative
# path references that no longer exist. Prints them one per line, deduped, in
# first-seen order, capped at 5. Always returns 0; prints nothing when FILE is
# missing/empty/clean. Assumes the caller already cd'd to the project dir.
#
# ponytail: heuristic prose scan — candidates are only backtick spans and
# markdown link targets, and a token is flagged only when its PARENT directory
# exists but the token itself doesn't. That parent-exists gate is the whole
# conservatism: gitignored/build-output trees are absent along with their parent
# dir, so they're never flagged — no .gitignore parsing needed. Upgrade path (if
# false positives show up): parse .gitignore, or track link-vs-code provenance.
claude_md_dead_refs() {
  local file="$1" tok first parent count=0 seen="" cr
  [ -n "$file" ] && [ -s "$file" ] || return 0
  cr=$(printf '\r')
  # One awk pass emits raw candidate tokens, skipping the managed block
  # (BEGIN..END inclusive) and fenced code blocks; the bash loop below applies
  # exclusions, the existence tests, dedup, and the cap.
  awk '
    /<!-- BEGIN lore-managed/ { inblock = 1 }
    inblock { if (/<!-- END lore-managed/) inblock = 0; next }
    /^[[:space:]]*```/ || /^[[:space:]]*~~~/ { infence = !infence; next }
    infence { next }
    {
      n = split($0, parts, "`")            # inside-backtick spans are the even fields
      for (i = 2; i <= n; i += 2) print parts[i]
      s = $0                               # markdown link targets: ](target)
      while (match(s, /\]\([^)]*\)/)) {
        print substr(s, RSTART + 2, RLENGTH - 3)
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$file" 2>/dev/null | while IFS= read -r tok; do
    tok="${tok%"$cr"}"                     # trailing CR (CRLF files)
    tok="${tok#./}"                        # leading ./
    tok="${tok%%#*}"                        # trailing #fragment (link targets)
    while : ; do                           # trailing punctuation
      case "$tok" in
        *[.,\;:\)\]\}]) tok="${tok%?}" ;;
        *) break ;;
      esac
    done
    tok="${tok%/}"                         # one trailing slash
    case "$tok" in
      */*) : ;;                            # a path reference has a slash
      *) continue ;;
    esac
    case "$tok" in
      *"://"*|mailto:*|tel:*|'#'*) continue ;;                # URLs / schemes / anchors
      /*|'~'*|-*) continue ;;                                 # absolute / home / flag-like
      ..*|*/../*) continue ;;                                 # escapes the repo — unverifiable from here
      *'<'*|*'>'*|*'$'*|*'{'*|*'}'*|*'*'*|*'?'*|*' '*|*'|'*|*';'*|*'&'*|*'"'*|*"'"*|*'`'*) continue ;;
      *path/to*|*foo/bar*|*example*|*...*) continue ;;        # obvious placeholders
    esac
    first="${tok%%/*}"
    case "$first" in
      node_modules|dist|build|out|target|coverage|.next|vendor|__pycache__|.venv) continue ;;
    esac
    parent=$(dirname "$tok")
    [ -d "$parent" ] && [ ! -e "$tok" ] || continue
    case "$seen" in *"|$tok|"*) continue ;; esac             # dedup, first-seen order
    seen="$seen|$tok|"
    printf '%s\n' "$tok"
    count=$((count + 1))
    [ "$count" -ge 5 ] && break            # cap
  done
  return 0
}
