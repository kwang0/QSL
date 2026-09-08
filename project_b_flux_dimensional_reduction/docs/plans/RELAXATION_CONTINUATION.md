# Bounded relaxation and flux-step comparison

Owner authorized on 2026-09-08: test whether limited relaxation preserves a
useful continuation before a later optimizer escape. Execution is manual on
Perlmutter. This diagnostic precedes the broader high-chi preparation work;
it does not implement or claim reproduction of Figure 2 energy gaps.

## Experiment

Use the same accepted chi512 parent at theta/pi=0.15, SHA-256
`38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`.
Every arm starts independently from that parent with random seed 101 reset.
Keep U(1), YC8-1, period 2,
uniform gauge, the existing Hamiltonian and pinned MPSKit 0.13.13 environment.

| Arm | Iterations at each flux | Fluxes theta/pi | Extra iterations at final flux |
|---|---:|---|---:|
| baseline | 32 | 0.15 | 0 |
| n8_grid1 | 8 | 0.175, 0.20 | 16 |
| n8_grid2 | 8 | 0.1625, 0.175, 0.1875, 0.20 | 16 |
| n16_grid1 | 16 | 0.175, 0.20 | 16 |
| n16_grid2 | 16 | 0.1625, 0.175, 0.1875, 0.20 | 16 |
| n32_grid1 | 32 | 0.175, 0.20 | 16 |
| n32_grid2 | 32 | 0.1625, 0.175, 0.1875, 0.20 | 16 |

These are **VUMPS outer iterations**, not iDMRG sweeps. VUMPS is chosen because
the previous matched pilot showed its substantial residual turnaround and
terminal continuity failure. This isolates the outer stopping policy without
simultaneously changing algorithms or bond dimensions. It does not establish
the authors' stopping rule. A later iDMRG comparison may still be useful.

There are 464 outer updates at most, including the baseline and holds. New
flux points rebuild their environments; a final fixed-flux hold continues the
same solver instance, preserving its iteration counter and accuracy schedule.
The inner accuracy policy matches the pilot. Every iteration saves a canonical
AL/C/AR checkpoint to scratch and a hash-backed compact record to output.

Only the predeclared N-th state seeds the next flux within its own diagnostic
arm. No best-residual substitution, cross-arm seed sharing or adaptive flux
step is used. A numerical/continuity gate failure does not prohibit these
explicitly authorized diagnostic steps. All resulting states remain
`continuation_accepted=false`; the accepted scientific lineage does not change.
An interrupted point is incomplete and cannot seed a subsequent point.

## What is measured

The `1e-5` Galerkin and four-record `1e-8` energy-span gate from the pilot is
reported for reference. It is not a stopping condition or a new production
acceptance rule. Existing campaigns retain their original gates.

The automatic analysis selects each N-th endpoint, the minimum residual up to
that endpoint, the final held state and the overall minimum when a hold exists.
It also selects the first sustained turnaround: three consecutive records
more than 5% above the running minimum. This is a **sampling marker**, never a
convergence criterion or an instruction to stop. Duplicate selections are
analyzed once. All other completed iterations remain available in scratch.

For each selected state the analysis verifies its payload hash, history,
U(1) basis, canonical relations and MPSKit/ITensor energy equality. It measures:

- energy, local energy terms, cut entropies and local magnetization;
- overlap, Schmidt changes, U(1) sectors and correlation-length changes against
  both the accepted parent and the immediate diagnostic seed;
- the same comparisons against the N-th endpoint for states during a hold;
- six leading transfer eigenvalues in each physical Sz=0 and Sz=1 sector,
  their Krylov convergence/residuals and YC8-1 momentum labels.

Inverse correlation lengths use complete period-2 transfer cells. Momentum
mapping receives theta in radians. These spectra are properties of diagnostic
states and must not be relabeled as energy gaps or accepted Figure 3 data.
Missing or unconverged transfer modes remain explicitly identified.

The compact summary compares energy, entropy and the complex Sz=1 spectrum at
common fluxes across step refinement and adjacent iteration-budget doubling.
Its bidirectional nearest-eigenvalue distance is a comparison aid, not a
one-to-one mode assignment or a promotion threshold. Review individual
momentum-resolved modes before interpreting a closing gap.

Evidence for useful limited relaxation would be a range of stopping budgets
with stable spectra under flux-step refinement, followed by a distinct later
escape at fixed flux. Strong dependence on N or step size would indicate
algorithmic lag. Neither a residual minimum nor a smooth curve establishes
adiabaticity, a local minimum or a physical spinodal. Higher-chi preparation
and the separate Figure 2 measurement remain necessary for reproduction.

## Resources and storage

One Shared-QOS CPU allocation: 10 logical CPUs, a four-CPU solver/analysis step,
two Julia threads, single-thread BLAS, 16G and a 36-hour hard limit. Its maximum
reservation is **1.40625 node-hours**, below the diagnostic cap of 1.5 and the
last reconciled Phase 1 balance of 1.953943142361. A fresh live guard must still
pass. No phase-budget reassignment is made.

The previous chi512 pilot measured about 179-206 seconds per late iteration.
464 updates alone suggest 23-27 hours; allow roughly **26-33 hours including
analysis and I/O**, with substantial uncertainty near an instability. This is
a forecast, not a convergence ETA. No new optimization starts after the
allocation's 34-hour soft deadline; USR1 at 35.5 hours requests a graceful
stop at a completed iteration. A long inner solve or spectrum calculation can
still reach the hard limit. Missing work is reported, not marked complete.

The uncompressed canonical payload is about 40 MiB per chi512 checkpoint:
approximately 18.4 GiB for all checkpoints and independent origins, excluding
filesystem/HDF5 overhead. Heavy files are under
`$PSCRATCH/QSL/project_b_flux_dimensional_reduction/relaxation/job_JOBID_HASH/`.
No tensor payload is copied into the project tree. Scratch remains purgeable.

Compact run packages are under
`output/mpskit_solver_pilot_jobs/relaxation/`. This is inside an existing common
accounting root: old and new source worktrees and all Project B launchers
share the same submission lock, one-job rule and Phase 1 budget. The old pilot
launcher is not the interface for this experiment.

## Run manually on Perlmutter

Sealed control: `configs/controls/relaxation_continuation_v1.toml`, SHA-256
`3e790f71089c87645fced05f1e7a0e7c3a49d78d5a6f5b73db19cfd0d7262fef`,
selected by `configs/relaxation_continuation_active_control.ref`.

The control and all prepared launch inputs arrive via Git. Existing accepted
parent and bridge tensors are read through the existing canonical output link.
This trial needs no chi1024 scratch checkpoint or repeat of its historical
audit, because no rejected chi1024 tensor is used.

```bash
cd ~/QSL-project-b &&
git pull --ff-only &&
cd project_b_flux_dimensional_reduction &&
bash slurm/run_relaxation_continuation_cpu.sh preflight &&
bash slurm/run_relaxation_continuation_cpu.sh submit &&
bash slurm/run_relaxation_continuation_cpu.sh status
```

`preflight` audits Git context, reconciles live accounting and executes the
full live `plan`, including source/data hashes and tests through a copied
worker. The `&&` chain submits only after that plan succeeds; `submit` repeats
the guards under the shared lock. No additional acknowledgement is needed.

For detailed status and the most recent solver output:

```bash
bash slurm/run_relaxation_continuation_cpu.sh progress
```

It prints the run directory, Slurm allocation/step accounting, scratch location
and the last 40 log lines. The default is the greatest recorded job ID;
`RUN_ID=JOB_ID bash slurm/run_relaxation_continuation_cpu.sh progress` selects a
specific job. To follow output continuously, use the printed run-directory path:

```bash
tail -f /printed/run/directory/logs/relaxation-JOB_ID.out
```

Ctrl-C exits `tail`; it does not cancel the job. Expect long quiet intervals
while Julia compiles, initializes environments or computes spectra.

After the job ends:

```bash
bash slurm/run_relaxation_continuation_cpu.sh reconcile &&
bash slurm/run_relaxation_continuation_cpu.sh analyze
```

`analyze` reads compact outputs and reports missing analyses or incomplete arms;
it does not rerun tensor calculations on a login node. Checksum-sync the compact
run package and `output/accounting/` back to Windows with Globus, mirroring and
deletion disabled. Full scratch checkpoints are excluded. Then review the
matched curves and holds locally before designing a successor.

## Local validation and remaining work

- Fixed-iteration/hold kernel, interruption, U(1) dimensions, energy consistency,
  minimum/turnaround selection and immutable export: 23 assertions passed.
- Tiny canonical import, provenance rejection and momentum units: nine passed.
- Schedule, parser, input coverage and retrospective accounting: 46 assertions
  passed against the final sealed control.
- Mocked launcher executes the copied worker; failure propagation, immutable
  submission, resource arguments and greatest-ID selection pass.
- Full chi512 bridge identity: ten assertions passed, with MPSKit/ITensor
  payload energy difference `2.2204460493e-15`, and all six requested modes
  converged in both Sz sectors (six neutral/eight charged modes converged).
  Recanonicalizing the historical AL bridge changes parent energy by
  `7.9410282683e-8`, below the existing `1e-6` model tolerance; it is not an
  exactly unchanged tensor. All arms use that same import procedure.
- Production analysis on an explicitly interrupted identity fixture:
  seven assertions passed; no optimization was performed by this fixture.
- Compact replay, missing/incomplete output reporting, spectrum comparison
  and provenance-tampering rejection: eight assertions passed.
- Real local Git push/pull into a clean sparse checkout passed: source hashes
  match, missing tensors block full validation, and altered runtime source is
  rejected. No ignored output supplied the prepared control.
- Final local `plan` passed through the copied worker with 23 solver and nine
  reader assertions, final sealed hashes and the retrospective accounting
  guard. The context audit passes with all four references matching, all 36
  documentation links resolve, and the final diff passes whitespace checks.
  Live authority is not inferred from these local checks.
- Live queue, fresh accounting, current parent/bridge presence, actual trial
  runtime and scientific outcome remain for the owner's Perlmutter execution.

No remote command, optimization run or transfer is initiated by Codex.
