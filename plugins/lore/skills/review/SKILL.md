---
description: Review the human-written PROSE of CLAUDE.md for staleness — claims, sections, and file paths that the repo has outgrown — and propose conservative, evidence-backed edits before applying them. Never touches lore's managed block.
when_to_use: Run when the SessionStart hook reports prose drift, or on demand to audit CLAUDE.md prose. Model-driven review of everything OUTSIDE the lore-managed markers. Presents findings first, edits prose only after; the managed block is /lore:refresh territory.
disable-model-invocation: true
allowed-tools: Read Write Edit Glob Grep Bash(bash *) Bash(git *) Bash(jq *) Bash(date *) Bash(cat *) Bash(ls *) Bash(head *) Bash(wc *) Bash(grep *) Bash(sed *) Bash(awk *) Bash(find *) Bash(test *) Bash(echo *)
---

# /lore:review — audit CLAUDE.md prose for staleness

lore keeps a tiny machine-managed block at the top of CLAUDE.md fresh (that's `/lore:refresh`). Everything below it is human-curated prose — architecture notes, conventions, paths, command examples — and prose rots silently. This skill reviews **only that prose**, proposes concrete edits, and applies them **after** you present findings.

## The one hard rule

**NEVER edit anything between `<!-- BEGIN lore-managed` and `<!-- END lore-managed`.** That block belongs to `/lore:refresh`, which routes edits through the deterministic writer. The recon output prints its exact line range. Treat those lines as read-only. If the *only* staleness you find is inside the managed block, do not touch it — tell the user to run `/lore:refresh` instead, and stop.

## Live context

A bundled recon script ran before you saw this skill. It reports the date, the lore version, which CLAUDE.md is in play, the managed-block line range (OFF LIMITS), a deterministic dead-ref pre-scan, repo context, and the full file inline. Use it instead of re-running its commands.

!`bash "${CLAUDE_SKILL_DIR}/scripts/recon.sh"`

## When to stop immediately

- Recon says no CLAUDE.md, or the file is nothing but the managed block (no prose outside the markers) → say so in one line and stop. Nothing to review.
- Recon says the markers are malformed → do not edit; tell the user to run `/lore:refresh force`, and stop.

## How to review

Read the whole CLAUDE.md from the recon output (Read the file only if it was truncated past 400 lines). Then judge the **prose outside the managed block** against the actual repo:

1. **Verify each dead ref from the pre-scan.** The scanner is deterministic and conservative; confirm each one. Was the file renamed or moved? `grep`/`Glob` for the basename to find the new path and propose it as the replacement. If it was deleted outright, propose removing or rewriting the sentence that cites it.
2. **Scan the rest of the prose for staleness the scanner can't see** — evidence-backed only:
   - commands or scripts the prose documents that no longer exist (check manifests, Makefile/justfile targets, package scripts),
   - renamed or removed directories referenced in prose,
   - framework / language / version claims contradicted by the repo (manifests, lockfiles, recent history),
   - instructions describing a workflow the recent commit history shows was replaced.
3. **Be conservative.** Only findings you can back with a specific repo fact. When unsure, leave it. Never delete large prose sections wholesale — propose a targeted rewrite, not a purge.

## Present, then apply

Show the user a short **numbered list** of findings before editing anything. For each: the current text (quote the stale phrase or line), why it's stale (the repo evidence), and the proposed replacement text (or a small diff). Keep it tight — a glance, not a report.

Then apply the accepted edits to the prose with `Edit`, one finding at a time. Prose only, always outside the markers.

## What NOT to do

- Do not edit inside the `BEGIN`/`END lore-managed` markers — ever. That's `/lore:refresh`.
- Do not delete large prose sections wholesale. Targeted, evidence-backed edits only.
- Do not invent findings. No repo evidence, no edit.
- Do not run linters, tests, builds, or installers. Read scripts; don't execute them.
- Do not commit anything.
- Do not produce a long report. The numbered findings and the edits are the output; the chat summary is one or two lines.
