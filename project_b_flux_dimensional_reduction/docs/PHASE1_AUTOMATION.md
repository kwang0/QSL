# Guarded Phase 1 campaign automation

## Scope

Launcher 2.7.0 automates the repeated terminal-job workflow for the dedicated
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
| Pinned final parallel-update control reaches `theta/pi=0.15` | Stop for successful-control review | No longer schedule is generated until the solver change is interpreted |
| Pinned final parallel-update control writes a numerical outcome | Stop and report the iDMRG pivot | No further VUMPS configuration or submission is generated |
| Pinned final control has only a scheduler or process failure | Stop as inconclusive | Infrastructure failure is not mislabeled as a VUMPS failure |
| SHA-pinned successful control is explicitly promoted | Schedule `0.2,0.3,...,1.0` with parallel VUMPS | Launcher verifies control job `57337312`, its config and decision, accepted state SHA-256, all inner solves, and the continuity gate |
| Promoted parallel descendant needs recovery | Apply the same continuation, midpoint, and contracting-retry policy | Every generated descendant retains the promotion record and must be named by an immutable automatic decision before submission |
| Promoted parallel recovery is exhausted | Stop for manual iDMRG review | Automation never changes solver, chi, tolerance, or branch on its own |

## In-job behavior

The first automatic recovery from job `57192723` scheduled
`0.15,0.2,0.3,...,1.0`, not merely two diagnostic bridge points. Job `57245573`
stopped at the first point, so no later target was attempted. At a later
ordinary automatic campaign interval, the adaptive queue may still insert one
0.05-pi midpoint without waiting for another analysis cycle; no point below
0.05-pi is inserted.

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

## Current promoted parallel campaign

Final-control job `57337312` accepted `theta/pi=0.15` with parallel VUMPS,
residual `9.183773e-6`, 60/60 converged inner solves, and overlap per site
`0.9999782682`. Its manual-review decision remains immutable. The explicit
promotion generator uses accepted state SHA-256
`38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`
as the next parent and schedules `0.2,0.3,...,1.0`.

After synchronizing launcher 2.7.0 and the new source files to Perlmutter
without overwriting remote `output/`, verify:

```bash
cd /global/homes/k/kwang98/QSL/project_b_flux_dimensional_reduction

grep '^readonly LAUNCHER_VERSION=' slurm/run_scan_cpu.sh
# Expected: readonly LAUNCHER_VERSION="2.7.0"
```

Generate, plan, and submit the promoted continuation using the exact commands
in `docs/PHASE1_PARALLEL_VUMPS_PROMOTION.md`. After it becomes terminal:

```bash
bash slurm/run_scan_cpu.sh reconcile
bash slurm/run_scan_cpu.sh advance
```

When no run ID is supplied, launcher 2.7.0 selects the run containing the
greatest recorded Slurm job ID. It does not trust `latest_run.txt`, because a
local-to-Perlmutter directory sync can overwrite that pointer with stale data.

For the promoted campaign, `advance` may prepare a remaining-grid continuation,
one canonical midpoint, or a contracting retry. It never submits unless the
operator explicitly invokes `advance-submit`. It stops for continuity loss,
inner-solver failure, a numerical failure at the `0.05*pi` floor, or unsupported
infrastructure state. Sync the resulting run/output directories locally before
detailed scientific interpretation; Perlmutter remains authoritative.
