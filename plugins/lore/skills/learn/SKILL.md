---
description: Analyze this repository from scratch and write durable knowledge into CLAUDE.md and per-project memory so future Claude Code sessions don't need to rediscover the same facts. Use when the user is in a repo for the first time, when they say "learn this repo" or "onboard", or after lore reports no state file exists.
when_to_use: First-time onboarding for an unfamiliar repo. Generates a managed CLAUDE.md section (stack, commands, layout, conventions) and seeds the auto-memory directory with topic files. Safe to re-run; updates the lore-managed block in place and leaves human-edited content untouched.
allowed-tools: Bash(git *) Bash(jq *) Bash(mkdir *) Bash(ls *) Bash(cat *) Bash(test *) Bash(wc *) Bash(date *) Bash(grep *) Bash(find *) Bash(echo *) Read Write Edit Glob Grep
disable-model-invocation: false
---

# /lore:learn — onboard a repo into persistent memory

You are running the first-time onboarding for this repository. Your output is two artifacts on disk: a managed section in `CLAUDE.md` (facts Claude needs every session) and a set of topic files in the per-project auto-memory directory (history, gotchas, architectural notes that accumulate over time). You also write a state file so future `/lore:refresh` runs know what changed.

Be efficient. The principle from the existing `codebase-onboarding` skill applies: **use Glob and Grep for reconnaissance, not Read on every file.** Read only the manifest files, README, and 2–4 representative source files. Anything more is wasted tokens.

## Live repo context

The following commands run before you see this skill. Use their output instead of re-running them.

```!
echo "=== cwd ==="
pwd
echo
echo "=== git ==="
git rev-parse --is-inside-work-tree 2>/dev/null && {
  echo "remote: $(git remote get-url origin 2>/dev/null || echo none)"
  echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "head:   $(git rev-parse HEAD 2>/dev/null)"
  echo "commits: $(git rev-list --count HEAD 2>/dev/null)"
} || echo "not a git repo"
echo
echo "=== top-level ==="
ls -A1 | head -40
echo
echo "=== manifests present ==="
for f in package.json pnpm-workspace.yaml turbo.json nx.json pyproject.toml requirements.txt poetry.lock Pipfile Cargo.toml go.mod go.sum pom.xml build.gradle build.gradle.kts Gemfile composer.json mix.exs deno.json bun.lockb Dockerfile docker-compose.yml docker-compose.yaml Makefile justfile flake.nix README.md README.rst README ARCHITECTURE.md CONTRIBUTING.md .nvmrc .python-version rust-toolchain.toml; do
  [ -f "$f" ] && echo "  $f"
done
echo
echo "=== existing lore state ==="
test -f .claude/lore-state.json && cat .claude/lore-state.json || echo "(none — fresh onboarding)"
echo
echo "=== existing CLAUDE.md ==="
if test -f CLAUDE.md; then
  echo "(exists, $(wc -l < CLAUDE.md) lines)"
  echo "--- first 40 lines ---"
  head -40 CLAUDE.md
else
  echo "(none)"
fi
echo
echo "=== memory dir candidate ==="
# Derive the auto-memory project key the same way Claude Code does:
#   - if inside a git repo, use the repo root
#   - otherwise use cwd
# Encode by replacing / with -
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
key="$(echo "$root" | sed 's|/|-|g')"
echo "$HOME/.claude/projects/$key/memory/"
test -d "$HOME/.claude/projects/$key/memory/" && ls -1 "$HOME/.claude/projects/$key/memory/" 2>/dev/null || echo "(memory dir not yet present — will create)"
```

## What you will produce

Three things, in this order:

1. **Reconnaissance findings** (in your reasoning, not on disk) — a structured picture of the repo.
2. **`CLAUDE.md` lore-managed block** (on disk in the user's repo) — facts every session needs.
3. **Memory files** (on disk under `~/.claude/projects/<key>/memory/`) — topic notes that grow over time.
4. **State file** at `.claude/lore-state.json` so `/lore:refresh` and the SessionStart hook know what's current.

## Phase 1 — Reconnaissance (lightweight)

Goal: build a mental model without reading more than ~6 files. Use **Glob** and **Grep**, not Read, for everything except specific manifest files.

Do this in roughly this order:

1. **Identify the stack**. Look at which manifests exist (already listed above) and pick the primary language(s). Read the *one or two* manifests that matter most:
   - JS/TS: `package.json` (scripts, deps, workspaces field)
   - Python: `pyproject.toml` or `requirements.txt`
   - Rust: `Cargo.toml`
   - Go: `go.mod`
   - Mixed/monorepo: the root workspace file plus one sub-package manifest

2. **Read the README**. If `README.md` exists, read it. Extract: purpose, install commands, how to run, anything labeled "architecture" or "structure". If README is huge (>400 lines), Read only the first 200 lines and grep for headings.

3. **Map the top level**. Use Glob to enumerate `src/`, `app/`, `lib/`, `packages/`, `apps/`, `cmd/`, `internal/`, `tests/`, `__tests__/`, etc. — but don't recurse into them yet.

4. **Find entry points**. Greps that pay off:
   - `Grep "if __name__ == .__main__." -l` → Python entrypoints
   - `Grep "func main" -l --type go` → Go entrypoints
   - `Grep "fn main" -l --type rust` → Rust entrypoints
   - `package.json` `"main"` / `"bin"` / `"scripts": { "dev": ... }` fields → JS entrypoints
   - Look for `index.ts`, `main.ts`, `server.ts`, `app.ts`, `manage.py`, `wsgi.py`, `asgi.py`, `cli.py`

5. **Find tests**. Glob for `test_*.py`, `*_test.go`, `*.test.ts`, `*.spec.ts`, `tests/`, `__tests__/`. Note the framework (pytest, jest, vitest, go test, cargo test).

6. **Find conventions**. Greps that pay off:
   - Indent style: peek at 2-3 source files (Read top 30 lines each, max)
   - Linter/formatter configs: `.eslintrc*`, `.prettierrc*`, `pyproject.toml [tool.ruff]`, `rustfmt.toml`, `.editorconfig`
   - CI config: `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Makefile` targets

7. **Stop**. Resist the urge to read more. If you're tempted to Read a 6th source file, write what you've inferred and let `/lore:refresh` correct you later.

## Phase 2 — Synthesize the CLAUDE.md block

Produce a managed block that goes at the **top** of `CLAUDE.md`. Keep it under 100 lines. Aim for facts, not narrative. Use this exact structure (skip any section you couldn't confidently determine — never invent):

```markdown
<!-- BEGIN lore-managed: do not edit between these markers. Run /lore:refresh to update. -->
<!-- lore-version: 0.1.0 -->
<!-- last-learned: YYYY-MM-DD -->
<!-- last-sha: <git head sha> -->

# Project: <name from package.json/pyproject.toml or directory name>

<one-sentence purpose if you have high confidence — otherwise omit>

## Stack
- Language(s): ...
- Framework(s): ...
- Package manager: ...
- Runtime / version pin: ... (from .nvmrc / .python-version / etc., omit if absent)

## Commands
- Install: `...`
- Build: `...`
- Test: `...`
- Lint: `...`
- Dev / run: `...`
- Type-check: `...` (if applicable)

## Layout
- Entry point: `path/to/file`
- Source: `path/`
- Tests: `path/`
- Config: `path/` (if non-obvious)

## Conventions
- Indent: <2-space | 4-space | tab>
- Style enforcement: <prettier | ruff | rustfmt | gofmt | none-detected>
- Test framework: ...
- Naming: <only include if you observed a pattern, e.g., "snake_case for python, camelCase for JS">

<!-- END lore-managed -->
```

**Hard rules for writing to CLAUDE.md:**

- If `CLAUDE.md` does not exist: create it with the lore-managed block, then a blank line, then a comment `<!-- Add project-specific instructions below this line. -->`.
- If `CLAUDE.md` exists and already contains `<!-- BEGIN lore-managed` and `<!-- END lore-managed -->`: Use the Edit tool to replace **only** the content between (and including) those markers. Leave everything else in the file alone.
- If `CLAUDE.md` exists with no lore markers: Use Edit to **prepend** the new lore-managed block plus one blank line at the very top of the file. Do not touch any existing content. Use Read first to capture the existing content, then Edit on the file's first line to insert before it.
- Never delete or rewrite human-authored content outside the markers.
- Never include a section you couldn't determine. Empty sections are worse than missing ones.

If `.claude/CLAUDE.md` exists instead of `CLAUDE.md` at root, edit that file instead. If neither exists, create `CLAUDE.md` at the repo root (it's the more common location and works for both team-shared and personal use).

## Phase 3 — Seed the memory directory

The auto-memory directory for this repo is at `$HOME/.claude/projects/<key>/memory/` where `<key>` is the absolute path of the git root (or cwd if not a git repo) with `/` replaced by `-`. The exact path was printed above in the live context block; use it.

Create the directory if missing (`mkdir -p`), then write these files. Each one is plain markdown. **Do not** duplicate what you wrote to CLAUDE.md — memory is for things CLAUDE.md shouldn't carry every turn.

### `MEMORY.md` (the index)

Keep it under 200 lines (Claude Code only loads the first 200 lines / 25KB). Format:

```markdown
---
project: <name>
learned: YYYY-MM-DD
---

# Memory index for <name>

Topic files in this directory. Claude reads them on demand.

- [Architecture](lore-architecture.md) — system shape, module boundaries, data flow
- [Gotchas](lore-gotchas.md) — landmines, surprising behavior, things that bit past sessions
- [History](lore-history.md) — what's been worked on recently, by lore
```

If `MEMORY.md` already exists, **do not overwrite it** — append/merge your lore section. Other tools and the user may have written to it.

### `lore-architecture.md`

3–10 short bullets on system shape: how data flows from entry to data store, which modules talk to which, any unusual architecture pattern. If you don't have high confidence, write less. One accurate sentence beats a paragraph of plausible-sounding fiction.

### `lore-gotchas.md`

Start with a header and a single line: `(populated by /lore:refresh as gotchas are observed)`. This file grows over time — leave room for it.

### `lore-history.md`

Initial entry recording the onboarding. Format:

```markdown
# Lore history

## YYYY-MM-DD — initial onboarding
- HEAD: <sha>
- Stack: <one-line summary>
- Notes: <anything noteworthy you observed but didn't put in CLAUDE.md>
```

## Phase 4 — Write the state file

Write `.claude/lore-state.json` in the **user's repo** (create the `.claude/` directory first if needed). Schema:

```json
{
  "version": 1,
  "loreVersion": "0.1.0",
  "lastLearnedSha": "<git head sha, or null if not a git repo>",
  "lastLearnedDate": "<ISO 8601 UTC>",
  "repoRoot": "<absolute path to git root or cwd>",
  "repoRemote": "<git remote origin url, or null>",
  "memoryDir": "<absolute path to ~/.claude/projects/<key>/memory>",
  "watchFiles": [
    "package.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "pyproject.toml",
    "requirements.txt",
    "poetry.lock",
    "Cargo.toml",
    "Cargo.lock",
    "go.mod",
    "go.sum",
    "README.md",
    "ARCHITECTURE.md",
    "Dockerfile",
    "docker-compose.yml",
    "Makefile",
    "justfile"
  ],
  "driftThresholds": {
    "commits": 20,
    "days": 30
  }
}
```

Use the actual current values from the live context, not placeholders. Pretty-print with 2-space indent so humans can read it.

Then ensure `.claude/lore-state.json` is in `.gitignore`:

- If `.gitignore` exists and does not contain `.claude/lore-state.json` (or `.claude/`): append a section:
  ```
  
  # lore (https://github.com/Luis-avalos1/lore)
  .claude/lore-state.json
  ```
- If `.gitignore` does not exist: create it with the lore section.
- If `.claude/` is already ignored broadly: do nothing.

## Phase 5 — Final summary to the user

After writing all files, print **one** short summary to the user. No tables, no markdown lists. Two or three sentences max. Example:

> Learned this repo (TypeScript / Next.js, pnpm, vitest). Wrote a lore-managed block to CLAUDE.md and seeded 4 memory files at `~/.claude/projects/...`. Future sessions will load this automatically — run `/lore:status` to inspect, `/lore:refresh` after big changes.

## Edge cases

- **Not a git repo**: still works. Use cwd as the project key. State file `lastLearnedSha` is `null`. The hook will use mtime-based drift detection instead.
- **No README, no manifests**: write what little you can confidently determine (just the layout section + commands you can infer from scripts/Makefile). Don't fabricate.
- **Huge monorepo**: stick to the top-level workspace file and one representative package. Note in `lore-architecture.md` that this is a monorepo and which package was used for convention detection.
- **CLAUDE.md is symlinked**: detect with `test -L CLAUDE.md`. If it's a symlink (likely to `AGENTS.md`), edit the target file instead — but only if the target is inside this repo. If it's outside the repo, write to `.claude/CLAUDE.md` instead and explain in the final summary.
- **Existing lore block from older version**: replace it fully. Don't try to merge field-by-field.
- **Existing lore block looks fresh (last-sha matches current HEAD)**: still rewrite it — the user explicitly invoked `/lore:learn`. Use `/lore:refresh` for the conservative incremental path.

## What NOT to do

- Do not run linters, tests, builds, or installers. Read the commands; don't execute them.
- Do not commit anything. Just write files; the user controls git.
- Do not invent file paths or claim things you didn't verify. If you didn't grep for it, don't write it.
- Do not produce a long final report. The files are the report; the chat summary is two sentences.
- Do not touch files outside `CLAUDE.md`, `.claude/lore-state.json`, `.gitignore`, and the auto-memory directory.
