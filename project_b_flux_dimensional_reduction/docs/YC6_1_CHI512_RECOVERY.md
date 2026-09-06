# YC6-1 chi-512 legacy-supercell recovery

## Decision

Recreate the desired branch from scratch. The legacy rolling checkpoint is not
a usable pre-jump restart: the local copy contains diagnostics through
`theta/pi=0.7` but no `psi`, and the original rolling file, if it still exists
on Perlmutter, was overwritten after every completed flux step. Its tensor would
therefore be the post-jump `0.7` state, not the desired `0.3` parent. The
per-flux legacy HDF5 files did not store an MPS.

This recovery is an independent YC6-1 comparison branch. It does not alter or
descend from the accepted YC8-1 state with SHA-256
`38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`.

## Convergence evidence

The evidence is the locally synced historical Slurm logs for jobs `54326239`
and `54370665`. Perlmutter remains authoritative for new run data. The two jobs
reproduce every completed chi-512 residual through `theta/pi=0.2` to printed
precision. Their first three `theta/pi=0.3` residuals also agree exactly:

| iteration | residual |
|---:|---:|
| 1 | `1.4864191777613171e-2` |
| 2 | `3.0722605239824918e-3` |
| 3 | `1.2842777310203694e-3` |

The completed trajectory then gives:

| theta/pi | final residual | last-10 log-fit R2 | projected batch iteration at `1e-5` |
|---:|---:|---:|---:|
| 0.0 | `1.504951901e-5` | `0.964250` | `28.91` |
| 0.1 | `1.002223553e-5` | `0.979641` | `20.03` |
| 0.2 | `1.127557518e-5` | `0.997436` | `21.15` |
| 0.3 | `3.675894784e-5` | `0.997929` | `31.13` |
| 0.4 | `3.920756081e-2` | `0.999517` with positive slope | no contraction |

At `0.4`, the residual reaches its minimum `5.489197800e-3` at iteration 3
and then rises monotonically to `3.920756081e-2`. A post-hoc ceiling of
`5e-5` would separate all stored pre-jump endpoints from even the best `0.4`
iterate by more than two orders of magnitude. It is not necessary to deploy
that looser ceiling: the pre-jump fits predict that the original `1e-5` target
is reachable with a modest iteration extension. The machine-readable fits are
in [`data/legacy_yc6_1_chi512_residual_trends.csv`](data/legacy_yc6_1_chi512_residual_trends.csv).

## Original strict recovery policy

- Keep the original VUMPS projected-residual target at `1e-5`; do not identify it with
  discarded weight or an iDMRG bond-matrix update norm.
- Allow up to 60 outer iterations, with a contracting/stalled classification
  and immutable residual history. The cap is safely above the largest
  pre-jump projection (`31.13` within its final batch).
- Recreate the exact legacy representation: U(1), YC6-1, six-site MPS
  supercell, uniform twist gauge, alternating seed, chi 512.
- Schedule the full `0.0,0.1,...,1.0` nominal grid, but automatically bisect a
  rejected continuation down to `0.00625*pi`. A rejected candidate never seeds
  its successor.
- Evaluate parent overlap and all stored observable jumps. The predeclared
  `0.90` overlap-per-site floor is only a permissive catastrophic-jump guard;
  it is not claimed to be a physical phase boundary. The measured overlap
  trend through `0.3`, entropy changes, energy-term changes, Schmidt-spectrum
  variation, and residual behavior must be reviewed together.
- Save accepted and rejected tensors immutably. This branch cannot promote or
  replace the accepted YC8-1 scientific lineage.

The original root configuration is
[`configs/science_yc6_1_legacy_period6_chi512.toml`](../configs/science_yc6_1_legacy_period6_chi512.toml).
Because a six-site YC6-1 supercell cannot use the project's minimal two-site
Hu momentum reconstruction, its first purpose is to test whether the legacy
qualitative spectrum survives real convergence. Publishable `(k1,k2)` labels
and the physical `Sz=1` comparison should then be repeated with a minimal
two-site YC6-1 control rather than inferred by dividing or unfolding ranks.

## Job 57629467 and restart

Perlmutter reports job `57629467` as `TIMEOUT` after `2-00:00:22`. The synced
log and immutable artifacts establish the following boundary:

- `theta/pi=0.0`, `0.1`, `0.2`, and `0.3` were accepted. The accepted `0.3`
  state SHA-256 is
  `741261e9fdef75b3793837f2b26f3daac4515c491baab622fc1e8d1e2c8bfe45`.
- The direct `0.4` candidate diverged and was saved rejected with SHA-256
  `971c4fe5a92fda9ad811dcb09d69689a8570f0b27d2a97f888ee9aa6f00bb523`.
  It remains numerical evidence only.
- Adaptive refinement then restarted from accepted `0.3` at `0.35`. The
  residual contracted from `6.118223e-3` to `1.644340e-4` over 36 completed
  outer iterations, but the old worker had no in-progress checkpoint, so that
  iterate was lost at the scheduler boundary.

The continuation control is
[`configs/science_yc6_1_legacy_period6_chi512_after_57629467.toml`](../configs/science_yc6_1_legacy_period6_chi512_after_57629467.toml).
It restarts `0.35` from accepted `0.3`, retains every scientific tolerance,
and uses a distinct output directory. It never seeds from rejected `0.4`.

Launcher 1.2.0 requests `USR1` for the batch shell one hour before the Slurm
limit. The worker records an atomic sentinel, and Julia checks it after each
completed VUMPS outer iteration. A sentinel causes an immutable full-state
checkpoint and a scheduler-boundary outcome without an acceptance, rejection,
overlap, or bisection decision. Independently of that signal, a full-state
checkpoint is written after every growth stage and every five completed
chi-512 outer iterations. Launcher 1.2.0 requests the Slurm `scratch` license
and places those full HDF5 checkpoints below
`$PSCRATCH/QSL/project_b_flux_dimensional_reduction/phase1_vumps/yc6_1/` in a
job- and config-specific directory. The project output retains only compact
hash-pinned resume TOMLs under `checkpoint_manifests/`; resumed checkpoints
remain numerical seeds under the same accepted parent. Scratch is temporary
and excluded from routine Globus sync.

To end a launcher-1.2.0 job early without discarding its current progress,
signal the batch shell rather than cancelling the allocation outright:

```bash
scancel --signal=USR1 --batch JOB_ID
```

The worker then writes the sentinel, waits for the current outer iteration,
checkpoints, and exits through its normal result path. A plain `scancel JOB_ID`
is only a fallback if that graceful path does not finish.

The continuation job submitted before launcher 1.2.0 remains governed by its
submitted worker and may therefore write `optimizer_checkpoints/` below the
project output. Do not cancel or alter that job for the storage migration.
Exclude that checkpoint directory from routine sync-back, retain its compact
logs/manifests and durable terminal scientific states, and use scratch routing
for any successor or checkpoint-resume job.

Charging three physical cores for the reported `172822` seconds gives
`1.125143229167` derived node-hours. This brings the tracked Phase 1 total to
`13.740251736728` and Project B including Phase 0 to `14.834684736728`
node-hours, pending any later authoritative accounting correction.

## Synced continuation endpoint and exploratory `1e-4` profile

The next synced continuation used the original `1e-5` residual gate. It first
ended two contracting `theta/pi=0.35` attempts at residuals
`6.4722240634e-5` and `5.5328186116e-5`, so both remain immutable rejected
states under their original controls. Adaptive refinement accepted
`theta/pi=0.325` after 37 iterations at residual `9.6774066605e-6`, then
accepted `theta/pi=0.3375` after 55 iterations at residual
`9.8245887550e-6`. The accepted `0.3375` SHA-256 is
`ac239341c6b4103e4bbeae2a2468d4fd9253d5db1fbbd0d6d7b5448f9e85234b`.

The terminal scheduler-boundary artifact is a `theta/pi=0.35` checkpoint after
six completed iterations, with residual `4.6601403116e-4` and SHA-256
`e120a02b50e645f6cc2b345021f122ee1248f4ec8d95454fddb4bf6c3af609b7`.
It was not classified for convergence or parent overlap and remains a
numerical seed only.

On 2026-08-30 the project owner authorized an exploratory `1e-4` VUMPS outer
residual gate for future YC6-1 recovery points. Retrospectively, the accepted
`0.325` and `0.3375` trajectories first crossed `1e-4` at iterations 12 and 16
instead of requiring 37 and 55 iterations to cross `1e-5`. This indicates a
large runtime saving, while the tenfold relaxation can change the transported
state and therefore remains a separately labeled numerical profile.

The prepared control
[`configs/science_yc6_1_legacy_period6_chi512_tol1e4_after_p0p3375.toml`](../configs/science_yc6_1_legacy_period6_chi512_tol1e4_after_p0p3375.toml)
restarts the remaining grid at `0.35` from the stricter-profile accepted
`0.3375` state. It deliberately does not import the old-tolerance checkpoint,
does not retroactively promote either rejected `0.35` state, retains the
`0.90` continuity guard and every other solver setting, and writes to a
distinct `tol1e4` output tree. Launcher 1.3.0 makes this control the default and
routes its heavy checkpoints to PSCRATCH.

## Perlmutter operation

After a complete checksum-preserving project-tree sync to Perlmutter, with
destination mirroring/deletion disabled and no project job writing the tree:

```text
module load julia
bash slurm/run_yc6_1_recovery_cpu.sh plan
bash slurm/run_yc6_1_recovery_cpu.sh submit
bash slurm/run_yc6_1_recovery_cpu.sh status
bash slurm/run_yc6_1_recovery_cpu.sh reconcile
```

The launcher requests one Shared-QOS allocation for 48 hours, six allocation
logical CPUs, an exact four-logical-CPU solver step, two Julia threads, 8 GiB,
and the Slurm `scratch` license. Its worst-case reservation is `1.125`
node-hours. Submission has no automatic advance, cancellation, deletion, or
promotion path.
