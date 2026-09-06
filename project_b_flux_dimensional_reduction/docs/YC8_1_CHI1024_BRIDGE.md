# YC8-1 chi=1024 primary-forward bridge

## Purpose

This campaign moves the Project B Phase 1 science path back to the accepted
YC8-1 primary-forward lineage while retaining the useful YC6-1 recovery as a
finite-size diagnostic only. The immutable scientific root remains the
accepted theta/pi=0.15 state with SHA-256
`38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`.
Rejected VUMPS and iDMRG states are numerical seeds or diagnostics only.

The controlled representation is unchanged: YC8-1, U(1)-conserving tensors,
minimal period-2 MPS, uniform twist gauge, and the
`primary_forward_chi512_legacy_0p1` branch prepared from the independent
theta-zero alternating state.

## Numerical sequence

The default control performs these operations in one resumable queue:

1. At theta/pi=0.15, grow the accepted state from chi=512 to chi=1024 and
   converge it before changing theta.
2. Advance from theta/pi=0.175 through 0.45 on a nominal 0.025 grid.
3. If a numerically converged candidate fails branch diagnostics, bisect only
   that interval, down to a minimum step of 0.00625.
4. Stop rather than seeding from a rejected state.
5. After an accepted theta/pi=0.45 endpoint exists, generate and run the
   reverse 0.425 to 0.15 diagnostic before promoting the bridge to a full
   theta sweep.

The exploratory VUMPS outer-residual target is `1e-4`, as selected on
2026-08-31. It is a VUMPS projected residual. It must not be interpreted as
an iDMRG bond-matrix update norm or as discarded weight.

The execution profile uses the parallel multisite VUMPS update. At the same
YC8-1 theta/pi=0.15 control, sequential VUMPS ran 32 outer iterations over
15,100.39 seconds without meeting the former `1e-5` residual target, while
parallel VUMPS converged in 10 iterations over 5,710.41 seconds. The accepted
lineage root was produced by that parallel control. The bridge therefore pins
`multisite_update_alg = "parallel"`; a sequential resume is rejected by the
validator.

## Multimetric branch trust region

The old overlap-only `0.99` rule is not used by this campaign. Parent overlap
per site is still computed, and `0.90` is an alarm floor, but crossing that
floor does not by itself accept or reject a state. Promotion requires:

- converged VUMPS outer residual and every recorded inner Krylov solve;
- maximum cut-entropy jump no larger than `0.10`;
- local energy-term RMS jump no larger than `0.02`;
- local magnetization RMS jump no larger than `1e-3`;
- mean Schmidt-distribution total variation no larger than `0.05`;
- maximum sectorwise `|delta log(xi)|` no larger than `0.05`, using the
  leading neutral and physical-Sz=1 correlation lengths; and
- successful U(1)-resolved virtual-sector diagnostics.

At the fixed-theta chi=512 to 1024 anchor growth only, the entropy and Schmidt
bounds are `0.35` and `0.15`. This is deliberate: increasing chi at a gapless
point can increase finite-entanglement entropy without changing basin. All
nonzero-theta steps and all equal-chi forward/reverse comparisons use the
tighter `0.10` and `0.05` bounds.

The fixed-theta chi-growth correlation-length bound is separately relaxed to
`|delta log(xi)| <= 1.0` (a factor of `e`) because finite-entanglement scaling
is expected to increase xi when chi doubles. Ordinary flux steps use `0.05`;
a rapid but smooth change is therefore resolved by adaptive bisection rather
than silently classified as a basin jump. This is a path-resolution guard,
not a physical phase-boundary threshold.

The exact virtual-sector labels and multiplicities are recorded. They are not
required to remain identical during the fixed-theta chi=512 to 1024 growth,
because bond-space expansion is supposed to change multiplicities.

These thresholds are empirical Phase 1 trust-region bounds, not physical
phase-boundary criteria. They were calibrated against the smooth accepted
theta/pi=0.10 to 0.15 transition and the discontinuous rejected 0.15 to 0.175
iDMRG candidate. The latter had overlap/site `0.9662443394`, but also had a
maximum cut-entropy jump `0.85575`, local-energy RMS jump `0.12781`, and mean
Schmidt total variation `0.30667`; it therefore remains rejected independently
of the old `0.99` cutoff. Its maximum neutral/spin-1
`|delta log(xi)|=0.07555`, versus `0.00282` for the smooth accepted
theta/pi=0.10 to 0.15 step, providing a separately resolved transfer-matrix
diagnostic.

VUMPS at fixed bond dimension does not expose an iDMRG-style discarded-weight
history. The campaign therefore records the subspace-expansion cutoff,
achieved bond dimension, full retained Schmidt-distribution change, projected
VUMPS residual, and every recorded inner Krylov solve; it does not manufacture
a discarded-weight number or conflate one with the VUMPS residual.

The calibration, evidence paths and SHA-256 values, and both threshold profiles
are pinned in `configs/phase1_yc8_1_multimetric_continuity.toml` (SHA-256
`51164d89ff6ca9ed4cc6cca839eec1f46a98cce2c99a68035c74b6665f97b7a3`).
The launcher validator hashes that policy and every named calibration artifact
before allowing a plan or submission.

Forward/reverse agreement is a campaign-level diagnostic. A reverse result is
never allowed to replace the primary-forward lineage.

## Storage and interruption

The launcher creates a job-specific package under
`$PSCRATCH/QSL/project_b_flux_dimensional_reduction/phase1_vumps/yc8_1/`.
Full chi=1024 states and optimizer checkpoints are written there. The project
contains only compact state manifests, hash-pinned resume TOMLs, logs, and
accounting records, so routine local synchronization does not copy the heavy
payload.

Checkpoints are written every two completed target-chi outer iterations, after
growth stages, and on the Slurm pre-timeout signal. The signal is sent two
hours before the 48-hour limit because a chi=1024 outer iteration may be long.
Do not delete the scratch package until every state needed for continuation or
publication has been selected and archived elsewhere.

An early checkpoint-and-stop request uses the batch-shell trap:

```bash
scancel --signal=USR1 --batch JOB_ID
```

Do not use a plain cancellation unless the graceful request fails to finish;
plain cancellation can remove the worker before it records a resumable result.

## Perlmutter commands

After the YC6 job is terminal and reconciled:

```bash
module load julia
bash slurm/run_yc8_1_chi1024_bridge_cpu.sh plan
bash slurm/run_yc8_1_chi1024_bridge_cpu.sh submit
```

Inspect and reconcile with:

```bash
bash slurm/run_yc8_1_chi1024_bridge_cpu.sh status
bash slurm/run_yc8_1_chi1024_bridge_cpu.sh reconcile
```

If the allocation reaches its pre-timeout boundary, use the generated
`resume_from_checkpoint_*.toml` with the same launcher:

```bash
bash slurm/run_yc8_1_chi1024_bridge_cpu.sh plan /absolute/path/to/resume_from_checkpoint_HASH.toml
bash slurm/run_yc8_1_chi1024_bridge_cpu.sh submit /absolute/path/to/resume_from_checkpoint_HASH.toml
```

After an accepted theta/pi=0.45 endpoint exists, prepare the reverse check on
Perlmutter using the full scratch state and its manifest hash:

```bash
julia --startup-file=no --project=. scripts/prepare_yc8_1_chi1024_reverse_check.jl \
  /absolute/scratch/path/to/accepted_theta_0p45_state.h5 STATE_SHA256
```

Then pass the generated configuration to the same `plan` and `submit`
launcher commands.

After the reverse run is reconciled, compare equal-theta forward and reverse
states while both scratch packages still exist:

```bash
julia --startup-file=no --project=. scripts/analyze_yc8_1_chi1024_forward_reverse.jl \
  FORWARD_PROJECT_STATE_MANIFEST_DIRECTORY \
  REVERSE_PROJECT_STATE_MANIFEST_DIRECTORY \
  output/science/yc8_1/chi1024_forward_reverse_analysis
```

This writes a compact TSV and TOML decision record. The full sweep is promoted
only if all common-theta comparisons pass the same multimetric trust region.
The guarded successor generator verifies the endpoint, decision record,
comparison table, hashes, thresholds, and all 12 common-theta decisions before
it can emit the primary-forward `0.475:0.025:1.0` continuation:

```bash
julia --startup-file=no --project=. scripts/prepare_yc8_1_chi1024_full_sweep.jl \
  /absolute/scratch/path/to/accepted_theta_0p45_state.h5 ENDPOINT_SHA256 \
  /absolute/project/path/to/chi1024_forward_reverse_analysis.toml ANALYSIS_SHA256
```

Pass the generated configuration to the same launcher `plan` and `submit`
commands. It remains impossible to generate this successor from a failed or
incomplete reverse comparison.

## Resource guard

The guarded job requests one Shared-QOS CPU allocation with 16 logical CPUs,
32 GiB, and 48 hours. The solver step uses eight logical CPUs and four Julia
threads. BLAS and Strided remain single-threaded, while NDTensors BlockSparse
threading remains enabled for the U(1)-resolved contractions. CPU and memory each
reserve one sixteenth of a Perlmutter CPU node, so the conservative worst-case
charge is 3.0 node-hours. The launcher retains the one-Project-B-job guard and
checks the Phase 1 ceiling before submission. After the first YC8 job, it
requires every earlier YC8 run package to be reconciled and adds the immutable
`charged_node_hours.txt` records to its accounting baseline; bridge, reverse,
and full-sweep jobs therefore cannot reuse the same nominal allowance.

## Current execution result

Job `57793343` used the original two-Julia-thread/four-step-CPU profile. Its
first chi-1024 outer iteration took 6,965.48 seconds and it exited cleanly at
the pre-timeout boundary with a hash-pinned checkpoint; it made no scientific
acceptance or continuity decision.

Job `57801654` restarted the fixed-flux growth from the accepted chi-512 parent
with four Julia threads and an eight-CPU solver step. Slurm completed the job
with exit `0:0` after 124,893 seconds. The optimizer reached its 60-iteration
cap while still contracting, restored its best iterate 52, and recorded:

```text
target residual       1.000000e-4
best residual         4.860776365225489e-4
terminal residual     4.970008632297692e-4
projected target iter 99.6173
candidate SHA-256     4e3a5f406f61cb791ea98ef6b0dc6cfb108877eb5199d4dc71d204f150c0a9e6
final checkpoint SHA  fa4d7f01dbb7e10deb1c37bab659c07a9dba60fe63ba3e3db34c705c102b3e9b
```

The candidate is rejected for failure of the declared numerical gate, so the
multimetric continuity checks were not run. No chi-1024 state was accepted and
no theta step began. This is an iteration-limit result, not a physical endpoint
or evidence of a basin jump.

The two 32-GiB jobs were each allocated 18 logical CPUs even though the job
ledger and forecast use 16. Their synchronized `charged_node_hours.txt` values
therefore undercount the authoritative `sacct` allocations. The corrected
charges are `0.14408203125` and `2.43931640625` node-hours, respectively; a
full 48-hour allocation at 18 CPUs would cost `3.375` node-hours. The launcher
accounting guard must be corrected and tested before another YC8 submission.
The rolling totals and ordered next actions are in `PROJECT_STATE.md`.
