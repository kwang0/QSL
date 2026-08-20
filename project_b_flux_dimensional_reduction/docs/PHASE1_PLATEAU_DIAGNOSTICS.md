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
stopped it after 265 iterations. At that stage `0.2421875` remained the
accepted theta frontier; the result did not establish a physical endpoint.

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

That chi-192 artifact was rejected only because the outer-iteration cap arrived
before the residual gate. Reconciled job `56978073` then reused it strictly as
a numerical checkpoint while keeping the accepted chi-128 state as the
lineage parent. All 130 new residuals decreased monotonically from
`2.313835e-5` to `9.953697e-6`. Acceptance occurred after 490 cumulative outer
iterations, close to the prior projection of `483.816`. The new log-residual
fit had slope `-0.006515326`, `R^2=0.99998567`, and no nondecreasing step.

All 1300 newly recorded inner solves converged. The accepted chi-192 state
passed the mixed-transfer gate with overlap per unit cell `0.9989331551` and
per site `0.9994664352`. Its immutable SHA-256 is
`312f08abf8c78f15382fac8165ebf138866be06bf0456fddd0d46995f272fc86`.
Job `56978073` ran for 1:50:41, used about 1.53 GiB MaxRSS in the scan step,
and was reconciled at `0.043235677` node-hours. The locally synced reconciled
Phase 1 total is `0.699863281` node-hours; Perlmutter must still be checked as
the live authority immediately before submission.

The accepted chi-192 state lowers the same-theta energy density from
`-0.502541951318` at chi 128 to `-0.504674048141` and raises mean entropy from
`1.78602218045` to `1.93363910147`. Both cuts retain exactly the same U(1)
charge labels while their multiplicities expand from 128 to 192. The
sector-weight total-variation distances are `0.01616689` and `0.02843619`.
Thus chi 128 was quantitatively representation-limited, but no missing charge
sector or failed inner solve explains the long outer convergence tail.

The derived chi-128 rows remain in
`docs/data/phase1_yc8_1_latest_residual_trends.csv` and
`docs/data/phase1_yc8_1_0p238_to_0p242_bond_sectors.tsv`. The chi-128 to
accepted-chi-192 sector comparison is in
`docs/data/phase1_yc8_1_0p242_chi128_to_chi192_bond_sectors.tsv`. The
synchronized chi-192 evidence is the immutable state and log under runs
`56712061`, `56890262`, and `56978073`.

Reconciled job `56994767` then performed the clean fixed-chi test from that
accepted parent to `theta/pi=0.24609375`. At chi 192 the residual fell from
`8.097135e-5` to a minimum `2.254667e-5` at iteration 352 and ended at
`2.256008e-5` after 360 iterations. The long trend window still labeled the
run contracting, but all final eight residual changes were nondecreasing. Its
iteration-1613 extrapolation is therefore not a sound reason to buy another
roughly 1250 chi-192 iterations. All 3600 inner Krylov solves converged without
an iteration-limit hit. Both cuts retained exactly the same U(1) labels and
multiplicities across the step.

At the same target, the minimum residual improved from `3.424244e-5` at chi
128 to `2.254667e-5` at chi 192, a `34.2%` reduction. Thus bond dimension
matters, but a converged chi-192 parent and the small `1/256*pi` step did not
remove the practical residual floor. The rejected candidate was never tested
by the overlap gate and is not accepted lineage. Job `56994767` cost
`0.120058594` node-hours; the locally synced reconciled Phase 1 total through
that job is `0.819921875` node-hours. Perlmutter remains the live authority.

## What the fresh chi-512 run established

Reconciled job `57192723` used the dedicated fresh-start configuration with
SHA-256 `09a1d32e17af6e27c0ee13dad946c3a31cf9477015201f6c118653fb46e34ce0`.
It completed normally in `14:49:53`, used about `1.90 GiB` MaxRSS in the Julia
step, and was charged `0.347610677` node-hours.

At `theta/pi=0`, growth proceeded through bond dimensions
`1,2,4,16,64,256,512`. The final chi-512 stage converged after 117 iterations;
all growth stages together used 306 iterations. The accepted state has
residual `9.5006856e-6`, energy density `-0.507212542889`, mean entropy
`2.318198535`, and SHA-256
`95255fbe3a590505902bd0061d7d9d9f14f8ecd7ca3e4eac1aacfc5c7fe72d0b`.

The direct `0 -> 0.1` continuation converged in 19 iterations to residual
`9.0649938e-6`. It passed the branch gate with overlap per site
`0.9999173509`; its accepted SHA-256 is
`f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc`.

The direct `0.1 -> 0.2` update did not converge. Its residual decreased from
`2.616349e-3` to `1.013369e-4` at iteration 14, then increased monotonically
to `2.011009e-3` at iteration 30. The divergence guard stopped it after eight
sustained iterations above four times the minimum. All 300 inner solves for
that point—and all 3550 inner solves in the job—converged. The failure is
classified `numerical_divergence_not_physical_endpoint`; numerical ineligibility
correctly prevented an official continuity test.

A retrospective read-only diagnostic on the rejected candidate found overlap
per site `0.9998896923` with the accepted `0.1` parent. Both cuts retained
exactly the same U(1) labels and multiplicities, with sector-weight total
variation `0.003153869` and `0.002422914`. Those sector rows are stored in
`docs/data/phase1_yc8_1_chi512_0p1_to_0p2_bond_sectors.tsv`. The Schmidt tails
remain chi-limited, so a larger representation may still matter, but there is
no abrupt sector or entropy discontinuity at `0.2`. The large scheduled step
and outer-update dynamics are therefore the leading controlled variable.

The locally synced reconciled Phase 1 total through job `57192723` is
`1.167532552` node-hours; the Project B total including the Phase 0 baseline is
`2.261965552` node-hours. Perlmutter remains authoritative immediately before
another submission.

## Automated next campaign step

Launcher 2.5.0 encodes the repeated recovery decisions in an immutable,
Perlmutter-side state machine. For job `57192723`, it verifies the reconciled
allocation, submitted config snapshot, accepted `0.1` hash, rejected `0.2`
hash, and convergence of every recorded inner solve. It then generates one
strict-lineage job with schedule `0.15,0.2,0.3,...,1.0` and minimum step `0.05`.

This is more than a two-point bridge. If `0.15` and `0.2` converge, the same
allocation proceeds immediately. A later failed 0.1-pi interval is bisected
once by the scan queue, but no step below 0.05-pi is inserted. The rejected
direct `0.2` state remains diagnostic only and is never a continuation parent.

First synchronize launcher 2.5.0 and the new source/docs to Perlmutter without
overwriting remote `output/`. Then run:

```bash
cd /global/homes/k/kwang98/QSL/project_b_flux_dimensional_reduction

grep '^readonly LAUNCHER_VERSION=' slurm/run_scan_cpu.sh
# Expected: readonly LAUNCHER_VERSION="2.5.0"

run_id=20260818T002056Z-yc8-1-primary_forward_chi512_legacy_0p1-512
bash slurm/run_scan_cpu.sh advance "$run_id"
```

The plan must report transition `refine_interval`, parent `theta/pi=0.1` with
SHA-256
`f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc`,
schedule `0.15,0.2,...,1.0`, chi 512, residual tolerance `1e-5`, overlap gate
`0.99`, no optimizer checkpoint, and a `0.562500000` node-hour reservation.

To submit that exact immutable decision through the ordinary live scheduler
and budget checks:

```bash
bash slurm/run_scan_cpu.sh advance-submit "$run_id"
```

Monitor normally:

```bash
bash slurm/run_scan_cpu.sh status

run_dir=$(tr -d '\r\n' < output/phase1_jobs/latest_run.txt)
job_id=$(awk -F '\t' 'NR == 2 {print $1}' "$run_dir/job.tsv")
tail -n 80 "$run_dir/logs/scan-$job_id.out"
```

After that job becomes terminal, the recurring command is simply:

```bash
bash slurm/run_scan_cpu.sh advance-submit
```

It reconciles the latest run if needed and automatically continues only for a
saved accepted parent after timeout/node failure, remaining nominal targets, a
failed interval wider than 0.05-pi, or a demonstrably contracting corrector
below the 720-iteration automatic cap. It stops without submission for a
continuity failure, any inner Krylov failure, a numerical failure at the
0.05-pi floor, an unsupported scheduler failure, changed/missing evidence, or
any requested chi/tolerance/solver change. The complete transition table and
artifact schema are in `docs/PHASE1_AUTOMATION.md`.

After each terminal run, synchronize its run and output directories locally
before requesting detailed scientific interpretation. The automation removes
routine classification and resubmission, not the need to interpret genuinely
new physics.

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

For a chi-192, chi-256, or chi-512 result, compare the virtual sectors against its exact
immutable parent:

```bash
julia --project=. --startup-file=no \
  scripts/compare_bond_sectors.jl \
  "$parent_state" \
  /absolute/path/to/expanded-state.h5 \
  /absolute/path/to/bond-sector-comparison.tsv
```

## If a live job truly plateaus

Use an explicit run ID. Launcher 2.5.0 preserves the intervention as a
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
is 48 times smaller, chi 192 is 32 times smaller, and chi 512 remains 12 times
smaller than `m=6144`. The new 0.1-pi schedule is therefore a deliberate
high-chi Project B experiment, not a claim that the paper documented identical
internal warm-start increments.

The current `1e-5` VUMPS stationarity threshold should not be loosened merely
to accept a smooth-looking state above tolerance. Job `56675925` demonstrated
that the threshold was reachable at `theta/pi=0.2421875` once the contracting
trajectory received 308 iterations. Fixed-flux job `56890262` then showed that
the chi-192 residual continued a smooth contraction after its expansion
transient, and job `56978073` reached the same threshold after 490 cumulative
iterations. Job `56994767` subsequently showed that the next fixed-chi 192
point flattens near `2.255e-5`, despite a converged parent, a 1/256-pi step, and
fully converged inner solves. This motivates the owner-approved chi-512 restart
without changing the numerical acceptance threshold. A VUMPS residual is also
not the same quantity as an iDMRG truncation error, so
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
