# Git source sync with Perlmutter

Use the existing repository `https://github.com/kwang0/QSL.git` for source,
configuration templates and documentation. The repository root is `~/QSL`,
one level above Project B. The owner runs all Perlmutter commands manually.

Git does not include Project B's ignored `output/`, full HDF5 states, caches
or scratch packages. Continue using checksum-verified Globus transfers for
the required compact controls, accounting and selected durable states. Keep
destination deletion disabled and exclude `.git`, `.julia` and `$PSCRATCH`.
Once Git is established, exclude tracked source from routine data transfers.

## Adopt the existing directory without replacing its files

The follow-up source branch is `codex/project-b-review-followup`. Verify that
it has been published before trying to fetch it. The adoption below starts
from the established `main` history so the existing source differences can be
reviewed; it does not install the follow-up branch or overwrite those files.

For the existing Git-free Perlmutter directory, the following creates Git
metadata and attaches the upstream history while preserving every working
file, including outputs and other QSL projects. The mixed reset updates only
HEAD and the index; existing file differences remain visible for review.
Do this while no task is editing the source tree.

Run manually on Perlmutter:

```bash
cd ~/QSL
if [ -e .git ]; then
    git status --short --branch
else
    git init -b main &&
    git remote add origin https://github.com/kwang0/QSL.git &&
    git fetch origin &&
    git reset --mixed origin/main &&
    git branch --set-upstream-to=origin/main main &&
    git status --short --branch
fi
```

Return the status output before the first pull or branch switch. A transferred
source export can differ from the upstream commit; review and preserve those
differences first. If initialization or authentication fails, stop at that
error. An existing `.git` directory is inspected rather than reinitialized.
No `.git` transfer, hard reset, forced checkout or cleanup is needed.
Once its existing source differences are resolved, use the published follow-up
branch for the current pilot. Other QSL projects' changes remain separate.

## Routine updates after the initial differences are resolved

On Windows, commit the reviewed source changes on the intended branch and
push that branch. On Perlmutter, verify that the worktree is clean and on
the corresponding branch, then use `git pull --ff-only`. If either check
fails, review the difference; do not discard remote edits. Compare `git
rev-parse HEAD` on both computers when an exact version matters.

Then checksum-sync any new ignored control and compact accounting artifacts.
The pilot active reference pins the exact control SHA-256, and the control
pins the source, environments, parent and bridge. A Git commit match alone
does not establish that the ignored inputs are present or valid.

The active runbook is [the review follow-up plan](plans/REVIEW_FOLLOWUP_IMPLEMENTATION.md).
Its `preflight` action verifies context, reconciles accounting, audits the
required scratch files and executes the guarded live plan. Only the owner
submits the pilot after that action succeeds. The source-export audit mode
remains available during the transition to Git.
