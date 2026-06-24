#!/usr/bin/env bash
# lore — deterministic managed-block writer for CLAUDE.md.
#
# This is the ONLY component that edits CLAUDE.md. The /lore:refresh skill
# derives the small block BODY (stack identifiers, commands, last-refresh
# metadata); this script owns the BEGIN/END markers and performs an atomic,
# marker-bounded splice. Everything OUTSIDE the markers is preserved
# byte-for-byte: surrounding text, blank lines, the file's line-ending style
# (LF or CRLF), and its trailing-newline state. It refuses to write when the
# markers are unbalanced or duplicated, so a half-written or multi-block file
# is never silently mangled.
#
#   bash apply-block.sh status TARGET            # report marker state, no write
#   bash apply-block.sh apply  TARGET < body     # splice stdin body into TARGET
#
# `status` prints, on stdout (exit 0):
#   state: create|insert|replace|malformed
#   begin: <count of BEGIN markers>
#   end:   <count of END markers>
#   [block: <begin_line>-<end_line>]   # only when state=replace
#   [reason: <text>]                   # only when state=malformed
#
# `apply` reads the block body from stdin and writes TARGET. Exit codes:
#   0  wrote successfully (create/insert/replace)
#   2  usage error
#   3  malformed/duplicate markers — NOTHING written
#   4  I/O error — NOTHING written
#
# Constraints: bash 3.2 (stock macOS), standard unix tools only, no jq, no GNU
# extensions (no readlink -f, sed -i, chmod --reference, mapfile).
# shellcheck shell=bash

set -u

BEGIN_RE='<!-- BEGIN lore-managed'
END_RE='<!-- END lore-managed'
BEGIN_LINE='<!-- BEGIN lore-managed: do not edit between these markers. Run /lore:refresh to update. -->'
END_LINE='<!-- END lore-managed -->'
TRAILER='<!-- Add project-specific instructions below this line. -->'

CR=$(printf '\r')

die() { printf 'lore apply-block: %s\n' "$1" >&2; exit "${2:-1}"; }

usage() {
  die 'usage: apply-block.sh status|apply TARGET   (apply reads the block body from stdin)' 2
}

# resolve_target PATH — print the real path to write. When PATH is a symlink we
# follow it (one level) so we replace the link target's contents in place rather
# than clobbering the symlink with a regular file. Prints PATH unchanged when it
# is not a symlink. Only used for write paths.
resolve_target() {
  local p="$1" tgt dir
  [ -L "$p" ] || { printf '%s\n' "$p"; return 0; }
  tgt=$(readlink "$p" 2>/dev/null) || { printf '%s\n' "$p"; return 0; }
  case "$tgt" in
    /*) printf '%s\n' "$tgt" ;;
    *)  dir=$(cd "$(dirname "$p")" 2>/dev/null && pwd) || { printf '%s\n' "$p"; return 0; }
        printf '%s/%s\n' "$dir" "$tgt" ;;
  esac
}

# detect_eol FILE — print 'crlf' if the file contains any CR byte, else 'lf'.
detect_eol() {
  if LC_ALL=C grep -q "$CR" "$1" 2>/dev/null; then printf 'crlf\n'; else printf 'lf\n'; fi
}

# ends_with_newline FILE — succeed iff FILE's last byte is a newline.
ends_with_newline() {
  [ -s "$1" ] || return 1
  [ -z "$(tail -c1 "$1" 2>/dev/null)" ]
}

# count_re RE FILE — number of lines matching RE (0 when file/key absent).
count_re() {
  local n
  n=$(grep -c "$1" "$2" 2>/dev/null) || n=0
  # grep -c can print a number even on no-match; normalize empties.
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

# first_line_re RE FILE — 1-based line number of the first line matching RE.
first_line_re() {
  grep -n "$1" "$2" 2>/dev/null | head -1 | cut -d: -f1
}

# analyze FILE — set A_STATE (create|insert|replace|malformed), A_BEGIN, A_END
# (marker counts), A_BN/A_EN (block line numbers when replace), A_REASON.
analyze() {
  local file="$1"
  A_STATE=''; A_BEGIN=0; A_END=0; A_BN=''; A_EN=''; A_REASON=''
  if [ ! -e "$file" ] || [ ! -s "$file" ]; then
    A_STATE=create
    return 0
  fi
  if [ ! -f "$file" ]; then
    A_STATE=malformed; A_REASON="target is not a regular file"; return 0
  fi
  A_BEGIN=$(count_re "$BEGIN_RE" "$file")
  A_END=$(count_re "$END_RE" "$file")
  if [ "$A_BEGIN" -eq 0 ] && [ "$A_END" -eq 0 ]; then
    A_STATE=insert; return 0
  fi
  if [ "$A_BEGIN" -eq 1 ] && [ "$A_END" -eq 1 ]; then
    A_BN=$(first_line_re "$BEGIN_RE" "$file")
    A_EN=$(first_line_re "$END_RE" "$file")
    if [ -n "$A_BN" ] && [ -n "$A_EN" ] && [ "$A_BN" -lt "$A_EN" ]; then
      A_STATE=replace; return 0
    fi
    A_STATE=malformed; A_REASON="END marker precedes BEGIN marker"; return 0
  fi
  A_STATE=malformed
  A_REASON="unbalanced or duplicate markers (begin=$A_BEGIN end=$A_END)"
}

# emit_block BODY EOL TERMINATE_END — print the full managed block (BEGIN, the
# normalized body, END) using EOL between lines. The END marker is terminated
# with EOL only when TERMINATE_END=yes (so a no-trailing-newline EOF is kept).
emit_block() {
  local body="$1" eol="$2" term="$3" line
  printf '%s%s' "$BEGIN_LINE" "$eol"
  # Re-terminate every body line with EOL after stripping any stray CR, so the
  # block's line endings always match the file regardless of the body's input.
  printf '%s' "$body" | while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$CR}"
    printf '%s%s' "$line" "$eol"
  done
  if [ "$term" = yes ]; then
    printf '%s%s' "$END_LINE" "$eol"
  else
    printf '%s' "$END_LINE"
  fi
}

# file_mode FILE — print octal permission bits (BSD then GNU stat), else empty.
file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || true
}

cmd_status() {
  local file="$1"
  analyze "$file"
  printf 'state: %s\n' "$A_STATE"
  printf 'begin: %s\n' "$A_BEGIN"
  printf 'end: %s\n' "$A_END"
  [ "$A_STATE" = replace ] && printf 'block: %s-%s\n' "$A_BN" "$A_EN"
  [ "$A_STATE" = malformed ] && printf 'reason: %s\n' "$A_REASON"
  exit 0
}

cmd_apply() {
  local path="$1" real body eol term tmp dir mode
  body=$(cat)
  # Refuse a body that itself carries markers — it would create a duplicate
  # block on the next run. The skill supplies only the inner content.
  if printf '%s' "$body" | grep -q "$BEGIN_RE" || printf '%s' "$body" | grep -q "$END_RE"; then
    die "block body must not contain lore markers" 3
  fi

  real=$(resolve_target "$path")
  analyze "$real"
  case "$A_STATE" in
    malformed) die "refusing to write: $A_REASON (run /lore:refresh force after fixing the markers by hand)" 3 ;;
  esac

  dir=$(dirname "$real")
  tmp=$(mktemp "$dir/.lore-claude.XXXXXX" 2>/dev/null) || die "could not create temp file in $dir" 4

  if [ "$A_STATE" = create ]; then
    # No existing file (or empty): fresh CLAUDE.md, LF, with a human trailer.
    {
      emit_block "$body" $'\n' yes
      printf '\n%s\n' "$TRAILER"
    } >"$tmp" || { rm -f "$tmp"; die "write failed" 4; }
  else
    eol=$(detect_eol "$real")
    [ "$eol" = crlf ] && eol="$CR"$'\n' || eol=$'\n'
    if [ "$A_STATE" = insert ]; then
      # Prepend a block + one blank line; keep existing content byte-for-byte.
      {
        emit_block "$body" "$eol" yes
        printf '%s' "$eol"
        cat "$real"
      } >"$tmp" || { rm -f "$tmp"; die "write failed" 4; }
    else
      # replace: splice between the single BEGIN/END lines. head/tail are
      # byte-exact for the untouched regions (CR bytes and all).
      if [ "$(tail -n +"$((A_EN + 1))" "$real" 2>/dev/null | wc -c | tr -d ' ')" -gt 0 ] \
        || ends_with_newline "$real"; then term=yes; else term=no; fi
      {
        # head -n 0 is an error on BSD, so skip it when the block is at line 1.
        [ "$A_BN" -gt 1 ] && head -n "$((A_BN - 1))" "$real"
        emit_block "$body" "$eol" "$term"
        tail -n +"$((A_EN + 1))" "$real"
      } >"$tmp" || { rm -f "$tmp"; die "write failed" 4; }
    fi
  fi

  # Match the original file's permissions where we can; default to 0644.
  mode=''
  [ -f "$real" ] && mode=$(file_mode "$real")
  case "$mode" in
    *[!0-7]*|'') chmod 644 "$tmp" 2>/dev/null || true ;;
    *)           chmod "$mode" "$tmp" 2>/dev/null || chmod 644 "$tmp" 2>/dev/null || true ;;
  esac

  mv -f "$tmp" "$real" 2>/dev/null || { rm -f "$tmp"; die "atomic replace failed" 4; }
  exit 0
}

[ "$#" -ge 2 ] || usage
SUB="$1"; TARGET="$2"
case "$SUB" in
  status) cmd_status "$TARGET" ;;
  apply)  cmd_apply "$TARGET" ;;
  *)      usage ;;
esac
