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

Reconciled job `56890262` performed that missing fixed-Hamiltonian control. It
expanded the exact accepted parent at `theta/pi=0.2421875` from chi 128 to chi
192 and kept theta fixed for all 360 iterations. After the expansion transient,
the residual reached a local minimum `5.255565e-5` at iteration 35, rebounded to
`1.262939e-4` at iteration 83, and then decreased on every iteration through
`2.332663382e-5` at iteration 360. Over the final 100 iterations it improved by
`19.4287%`; the log-residual fit had slope `-0.006840884`, `R^2=0.99997398`, and
projected the `1e-5` crossing near cumulative iteration `483.816`. All 3600
recorded inner Krylov solves converged.

The chi-192 artifact is therefore rejected only because the outer-iteration
cap arrived before the residual gate. It is not accepted branch lineage and it
is not evidence of a fixed-chi self-consistency obstruction. Its immutable
SHA-256 is
`b34fc59421524efb509c0801cfdbac4c30c77ebac59d947985a88f6e2a5bafa3`.
Job `56890262` ran for 6:00:41, used about 1.61 GiB MaxRSS in the scan step,
and was reconciled at `0.140957031` node-hours. The locally synced reconciled
Phase 1 total is `0.656627604` node-hours; Perlmutter must still be checked as
the live authority immediately before submission.

The derived chi-128 rows remain in
`docs/data/phase1_yc8_1_latest_residual_trends.csv` and
`docs/data/phase1_yc8_1_0p238_to_0p242_bond_sectors.tsv`. The synchronized
chi-192 evidence is the immutable state and log under runs `56712061` and
`56890262`.

## Next test: finish the contracting fixed-flux chi-192 solve

The next job remains an isolated one-point test at `theta/pi=0.2421875`. It
uses the rejected chi-192 artifact only as a numerical MPS seed and permits 180
additional outer iterations. The accepted chi-128 state remains the immutable
branch parent used for lineage and for the `0.99` mixed-transfer overlap gate.
The `1e-5` residual gate and inner-solver settings are unchanged, all inner
solves remain recorded, and generic plateau termination remains disabled.
Nonfinite-residual and catastrophic-divergence guards remain active.

The 180-iteration allowance covers the measured projection of roughly 124 more
iterations with 56 iterations of margin. This resumes the stored MPS tensors;
the VUMPS environments and eigensolver workspaces are rebuilt by the new
process, so the first new residual need not equal the previous final residual
bit-for-bit. Theta, chi, symmetry sectors, model parameters, and branch metadata
must match exactly. Do not loosen the residual gate or advance theta in this
job.

Launcher 2.3.0 and the Julia loader require two independent SHA-pinned inputs.
`initial_state_file` must be converged and accepted; it defines branch lineage.
`optimizer_checkpoint_file` must be rejected, nonconverged, at the identical
flux and chi, descended from that accepted parent, and stopped specifically as
`maximum_iterations_contracting`. It is never promoted to the branch parent.
A nonaccepted retry writes
`project_b_fixed_flux_optimizer_resume_outcome`, including both source hashes,
the prior and additional iteration counts, and `physical_endpoint=false`; it is
never mislabeled as a zero-width continuation bracket.

## Perlmutter generation and submission

First synchronize this code to Perlmutter. The resume generator, schema-v6
state writer, and launcher 2.3.0 must all be present remotely before planning.
Then, from the Perlmutter project root:

```bash
grep '^readonly LAUNCHER_VERSION=' slurm/run_scan_cpu.sh
# Expected: readonly LAUNCHER_VERSION="2.3.0"

parent_state=output/phase1/yc8_1/primary_forward_recovery_from_0p23828125/seed_101/chi128/states/state_0001_yc8-1_primary_forward_independent_theta0_alternating_forward_seed101_chi128_theta_p0p24218750_accepted_0a7c9cba9e2c.h5
parent_sha256=37fdbca9e3c5d1089085b709948cfbf854593301bb242c46c93c7895e76e7caf
checkpoint_state=output/phase1_tests/yc8_1/fixed_flux_p0p24218750_chi128_to_chi192_37fdbca9e3c5/chi192/states/state_0001_yc8-1_primary_forward_independent_theta0_alternating_forward_seed101_chi192_theta_p0p24218750_rejected_2fc831e282a3.h5
checkpoint_sha256=b34fc59421524efb509c0801cfdbac4c30c77ebac59d947985a88f6e2a5bafa3

test "$(sha256sum "$parent_state" | awk '{print $1}')" = "$parent_sha256" || {
  echo "parent digest mismatch" >&2
  exit 1
}
test "$(sha256sum "$checkpoint_state" | awk '{print $1}')" = "$checkpoint_sha256" || {
  echo "optimizer checkpoint digest mismatch" >&2
  exit 1
}

julia --project=. --startup-file=no \
  scripts/prepare_phase1_fixed_flux_resume.jl \
  "$parent_state" "$parent_sha256" \
  "$checkpoint_state" "$checkpoint_sha256"

test_dir=output/phase1_test_configs/fixed_flux_resume_p0p24218750_chi192_b34fc5942152
config=$test_dir/phase1_fixed_flux_resume_chi192.toml

bash slurm/run_scan_cpu.sh plan "$config"
```

Before submission, the plan must show all of the following:

- `YC8-1`, `primary_forward`, seed 101, and chi 192;
- a one-point schedule containing only `0.2421875`;
- the accepted parent path and exact SHA-256 above;
- the separate optimizer-checkpoint path and exact SHA-256 above;
- maximum iterations 180 and `Plateau detector: false`; and
- an empty, new output directory.

If every field matches, submit exactly that generated config:

```bash
bash slurm/run_scan_cpu.sh submit "$config"
```

Do not resubmit either the earlier step-and-expand config or the completed
`phase1_fixed_flux_expand_chi192.toml`. Do not edit either old config to use the
rejected candidate as `initial_state_file`.

## Monitor, reconcile, and inspect

```bash
bash slurm/run_scan_cpu.sh status

run_dir=$(tr -d '\r\n' < output/phase1_jobs/latest_run.txt)
job_id=$(awk -F '\t' 'NR == 2 {print $1}' "$run_dir/job.tsv")
tail -n 80 "$run_dir/logs/scan-$job_id.out"
```

Because VUMPS environments are rebuilt, a short restart transient is not by
itself a reason to cancel this job. Intervene only for nonfinite values, a
scheduler/node failure, or a clearly catastrophic trajectory. Once Slurm
reports a terminal state:

```bash
run_id=$(basename "$run_dir")
bash slurm/run_scan_cpu.sh reconcile "$run_id"

output_dir=output/phase1_tests/yc8_1/fixed_flux_resume_p0p24218750_chi192_b34fc5942152/chi192
if [[ -f "$output_dir/scan_outcome.toml" ]]; then
  cat "$output_dir/scan_outcome.toml"
else
  accepted_state=$(find "$output_dir/states" -type f -name '*_accepted_*.h5' -print -quit)
  sha256sum "$accepted_state"
fi
```

After reconciliation, synchronize the new run directory and complete output
directory locally before asking for analysis. If chi 192 is accepted, stop
there: it becomes the inspected fixed-flux parent for a later theta step, not
an automatic authorization to advance or promote to chi 256. If the new run is
still smoothly contracting at its cap, inspect its updated projection before
considering another checkpoint resume. A stalled or divergent retry is a
different diagnosis and should not be extended automatically. Never edit an
old generated config to point at a different state.

The older `scripts/prepare_phase1_plateau_tests.jl` and
`scripts/prepare_phase1_fixed_flux_expansion.jl` generators remain for
reproducing completed controls. Neither is the generator for the next
submission.

## Stored diagnostics

Every new schema-v6 state stores the schema-v5 optimizer diagnostics plus:

- a separate optimizer-restart checkpoint path, basename, SHA-256, prior
  cumulative iteration count, residual, minimum residual, and stop reason; and
- `continuation/preparation_source=optimizer_checkpoint_resume`, while the
  accepted parent remains under the ordinary continuation-parent fields.

The optimizer diagnostics include:

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

A failed fixed-flux optimizer resume similarly writes
`fixed_flux_optimizer_resume_numerical_failure` or
`fixed_flux_optimizer_resume_continuity_rejected`, with accepted-parent,
optimizer-checkpoint, and new-candidate hashes kept distinct. The cumulative
iteration count is reported without treating the rejected checkpoint as
accepted lineage.

Schema-v6 Schmidt total variation is computed after sorting each cut's Schmidt
probabilities by descending rank and padding missing tail weight with zero.
This avoids the meaningless near-unity distance produced when symmetry-block
multiplicity changes merely shift serialized vector positions. U(1)-sector
multiplicities and weights remain a separate diagnostic through
`compare_bond_sectors.jl`.

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

Use an explicit run ID. Launcher 2.3.0 preserves the intervention as a
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
trajectory received 308 iterations. Fixed-flux job `56890262` then showed that
the chi-192 residual continued a smooth contraction after its expansion
transient; the next resume tests the measured iteration-limit explanation
without changing theta or accepting the rejected checkpoint as lineage. A
VUMPS residual is also not the same quantity as an iDMRG truncation error, so
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
