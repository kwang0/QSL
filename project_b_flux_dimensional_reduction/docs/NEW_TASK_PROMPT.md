# Fresh Codex task bootstrap

Use this prompt when opening a new conversation in this project on Windows,
Perlmutter, or another synchronized checkout. It intentionally contains no job
ID, mutable endpoint, or copied project status.

```text
Continue Project B from the current state recorded in this checkout. Do not
rely on or ask me to reconstruct an earlier conversation.

Before substantive action, read completely:
1. AGENTS.md
2. docs/PROJECT_STATE.md
3. docs/ARCHITECTURE.md
4. docs/plans/README.md
5. the active plan and decision sources that PROJECT_STATE.md names

Then begin read-only by running:

    julia --startup-file=no scripts/audit_project_context.jl

Report the Git root, branch, HEAD, complete dirty state, instruction and state
files found, every active-control reference and hash result, and the freshness
boundary of the local output mirror. Preserve every existing change.

This local computer is Windows with PowerShell; Perlmutter is a separate Linux
system. Perlmutter is authoritative for live Slurm state, accounting, scratch
contents, and newly generated run artifacts. Use only the minimal remote
status/hash evidence needed, and never put `set -e` or `set -euo pipefail` in
commands for my interactive Perlmutter SSH shell.

Before changing or running anything, summarize the current objective,
accepted lineage, latest trusted result, unresolved issues, and next priority
from the repository sources. Use the documented guarded launchers for remote
work and honor the standing authorizations and exclusions in AGENTS.md and
PROJECT_STATE.md.

After substantial work, update only the durable layer that changed:
PROJECT_STATE.md for current status, ARCHITECTURE.md for design,
docs/decisions/ for durable rationale, and the relevant plan for execution
progress. Conversation history is working memory, not authority.
```

The audit command is intentionally the same on both operating systems. It uses
only Julia standard libraries and does not modify the checkout.
