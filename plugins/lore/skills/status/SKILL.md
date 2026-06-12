---
description: Show whether lore's managed block in CLAUDE.md has drifted since the last refresh. Use when the user asks "is lore up to date", "what does lore know", or to inspect the lore state file before deciding whether to refresh.
when_to_use: Read-only inspection. Reports last-refresh date, current drift (commits, watch files, days), effective thresholds, and whether CLAUDE.md still has the managed block. Does not modify anything.
allowed-tools: Read Bash(bash *)
---

# /lore:status — is lore up to date?

This is a **read-only** status report. Do not write any files. Do not modify CLAUDE.md or the state file. Just present the facts below concisely.

## Live status

A bundled recon script ran before you saw this skill. It uses the exact same drift logic as the SessionStart hook, so report its output verbatim — do not recompute.

!`bash "${CLAUDE_SKILL_DIR}/scripts/recon.sh"`

## How to present this

Answer in a tight format: three or four short lines, no headers, no tables.

If `NO_STATE` and CLAUDE.md has no lore-managed block:
> No lore state for this repo yet. Run `/lore:refresh` to bootstrap a managed block in CLAUDE.md.

If `NO_STATE` but CLAUDE.md **has** a lore-managed block (fresh clone — the baseline is per-machine and gitignored):
> CLAUDE.md has a lore-managed block (last refreshed <DATE from the block>), but no local baseline. Run `/lore:refresh` to rebuild it.

If state exists, no drift:
> Lore last refreshed <DATE> at <SHA[:12]>. No drift detected (thresholds: <X> commits / <Y> days).

If state exists, drift detected:
> Lore last refreshed <DATE> at <SHA[:12]>. <X> commits, watch files changed: <list>. Run `/lore:refresh` to catch up.

If the recon output says `watch files changed: none`, write `<X> commits since last refresh, no watch-file changes` instead — that's the case where the block is probably still accurate and `/lore:refresh` is optional.

Add one extra line ONLY if something looks off, one sentence each. Examples: the lore-managed block was removed from CLAUDE.md (suggest `/lore:refresh force`); nudges are disabled for this repo; the baseline commit is missing (rebase or shallow clone).

## Do not

- Do not write any files.
- Do not run git commands beyond what the recon script already produced.
- Do not produce a long report. The user wants a glance.
