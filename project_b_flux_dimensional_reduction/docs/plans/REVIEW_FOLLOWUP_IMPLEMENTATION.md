# Review follow-up implementation

Authorized by the owner on 2026-09-06 following decision 002. Perlmutter
execution is always manual by the owner; Codex implements and tests locally.

## Scope and progress

- [x] Common allocation accounting and cumulative Phase 1 guard across launchers.
- [x] Actual Julia RSS, step accounting, and copied-worker checks.
- [x] Reproducible scalar/lineage/checkpoint audit with explicit evidence limits.
- [x] Independent finite-Hamiltonian, gauge, distinct-state and residual-decrease tests.
- [x] Immutable, hash-pinned chi-512 MPSKit VUMPS/gradient pilot, at most 0.5 node-hours.
- [x] Local pilot smoke tests and common-representation analysis.
- [x] Owner supplies live terminal status, queue snapshot, and step-level accounting.
- [ ] Owner completes common live reconciliation and hash-verified scratch audit.
- [ ] Owner runs successful live plan then submits the pilot; reconcile and analyze.
- [ ] Select scientific successor using pilot and continuity evidence.

Keep the accepted theta/pi=0.15 parent, existing campaign thresholds, and
one-job policy. Pilot states are diagnostics until all declared gates are
evaluated; no automatic primary-lineage promotion or theta advance is allowed.
Later items depend on remote evidence and must not be marked complete from
local simulations or a structural plan.

## Owner-reported live evidence, September 6

The owner ran status, squeue and step-level sacct. Job 57801654 is COMPLETED,
exit 0:0, elapsed 124893 seconds, NCPUS=18, ReqMem=32G. Its Julia step
`57801654.0` reports 124833 seconds, 8 CPUs and MaxRSS=2776996K
(approximately 2.65 GiB); the batch shell's RSS is a different measurement.
The queued `lmf1-*` jobs belong to another project. No Project B job was
present in that queue snapshot. Scratch presence/hashes and later allocation
accounting still need the commands below.

The first owner-run preflight attempt exposed two operational failures: the
Globus source export has no Git metadata, and the Aug 1 to Sep 6 `sacct`
query exceeded NERSC's [31-day query limit](https://docs.nersc.gov/jobs/monitoring/).
The later Ctrl-C traces occurred during file hashing and Julia compilation.
They do not establish a solver failure, completed scratch audit or successful
plan. The revised preflight stops on its first failed stage, uses contiguous
28-day accounting windows, and prints hashing/compilation progress.

The owner prefers Git for future source synchronization. The
[Git adoption guide](../PERLMUTTER_GIT_SYNC.md) preserves the existing remote
working files; Globus remains the transport for ignored artifacts. Source
export validation remains available while Git is being established.

## Prepared experiment

`configs/mpskit_solver_pilot.toml` declares three independent starts from the
accepted parent: VUMPS at theta/pi=0.15, then VUMPS and GradientGrassmann at
0.2. Virtual spaces stay fixed at chi512. The two native errors are distinct;
both also need a four-iteration energy window of span <=1e-8. Common
representation checks require overlap >=0.99 plus entropy, local energy,
magnetization, Schmidt, correlation-length and U1 diagnostics. These are
pilot criteria, with no changes to the old campaigns or automatic acceptance.

The allocation is Shared QOS, 10 logical CPUs, a 4-CPU solver step, 2 Julia
threads, single-thread BLAS, 16G, and 12 hours. The reservation is 0.46875
node-hours, below the authorized 0.5 cap. Stages have separate wall limits;
USR1 requests a stop at a completed iteration. Long individual iterations or
line searches can still reach Slurm's hard timeout; scratch checkpoints and
the scalar journal preserve completed work. Runtime and common analysis are
both inside the same allocation.

Pilot schema 2 stores the complete canonical AL/C/AR tensors. An AL-only
identity integration test exposed a negative transfer fixed-point eigenvalue
in the legacy reconstruction even for the accepted parent. Exporting the
existing canonical tensors permits direct isometry and center-relation
checks without relaxing that legacy importer's tolerances.

The active reference `configs/mpskit_solver_pilot_active_control.ref` points to
`output/review_followup/solver_pilot_control_v2.toml`, SHA-256
`969b69b1c40d3a70e07c58fe9b12d123564781c5f40b9a4058b74f4382278818`.
This revision pins the operational fixes. It preserves the three scientific
stages, thresholds and resource limits; the recipe changes only the new audit
report path. The initial control `solver_pilot_control.toml` with SHA-256
`6069c11474072d57d05b51efea9c4ff41f74eff3a5eaa15ad5dd91ed0c5447e1`
and its numerical validation record `local_validation.toml` remain immutable.
Transfer the active control with the exact source it pins; a later source edit
requires a new control and reference update.

## Perlmutter command sequence

Publish and fetch the changed source through Git once the existing remote
export is connected and its differences are reviewed. During Git setup, a
completed source checksum sync is also supported. While no Project B job
writes the destination, checksum-sync the ignored
`output/review_followup/solver_pilot_control_v2.toml` and `output/accounting/`.
The existing accepted parent and MPSKit bridge remain the input files; no new
full-state copy is needed. Verify publication of
`codex/project-b-review-followup` before the first fetch.
The initial `main` adoption preserves existing files and needs review before
switching to that source branch.

Run manually on Perlmutter:

```bash
cd ~/QSL/project_b_flux_dimensional_reduction
bash slurm/run_mpskit_solver_pilot_cpu.sh preflight
```

This child Bash process runs context/source checks, live reconciliation,
the selected scratch audit and the full live plan in order. It stops at the
first error without closing the interactive SSH shell and never submits.
The scratch audit hashes the returned candidate and checkpoints 52 and 60,
reads scalar metadata without optimizing, and writes
`output/review_followup/checkpoint_audit_57801654_v2.toml`. The full 30-checkpoint
history remains an optional `--all` audit to a separate new report. Existing
valid reports are reused; controls and reports are never overwritten.
Hashing reports file names and sizes. First-use solver compilation can take
several minutes even though the executable checks use tiny test states.

After `PREFLIGHT PASSED`, submit the one authorized pilot; submission repeats
the full guards against current source and accounting:

```bash
bash slurm/run_mpskit_solver_pilot_cpu.sh submit
bash slurm/run_mpskit_solver_pilot_cpu.sh status
```

After the job becomes terminal:

```bash
bash slurm/run_mpskit_solver_pilot_cpu.sh reconcile
bash slurm/run_mpskit_solver_pilot_cpu.sh analyze
```

Return the plan, checkpoint-audit summary, final status and analysis output.
Checksum-sync the compact run package back to Windows after the job stops.
Full candidate tensors stay in scratch until a reviewed state is deliberately
selected. A missing common analysis or a failed native/continuity gate means
the scientific successor still needs review; it is not evidence of a spinodal.

## Successor decision

- If the baseline reproduces the parent and a difficult-point method passes
  every declared check, review it as evidence of recoverability. Preparing a
  continuation still requires explicit owner direction for a new parent.
- If native convergence fails, report a solver/budget limit and use the
  retained histories and checkpoints to choose a bounded next diagnostic.
- If native convergence passes but continuity fails, keep that candidate as
  a separate basin diagnostic. Design independent entangled U1 preparations
  and forward/reverse tests before a physical branch-loss claim.
- A chi1024 resume must separately justify both convergence and continuity.
  The old 32G/48h reservation is 3.375 node-hours and exceeds the currently
  remaining Phase 1 allowance.

## Validation record

The operational revision passes 51 focused Julia assertions for allocation
accounting, date-window coverage/deduplication, native/streaming hash parity,
Git-free source validation and unchanged data/audit gates. Launcher regressions
inject failures at five stages and verify that no later stage or submission
runs. The revised copied worker executes both tiny solver kernels and HDF5
I/O successfully. A six-assertion Git fixture confirms that mixed-reset
adoption preserves modified source, new files, ignored data and another
project's files. All Slurm Bash syntax checks pass. The operational evidence
is `output/review_followup/local_validation_v2.toml`; the original numerical
validation remains attached to its original control. Scientific kernel,
analysis and environment hashes are unchanged, so their full numerical suites
were not repeated for these operational edits.

The existing root Julia suite, new accounting tests, independent finite-cylinder
tests, distinct-state overlap and VUMPS residual-decrease tests pass locally.
Both MPSKit algorithms passed executable smoke tests. The U1 pilot tests cover
graceful stopping, finite energy/error records, immutable export and tensor
round trips. The full chi512 common-representation round trip passes all six
assertions: cross-library energy difference 2.665e-15, overlap per site 1.0,
maximum cut-entropy difference 3.743e-6, and all multimetric checks passing.
The center-relation error is 3.279e-15. No optimization was performed, so
the fixture correctly remains native-ineligible and unaccepted. Compact
evidence is in `output/review_audit/accepted_parent_roundtrip/`; its transient
full tensor payload was removed after validation.

The copied pilot worker passed executable VUMPS, GradientGrassmann and HDF5
checks in a local structural plan. The full chi512 accepted bridge constructs
successfully in MPSKit: energy density is -0.5071942384761774, within
7.95e-8 of the stored parent energy. Its initial MPSKit Galerkin error is
8.081699547412416e-5; it is a distinct quantity from the parent artifact's
ITensor residual. This fixture performs no optimization or acceptance.

The independent Hamiltonian test also exposed and fixed a nonzero-Bz OpSum
construction error. Both cylinder geometries pass the matrix and gauge
checks; the campaign uses Bz=0.

The scalar audit covers 48 unique artifacts and all 60 logged outer
iterations. It records per-cut entropy, local energy patterns, U1 support,
qualified fixed-chi finite-step fidelity susceptibility, and explicit xi units.
Unavailable diagnostics remain unavailable. The audit does not establish
gauge-equivalent period-2 tensors for the YC6 period-6 branch.

The final scalar audit is `output/review_audit/20260906_final/audit.toml`,
with `lineages.tsv` beside it. The scan and iDMRG launcher regressions pass,
including execution from a copied worker path. Bash syntax checks pass for
all Slurm scripts. The historical resource-benchmark control still pins its
original worker and launcher; its old replay test is not a validation of
the revised source and was not rerun. A future benchmark needs a newly
prepared control, preserving the completed benchmark evidence.
