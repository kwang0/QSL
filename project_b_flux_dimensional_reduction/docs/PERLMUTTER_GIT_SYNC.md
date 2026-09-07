# Git push/pull with Perlmutter

Use `https://github.com/kwang0/QSL.git` for source, documentation and locally
prepared launch inputs. Commit compact sealed controls under `configs/controls/`
with their active references and pinned source so a single push/pull delivers
the prepared run. The owner runs all Perlmutter commands manually.

The original repository is `~/QSL`; Project B runs from the clean sparse
worktree `~/QSL-project-b`. Its ignored `output` link accesses existing data in
the original directory. The current pilot needs no additional local-to-Perlmutter
transfer beyond Git: the parent and bridge are existing data, and preflight
generates fresh accounting and scratch-audit records on Perlmutter.

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

## Pull and execute the pilot

The owner has completed the worktree setup above. The first preflight exposed
an ignored control missing on Perlmutter. That control now lives at tracked
`configs/controls/solver_pilot_control_v2.toml`, with the same SHA-256
`969b69b1c40d3a70e07c58fe9b12d123564781c5f40b9a4058b74f4382278818`.
The active reference points there, so pulling the branch fixes its delivery.

Run manually on Perlmutter:

```bash
cd ~/QSL-project-b &&
git pull --ff-only &&
cd project_b_flux_dimensional_reduction &&
bash slurm/run_mpskit_solver_pilot_cpu.sh preflight &&
bash slurm/run_mpskit_solver_pilot_cpu.sh submit &&
bash slurm/run_mpskit_solver_pilot_cpu.sh status
```

The chain stops on any failure and submits only after `PREFLIGHT PASSED`.

## Routine updates

On Windows, prepare and validate source changes and any new compact launch
inputs, commit them with their active references, and push the intended branch.
Controls are immutable; a pinned source change requires a new control filename.
On Perlmutter, use `~/QSL-project-b`, verify that its worktree
is clean and on the corresponding branch, then use `git pull --ff-only`. If either check
fails, review the difference; do not discard remote edits. Compare `git
rev-parse HEAD` on both computers when an exact version matters.

The active reference pins the control SHA-256, and the control pins the source,
environments, parent and bridge. Preflight verifies the pulled files and the
existing scientific data, then creates live accounting and scratch evidence.
No separate transfer of locally generated accounting records is required.

The active runbook is [the review follow-up plan](plans/REVIEW_FOLLOWUP_IMPLEMENTATION.md).
Its `preflight` action verifies context, reconciles accounting, audits the
required scratch files and executes the guarded live plan. Only the owner
submits the pilot after that action succeeds. Source and state hashes remain
the identity checks after a Git update.

If later work needs selected new scientific payloads or run results on the
other computer, checksum-sync those files separately with Globus. Use the
original canonical output directory, keep destination deletion disabled, and
exclude tracked source, `.git`, `.julia` and `$PSCRATCH`. This is a data transfer
only when needed; prepared compact launch inputs belong in Git.
