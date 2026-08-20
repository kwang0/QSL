# Project B phases 0–4

This file is the durable cross-chat project plan. Update the status table, the
decision log, and measured node-hour ledger whenever results arrive. The hard
Project B submission limit is **150 Perlmutter node-hours** until explicitly
changed by the project owner.

## Budget and status

The ceilings are permission gates, not spending targets. Unused hours remain in
the reserve and are not automatically reassigned.

| Phase | Ceiling | Current status | Exit product |
|---|---:|---|---|
| 0 — correctness and resource calibration | 10 node-h | **Complete**; corrected seed, 13-candidate matrix, and chi=512 validation copied locally | Correct minimal-cell timing, peak RSS, and one recommended threading configuration |
| 1 — metastable branch tracking and basin diagnostics | 20 node-h | **In progress**; fresh chi-512 forward lineage is accepted through theta/pi=0.1; launcher 2.5.0 can advance the adaptive remaining grid from the reconciled run | Forward threaded branches, independent competing basins, hysteresis, and approximate critical fluxes |
| 2 — moderate-chi Hu reproduction | 35 node-h | Not started | Converged entropy response and momentum-resolved physical-Sz transfer flow |
| 3 — critical-point chi ladders | 60 node-h | Not started | Controlled `S = (c/6) log(xi) + a` analysis at selected crossings |
| 4 — one independent validation | 15 node-h | Not started | One decisive second route, seed, geometry, or width check |
| Protected contingency | 10 node-h | Unspent | Accounting lag, one failed job, or one result-changing extra point |
| **Hard total** | **150 node-h** |  | No submission may exceed this total |

Maintain a soft review at 120 node-hours and stop all automatic submission at
140 node-hours, leaving the protected 10-node-hour contingency untouched.

Current accounting snapshot (2026-08-06):

- estimated failed first-attempt charge: `0.661567` node-hours;
- estimated successful retry, matrix, and validation charge: `0.432866`
  node-hours;
- estimated Phase 0 total: **`1.094433` node-hours**;
- fraction of the 150-node-hour project limit used: **`0.729622%`**;
- remaining project allowance before any later-phase jobs: **`148.905567`
  node-hours**.

These are the Phase 0 script's Shared-QOS estimates. Reconcile them with
`sacct` if an allocation-accounting export becomes available. Unused Phase 0
ceiling is not automatically reassigned.

## Current handoff snapshot

### Data-authority rule

Perlmutter is authoritative for current job state, logs, artifacts, state
hashes, and accounting. The local checkout may be stale or only partially
synced. Local `output/`, `output/phase1_jobs/`, and `latest_run.txt` may be used
for compatibility tests or explicitly retrospective analysis, but never to
infer the latest remote state. Before a run-dependent decision, obtain the
smallest necessary Perlmutter output from the project owner or sync the
relevant artifacts. A local launcher `plan` validates code paths only; its
ledger is not live accounting. This rule is also recorded in `AGENTS.md` for
future project work.

Phase 0 is complete and Phase 1 is in progress. Reconciled YC8-1 job `56675925`
confirmed the earlier residual projection and accepted the chi-128
primary-forward state at `theta/pi=0.2421875` after 308 iterations, with
residual `9.994862e-6` and parent overlap per site `0.9999951622`. Its next
chi-128 point, `theta/pi=0.24609375`, plateaued near residual `3.43e-5`.

Reconciled job `56712061` changed both theta (`0.2421875` to `0.24609375`) and
chi (128 to 192). All 710 recorded inner solves converged, but the outer
residual reached `2.865161e-5` at iteration 39 and rebounded before the generic
plateau detector stopped it at iteration 71. That is not a clean test of
whether the expanded representation can settle, and neither numerical result
establishes a physical branch endpoint.

Reconciled fixed-flux job `56890262` then changed chi only, expanding the exact
accepted `theta/pi=0.2421875` parent from 128 to 192. The expansion transient
rebounded through iteration 83, after which the residual decreased on every
iteration to `2.332663382e-5` at the 360-iteration cap. Its final-100 trend
improved by `19.4287%` with log-fit `R^2=0.99997398` and projected the `1e-5`
gate near cumulative iteration `483.816`. All 3600 inner Krylov solves
converged. This is an iteration-limited contracting solve, not evidence that
chi-192 VUMPS lacks a self-consistent solution. The rejected candidate SHA-256
is `b34fc59421524efb509c0801cfdbac4c30c77ebac59d947985a88f6e2a5bafa3`.

Reconciled job `56978073` resumed that contracting chi-192 MPS at the identical
Hamiltonian while retaining the accepted chi-128 state as its lineage and
overlap reference. All 130 new residuals decreased monotonically from
`2.313835e-5` to `9.953697e-6`, so acceptance occurred after 490 cumulative
outer iterations, only 6.2 iterations beyond the prior projection. All 1300
inner Krylov solves converged. The candidate passed the continuity gate with
overlap per site `0.9994664352` and is now accepted primary-forward lineage at
chi 192. Its SHA-256 is
`312f08abf8c78f15382fac8165ebf138866be06bf0456fddd0d46995f272fc86`.

Relative to the accepted chi-128 state at the same theta, the accepted chi-192
state lowers the energy density by `0.0021320968` and raises mean entropy by
`0.1476169210`. It has the same seven and eight U(1) sectors on the two cuts,
with larger multiplicities rather than new charge labels. The sector-weight
total-variation distances are `0.01616689` and `0.02843619`. This identifies a
finite-representation change within the same symmetry support, not a missing
U(1) sector or an inner-solver failure.

Reconciled job `56994767` then changed only theta, using that accepted chi-192
state for a `1/256*pi` step to `0.24609375`. Its residual decreased from
`8.097135e-5` to `2.254667e-5` at iteration 352 and ended at `2.256008e-5`
after 360 iterations. Although the final 100-iteration fit remained negative,
the final eight residual changes were nondecreasing, so the projected crossing
near iteration 1613 is not a responsible basis for extending chi 192. All 3600
inner solves converged, and the two cuts retained identical U(1) sector labels
and multiplicities. Relative to the chi-128 minimum `3.424244e-5` at the same
theta, chi 192 improved the floor by `34.2%` but did not pass `1e-5`. The state
was not continuity-tested because numerical eligibility failed first.

Reconciled job `57192723` independently grew the alternating theta-zero state
to chi 512 and attempted the requested `0.0,0.1,...,1.0` grid. Theta zero
converged after 306 cumulative growth-stage iterations, including 117 at chi
512, to residual `9.5006856e-6`. The `0.1` child then converged in 19 iterations
to residual `9.0649938e-6` and passed parent overlap per site at
`0.9999173509`. Its accepted SHA-256 is
`f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc`.

The direct `0.1 -> 0.2` update decreased to residual `1.013369e-4` at iteration
14, then grew monotonically to `2.011009e-3` at iteration 30. It stopped as
`diverging_residual`. All 3550 recorded inner solves in the job converged. A
retrospective, non-acceptance overlap calculation on the rejected candidate
gave `0.9998896923` per site; both cuts retained identical U(1) labels and
multiplicities, with only small sector-weight shifts. This establishes an outer
VUMPS/continuation instability, not a physical endpoint, inner-solver failure,
or demonstrated basin jump. Job `57192723` ran for `14:49:53`, used about
`1.90 GiB` MaxRSS in the Julia step, and cost `0.347610677` node-hours.

The implementation now makes branch identity an explicit acceptance condition.
For every child of an immutable accepted parent, schema-v4-and-newer state
files store a
gauge-invariant mixed-transfer overlap per site plus energy, entropy,
local-observable, and Schmidt-spectrum jumps. A child may seed the next point
only if it passes both the residual gate and the configured overlap threshold
(`0.99` per site for Phase 1). An independently prepared first point has no
parent and is therefore exempt from the overlap gate.

A retrospective read-only check on the existing accepted schema-v3 branch
found overlap per site `0.999804580663` from `0` to `0.125` and
`0.999987222742` from `0.1875` to `0.21875`. Thus `0.99` does not falsely reject
those known smooth steps. This check does not calibrate the score of a genuine
basin jump, so the first continuity-gated job still requires inspection rather than an
automatic threshold change.

The project owner has ended further low-chi correctors. Launcher 2.5.0 now
automates the repeated terminal-job workflow for the dedicated chi-512 branch.
From reconciled job `57192723`, `advance` verifies the submitted snapshot,
accepted/rejected hashes, lineage, and every recorded inner solve, then plans
`0.15,0.2,0.3,...,1.0` from the accepted `0.1` parent. The `0.05` minimum step
lets later nominal failures bisect once in the same allocation while forbidding
smaller automatic refinement. `advance-submit` is the only one-command path
that may reconcile and submit; it retains all ordinary live budget and
one-pilot guards. Continuity loss, an inner-solver failure, a numerical failure
at the step floor, changed evidence, or an unsupported outcome stops for manual
review. Exact commands and the transition table are in
`docs/PHASE1_AUTOMATION.md` and `docs/PHASE1_PLATEAU_DIAGNOSTICS.md`.

Canonical evidence:

- complete source-backed report:
  `docs/reports/phase0_performance_analysis/report.html`;
- report payload and exact derived rows:
  `docs/reports/phase0_performance_analysis/artifact.json` and
  `docs/data/phase0_performance_comparison.csv`;
- winning candidate matrix:
  `output/phase0_calibration/phase0_retry_80iter/summary.csv`;
- chi=512 validation:
  `output/phase0_calibration/phase0_retry_80iter/metrics/validation.result` and
  `metrics/validation.time` in the same run directory;
- successful recommendation:
  `output/phase0_calibration/phase0_retry_80iter/recommendation.txt`;
- failed first-attempt accounting:
  `output/phase0_calibration/20260804T205703Z/recommendation.txt`;
- accepted chi-128 YC8-1 fixed-flux source:
  `output/phase1/yc8_1/primary_forward_recovery_from_0p23828125/seed_101/chi128/states/state_0001_yc8-1_primary_forward_independent_theta0_alternating_forward_seed101_chi128_theta_p0p24218750_accepted_0a7c9cba9e2c.h5`;
- latest numerical recovery outcome:
  `output/phase1/yc8_1/primary_forward_recovery_from_0p23828125/seed_101/chi128/scan_outcome.toml`;
- completed step-and-expand chi-192 control:
  `output/phase1_tests/yc8_1/from_p0p24218750_to_p0p24609375_37fdbca9e3c5/bond_expansion/chi192/scan_outcome.toml`;
- completed fixed-flux chi-192 contraction:
  `output/phase1_tests/yc8_1/fixed_flux_p0p24218750_chi128_to_chi192_37fdbca9e3c5/chi192/scan_outcome.toml`;
- current accepted chi-192 YC8-1 parent:
  `output/phase1_tests/yc8_1/fixed_flux_resume_p0p24218750_chi192_b34fc5942152/chi192/states/state_0001_yc8-1_primary_forward_independent_theta0_alternating_forward_seed101_chi192_theta_p0p24218750_accepted_ee45b7d8c9af.h5`;
- chi-128 to chi-192 U(1)-sector comparison:
  `docs/data/phase1_yc8_1_0p242_chi128_to_chi192_bond_sectors.tsv`;
- completed fixed-chi chi-192 forward-step outcome:
  `output/phase1_tests/yc8_1/forward_step_p0p24218750_to_p0p24609375_chi192_312f08abf8c7/chi192/scan_outcome.toml`;
- fresh chi-512 campaign config:
  `configs/phase1_yc8_1_forward_chi512_legacy_0p1.toml`;
- completed fresh chi-512 numerical outcome:
  `output/phase1/yc8_1/primary_forward_chi512_legacy_0p1/seed_101/chi512/scan_outcome.toml`;
- accepted chi-512 `theta/pi=0.1` bridge parent:
  `output/phase1/yc8_1/primary_forward_chi512_legacy_0p1/seed_101/chi512/states/state_0002_yc8-1_primary_forward_chi512_legacy_0p1_independent_theta0_alternating_chi512_forward_seed101_chi512_theta_p0p10000000_accepted_12126bd1b66b.h5`;
- chi-512 accepted-0.1 to rejected-0.2 sector comparison:
  `docs/data/phase1_yc8_1_chi512_0p1_to_0p2_bond_sectors.tsv`;
- exact-parent chi-512 bridge generator:
  `scripts/prepare_phase1_chi512_bridge_from_0p1.jl`;
- guarded chi-512 automatic advance implementation:
  `src/Automation.jl`, `scripts/prepare_phase1_automatic_advance.jl`, and
  launcher `slurm/run_scan_cpu.sh`;
- automatic transition contract and commands:
  `docs/PHASE1_AUTOMATION.md`;
- diagnostic protocol and interpretation:
  `docs/PHASE1_PLATEAU_DIAGNOSTICS.md`.

Do **not** submit either existing `configs/hu_yc8_*_forward.toml` as a Phase 1
campaign. Use launcher `advance|advance-submit` for the dedicated chi-512
lineage, or ordinary `plan|submit` only for a configuration that the automatic
decision artifact generated:

- the launcher fixes two Julia threads, a four-CPU scan step, 8 GiB, Shared QOS,
  and a one-pilot-at-a-time submission policy. Shared QOS may expose five task
  CPUs and report six allocated logical CPUs to satisfy/round the memory
  request; this remains the same three-physical-core charge;
- it forecasts the new reservation together with active Project B work,
  enforces the Phase 1 and project limits, and requires `sacct` reconciliation
  before another Phase 1 submission;
- the later-phase `hu_yc8_*` configs use `chi=512`, `residual_tol=1e-8`, different flux lists,
  `neigs=24`, and `threaded_blocksparse=false`; they are later-phase templates,
  not the cheap Phase 1 scout;
- `run_scan.jl` currently performs optimization and state saving only, despite
  the `[spectrum]` table in the config. This is desirable for Phase 1.
  Spectroscopy is invoked separately through `run_spectrum.jl`.

## Phase 0 — correctness and resource calibration

Goals:

- Use the Hu-compatible minimal MPS period: `Ly` sites for even YC(Ly)-0 and
  two sites for YC(Ly)-1.
- Use the translation-compatible uniform flux gauge.
- Benchmark one deterministic YC6-1, theta=0, chi=256 state with exactly one
  threading layer enabled at a time.
- Measure kernel seconds, residual reduction, peak RSS, and estimated shared-QOS
  node-hours per iteration.
- Validate the winner once at chi=512 only after inspecting the automatic report.

### Completed Phase 0 result

All Phase 0 gates passed. The corrected seed reports `mps_period=2`,
`minimal_mps_period=2`, `unit_cell_status=minimal`, and `twist_gauge=uniform`.

Recommended optimization allocation:

| Setting | Selected value |
|---|---:|
| Exclusive contraction backend | threaded block sparse |
| Julia/compute threads | 2 |
| BLAS threads | 1 |
| Strided threads | 1 |
| Slurm `--cpus-per-task` | 4 logical CPUs |
| Production memory request | 8 GiB |
| YC6-1 MPS period | 2 |

Measured results:

- at chi=256, `blocksparse-t2` took `27.770756 s/iteration` with
  `1.368 GiB` MaxRSS and a projected `0.000180799 node-h/iteration`;
- serial-t1 took `36.853312 s/iteration`;
- blocksparse-t32 took `57.195206 s/iteration`, making it `2.06x` slower in
  wall time and `21.97x` more expensive per projected iteration than the
  two-thread winner;
- the chi=512 validation grew the corrected state in `57.912413 s`, then ran
  exactly one iteration in `381.741061 s`; full-process MaxRSS was
  `1.414 GiB` and average CPU use was about `1.44` logical CPUs;
- the 8-GiB production request therefore has about `5.66x` headroom over the
  measured chi=512 MaxRSS. It remains deliberately conservative.

### Interpretation of the apparent speedup

The chi=512 validation is a timing and memory smoke test, **not a convergence
benchmark**. It deliberately stopped after one post-expansion iteration at
residual `6.971664e-3`. Its roughly 8m24s total elapsed time must not be used as
the expected time for a converged chi=512 state.

At the matched chi=512, theta=0 point:

- legacy job 54370665 averaged `408.951256 s/iteration` over 40 iterations;
- its median was `397.950046 s`, and its last ten iterations averaged
  `388.843571 s`;
- Project B's one validation iteration took `381.741061 s`.

This is only a `1.071x` wall-time improvement against the legacy mean and a
`1.019x` improvement against the legacy last-ten mean. The strong result is
allocation efficiency: the old 69-logical-CPU, 128-GiB request was charged as
35 physical cores, while the calibrated 4-logical-CPU, 8-GiB request is charged
as three. Projected cost falls from `0.031061836` to `0.002485293`
node-hours per matched iteration, a `12.50x` reduction. The `11.67x` charge-rate
ratio supplies almost all of that gain.

Do not claim that the numerical kernel or memory footprint improved by an
order of magnitude. Legacy MaxRSS and CPU utilization were not captured; only
the old request is known. The current result proves that the legacy allocation
was vastly overprovisioned for this workload.

The corrected period-2 cell, two-thread block-sparse backend, adaptive
continuation, and separation of optimization from spectroscopy should reduce
full-campaign work, but their individual contributions have not been isolated.
New finite-flux and spectrum timings are still required.

## Phase 1 — metastable branch tracking and basin diagnostics

### Scientific objective

The primary purpose of flux threading is to **follow an adiabatically connected
metastable branch**, including through intervals where another variational
state has lower energy. Phase 1 must not construct a pointwise lower-energy
envelope.

Use chi=64–256 and two independent preparations:

1. **Forward continuation is the primary threaded branch.** Prepare its first
   state independently, then use every continuation-accepted state to seed the
   next larger flux. Continue the labeled branch even when it is not the
   lowest-energy candidate at that flux.
2. **Reverse continuation or a second seed is the basin diagnostic.** Prefer a
   reverse scan from an independently prepared endpoint when practical;
   otherwise repeat the forward scan from a different random seed or distinct
   initial ansatz. This preparation must never inherit a checkpoint descended
   from the primary forward branch.

The second preparation identifies what the forward state is metastable
relative to, reveals hysteresis and crossings, and distinguishes a physical
branch from an accidental optimizer trap. It is not a replacement state chosen
solely because its energy is lower.

Initial sparse flux points:

- YC8-1: `theta/pi = 0, 0.5, 0.75, 0.875, 1.0`;
- YC8-0: `theta/pi = 0, 1.0, 1.5, 1.75, 2.0`.

### Branch-preservation rules

- Give every saved state a preparation/branch label and preserve its parent
  checkpoint, seed, direction, and flux history.
- Never overwrite or reseed the forward branch with the competing branch merely
  because the latter has lower energy.
- Save every distinct, branch-continuous state. A smooth, converged,
  higher-energy state is an intended metastable result, not a rejected state.
- A state is `continuation_accepted` only when it passes numerical eligibility
  and, when it has a parent, the mixed-transfer overlap gate. A rejected state
  is numerically unconverged, branch-discontinuous, invalid, corrupted, or
  demonstrably duplicate—not simply higher energy.
- Compare converged candidates using energy, residual, entropy, correlation
  length, local observables, and, when available, state overlap/fidelity.
- Treat a sudden state jump as a possible basin change. Attempt interval
  bisection and branch recovery before calling it a physical endpoint.
- Stop continuation only when residuals rebound repeatedly, stagnate far above
  tolerance, the checkpoint fails validation, or repeated refinements cannot
  recover the labeled branch. Record whether the outcome is a numerical
  failure, a basin jump, or a bracketed branch-loss/spinodal point.

Optimize first and do not run transfer spectroscopy during the scout scan.
Use roughly `1e-5`–`1e-6` while scouting; reserve `1e-8` for the selected
production states in Phase 2 after observables and branch identity stabilize.
The residual is a stationarity test, not a global-ground-state selector:
converging a warm-started candidate more accurately does not by itself erase
its metastable identity. Branch identity is tested separately with the parent
overlap and stored continuity diagnostics.

For a period-`p` MPS, the continuity score is
`abs(lambda_max(T_parent,candidate))^(1/p)`, where `T_parent,candidate` is the
mixed transfer map. Phase 1 currently requires a score of at least `0.99` per
site. This is a configurable trust-region guard rather than a universal
physical threshold. Review the measured overlaps and accompanying audit jumps
after the first real job before changing it; do not loosen it merely to force
the scan through a suspected basin jump.

### Phase 1 compute protocol

- Use the calibrated optimization setting: two Julia threads, BLAS=1,
  Strided=1, threaded block sparse enabled, a four-CPU scan step, and 8 GiB.
  Accept Shared-QOS memory-driven allocation expansion only while it remains
  within the same three-charged-physical-core forecast.
- Use the minimal cell and uniform gauge: period 2 for YC8-1 and period 8 for
  YC8-0.
- The original scout began at chi 128 and diagnosed the local continuation
  failure through chi 192. As an explicit project-owner override, the new
  primary-forward restart begins independently at chi 512. Do not extrapolate
  this authorization to chi above 512 or to the incompatible `hu_yc8_*`
  templates.
- Submit one small pilot at a time and reconcile `sacct` before launching a
  wider set. Do not infer wall time from the one-iteration theta=0 validation.
- Until finite-flux data exist, allow a `2–3x` wall-time contingency per
  iteration and checkpoint frequently. The legacy finite-flux points averaged
  roughly 980–1162 seconds per chi=512 iteration, but this has not yet been
  measured in the corrected implementation.
- If a compatible corrected chi=512 checkpoint already exists, run 3–5 timed
  iterations at one nonzero flux to calibrate finite-flux cost. If not, defer
  that chi=512 probe until the first Phase 2 promotion rather than creating an
  expensive state solely for benchmarking.
- After the first immutable accepted state exists, benchmark transfer
  spectroscopy in a separate job with only 4–6 eigenvalues. Measure neutral
  and physical-Sz sectors separately. Do not assume the optimizer's 8-GiB
  request is sufficient for the Krylov solves.

### Implemented Phase 1 submission safeguards

1. Update `slurm/run_scan_cpu.sh` so Julia uses two compute threads with four
   Slurm logical CPUs and so the Shared-QOS memory request is explicit.
2. Create dedicated sparse Phase 1 configs rather than repurposing the current
   chi=512 YC8 production templates.
3. Create a reverse-direction config for each geometry, or a clearly distinct
   second-seed config when reverse preparation is not practical.
4. Ensure output directories, filenames, and HDF5 metadata encode geometry,
   branch/preparation, direction, seed, chi, and flux so branches cannot be
   silently mixed.
5. Add a pre-submission charge forecast and hard refusal if submitted and
   running Project B work could exceed the 150-node-hour limit.
6. Require a gauge-invariant parent-overlap gate in addition to the residual
   gate, persist its Krylov diagnostics and observable jumps, and classify an
   overlap-limited bracket separately from numerical continuation loss.

Gate to Phase 2:

- the primary forward metastable branch reaches both sides of each proposed
  crossing, or its loss is bracketed and classified;
- the independent preparation either reaches the same basin or establishes a
  distinct competing basin whose hysteresis is explicitly mapped;
- no branch is discarded merely because it is higher in energy;
- enough timing, MaxRSS, and charged-node-hour data exist to replace the
  temporary `2–3x` finite-flux contingency;
- one small spectrum job has established a separate resource request before
  Phase 2 spectroscopy expands;
- no feature is inferred from an unconverged checkpoint.
- no child checkpoint seeds continuation unless both numerical eligibility and
  parent continuity pass.

## Phase 2 — moderate-chi Hu reproduction

- Densify flux only near the crossing, using adaptive interval halving.
- Use chi=256, 512, 1024 only where the lower-cost scans justify it.
- Run transfer spectroscopy only on immutable, numerically valid,
  branch-labeled states. Metastable states remain eligible.
- Resolve physical `Sz=1` together with the neutral reference.
- Use 4–6 eigenvalues for scouting and 8–12 at final selected points.
- For YC(Ly)-0, use the mixed one-site circumference-translation transfer
  matrix for `k1` and the pure transfer matrix for `k2`.
- For YC(Ly)-1, use the two-site pure transfer phase and Hu Eq. (4), retaining
  both `k1` branches separated by pi.
- Approach each crossing from both directions.

Gate to Phase 3:

- the expected two-flavor and four-flavor closing locations are reproduced;
- momentum labels pass their stored translation-fidelity, Schmidt-diagonality,
  coverage, and coherence checks;
- energy, entropy, and correlation lengths are stable under checkpoint/restart
  and independent preparation **within each identified branch**; differences
  between genuinely distinct branches are retained and reported.

## Phase 3 — high chi only at selected critical fluxes

Run `chi = 128, 256, 512, 1024` ladders at the selected `theta_c`, not over the
whole trajectory. Admit chi=2048 only after a node-hour review and only with
restart safety.

Promote to the next chi only if:

- the VUMPS residual passes;
- the selected branch can be recovered or tracked reproducibly from its stored
  history; reverse/second-seed disagreement is allowed when it is an explicitly
  mapped competing branch rather than an unidentified basin jump;
- correlation length grows materially;
- the relevant inverse-correlation-length level decreases consistently;
- adjacent-window `c_eff` estimates agree within approximately 20–30%.

Stop if two successive doublings show little correlation-length growth, the
central-charge estimate drifts without a stable window, or the state changes
basin.

## Phase 4 — one decisive independent validation

Choose exactly one based on the Phase 2–3 uncertainty:

- a second seed at the final critical point;
- reverse-flux confirmation;
- one targeted YC10 critical-point check;
- a second central-charge ladder if the first geometry was genuinely conclusive.

Broad YC10 scans and dynamics remain outside this 150-node-hour campaign.

## Operational rules and ledger

Every job record must include job ID, geometry, MPS period, twist gauge, theta,
chi, branch ID, preparation type, direction, random seed, parent checkpoint or
state hash, requested CPUs and memory, wall time, peak RSS, charged node-hours,
final residual, numerical acceptance, basin classification, entropy, and
leading correlation length. Record optimization and spectrum resources
separately. Do not promote automatically to a higher phase or chi, and never
mark a converged state rejected solely because another branch has lower energy.

| Date | Phase | Job IDs | Estimated node-h | Charged node-h | Decision / result |
|---|---:|---|---:|---:|---|
| 2026-08-04 | 0 | 56334122–56334138 | 0.661567 | Not reconciled | Correct two-site seed reached residual 1.3047e-5 after 60 chi=256 iterations; the strict calibration gate stopped it and all dependent workers exited without timing |
| 2026-08-06 | 0 | 56387697, 56387700–56387713, 56400726–56400727 | 0.432866 | Not reconciled | Retry converged; all 13 candidates completed; blocksparse-t2 won; one chi=512 timing/memory validation completed |
| 2026-08-06 | **0 total** | Both calibration attempts | **1.094433** | Not reconciled | Phase 0 complete; estimated project allowance remaining is 148.905567 node-hours |
| 2026-08-07 | 1 | 56434602 | 0.050332031 | 0.050332031 | Accepted primary forward theta/pi=0.2265625 at residual 9.9814e-6; bracketed numerical continuation loss at 0.234375 |
| 2026-08-08 | 1 | 56456634 | 0.190598958 | 0.190598958 | Accepted primary forward theta/pi=0.23828125; theta/pi=0.2421875 remained smoothly contracting at the 200-iteration cap |
| 2026-08-11 | **1 reconciled total** | All tracked Phase 1 jobs | — | **0.368613281** | Synced local ledger after user-confirmed Perlmutter reconciliation; reverify the live remote ledger before submission |
| 2026-08-12 | 1 | 56675925 | 0.117122396 | 0.117122396 | Accepted chi-128 primary forward theta/pi=0.2421875 after 308 iterations; bracketed a numerical plateau at theta/pi=0.24609375 |
| 2026-08-12 | 1 | 56712061 | 0.029934896 | 0.029934896 | Step-and-expand chi-192 control stopped at iteration 71; all 710 inner solves converged, but simultaneous theta/chi changes and early plateau termination make it inconclusive as a representation test |
| 2026-08-12 | **1 reconciled total** | All tracked Phase 1 jobs | — | **0.515670573** | Latest locally synced reconciled total; verify the live Perlmutter ledger before the next submission |
| 2026-08-13 | 1 | 56890262 | 0.140957031 | 0.140957031 | Fixed-flux chi-128 to chi-192 expansion reached the 360-iteration cap while smoothly contracting; residual `2.332663e-5`, projected `1e-5` crossing near cumulative iteration 484, all 3600 inner solves converged |
| 2026-08-13 | **1 reconciled total** | All tracked Phase 1 jobs | — | **0.656627604** | Latest locally synced reconciled total; Project B total including the Phase 0 baseline is `1.751060604` node-hours; verify live Perlmutter accounting before submission |
| 2026-08-14 | 1 | 56978073 | 0.043235677 | 0.043235677 | Fixed-flux chi-192 resume converged after 130 additional and 490 cumulative iterations; residual `9.953697e-6`, overlap/site `0.9994664352`, all 1300 inner solves converged |
| 2026-08-14 | **1 reconciled total** | All tracked Phase 1 jobs | — | **0.699863281** | Latest locally synced reconciled total; Project B total including the Phase 0 baseline is `1.794296281` node-hours; verify live Perlmutter accounting before submission |
| 2026-08-15 | 1 | 56994767 | 0.120058594 | 0.120058594 | Fixed-chi 192 step to theta/pi=0.24609375 reached minimum residual `2.254667e-5` at iteration 352 and flattened; all 3600 inner solves converged, but the point was not numerically eligible for continuity testing |
| 2026-08-15 | **1 reconciled total** | All tracked Phase 1 jobs | — | **0.819921875** | Locally synced total through job 56994767; Project B total including the Phase 0 baseline is `1.914354875` node-hours; verify live Perlmutter accounting before submission |
| 2026-08-18 | 1 | 57192723 | 0.347610677 | 0.347610677 | Fresh chi-512 lineage accepted theta/pi=0 and 0.1; the direct 0.1-to-0.2 update stopped as `diverging_residual`, while all 3550 recorded inner solves converged |
| 2026-08-18 | **1 reconciled total** | All tracked Phase 1 jobs | — | **1.167532552** | Locally synced total through job 57192723; Project B total including the Phase 0 baseline is `2.261965552` node-hours; verify live Perlmutter accounting before submission |

## Decision log

- 2026-08-05: hard Project B limit fixed at 150 node-hours.
- 2026-08-05: Hu unit-cell convention adopted: even YC(Ly)-0 uses `Ly`; YC(Ly)-1 uses two sites.
- 2026-08-05: uniform twist gauge is the production default; seam-gauge files remain readable as legacy artifacts.
- 2026-08-05: full-cell phases are never silently unfolded; momentum resolution requires the geometry's minimal cell.
- 2026-08-05: the first corrected chi=256 seed stopped at 1.3047e-5 after 60 final-stage iterations. The retry keeps the 1e-5 gate and raises the ceiling to 80; a looser calibration tolerance was rejected because the residual was converging smoothly.
- 2026-08-06: Phase 0 completed for the corrected period-2 YC6-1 state. The selected optimization setting is threaded block sparse with two Julia threads, BLAS=1, Strided=1, four Slurm logical CPUs, and an 8-GiB production request.
- 2026-08-06: the chi=512 validation is explicitly classified as a one-iteration timing and memory smoke test, not a converged-state benchmark. Do not extrapolate its 8m24s elapsed time to a full solve.
- 2026-08-06: the measured wall-clock kernel is only about 1.02–1.07x faster than the matched legacy theta=0 iterations. The approximately 12.5x node-hour reduction is dominated by Shared-QOS right-sizing, not an order-of-magnitude kernel speedup.
- 2026-08-06: Phase 1's primary observable is the forward, adiabatically threaded metastable branch. Reverse continuation or a second seed is an independent basin diagnostic; lower energy alone never authorizes replacing the primary branch.
- 2026-08-06: a converged higher-energy branch is a valid metastable result. “Rejected” is reserved for numerical failure, invalid state data, or a verified duplicate.
- 2026-08-06: existing chi=512 YC8 configs and the eight-thread scan launcher are not Phase 1 submission artifacts. Dedicated sparse configs, calibrated launcher resources, independent branch metadata, and budget refusal must be implemented first.
- 2026-08-06: optimization and transfer spectroscopy remain separate jobs. Spectrum resource usage is uncalibrated and must receive its own small benchmark before Phase 2 expands it.
- 2026-08-06: Phase 1 launch support was implemented with four independent chi=128 YC8 forward/reverse configs, schema-v3 parent/hash/history metadata, strict lineage checks, and a guarded `plan`/`submit`/`reconcile` launcher. No Phase 1 job was submitted during implementation.
- 2026-08-06: the first Phase 1 pilot failed before Julia startup because Shared QOS raised `SLURM_CPUS_PER_TASK` from the requested four to five for the 8-GiB request. The worker guard now accepts four through six effective logical CPUs—the range covered by the existing three-physical-core forecast—while retaining two Julia threads and a four-CPU `srun` step.
- 2026-08-06: the first retry exposed a stale empty `.submission-lock`: the EXIT trap had referenced a function-local path after the function returned. Launcher 2.0.2 keeps the lock path at script scope so both successful and failed submission checks clean it at process exit.
- 2026-08-06: the second retry reached `srun` but resolved the Julia project as `/var/spool/slurmd`, where Slurm stages the submitted batch script. Launcher 2.0.3 passes and validates the original absolute project directory as an explicit worker argument, so the staged script invokes the repository's `Project.toml` and `scripts/run_scan.jl`.
- 2026-08-07: the first full Phase 1 job produced a valid primary-forward lineage through theta/pi=0.21875 and bracketed numerical continuation loss at 0.25, but buffered logging obscured those artifacts and a retry recomputed theta/pi=0 before colliding with its immutable filename. Launcher 2.0.4 refuses nonempty state-output directories before submission. Minimum-step continuation loss now writes `scan_outcome.toml`, exits normally, and is explicitly classified as numerical rather than a physical endpoint.
- 2026-08-07: the primary-forward branch is not abandoned at the first bracket. A dedicated strict-lineage recovery config resumes from the accepted theta/pi=0.21875 artifact, first targets 0.234375, permits refinement down to 1/128 of pi, inserts intermediate targets through the crossing, and writes to a distinct output directory. Rejected theta/pi=0.25 artifacts remain excluded from continuation.
- 2026-08-07: job 56434602 accepted the recovered primary-forward state at theta/pi=0.2265625 with residual 9.9814e-6. Its theta/pi=0.234375 corrector remained above tolerance after 100 iterations, narrowing numerical continuation loss to [0.2265625, 0.234375]. Smooth energy and entropy do not turn that numerical bracket into a physical endpoint.
- 2026-08-07: residual convergence and adiabatic branch identity are now separate gates. Schema-v4 states store the dominant mixed parent-candidate transfer eigenvalue, overlap per unit cell and per site, Krylov convergence data, and energy/entropy/local-observable/Schmidt-spectrum jumps. Phase 1 requires overlap per site >=0.99 before a child can seed continuation; overlap failure is classified as a possible basin jump, not a physical endpoint.
- 2026-08-07: retrospective overlap checks on accepted schema-v3 neighbors gave 0.999804580663 per site for theta/pi 0 -> 0.125 and 0.999987222742 for 0.1875 -> 0.21875. Both clear the 0.99 gate; no genuine basin-jump example has yet calibrated its discriminating power.
- 2026-08-07: the next forward corrector resumes from the immutable accepted theta/pi=0.2265625 parent, keeps residual_tol=1e-5, raises max_iterations to 200, permits refinement to 1/256 of pi, and writes to a distinct output directory. The forward pass remains the primary branch.
- 2026-08-07: launcher 2.1.1 and the Julia restart loader require strict restart configs to pin `initial_state_sha256`. Both verify the digest before optimization, closing the gap where a same-path parent could have been replaced before job startup.
- 2026-08-11: reconciled job 56456634 accepted the chi-128 primary-forward branch through theta/pi=0.23828125. Its final theta/pi=0.2421875 attempt was still contracting at iteration 200, with a log-linear projection near iteration 307, so it is classified as iteration-limited rather than plateaued.
- 2026-08-11: launcher 2.2.1 and schema-v5 states restore environment/C/AC Krylov instrumentation, a conservative plateau detector, residual-trend projections, and distinct contracting/stalled/plateau outcome labels. The next recovery preserves the original inner solver and raises only the outer cap to 360; tighter inner solves and chi expansion remain separate controls.
- 2026-08-11: the Hu et al. comparison does not establish a 0.1-pi internal continuation step. Their calculations used iDMRG and much larger reported bond dimensions (m=6144 for YC8 gap data and m=12288 for YC8-1 correlation spectra), so figure-point spacing is not evidence that chi-128 VUMPS should traverse the same interval without slowing.
- 2026-08-12: job 56675925 accepted the chi-128 primary-forward state at theta/pi=0.2421875 after 308 iterations, validating the earlier contracting-trend diagnosis without loosening the 1e-5 residual gate. The subsequent theta/pi=0.24609375 point plateaued near residual 3.43e-5.
- 2026-08-12: job 56712061 expanded to chi 192 and stepped to theta/pi=0.24609375 simultaneously. Its 710 inner Krylov solves all converged, but the generic plateau detector stopped an irregular post-expansion trajectory at iteration 71, so the job does not establish that chi 192 itself is unable to converge.
- 2026-08-13: the next controlled test expands the exact accepted theta/pi=0.2421875 parent from chi 128 to chi 192 without changing flux. Generic plateau termination is disabled for the 360-iteration settling window; residual and parent-overlap gates remain strict. Same-flux failures now receive a dedicated immutable outcome rather than a zero-width continuation bracket.
- 2026-08-14: fixed-flux job 56890262 showed a long, exceptionally smooth chi-192 contraction after the expansion transient. It stopped at residual 2.332663e-5 solely because of the 360-iteration cap; the final trend projected tolerance near cumulative iteration 484. The next test reuses that rejected MPS only as a numerical seed for 180 more iterations at the identical flux.
- 2026-08-14: launcher 2.3.0 and schema-v6 states separate optimizer-restart provenance from accepted continuation lineage. A resume requires SHA-pinned accepted-parent and rejected-checkpoint files, identical model/flux/branch metadata, checkpoint chi equal to requested chi, and `maximum_iterations_contracting`; it is restricted to one fixed flux. The accepted parent remains the overlap reference. Failed retries receive a dedicated nonphysical-endpoint outcome.
- 2026-08-14: schema-v6 rank-aligns Schmidt probabilities before total-variation comparison so symmetry-block multiplicity changes do not create a spurious near-unity distance merely by shifting serialized positions. Sector-resolved multiplicities and weights remain a separate diagnostic.
- 2026-08-14: fixed-flux resume job 56978073 validated the prior contracting-trend projection. It accepted chi 192 at theta/pi=0.2421875 after 490 cumulative iterations without loosening the residual gate; all 1300 new inner solves converged and parent overlap per site was 0.9994664352.
- 2026-08-14: the next controlled test uses the accepted chi-192 state itself as the strict-lineage parent and changes only theta by 1/256 of pi to 0.24609375. Chi remains 192, the residual and overlap gates are unchanged, inner diagnostics stay enabled, and no rejected optimizer checkpoint participates.
- 2026-08-15: job 56994767 established that a converged chi-192 parent and a 1/256-pi step still flatten near residual 2.255e-5 at theta/pi=0.24609375. The 34.2% improvement over chi 128 confirms a bond-dimension effect, while converged inner solves and stable sector multiplicities exclude the tested inner-solver and missing-sector explanations.
- 2026-08-17: the project owner ended further low-chi correctors and authorized a fresh chi-512 YC8-1 primary-forward restart on the exact 0.1-pi grid. Launcher 2.4.0 admits chi through 512 and recognizes only the dedicated fresh campaign metadata for this alternate schedule. The `1e-5` residual, `0.99` overlap, minimal-cell, uniform-gauge, immutable-output, and budget safeguards remain unchanged.
- 2026-08-18: job 57192723 accepted the fresh chi-512 lineage through theta/pi=0.1. The direct step to 0.2 reached minimum residual `1.013369e-4` and then diverged, despite convergence of every recorded inner solve. The rejected candidate retained high retrospective overlap and unchanged U(1) sector multiplicities, so it is a numerical outer-update failure rather than evidence of a physical endpoint or demonstrated basin change.
- 2026-08-18: the next controlled job first halves only the failed continuation interval. A SHA-pinned generator accepts exactly the immutable theta/pi=0.1 state from job 57192723, schedules 0.15 followed by 0.2 through 1.0 at chi 512, retains the strict residual and continuity gates, and refuses the rejected direct-0.2 candidate. Its minimum step is 0.05, so later 0.1-pi failures may bisect once but the job cannot silently return to the earlier fine-step campaign.
- 2026-08-18: launcher 2.5.0 replaces repeated manual chi-512 classification/configuration/reconciliation with immutable `advance` decisions. The first transition schedules 0.15 followed by every remaining nominal target, so success at the bridge continues in the same allocation. Infrastructure recovery, remaining-grid continuation, one midpoint down to 0.05 pi, and capped contracting retries are automated; continuity loss, inner-solver failure, failure at the floor, changed hashes, and unsupported outcomes stop without submission. `advance-submit` remains an explicit operator action and still passes through every live budget guard.
