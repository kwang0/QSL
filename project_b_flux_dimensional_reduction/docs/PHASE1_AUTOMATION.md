# Guarded Phase 1 campaign automation

## Scope

Launcher 2.5.0 automates the repeated terminal-job workflow for the dedicated
YC8-1 primary-forward chi-512 campaign. It does not generalize the chi-512
exception to other branches, geometries, or phases, and it does not run an
unattended process on a Perlmutter login node.

The ordinary non-submitting command is:

```bash
bash slurm/run_scan_cpu.sh advance [RUN_ID]
```

It requires a terminal Perlmutter allocation, reconciles it when necessary,
verifies the submitted configuration snapshot and HDF5 state hashes, writes an
immutable `automatic_advance.toml`, generates a next configuration only when a
transition is preapproved, and runs the ordinary launcher `plan`.

The explicit mutation command is:

```bash
bash slurm/run_scan_cpu.sh advance-submit [RUN_ID]
```

It repeats every immutable-decision and plan check, then calls the existing
budget-guarded submission path. The launcher still permits only one active
Phase 1 pilot, requires all prior jobs to be reconciled, reserves the complete
24-hour worst case, and enforces both Phase 1 and Project B ceilings. It also
refuses to submit the same generated configuration hash twice.

## Encoded transitions

| Terminal evidence | Automated action | Safety boundary |
|---|---|---|
| Clean completion with accepted targets remaining | Continue from the highest-index immutable accepted state through the remaining nominal 0.1-pi grid | Parent file, hash, lineage, chi, residual tolerance, geometry, and inner solves are reverified |
| `TIMEOUT`, `NODE_FAIL`, `PREEMPTED`, `BOOT_FAIL`, or `REVOKED` after saving an accepted state | Resume the remaining grid from that accepted state | A rejected or partially optimized state is never promoted to parent |
| Numerical divergence, plateau, or stalled cap on an interval wider than `0.05*pi` | Insert the canonical midpoint and retain all later nominal targets in the same next job | Generated scans use `minimum_step_over_pi=0.05`, so later 0.1-pi failures are bisected once inside the same allocation |
| `maximum_iterations_contracting` at the approved step floor | Retry from the accepted parent with `max(2 * current_cap, 1.1 * projected_crossing)`, clipped at 720 | The rejected candidate remains diagnostic only; this deliberately recomputes from accepted lineage |
| Accepted `theta/pi=1.0` | Mark the campaign complete | No configuration or submission is produced |
| Continuity-gate failure | Stop for manual review | Possible basin changes are never advanced automatically |
| Any recorded inner Krylov failure | Stop for manual review | A failed inner solve cannot trigger acceptance, midpoint insertion, or automatic resubmission |
| Numerical failure already bracketed at `0.05*pi`, a nonfinite trajectory, ordinary `FAILED`/`CANCELLED`/OOM, missing parent, changed hash, or unsupported outcome type | Stop for manual review | No speculative chi, tolerance, solver, or branch change is made |

## In-job behavior

The first automatic recovery from job `57192723` schedules
`0.15,0.2,0.3,...,1.0`, not merely the two diagnostic bridge points. If `0.15`
and `0.2` converge, that same allocation continues immediately. At every later
0.1-pi interval, the existing adaptive queue may insert one 0.05-pi midpoint
without waiting for another analysis cycle. No point below 0.05-pi is inserted.

The scan now also treats recorded inner-solver convergence as part of numerical
eligibility whenever Krylov diagnostics are enabled. An unconverged inner solve
therefore cannot pass the residual/overlap gates or initiate adaptive
bisection.

## Immutable artifacts and idempotence

Each source run receives exactly one
`output/phase1_jobs/RUN_ID/automatic_advance.toml`. It records:

- the scheduler state, submitted config SHA-256, outcome type, classification,
  and optimizer stop reason;
- accepted-parent and rejected-candidate paths, hashes, and inner-solve checks;
- the policy transition, reason, next iteration cap, and complete next flux
  schedule; and
- the generated config path, config SHA-256, and isolated output directory.

Repeating `advance` revalidates and reuses that decision instead of creating a
different recommendation. Repeating `advance-submit` after submission is
refused by config hash and directs the operator to the latest resulting run.

## Current campaign command

After synchronizing launcher 2.5.0 and the new source files to Perlmutter
without overwriting remote `output/`, use the reconciled fresh-run directory:

```bash
cd /global/homes/k/kwang98/QSL/project_b_flux_dimensional_reduction

grep '^readonly LAUNCHER_VERSION=' slurm/run_scan_cpu.sh
# Expected: readonly LAUNCHER_VERSION="2.5.0"

run_id=20260818T002056Z-yc8-1-primary_forward_chi512_legacy_0p1-512
bash slurm/run_scan_cpu.sh advance "$run_id"
```

The plan must identify transition `refine_interval`, accepted parent
`theta/pi=0.1` with SHA-256
`f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc`,
schedule `0.15,0.2,...,1.0`, chi 512, residual tolerance `1e-5`, overlap floor
`0.99`, no optimizer checkpoint, and a `0.562500000` node-hour reservation.

To submit that exact immutable decision:

```bash
bash slurm/run_scan_cpu.sh advance-submit "$run_id"
```

After the new job becomes terminal, the recurring workflow is one command:

```bash
bash slurm/run_scan_cpu.sh advance-submit
```

When no run ID is supplied, launcher 2.5.0 selects the run containing the
greatest recorded Slurm job ID. It does not trust `latest_run.txt`, because a
local-to-Perlmutter directory sync can overwrite that pointer with stale data.

It will reconcile and submit only if the outcome matches an encoded safe
transition. Otherwise it prints `manual_review` and leaves scheduler state
unchanged. Sync the resulting run/output directories locally before asking for
detailed scientific interpretation; Perlmutter remains authoritative.
