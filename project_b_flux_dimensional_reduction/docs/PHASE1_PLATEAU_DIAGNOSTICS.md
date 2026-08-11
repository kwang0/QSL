# Phase 1 continuation diagnostics

This protocol distinguishes a slow but healthy VUMPS contraction from a true
numerical plateau, an inaccurate inner Krylov solve, a continuation-step/basin
problem, and insufficient fixed-chi virtual-sector support. None of those
numerical outcomes is, by itself, a physical endpoint of the flux-threaded
branch.

Perlmutter is authoritative for every job ID, state path, hash, log, and
accounting value. Local `output/` is a retrospective mirror only. Synchronize
these code changes to Perlmutter before using a new configuration, and verify
the proposed parent digest on Perlmutter immediately before `plan` or
`submit`.

## What the synchronized run established

The reconciled job `56456634` reached an accepted chi-128 primary-forward
state at `theta/pi=0.23828125`:

- accepted SHA-256:
  `b6b54e47f894158f291e0f9851bce4fdc2322e31a49d3b79155acf21059ebeee`;
- the subsequent `theta/pi=0.2421875` attempt ended at residual
  `1.5338554e-5` after 200 iterations;
- over its final 100 iterations, the residual contracted by a factor of about
  `0.995999` per iteration with `R^2 > 0.99999`;
- the last 24 iterations improved the residual by about `9.1%`; and
- that log-linear trend projects the `1e-5` crossing near iteration 307.

Therefore the closest failed point was not plateauing. It was stopped by an
outer-iteration cap while still making smooth progress. In contrast, the
earlier direct jump to `theta/pi=0.25` reached its best residual near iteration
8 and then rebounded through iteration 200. These two behaviors must not share
one generic “failed to converge” label.

The accepted `0.23828125` and rejected `0.2421875` states had the same virtual
U(1) sector multiplicities. That rules out an observed sector reallocation in
that fixed-chi step, but it does not show that the fixed allocation is adequate;
one-site VUMPS cannot create new sector multiplicities without an explicit
bond-space expansion.

The derived rows are preserved in
`docs/data/phase1_yc8_1_latest_residual_trends.csv` and
`docs/data/phase1_yc8_1_0p238_to_0p242_bond_sectors.tsv`; both point back to
the synchronized immutable states or job log from which they were computed.

## Recommended next production attempt

The next primary-forward configuration is
`configs/phase1_yc8_1_forward_recovery_from_0p23828125_chi128.toml`. It starts
at `theta/pi=0.2421875`, preserves the completed run's inner tolerance and
default Krylov space, raises only the outer limit from 200 to 360, records all
inner solves, and enables a conservative plateau detector.

On Perlmutter:

```bash
grep '^readonly LAUNCHER_VERSION=' slurm/run_scan_cpu.sh
# Expected: readonly LAUNCHER_VERSION="2.2.1"

parent_state=output/phase1/yc8_1/primary_forward_recovery_from_0p2265625/seed_101/chi128/states/state_0004_yc8-1_primary_forward_independent_theta0_alternating_forward_seed101_chi128_theta_p0p23828125_accepted_1f5d14a8fd65.h5
sha256sum "$parent_state"
# Expected digest: b6b54e47f894158f291e0f9851bce4fdc2322e31a49d3b79155acf21059ebeee

bash slurm/run_scan_cpu.sh plan \
  configs/phase1_yc8_1_forward_recovery_from_0p23828125_chi128.toml
bash slurm/run_scan_cpu.sh submit \
  configs/phase1_yc8_1_forward_recovery_from_0p23828125_chi128.toml
```

Do not seed this run from either rejected `theta/pi=0.2421875` state. The
immutable accepted `0.23828125` state is the restart parent.

The plateau rule begins after 40 iterations and compares the best residual in
the most recent 32 iterations with the best earlier residual. It stops only if
the relative improvement is below `0.5%` while the residual remains above
`1e-5`. The synchronized `0.2421875` trajectory improved by roughly 9% over a
shorter 24-iteration window, so this rule would not stop that contraction.

## Generate controlled one-point tests

The generator now accepts any verified, accepted chi-128 YC8-1
primary-forward parent and an explicit target. This avoids hard-coding a stale
parent and prevents a diagnostic run from silently adding bisection points.

```bash
parent_state=/absolute/Perlmutter/path/to/accepted-parent.h5
parent_sha256=$(sha256sum "$parent_state" | awk '{print $1}')
target_theta_over_pi=0.2421875

julia --project=. --startup-file=no \
  scripts/prepare_phase1_plateau_tests.jl \
  "$parent_state" "$parent_sha256" "$target_theta_over_pi"
```

The generator verifies the digest, convergence and continuation acceptance,
geometry, minimal cell, branch, direction, and actual chi before writing four
isolated configurations:

| Configuration | Changed variable | Purpose |
|---|---|---|
| `phase1_plateau_baseline_chi128.toml` | Outer cap 360; otherwise original solver | Finish/measure the same chi-128 fixed point |
| `phase1_plateau_inner_krylov_chi128.toml` | Inner scale 1000, floor `1e-12`, Krylov dimension 64 | Test inaccurate inner solves |
| `phase1_plateau_expand_chi192.toml` | Expand to chi 192 | Test fixed-chi/sector support |
| `phase1_plateau_expand_chi256.toml` | Expand to chi 256 | Escalation only if chi 192 is inconclusive |

Run only the recorded baseline first. Reconcile and inspect it before choosing
one control. If the baseline converges with all inner solves converged, there
is no reason to spend a job on the tighter-inner test. If it converges at chi
128, do not run chi expansion merely because the larger dimension is
available.

After a new point is accepted, rerun the generator using that new immutable
state and its new Perlmutter SHA-256. Never edit an old generated configuration
to point at a different parent; generate a distinct output directory instead.

## Stored diagnostics

Every new schema-v5 state stores:

- the residual and left/right energy histories;
- recent relative improvement and a log-residual trend fit;
- the projected total iteration at which the configured tolerance would be
  reached, when such a projection is meaningful; and
- every environment-left, environment-right, center-`C`, and center-`AC`
  Krylov solve, with requested tolerance, convergence count, residual norm,
  restart count, operator applications, Krylov dimension, maximum restarts,
  and elapsed time.

Summarize an accepted or rejected state with:

```bash
julia --project=. --startup-file=no \
  scripts/summarize_krylov_diagnostics.jl \
  /absolute/path/to/state.h5 \
  /absolute/path/to/krylov-solves.tsv
```

New bracket outcomes distinguish:

- `iteration_limit_while_contracting_not_physical_endpoint`;
- `iteration_limit_stalled_not_physical_endpoint`;
- `numerical_plateau_not_physical_endpoint`;
- `numerical_divergence_not_physical_endpoint`; and
- a separately gated possible branch-continuity loss.

For a chi-192 or chi-256 result, compare the virtual sectors against its exact
immutable parent:

```bash
julia --project=. --startup-file=no \
  scripts/compare_bond_sectors.jl \
  "$parent_state" \
  /absolute/path/to/expanded-state.h5 \
  /absolute/path/to/bond-sector-comparison.tsv
```

## If a live job truly plateaus

Use an explicit run ID. Launcher 2.2.1 preserves the intervention as a
scientific failure artifact before the job is reconciled:

```bash
run_dir=$(tr -d '\r\n' < output/phase1_jobs/latest_run.txt)
run_id=$(basename "$run_dir")
bash slurm/run_scan_cpu.sh cancel-plateau "$run_id"
```

The command accepts only a `RUNNING` or `SUSPENDED` job, or an already-terminal
failed/cancelled job that needs its scientific record. It writes immutable
`termination.toml` with `continuation_accepted=false` and
`physical_endpoint=false`; it does not delete logs or states. After Slurm
reports a terminal state:

```bash
bash slurm/run_scan_cpu.sh status "$run_id"
bash slurm/run_scan_cpu.sh reconcile "$run_id"
```

## Interpretation relative to Hu et al.

The comparison to the original work is not like-for-like. Hu et al. used
infinite DMRG, not this VUMPS implementation, and report `m=6144` for the YC8
gap calculations and `m=12288` for the YC8-1 correlation spectra. The paper
also explicitly says adiabatic insertion becomes challenging near the Dirac
cone because of the small gap and large entanglement, and that failed
continuations can collapse into another sector or symmetry-broken state. See
the [paper](https://arxiv.org/pdf/1905.09837) and its
[arXiv record](https://arxiv.org/abs/1905.09837).

No textual method statement in that paper establishes an internal
`0.1*pi` warm-start step. Spacing between plotted points is not evidence that
the optimization used those same increments internally. In any case, chi 128
is 48 times smaller than `m=6144`, so the paper does not demonstrate that the
present variational space should cross every intermediate theta easily.

The current `1e-5` VUMPS stationarity threshold should not be loosened merely
to accept `1.5e-5`. The latest curve predicts that the existing threshold is
reachable with more outer iterations. A VUMPS residual is also not the same
quantity as an iDMRG truncation error, so their numerical values should not be
equated. Fully converging a fixed-chi, symmetry-constrained VUMPS state does
not automatically find the unrestricted global ground state; initialization,
sector content, and local basins still matter, while the parent-overlap gate
audits whether the continuation changed branch.

The legacy chi-512 results are useful context but not a direct control: they
used YC6-1, a six-site supercell, no parent-overlap gate, and saved several
points whose optimizer residuals were above `1e-5`. Their smoother plotted
observables therefore do not establish that the current YC8-1 chi-128 state
was converged or branch-continuous. A meaningful method comparison must hold
geometry, cell, parent, tolerance, and branch gate fixed.
