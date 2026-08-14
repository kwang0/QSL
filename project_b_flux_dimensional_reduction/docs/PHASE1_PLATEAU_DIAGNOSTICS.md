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

## What the synchronized runs established

Reconciled job `56675925` confirmed the earlier log-trend projection. Starting
from the accepted chi-128 state at `theta/pi=0.23828125`, it reached
`theta/pi=0.2421875` at iteration 308 with:

- residual `9.994862e-6` against the unchanged `1e-5` acceptance gate;
- parent overlap per site `0.9999951622` against the `0.99` branch gate; and
- accepted SHA-256
  `37fdbca9e3c5d1089085b709948cfbf854593301bb242c46c93c7895e76e7caf`.

The next chi-128 point at `theta/pi=0.24609375` did not converge. Its residual
settled near `3.43e-5`, with a minimum of `3.424244e-5`, and the plateau rule
stopped it after 265 iterations. Thus `0.2421875` is the current accepted
primary-forward frontier; the result does not establish a physical endpoint.

Reconciled job `56712061` then expanded the accepted chi-128 parent to chi 192
while also stepping from `0.2421875` to `0.24609375`. The residual fell from
`1.213627e-2` to a minimum of `2.865161e-5` at iteration 39, then rebounded to
`1.031162e-4`; the generic plateau detector stopped the run at iteration 71.
All 710 recorded inner Krylov solves converged, so inaccurate inner solves are
not the leading explanation. However, that job changed two variables at once
and stopped during the transient following subspace expansion. It therefore
does not answer whether the enlarged chi-192 space can first settle at the
already accepted Hamiltonian.

The derived chi-128 rows remain in
`docs/data/phase1_yc8_1_latest_residual_trends.csv` and
`docs/data/phase1_yc8_1_0p238_to_0p242_bond_sectors.tsv`. The synchronized
chi-192 evidence is the immutable state and log under run `56712061`.

## Next test: expand at fixed flux

The next job is a controlled bond-space initialization test, not another flux
step. It starts from the exact accepted chi-128 parent at
`theta/pi=0.2421875`, expands to chi 192 at that same theta, and changes no
Hamiltonian parameter. It keeps the `1e-5` residual and `0.99` parent-overlap
gates, records all inner solves, permits 360 outer iterations, and disables the
generic plateau stop. Nonfinite-residual and catastrophic-divergence guards
remain active.

This separation matters: if the fixed-flux expansion converges, it produces a
well-defined chi-192 parent from which a later flux step can be tested. If it
does not converge after the full settling window, the failure concerns the
bond-expansion/VUMPS initialization itself, not adiabaticity across a theta
increment. Do not loosen the residual gate for this test.

The scan engine treats this exact same-flux, higher-chi request as a dedicated
diagnostic. A nonaccepted candidate writes
`project_b_fixed_flux_expansion_outcome` with source, requested, and achieved
chi, optimizer history, parent/candidate hashes, and
`physical_endpoint=false`; it is never mislabeled as a zero-width continuation
bracket.

## Perlmutter generation and submission

First synchronize this code to Perlmutter. The generator and the new scan
outcome handling must both be present remotely before the job is planned.
Then, from the Perlmutter project root:

```bash
grep '^readonly LAUNCHER_VERSION=' slurm/run_scan_cpu.sh
# Expected: readonly LAUNCHER_VERSION="2.2.1"

parent_state=output/phase1/yc8_1/primary_forward_recovery_from_0p23828125/seed_101/chi128/states/state_0001_yc8-1_primary_forward_independent_theta0_alternating_forward_seed101_chi128_theta_p0p24218750_accepted_0a7c9cba9e2c.h5
parent_sha256=37fdbca9e3c5d1089085b709948cfbf854593301bb242c46c93c7895e76e7caf

test "$(sha256sum "$parent_state" | awk '{print $1}')" = "$parent_sha256" || {
  echo "parent digest mismatch" >&2
  exit 1
}

julia --project=. --startup-file=no \
  scripts/prepare_phase1_fixed_flux_expansion.jl \
  "$parent_state" "$parent_sha256" 192

test_dir=output/phase1_test_configs/fixed_flux_p0p24218750_chi128_to_chi192_37fdbca9e3c5
config=$test_dir/phase1_fixed_flux_expand_chi192.toml

bash slurm/run_scan_cpu.sh plan "$config"
```

Before submission, the plan must show all of the following:

- `YC8-1`, `primary_forward`, seed 101, and chi 192;
- a one-point schedule containing only `0.2421875`;
- the parent path and exact SHA-256 above;
- maximum iterations 360 and `Plateau detector: false`; and
- an empty, new output directory.

If every field matches, submit exactly that generated config:

```bash
bash slurm/run_scan_cpu.sh submit "$config"
```

Do not submit the earlier
`from_p0p24218750_to_p0p24609375_37fdbca9e3c5/phase1_plateau_expand_chi192.toml`;
it is the already completed step-and-expand control.

## Monitor, reconcile, and inspect

```bash
bash slurm/run_scan_cpu.sh status

run_dir=$(tr -d '\r\n' < output/phase1_jobs/latest_run.txt)
job_id=$(awk -F '\t' 'NR == 2 {print $1}' "$run_dir/job.tsv")
tail -n 80 "$run_dir/logs/scan-$job_id.out"
```

An early residual rebound is not, by itself, a reason to cancel this job: the
purpose is to give the expanded state its full settling window. Intervene only
for nonfinite values, a scheduler/node failure, or a clearly catastrophic
trajectory. Once Slurm reports a terminal state:

```bash
run_id=$(basename "$run_dir")
bash slurm/run_scan_cpu.sh reconcile "$run_id"

output_dir=output/phase1_tests/yc8_1/fixed_flux_p0p24218750_chi128_to_chi192_37fdbca9e3c5/chi192
if [[ -f "$output_dir/scan_outcome.toml" ]]; then
  cat "$output_dir/scan_outcome.toml"
else
  accepted_state=$(find "$output_dir/states" -type f -name '*_accepted_*.h5' -print -quit)
  sha256sum "$accepted_state"
fi
```

After reconciliation, synchronize the new run directory and complete output
directory locally before asking for analysis. If chi 192 is accepted, stop
there: generate the chi-256 fixed-flux test from the new immutable chi-192
parent only after inspecting this result. Never edit an old generated config
to point at a different state.

The older `scripts/prepare_phase1_plateau_tests.jl` four-way generator remains
for reproducing the completed step-size/inner-solver controls. It is not the
generator for the next submission.

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

Continuation-bracket outcomes distinguish:

- `iteration_limit_while_contracting_not_physical_endpoint`;
- `iteration_limit_stalled_not_physical_endpoint`;
- `numerical_plateau_not_physical_endpoint`;
- `numerical_divergence_not_physical_endpoint`; and
- a separately gated possible branch-continuity loss.

A failed same-flux expansion instead writes a dedicated outcome with status
`fixed_flux_expansion_numerical_failure` or
`fixed_flux_expansion_continuity_rejected`. It records the source, requested,
and achieved bond dimensions without claiming that any theta interval or
physical endpoint was found.

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
to accept a smooth-looking state above tolerance. Job `56675925` demonstrated
that the threshold was reachable at `theta/pi=0.2421875` once the contracting
trajectory received 308 iterations. The fixed-flux expansion now tests whether
a larger variational space can be initialized cleanly before changing theta.
A VUMPS residual is also not the same quantity as an iDMRG truncation error, so
their numerical values should not be equated. Fully converging a fixed-chi,
symmetry-constrained VUMPS state does not automatically find the unrestricted
global ground state; initialization, sector content, and local basins still
matter, while the parent-overlap gate audits whether the continuation changed
branch.

The legacy chi-512 results are useful context but not a direct control: they
used YC6-1, a six-site supercell, no parent-overlap gate, and saved several
points whose optimizer residuals were above `1e-5`. Their smoother plotted
observables therefore do not establish that the current YC8-1 chi-128 state
was converged or branch-continuous. A meaningful method comparison must hold
geometry, cell, parent, tolerance, and branch gate fixed.
