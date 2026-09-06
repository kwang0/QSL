# Superseded cross-device bootstrap

This filename is retained so links from the 2026-08-25 handoff do not break.
Its former prompt embedded a specific transfer commit, benchmark status, and
authorization boundary that are now historical.

Use [`NEW_TASK_PROMPT.md`](NEW_TASK_PROMPT.md) for every new Codex conversation
or device. It routes the task through the rolling
[`PROJECT_STATE.md`](PROJECT_STATE.md), the stable architecture map, and a
cross-platform read-only audit instead of copying mutable state into a prompt.

The original transfer prompt remains available in Git history at commit
`0e244cb5ddd3efea98ad96bd281ed395fd31202d`.
