# YC8-1 chi1024 VUMPS threading comparison

Status: v1 job 58275828 failed during startup; v2 fixes allocation handling
and is locally validated for an owner-run retry.
Date: 2026-09-14.

## Purpose and scope

The owner authorized a small threading comparison before larger-bond-dimension
preparation. Compare Julia/BLAS thread counts **2/1, 2/4 and 1/8** using exactly
the same chi1024 state and fixed-update VUMPS kernel as the limited-relaxation
experiments. Each fresh process runs one warm-up update and three measured
updates: twelve updates total. Initialization, canonical import and the first
update are excluded from the reported update times. All three trajectories
restart from the same seed; they do not continue one another.

The old chi512 one-site iDMRG benchmark varied Julia threads with BLAS fixed
at one and found little speedup. It did not measure these BLAS settings or
the current VUMPS kernel. This comparison measures that missing information.
Three samples give a provisional choice, not a precise scaling law or an
estimate of iterations needed for convergence. Keep the baseline if the
differences are small relative to their per-update variation.

## Timing seed and scientific boundary

`configs/seeds/thread_benchmark_chi1024.toml` identifies the **rejected**
chi1024 candidate at theta/pi=0.15 from job 57801654, SHA-256
`4e3a5f406f61cb791ea98ef6b0dc6cfb108877eb5199d4dc71d204f150c0a9e6`.
The September 7 owner-run audit recorded it in scratch. The full tensor is
not in the local mirror; preflight must establish its current presence and
hash under the owner's `$PSCRATCH`. A missing or changed seed prevents
submission. The tracked manifest supplies the exact path, so no compact
launch input needs a separate transfer.

Export its AL tensors once, convert their explicit U(1) bases and canonicalize
once in MPSKit. Check bond dimensions, charge multiplicities, left/right
isometries and center consistency. Serialize that common block-sparse MPS
into scratch, hash it and reload the identical payload for all settings.
Record the original and imported energies. Recanonicalizing an unconverged
AL seed may change its energy; this is a timing sample, with no claim to
reproduce or improve the rejected scientific state.

The model is unchanged: YC8-1, minimal period two, U(1), uniform gauge,
J1=1, J2=0.12. No flux advancement, bond growth, convergence gate change or
scientific promotion occurs. The accepted chi512 parent at 0.15 remains
unchanged. This experiment does not create the proposed converged theta=0
chi1024/2048 family. General-chi growth and portable production checkpoint
support remain separate work.

## Measurements and resources

All settings use a sequential step with sixteen logical CPUs, core binding
and the same allocation. Record the actual Julia and BLAS thread counts,
BLAS backend, Julia version and CPU affinity. Timings include the unchanged
kernel's update and scalar energy/error measurement, excluding journal I/O.
The compact summary reports mean, median and range, process CPU time divided
by wall time, whole-process peak RSS, speedup against 2/1, and projected
cost per 100 updates at the benchmark's allocation size. The displayed table
includes the mean and range; the summary API also returns the median.

The summary checks all step exits, input provenance, complete journals and
identical initial energies (absolute tolerance 1e-10). It requires matching
per-update energies (1e-8 absolute) and native Galerkin errors (1e-3 relative,
1e-12 absolute). These are numerical-comparison checks, not scientific
convergence thresholds. A failed check leaves the raw records for inspection
and produces no validated fastest-setting recommendation.

Request Shared QOS, 64 GiB, 36 allocation logical CPUs and six hours. The
initial 34-CPU request received 36 CPUs on Perlmutter. V2 budgets the observed
18 charged physical cores out of 128, for a maximum reservation of
**0.84375 node-hours**. The last synchronized Phase 1 balance is
50.486642795139; live reconciliation is authoritative. The worker separately
records the per-task request and allocated CPUs. It accepts 34-36 allocated
CPUs with sufficient task CPUs for the unchanged 16-CPU step, and rejects an
allocation beyond the sealed budget. Cost projections use the recorded
actual allocation; live reconciliation continues to use Slurm accounting.
The six-hour limit provides headroom for import, compilation and twelve
updates; this chi1024 VUMPS workload has no measured completion-time estimate
yet. A pretimeout signal preserves the compact progress and prevents further
updates. There is no automatic resubmission.

Compact jobs live under
`output/mpskit_solver_pilot_jobs/thread_benchmark/TIMESTAMP_HASH/`, so the
existing accounting root and common submission lock include them. The AL
bridge and common serialized seed live under
`$PSCRATCH/QSL/project_b_flux_dimensional_reduction/thread_benchmark/job_JOBID_HASH/`.
Per-update tensors are not saved for this timing-only workload. The original
source checkpoint is never modified.

## Controls and minimal validation

`configs/thread_benchmark.toml` defines the recipe. The tracked
`configs/thread_benchmark_active_control.ref` selects the sealed control in
`configs/controls/thread_benchmark_v2.toml`, SHA-256
`6e36988cff62f946cde4a661e46375a0a3d3618c78125a3e747d67b32aaba9cd`.
It pins both environments, source, seed manifest and
accounting policy. New helpers live in `scripts/thread_benchmark/` and
`idmrg/thread_benchmark/`, preserving the runtimes and source enumeration of
completed experiments.

Local validation covers one real chi512 export/import without optimization,
a tiny period-two U(1) restart under the three thread settings, compact
summary/failure handling, a copied-worker plan and Git delivery without
ignored output. Numerical checks run only locally. Remote preflight checks
Julia compatibility, pinned inputs, the live scratch seed, accounting and
the copied worker without loading tensor libraries or running a test suite.
The full chi1024 tensor cannot be tested locally; runtime import and
trajectory checks cover that remaining host-specific uncertainty.

Local validation completed September 13. The real chi512 import preserved
charge multiplicities and canonical identities; its energy change was
-1.8734258699915074e-8. All three tiny-state thread settings passed the
canonical restart and matched-trajectory check. Five compact checks passed,
including refusal to rank a mismatched trajectory or a failed worker step.
The final copied-worker plan passed. A clean Git export with no ignored
output validated the sealed launch inputs, and a deliberately changed worker
was rejected. The tiny fixture's timings are not Perlmutter performance data.

## Manual Perlmutter commands

From the existing clean worktree:

```bash
cd ~/QSL-project-b &&
git pull --ff-only &&
cd project_b_flux_dimensional_reduction &&
bash slurm/run_thread_benchmark_cpu.sh preflight &&
bash slurm/run_thread_benchmark_cpu.sh submit &&
bash slurm/run_thread_benchmark_cpu.sh status
```

Preflight reconciles live accounting and runs the required live `plan`.
Submit repeats the integrity, queue, lock and budget guards. It uses a copied
worker with an explicit absolute project root. For detailed progress:

```bash
bash slurm/run_thread_benchmark_cpu.sh progress
```

After completion:

```bash
bash slurm/run_thread_benchmark_cpu.sh reconcile &&
bash slurm/run_thread_benchmark_cpu.sh analyze
```

Expect `BENCHMARK_COMPLETE=true` and the three-row timing table. Slurm
`COMPLETED` alone is not the result. `RUN_ID=JOB_ID` selects an older recorded
run; otherwise the largest recorded job ID is used. Checksum-sync the compact
`thread_benchmark/` package and `output/accounting/` back locally using Globus,
with deletion/mirroring off. Do not transfer scratch tensors or `.git`.

## September 14 startup failure and repair

The owner-confirmed sync contains job **58275828**, `FAILED`, exit `2:0`,
14 seconds, 36 allocated CPUs and 64G. Its log contains only the successful
copied-worker smoke message; there are no `srun` steps, scratch-package
manifest, seed export, canonical seed or timing reports. The submitted v1
control and all 44 source pins matched the original checkout at review.
The missing `seed.toml` on analysis is a consequence of failing before seed
preparation, not evidence of a transfer problem or numerical failure.

V1 silently exited unless `SLURM_CPUS_PER_TASK` equaled the requested 34.
The 36-CPU allocation strongly suggests this check was the trigger, although
the old log did not capture that variable or distinguish it from the next
scratch prerequisite guard. We therefore cannot identify the exact failing
guard conclusively from the saved artifacts. Slurm distinguishes the
[per-task request from CPUs allocated on each node](https://slurm.schedmd.com/sbatch.html#SECTION_OUTPUT-ENVIRONMENT-VARIABLES).
The site's precise reason for granting 36 instead of 34 is not established
by this record.

V2 requests and budgets 36 CPUs, checks allocation bounds separately from
the task request, logs Slurm startup fields, and records the failed stage on
an early exit. Missing result records now produce `BENCHMARK_COMPLETE=false`
and an explanation, with nonzero CLI status and no timing recommendation.
Seed, algorithms, thread settings, update counts, memory and wall limit are
unchanged. Preserve the v1 control and failed package; do not resubmit v1.

The live accounting evidence
`output/accounting/evidence/812f1f5c01060eb7a113493caf453a40b9e4255719d7c2b7f354476391f58a5e.tsv`
charges this attempt **0.000546875 node-hours**. Phase 1 is now
19.513357204861 consumed, 50.486642795139 remaining.

Targeted v2 validation covers the observed 36-CPU startup, differing
requested/allocated counts, insufficient and over-budget allocations, and
an actual copied-worker execution that reaches a deliberately unavailable
scratch path and records that failure explicitly. Eight compact replay
checks pass using the prior tiny fixture, including actual-CPU cost and
missing-result handling. No numerical solver tests were rerun. The final
local plan and Git delivery checks validate the newly sealed inputs.

## Remaining work

1. Owner runs preflight and submits on Perlmutter.
2. Owner reconciles the completed job and syncs compact results.
3. Compare speed, variation, numerical agreement and memory; select a setting
   for a separately prepared zero-flux chi1024/2048 study. Measure its actual
   preparation cost before scheduling the larger full-flux trajectories.
