# QSL workspace routing

This repository contains multiple research workspaces. Apply instructions only
to the subtree they govern.

- For any task concerning `project_b_flux_dimensional_reduction/`, read that
  directory's `AGENTS.md` completely before substantive action, even when the
  task was opened from this Git root. Then follow its resume contract and
  repository-state routing.
- Do not apply Project B scientific controls, storage rules, or authorization
  boundaries to work outside that subtree.
- Preserve unrelated worktree changes throughout the repository.

## Perlmutter execution preference

The project owner always executes Perlmutter commands manually. Work locally
and provide concise, tested commands for the owner's Perlmutter shell; do not
initiate SSH commands, remote jobs, or remote transfers on their behalf.
Ask for the smallest remote output needed and continue independent local work.

Use Git push/pull for local-to-Perlmutter source and prepared launch inputs,
including compact sealed controls and required manifests. Put new compact
launch inputs in tracked paths so a pull delivers them with their source.
Use Globus when selected scientific data or run results need a separate transfer;
never synchronize `.git` through Globus. Preserve existing files when connecting
a source export to Git.
