---
description: Show whether lore's managed block in CLAUDE.md has drifted since the last refresh. Use when the user asks "is lore up to date", "what does lore know", or to inspect the lore state file before deciding whether to refresh.
when_to_use: Read-only inspection. Reports last-refresh date, current drift (commits, watch files), and whether CLAUDE.md still has the managed block. Does not modify anything.
allowed-tools: Bash(bash *) Read
disable-model-invocation: false
---

# /lore:status — is lore up to date?

This is a **read-only** status report. Do not write any files. Do not modify CLAUDE.md or the state file. Just gather the facts and present them concisely.

## Live status

A bundled recon script runs before you see this skill. Use its output verbatim.

!`bash "${CLAUDE_SKILL_DIR}/scripts/recon.sh"`

## How to present this

Look at the live output above and answer in a tight format. Three or four short lines, no headers, no tables.

If `NO_STATE`:
> No lore state for this repo yet. Run `/lore:refresh` to bootstrap a managed block in CLAUDE.md.

If state exists, no drift:
> Lore last refreshed <DATE> at <SHA[:8]>. No drift detected.

If state exists, drift detected:
> Lore last refreshed <DATE> at <SHA[:8]>. <X> commits, watch files changed: <list from the recon output>. Run `/lore:refresh` to catch up.

If the recon output says `watch files changed: none`, write `<X> commits since last refresh, no watch-file changes` instead — that's the case where the block is probably still accurate and `/lore:refresh` is optional.

Add a fourth line ONLY if something looks off (e.g., CLAUDE.md exists but the lore-managed block was removed). One sentence each.

## Do not

- Do not write any files.
- Do not run git commands beyond what the recon script already produced.
- Do not produce a long report. The user wants a glance.
