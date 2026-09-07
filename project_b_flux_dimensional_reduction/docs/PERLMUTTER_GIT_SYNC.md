# Git source sync with Perlmutter

Use the existing repository `https://github.com/kwang0/QSL.git` for source,
configuration templates and documentation. The repository root is `~/QSL`,
one level above Project B. The owner runs all Perlmutter commands manually.

Git does not include Project B's ignored `output/`, full HDF5 states, caches
or scratch packages. Continue using checksum-verified Globus transfers for
the required compact controls, accounting and selected durable states. Keep
destination deletion disabled and exclude `.git`, `.julia` and `$PSCRATCH`.
Once Git is established, exclude tracked source from routine data transfers.

## Git history is attached; preserve the existing export

The owner attached `~/QSL` to `origin/main` and fetched the published
`codex/project-b-review-followup` branch. The resulting status shows missing,
modified and untracked files across the repository. The mixed reset did not
delete working files: its `D` entries describe files already absent from the
export compared with the upstream tree. An `M` alone does not distinguish
content changes from executable-mode changes.

Use a separate linked worktree for Project B source. The existing `~/QSL`
files and other projects stay available for their current work. The linked
checkout reuses the Git object database already downloaded into `~/QSL/.git`.
Cone-mode sparse checkout materializes Project B and the small root-level
files, while leaving the other large tracked data directories unpopulated.
This follows Git's [worktree](https://git-scm.com/docs/git-worktree) and
[sparse-checkout](https://git-scm.com/docs/git-sparse-checkout) interfaces.

## Create the Project B source worktree

Run manually on Perlmutter:

```bash
git -C "$HOME/QSL" fetch origin &&
git -C "$HOME/QSL" worktree add --no-checkout \
    -b codex/project-b-review-followup "$HOME/QSL-project-b" \
    origin/codex/project-b-review-followup &&
git -C "$HOME/QSL-project-b" sparse-checkout init --cone &&
git -C "$HOME/QSL-project-b" sparse-checkout set project_b_flux_dimensional_reduction &&
git -C "$HOME/QSL-project-b" read-tree -mu HEAD &&
ln -sT "$HOME/QSL/project_b_flux_dimensional_reduction/output" \
    "$HOME/QSL-project-b/project_b_flux_dimensional_reduction/output" &&
git -C "$HOME/QSL-project-b" status --short --branch
```

Run this creation block once. If the directory or branch already exists,
stop at Git's error and inspect that existing setup rather than using a force
option. `read-tree` populates only the newly created worktree after its sparse
configuration; it is never run against the original export. No source file
in `~/QSL` is overwritten. Project B's states are accessed through the output
link without copying them.

The directory link points to the original canonical output. The `/output`
ignore rule covers both a directory and this link. Keep `~/QSL/.git` and the
original output directory in place; the new checkout uses both. The old and
new source trees share one Project B budget, lock and one-job rule.

Local validation exercised this sequence with missing, modified and untracked
files, a separate project's edits and a linked data directory. All 14
preservation and ignore-rule assertions passed. The transcript is
`output/review_audit/sparse_worktree_preservation_test_final.log`.

## Data sync and execution

Checksum-sync the new ignored
`output/review_followup/solver_pilot_control_v2.toml` and any needed
`output/accounting/` evidence from Windows to the original Perlmutter path
under `~/QSL/project_b_flux_dimensional_reduction/output/`. The new checkout
sees them through its link. Use the original data path as the Globus endpoint;
the source worktree does not need a second data transfer.

After that sync, run:

```bash
cd ~/QSL-project-b/project_b_flux_dimensional_reduction &&
bash slurm/run_mpskit_solver_pilot_cpu.sh preflight
```

After `PREFLIGHT PASSED`, the owner may run the guarded `submit` and `status`
commands in the active plan. A missing control requires the artifact sync;
Git alone cannot supply this ignored file.

## Routine source updates

On Windows, commit the reviewed source changes on the intended branch and
push that branch. On Perlmutter, use `~/QSL-project-b`, verify that its worktree
is clean and on the corresponding branch, then use `git pull --ff-only`. If either check
fails, review the difference; do not discard remote edits. Compare `git
rev-parse HEAD` on both computers when an exact version matters.

Then checksum-sync any new ignored control and compact accounting artifacts.
The pilot active reference pins the exact control SHA-256, and the control
pins the source, environments, parent and bridge. A Git commit match alone
does not establish that the ignored inputs are present or valid.

The active runbook is [the review follow-up plan](plans/REVIEW_FOLLOWUP_IMPLEMENTATION.md).
Its `preflight` action verifies context, reconciles accounting, audits the
required scratch files and executes the guarded live plan. Only the owner
submits the pilot after that action succeeds. Source and state hashes remain
the identity checks after a Git update or a data sync.
