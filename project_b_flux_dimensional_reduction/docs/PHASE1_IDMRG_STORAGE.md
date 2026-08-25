# Phase 1 iDMRG storage policy

Phase 1 now separates restart-heavy working data from durable scientific
artifacts. Serialized MPSKit checkpoints belong under the operator's
Perlmutter scratch allocation. Controls, logs, `sacct` evidence, the final
restartable result bridge, analysis, and compact checkpoint manifests remain
under the project directory in home and are synced locally.

This is required because NERSC home has a 40 GB quota, while Perlmutter scratch
provides 20 TB per user. Scratch is temporary: files not accessed for eight
weeks are eligible for purge, and scratch is not backed up. NERSC also advises
running production jobs from scratch and requires the `scratch` license for
jobs that use it. See the official
[Perlmutter scratch policy](https://docs.nersc.gov/filesystems/perlmutter-scratch/),
[filesystem quotas](https://docs.nersc.gov/filesystems/quotas/), and
[job best practices](https://docs.nersc.gov/jobs/best-practices/).

## Artifact split

For each new iDMRG run:

- `$PSCRATCH/QSL/project_b_flux_dimensional_reduction/phase1_idmrg/.../checkpoints/`
  holds the roughly 0.4 GiB serialized checkpoints;
- the home-side package holds `phase1_idmrg_control.toml`, its small bridge,
  `logs/`, reconciled `sacct-*.tsv`, and the roughly 16 MiB
  `idmrg_result_bridge.h5` needed to seed a reviewed continuation;
- `idmrg_result_lightweight.h5` is written automatically at normal solver
  completion. Like the repository-level `copy_data.jl` pattern, it retains
  provenance, full scalar histories, checkpoint paths, sizes, iterations, and
  SHA-256 values while omitting full state tensors and serialized solvers.

The launcher resolves the PSCRATCH-relative path from the immutable control,
passes it through `PROJECT_B_IDMRG_CHECKPOINT_DIRECTORY`, and requests
`--licenses=scratch`. It refuses a nonempty checkpoint directory and never
deletes scratch data automatically.

## Deleted job 57452187 checkpoints

The first iDMRG control predates this policy and originally wrote 16
checkpoints, about 6.7 GiB total, into the project directory in home. Their
interrupted Globus transfer made the copies untrustworthy, and the project
owner deleted them on 2026-08-23. They are not inputs to the prepared successor
and must not be recopied or reconstructed.

The successor starts a new solver from
`rejected_idmrg_seed_to_mpskit_bridge.h5`, a complete, hash-pinned tensor bridge
derived from the final job `57452187` result. The launcher invokes
`run_idmrg.jl` without its optional checkpoint-resume argument and requires the
successor's distinct PSCRATCH checkpoint directory to be absent or empty. The
plan therefore prints both `startup source: immutable bridge only; no prior
checkpoint` and `job 57452187 checkpoints required: no`.

Keep the immutable first result bridge, its analysis, lightweight archive,
control, log, and `sacct` evidence in home/local storage. Losing the old
serialized solver checkpoints removes only the ability to resume the old
control mid-iteration; it does not change the reconciled result or the prepared
successor seed.

## Globus sync policy

For normal sync-back, copy only the completed run package from the Perlmutter
home endpoint to the matching local parent:

- source:
  `/global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction/output/phase1_idmrg/yc8_1/RUN_PACKAGE/`
- destination parent:
  `/Users/kevin/Code/QSL/project_b_flux_dimensional_reduction/output/phase1_idmrg/yc8_1/`
- direction: Perlmutter to Mac.

Do not select any `checkpoints/` subdirectory or anything below
`$PSCRATCH/QSL/project_b_flux_dimensional_reduction/phase1_idmrg/` in a normal
Globus transfer. The final bridge, lightweight file, logs, `job_id.txt`, and
reconciled `sacct` evidence stay small enough for home and local storage.

If a scheduler-interrupted run must resume from scratch, first inspect the
latest complete checkpoint and its hash recorded in the lightweight manifest.
Do not select a checkpoint merely for lower energy, and do not treat a missing
or purged scratch checkpoint as a scientific endpoint. A scientifically
completed but nonconverged result requires a new reviewed bridge/control, as
done for the successor to job `57452187`.

## Job 57500598 and the resource benchmark

Job `57500598` followed this policy: its 20-iteration-cadence serialized
checkpoints were written under
`$PSCRATCH/QSL/project_b_flux_dimensional_reduction/phase1_idmrg/yc8_1/theta_p0p20000000_resume_from_527afdf421e3/checkpoints/`,
not into Perlmutter home. Its ordinary home/local package is about 32 MiB:
roughly 16 MiB each for the final result bridge and its numerical-seed bridge,
plus a 52 KiB lightweight history/manifest and small logs/accounting. Normal
Globus sync-back must continue to exclude the PSCRATCH checkpoint directory.

The 2/4/8/16-thread resource benchmark is deliberately checkpoint-free. Every
setting restarts from the same 16 MiB result bridge, runs five updates, and
writes only a small timing HDF5 file. It therefore needs neither a scratch
license nor a scratch transfer. A later scientific continuation will again use
PSCRATCH for heavy checkpoints after the benchmark selects a right-sized
Shared-QOS resource request.
