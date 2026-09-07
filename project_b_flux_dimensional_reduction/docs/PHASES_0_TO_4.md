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
| 1 — metastable branch tracking and basin diagnostics | 20 node-h | **In progress**; YC8-1 chi-512 remains accepted through theta/pi=0.15; chi-1024 anchor failed numerically and needs checkpoint review plus accounting repair. YC6-1 is paused after diagnostic acceptance at 0.35 under its separate `1e-4` profile. See `PROJECT_STATE.md` and decision 002. | Forward threaded branches, independent competing basins, hysteresis, and approximate critical fluxes |
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

Reconciled job `57245573` then held the parent and chi fixed while halving the
target to `theta/pi=0.15`. The residual reached `4.279780651e-5` at iteration
13, then diverged to `1.027012e-3` at iteration 32; all 320 inner solves
converged. Retrospective overlap per site was `0.9999724354`, both cuts retained
identical virtual U(1) sector labels and multiplicities, and the sector-weight
changes were about `1e-3`. The smaller step improved the minimum by `2.37x`
relative to the direct `0.2` attempt but still missed the gate by `4.28x`.
This is stronger evidence for a sequential outer-VUMPS instability, not a
physical endpoint or demonstrated branch jump. The job cost `0.098899740`
node-hours.

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

Final-control job `57337312` changed only the multisite update schedule from
sequential to parallel and converged monotonically at `theta/pi=0.15` in 10
outer iterations, residual `9.183773e-6`. All 60 inner solves converged and
parent overlap per site was `0.9999782682`. Launcher 2.7.0 therefore admits a
SHA-pinned parallel continuation from accepted state
`38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`
through `0.2,0.3,...,1.0`. Best-iterate restoration, the `1e-5` residual gate,
the `0.99` continuity floor, automatic midpoint recovery down to `0.05*pi`,
and the explicit submission gate remain unchanged. Exhausted numerical
recovery triggers iDMRG review; scheduler/process failure remains
inconclusive. Exact commands are in
`docs/PHASE1_PARALLEL_VUMPS_PROMOTION.md`.

Promoted parallel-VUMPS job `57392725` then exhausted that policy at the first
remaining point, `theta/pi=0.2`. Its best residual was
`1.192367929e-5` at iteration 15, narrowly above the unchanged `1e-5` gate;
the terminal residual diverged to `1.030614057e-3` at iteration 46. All 276
inner solves converged. The restored best tensor is immutable but rejected,
with SHA-256
`f59dd18f29004d259a3d94e7bedadd99a7fcb88b1ba960fb7e357dd8e645e7c0`.
The accepted `theta/pi=0.15` state remains the parent. This exhausts the
approved VUMPS recovery rather than establishing a physical endpoint.

Perlmutter job `57452187` then ran the single fixed-chi-512, period-2, U(1)
MPSKit 0.13.13 one-site iDMRG control at `theta/pi=0.2`. It completed at the
scheduler/process level after 6,567 seconds, but its 80-iteration result failed
the predeclared native criteria: final MPSKit bond-matrix update norm
`3.781953625e-5` versus `1e-8`, and corrected final-four intensive-energy span
`6.930349628e-9` versus `1e-9`. The original stored cumulative superblock
energy was not a valid stationarity history; the corrected period-normalized
MPSKit energy increment is now the schema-2 native quantity. The tolerances
were not changed.

The ITensor-side analysis of result SHA-256
`527afdf421e3411fb91f622ae0a5f8764d453f892c7752b2294913813749c8de`
found parent overlap per site `0.9999707484`, unchanged U(1) sector
multiplicities, and small entropy/magnetization/local-energy changes. It is a
scientifically justified continuation seed but remains explicitly rejected and
cannot replace accepted theta/pi=0.15 parent SHA-256
`38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`.

The next controlled continuation used the same rejected tensors, with every
native and branch gate unchanged. Its streamlined active-control SHA-256 was
`67e258ee244ddaf397d9f493a09c1a30d4a0b1e0f4a3a001e954db8f287a89d0`
and bridge SHA-256 is
`f0612ee36814a7830253d3bc0f80ebeee1031ff104f4075cb519e02ec7f4ef95`.
Heavy checkpoints go to `$PSCRATCH` every 20 iterations, while the home package
automatically receives a compact manifest/history HDF5.

That control ran as Perlmutter job `57500598`. It completed with exit `0:0`
after `08:48:35` and 400 iDMRG updates. Result SHA-256
`c7ef67c0e22b32d581fec9ed3d4f86b14182db15a1f80688c88fc311eb326116`
maintained chi 512 and zero one-site discarded weight. Its final-four
period-normalized energy span is `1.222133506e-12`, passing the `1e-9` gate,
but its MPSKit stopping value is `2.311348784e-6`, still 231 times above the
fixed `1e-8` gate. Pinned MPSKit source defines this value as
`norm(C_new - C_old)` after a complete sweep; the legacy field name
`environment_error` is not an environment residual. It decreased monotonically
over the final 100 iterations and reached its run minimum at iteration 400, so
the state is slowly contracting rather than plateaued.

Native convergence already rejects this state, so the corrected analyzer did
not perform the ITensor conversion, parent-overlap, observables, sector
comparison, or common VUMPS probe. Those remain promotion gates for a future
native-converged candidate. The native-only analysis SHA-256 is
`eb7d1fa5b655f212ce30d88963d16900d0c9e2070f03014b7c1b32db05ba66c1`.

After reviewing this evidence, the project owner selected a post-hoc working
exploratory gate of bond-matrix update norm at most `1e-5` and final-four
energy span at most `1e-8`. Job `57500598` passes that working native gate.
Its immutable source control and original rejection remain unchanged, and the
working passage is not a promotion: overlap, common observables, U(1) sectors,
and primary-forward continuity remain unevaluated. The exact policy and source
hashes are recorded in `configs/phase1_idmrg_working_convergence.toml`.

Detailed job-57500598 accounting shows 128 logical CPUs in the solver step but
only `150866` TotalCPU seconds over `31707` wall seconds, or 4.7586 CPUs on
average and 3.72% scheduler CPU efficiency; MaxRSS was 9.63 GiB. The exclusive
regular-QOS allocation therefore cost approximately `8.809722222` node-hours.
Before any further scientific continuation, one guarded Shared-QOS job will
benchmark independent 2/4/8/16-thread restarts from the same rejected tensor.
It writes no checkpoints or full states and is capped at `0.1875` node-hours.
Exact commands and the full-tree Globus sync cycle are in
`docs/PHASE1_IDMRG_BENCHMARK.md`; storage details remain in
`docs/PHASE1_IDMRG_STORAGE.md`.

Benchmark jobs `57548405` and `57550459` both failed before the first iDMRG
update and provide no timing evidence. The first worker resolved the repository
below Slurm's spool directory. The second reached the correct package but called
the nonexistent Julia 1.12 API `Base.cputime()` before state initialization.
Job `57574096` completed five 2-thread solver updates but then failed while HDF5
serialized a packed `BitVector`; its partial file contains no timing histories.
The final schema-4 retry uses libuv process CPU accounting, dense `UInt8` mask
serialization, atomic temporary cleanup, and exact timing plus HDF5 writer
preflights on both login and compute nodes. It propagates the validated Julia
binary into the worker and hash-pins all three failed attempts. Its
active-control SHA-256 is
`8fb5a1c0b99e5fa3c955f9e0e914913735e08fe64e90681a648d9ca339a05110`.

Benchmark job `57576411` then completed all four independent thread settings
with exit `0:0` and selected two Julia threads with a four-logical-CPU solver
step. Its Shared-QOS charge was `0.1087152778` node-hours. The subsequent
theta/pi=0.175 science job `57608599` failed after eight seconds before Julia
started: the 16-GiB request produced a 10-logical-CPU allocation, but the old
launcher combined a memory-derived `SLURM_CPUS_PER_TASK=9` with
`SLURM_TRES_PER_TASK=cpu=4`. No scientific update or result exists. Charging
five physical cores for eight seconds contributes `0.0000868056` node-hours,
bringing Phase 1 to `12.2524457471` and Project B including Phase 0 to
`13.3468787471` node-hours. The immutable retry separates a 10-logical-CPU
outer allocation from an exact four-logical-CPU solver step while retaining
two Julia threads, 16 GiB, and the same five-core maximum-charge forecast.

The corrected retry completed as job `57611537` after 33,423 seconds and 371
one-site updates. It passed the predeclared working iDMRG gate with final
bond-matrix update norm `9.784243013e-6` and final-four intensive-energy span
`1.699703489e-9`. Full common-representation analysis nevertheless measured
overlap per site `0.9662443394` with the accepted theta/pi=0.15 parent, below
the fixed `0.99` branch gate, so theta/pi=0.175 remains rejected and cannot
advance the lineage. The next package bisects to theta/pi=0.1625 and again uses
the accepted 0.15 parent itself as its startup tensor. Job `57611537` charged
`0.3626627604` node-hours, bringing Phase 1 to `12.6151085076` and Project B
including Phase 0 to `13.7095415076` node-hours.

Independent YC6-1 period-6 job `57629467` then accepted theta/pi through 0.3,
rejected the divergent direct 0.4 candidate, and adaptively attempted 0.35 from
the accepted 0.3 parent. The 0.35 residual contracted from `6.118223e-3` to
`1.644340e-4` over 36 iterations, but the run reached its 48-hour limit before
the old worker persisted an in-progress iterate. The accepted 0.3 SHA-256 is
`741261e9fdef75b3793837f2b26f3daac4515c491baab622fc1e8d1e2c8bfe45`;
the rejected 0.4 SHA-256 is
`971c4fe5a92fda9ad811dcb09d69689a8570f0b27d2a97f888ee9aa6f00bb523`.
The continuation restarts 0.35 from accepted 0.3, with immutable checkpoints
every five iterations and after growth stages plus a one-hour Slurm USR1
pre-timeout path. The status-derived `1.1251432292` node-hour charge brings
Phase 1 to `13.7402517367` and Project B to `14.8346847367` node-hours.

The next synced continuation retained the original `1e-5` gate, accepted
adaptive points `0.325` and `0.3375`, and stopped at the scheduler boundary
with an unclassified `0.35` checkpoint at residual `4.6601403116e-4`. The
accepted `0.3375` SHA-256 is
`ac239341c6b4103e4bbeae2a2468d4fd9253d5db1fbbd0d6d7b5448f9e85234b`.
Its job ID and authoritative accounting row are not present in the current
local sync, so the ledger remains unchanged; the launcher conservatively
reserves the full `1.125` node-hour forecast until reconciliation. The owner
then authorized an exploratory `1e-4` YC6-1 VUMPS residual profile. Its
successor restarts `0.35` from the stricter accepted `0.3375` state, not from
the old-tolerance checkpoint, and preserves every other solver and branch
gate.

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
- completed sequential `theta/pi=0.15` outcome:
  `output/phase1/yc8_1/chi512_auto_refine_interval_from_p0p10000000_p0p15000000_to_p1p00000000_f71fc084883e/seed_101/chi512/scan_outcome.toml`;
- final parallel-update control generator:
  `scripts/prepare_phase1_chi512_parallel_control.jl`;
- promoted parallel-continuation generator:
  `scripts/prepare_phase1_chi512_parallel_continuation.jl`;
- final VUMPS control contract and commands:
  `docs/PHASE1_FINAL_VUMPS_CONTROL.md`;
- successful-control promotion contract and commands:
  `docs/PHASE1_PARALLEL_VUMPS_PROMOTION.md`;
- automatic transition contract and commands:
  `docs/PHASE1_AUTOMATION.md`;
- diagnostic protocol and interpretation:
  `docs/PHASE1_PLATEAU_DIAGNOSTICS.md`.

Do **not** submit either existing `configs/hu_yc8_*_forward.toml` as a Phase 1
campaign. Generate the pinned final control exactly as documented, then use
ordinary launcher `plan|submit`. Do not hand-edit or generalize its parallel
solver settings:

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
| 2026-08-20 | 1 | 57245573 | 0.098899740 | 0.098899740 | Exact-parent chi-512 midpoint to theta/pi=0.15 reached minimum residual `4.279781e-5` before diverging; all 320 inner solves converged and retrospective branch diagnostics stayed smooth |
| 2026-08-20 | **1 reconciled total** | All tracked Phase 1 jobs | — | **1.266432292** | Locally synced total through job 57245573; Project B total including the Phase 0 baseline is `2.360865292` node-hours; verify live Perlmutter accounting before submission |
| 2026-08-21 | 1 | 57337312 | 0.038216146 | 0.038216146 | Exact-parent parallel-VUMPS control accepted theta/pi=0.15 in 10 monotone iterations; residual `9.183773e-6`, overlap/site `0.9999782682`, and all 60 inner solves converged |
| 2026-08-21 | **1 reconciled total** | All tracked Phase 1 jobs | — | **1.304648438** | Locally synced total through job 57337312; Project B total including the Phase 0 baseline is `2.399081438` node-hours; verify live Perlmutter accounting before submission |
| 2026-08-22 | 1 | 57392725 | 0.562500000 | 0.166842448 | Promoted parallel VUMPS exhausted the 0.05-pi recovery floor at theta/pi=0.2; best restored residual `1.192368e-5`, terminal residual `1.030614e-3`, and all 276 inner solves converged; tensor remains rejected |
| 2026-08-22 | **1 reconciled total** | All tracked Phase 1 jobs | — | **1.471490886** | Locally synced total through job 57392725; Project B total including the Phase 0 baseline is `2.565923886` node-hours; verify live Perlmutter accounting before submission |
| 2026-08-23 | 1 | 57452187 | 6.000000000 | 1.824166667 | First MPSKit one-site iDMRG job completed scheduler/process successfully; 80-iteration result stayed on the primary branch but failed unchanged native environment and intensive-energy-span gates, so it remains a rejected numerical seed |
| 2026-08-23 | **1 reconciled total** | All tracked Phase 1 jobs | — | **3.295657553** | Synced total through job 57452187; Project B total including the Phase 0 baseline is `4.390090553` node-hours; successor forecast is at most 10 node-hours and still requires live Perlmutter plan plus explicit submission authorization |
| 2026-08-24 | 1 | 57500598 | 10.000000000 | 8.809722222 | Scratch-backed MPSKit continuation completed 400 updates; intensive energy passed, but the final bond-matrix update norm `2.311349e-6` failed the unchanged `1e-8` native gate; result remains rejected |
| 2026-08-24 | **1 reconciled total** | All tracked Phase 1 jobs | — | **12.105379775** | Total through job 57500598; Project B total including Phase 0 is `13.199812775` node-hours; next action is a Shared-QOS benchmark capped at `0.1875` node-hours, not another full-node continuation |
| 2026-08-24 | 1 | 57548405 | 0.187500000 | 0.000381944 derived | First Shared-QOS benchmark attempt failed after 11 seconds before any scientific iteration because its Slurm-spooled batch script resolved the project root as `/var/spool/slurmd`; no timing result exists |
| 2026-08-24 | **1 reconciled total** | All tracked Phase 1 jobs | — | **12.105761719** | Total including failed benchmark attempt 57548405; Project B total including Phase 0 is `13.200194719` node-hours; an immutable corrected retry is capped at an additional `0.1875` node-hours |
| 2026-08-24 | 1 | 57550459 | 0.187500000 | 0.007013889 derived | Second Shared-QOS benchmark attempt failed after 202 seconds before state initialization or any scientific update because `Base.cputime()` is unavailable in Julia 1.12; no timing result exists |
| 2026-08-24 | **1 reconciled total** | All tracked Phase 1 jobs | — | **12.112775608** | Total including both zero-update benchmark failures; Project B total including Phase 0 is `13.207208608` node-hours; schema-3 retry control `1cbfc097ccd1...` is capped at an additional `0.1875` node-hours |
| 2026-08-24 | 1 | 57574096 | 0.187500000 | 0.030868056 derived | Third Shared-QOS benchmark attempt completed five 2-thread iDMRG updates, then failed while HDF5 serialized a packed `BitVector`; the partial file has no timing histories, so no benchmark timing result is valid |
| 2026-08-24 | **1 reconciled total** | All tracked Phase 1 jobs | — | **12.143643664** | Total including all three invalid benchmark attempts; Project B total including Phase 0 is `13.238076664` node-hours; schema-4 retry control `8fb5a1c0b99e...` is capped at an additional `0.1875` node-hours |
| 2026-08-25 | 1 | 57576411 | 0.187500000 | 0.108715278 | Thread benchmark completed all 2/4/8/16-thread steps; independent analysis selected two Julia threads and a four-logical-CPU solver step by projected Shared-QOS node-hours per 100 updates |
| 2026-08-25 | **1 reconciled total** | All tracked Phase 1 jobs | — | **12.252358942** | Total through benchmark job 57576411; Project B total including Phase 0 is `13.346791942` node-hours |
| 2026-08-25 | 1 | 57608599 | 0.468750000 | 0.000086806 derived | First theta/pi=0.175 Shared-QOS science attempt failed after eight seconds before Julia because its four-CPU batch task conflicted with the memory-sized allocation; no scientific update or result exists |
| 2026-08-25 | **1 reconciled total** | All tracked Phase 1 jobs | — | **12.252445747** | Total including zero-update infrastructure failure 57608599; Project B total including Phase 0 is `13.346878747` node-hours; the immutable retry retains the `0.46875`-node-hour ceiling |
| 2026-08-26 | 1 | 57611537 | 0.468750000 | 0.362662760 | Theta/pi=0.175 retry completed 371 iDMRG updates and passed its predeclared working native gate, but parent overlap per site `0.9662443394` failed the fixed `0.99` primary-forward branch gate |
| 2026-08-26 | **1 reconciled total** | All tracked Phase 1 jobs | — | **12.615108508** | Total through job 57611537; Project B total including Phase 0 is `13.709541508` node-hours; next theta/pi=0.1625 midpoint retains the `0.46875`-node-hour ceiling |
| 2026-08-28 | 1 | 57629467 | 1.125000000 | 1.125143229 derived | Independent YC6-1 period-6 recovery accepted theta/pi through 0.3, rejected direct 0.4, then timed out after 36 contracting iterations at 0.35; no 0.35 state was persisted |
| 2026-08-28 | **1 tracked total** | All tracked Phase 1 jobs | — | **13.740251737** | Status-derived total through TIMEOUT job 57629467; Project B total including Phase 0 is `14.834684737` node-hours; the continuation restarts from accepted theta/pi=0.3 |
| 2026-08-29 | 1 | 57690953 | 1.125000000 | 1.104309896 | Strict YC6 continuation accepted theta/pi 0.325 and 0.3375, then preserved an unclassified theta/pi 0.35 pre-timeout checkpoint |
| 2026-08-29 | **1 reconciled total** | All tracked Phase 1 jobs | — | **14.844561633** | Total through job 57690953; Project B total including Phase 0 is `15.938994633` node-hours |
| 2026-08-31 | 1 | 57768008 | 1.125000000 | 0.333548177 | Relaxed YC6 diagnostic accepted theta/pi 0.35 at residual `9.840437e-5`, then was canceled during a diverging direct-0.4 trajectory |
| 2026-08-31 | **1 reconciled total** | All tracked Phase 1 jobs | — | **15.178109810** | Total through job 57768008; Project B total including Phase 0 is `16.272542810` node-hours |
| 2026-09-01 | 1 | 57793343 | 3.000000000 ledger | 0.144082031 corrected | Initial YC8 chi-1024 growth completed one outer iteration and honored its pre-timeout signal without making a scientific decision; Slurm allocated 18 rather than the ledger's 16 CPUs |
| 2026-09-01 | **1 corrected total** | All tracked Phase 1 jobs | — | **15.322191841** | `sacct`-corrected total through job 57793343; Project B total including Phase 0 is `16.416624841` node-hours |
| 2026-09-02 | 1 | 57801654 | 3.000000000 ledger | 2.439316406 corrected | Four-thread YC8 chi-1024 fixed-flux growth reached its 60-iteration cap while contracting, with best residual `4.860776e-4`; no chi-1024 state or theta step was accepted |
| 2026-09-02 | **1 corrected total** | All tracked Phase 1 jobs | — | **17.761508247** | `sacct`-corrected total through job 57801654; Project B total including Phase 0 is `18.855941247` node-hours; Phase 1 has about `2.238491753` node-hours remaining before later corrections |

The two 32-GiB YC8 jobs have `NCPUS=18` in synchronized `sacct.tsv` records,
but their job ledgers, forecasts, and `charged_node_hours.txt` calculations use
16. The measured charges and totals above correct that discrepancy. A full
48-hour allocation at 18 CPUs costs `3.375` node-hours, not the recorded
`3.0`; the launcher accounting guard must be corrected before another YC8
submission and all totals must still be refreshed from live Perlmutter data.

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
- 2026-08-20: job 57245573 tested the canonical 0.05-pi midpoint from the exact accepted chi-512 theta/pi=0.1 parent. The minimum residual improved by 2.37x relative to the direct 0.2 attempt but remained 4.28x above tolerance and then diverged. Parent overlap, U(1) sector support, entropy/Schmidt changes, and all inner solves remained smooth, isolating the sequential outer update as the remaining VUMPS-specific variable.
- 2026-08-20: launcher 2.6.0 and schema-v7 implement one final, pinned parallel multisite-update control at theta/pi=0.15. The generator verifies every source hash and inner solve; the launcher forbids this solver setting elsewhere. On failure, the lowest-residual iterate is saved only as a rejected diagnostic while the terminal residual is recorded separately. Numerical failure ends VUMPS and triggers iDMRG planning; infrastructure failure does not.
- 2026-08-21: final-control job 57337312 converged at theta/pi=0.15 with parallel VUMPS after 10 monotone outer iterations, residual `9.183773e-6`, 60/60 converged inner solves, and parent overlap per site `0.9999782682`. The sequential and parallel candidates have direct overlap per site `0.9999953317` and identical virtual U(1) sector support, so the control identifies instability of the sequential outer update rather than a branch change. Launcher 2.7.0 promotes only accepted state SHA-256 `38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803` and requires pinned control evidence plus immutable automatic-decision provenance for every descendant.
- 2026-08-22: promoted job 57392725 completed successfully at the scheduler/process level but failed the parallel-VUMPS residual gate at theta/pi=0.2. The restored best residual was `1.192367929e-5`, terminal residual was `1.030614057e-3`, and all 276 inner solves converged. This is the approved VUMPS recovery floor, so the rejected tensor cannot seed the primary lineage automatically and the solver transition proceeds to manual iDMRG control.
- 2026-08-22: MPSKit 0.13.13 one-site iDMRG was selected over TeNPy and the current ITensor Julia ecosystem. MPSKit supplies genuine IDMRG while permitting an exact, round-trip-checked U(1) bridge inside Julia; TeNPy is mature but adds avoidable cross-language state and model conversion risk, and the current ITensor stack does not implement true iDMRG. The first package is one point at theta/pi=0.2, fixed chi 512, with immutable per-iteration checkpoints, a pre-solver Hamiltonian-equivalence gate, independent native convergence criteria, parent overlap against the accepted 0.15 state, and no automatic submission or advance. No Perlmutter job was submitted during implementation.
- 2026-08-23: job 57452187 completed with exit `0:0` and charged `1.824166667` node-hours, but its 80-iteration iDMRG result failed the unchanged native convergence gates. Reconciliation exposed that schema-1 `energy_density` stored cumulative growing-superblock energy; the valid intensive MPSKit history is the period-normalized iterator increment previously stored as `energy_density_delta`. Schema 2 makes that quantity canonical and retains cumulative energy only as a diagnostic. The corrected span still fails, so this semantics fix does not retroactively accept the state.
- 2026-08-23: the rejected first iDMRG result passes the `0.99` overlap gate at `0.9999707484`, preserves all recorded U(1) sector multiplicities, and has smooth common observables. One continuation from its tensors is scientifically approved as a numerical retry, while the accepted theta/pi=0.15 state remains the immutable lineage parent and overlap reference. The new control permits at most 400 additional iterations and 10 node-hours without changing chi, solver, model, symmetry, gauge, period, or any tolerance; it has no automatic advance and is not submitted.
- 2026-08-23: all new heavy iDMRG checkpoints are routed to Perlmutter `$PSCRATCH` with the Slurm scratch license. Home retains controls, logs, accounting, the restartable final bridge, analyses, and an automatic lightweight checkpoint manifest/history. The project owner deleted the job-57452187 checkpoints after canceling a Globus transfer made the copies untrustworthy. The prepared successor does not depend on them: it starts fresh from the hash-pinned final-result tensor bridge and uses a distinct empty scratch directory.
- 2026-08-23: the iDMRG operator interface now mirrors the concise VUMPS workflow. A hash-pinned active-control reference permits bare `plan`, `submit`, `status`, `reconcile`, and local `analyze` commands; `submit` is the literal operational mutation, account `m4863` is the overridable default, and the submitted job ID is recorded automatically. Immutable-input, branch, one-job, no-overwrite, scratch, and budget guards remain enforced. Standing authorization was granted separately on 2026-08-25.
- 2026-08-24: job 57500598 completed 400 additional one-site iDMRG updates. Its energy-density span passed, but MPSKit's `norm(C_new-C_old)` stopping value remained `2.311349e-6` and was still contracting at the cap. The quantity had been mislabeled as an environment error in Project B artifacts; the legacy path remains readable, while new analysis names its actual bond-matrix-update semantics. Native failure now short-circuits ITensor promotion conversion and records a native-only rejected artifact.
- 2026-08-24: detailed `sacct` evidence showed only 4.7586 average CPUs and 9.63 GiB MaxRSS in an exclusive full-node allocation that cost about 8.81 node-hours. Further regular-QOS iDMRG is blocked pending one 2/4/8/16-thread Shared-QOS benchmark with correct core binding, independent restarts, no checkpoints or full states, a 0.1875-node-hour ceiling, and no automatic scientific submission.
- 2026-08-24: the project owner selected post-hoc working exploratory iDMRG thresholds of `1e-5` for the bond-matrix update norm and `1e-8` for the final-four intensive-energy span. Job 57500598 passes this working native gate, while its original predeclared-control rejection remains immutable and all branch-promotion gates remain outstanding.
- 2026-08-24: benchmark job 57548405 failed `1:0` after 11 seconds because the batch worker derived the repository root from `BASH_SOURCE` after Slurm copied it below `/var/spool/slurmd`. It ran zero scientific iterations and produced no timing artifact. The corrected worker takes an explicit project root, `plan` invokes it in preflight mode, the job sets `--chdir`, and a regression test executes a copied worker from a spool-like temporary directory. A separate retry package preserves all failed-attempt hashes and carries forward its approximately `0.000381944` node-hour charge.
- 2026-08-24: retry benchmark job 57550459 reached the correct source tree but failed `1:0` after 202 seconds at the first 2-thread step because the benchmark called `Base.cputime()`, which is absent from Julia 1.12. It completed zero iDMRG updates, wrote no timing result, and cost approximately `0.007013889` derived Shared-QOS node-hours. Its schema-3 retry replaced that unsupported call with libuv `uv_getrusage`, executed the timing helper during `plan`, propagated the exact validated Julia binary, tested the real MPSKit iterator locally, and made failed `reconcile`/`analyze` commands print recognized causes. Neither failed job is scientific nonconvergence or valid resource data.
- 2026-08-24: retry benchmark job 57574096 proved that the corrected Perlmutter path, Julia 1.12 timing helper, U(1) seed conversion, state construction, and five 2-thread iDMRG updates execute successfully. It then failed `1:0` after 889 seconds because HDF5 0.17.3 cannot serialize a packed `BitVector` measured-mask. The partial file contains no timing histories, so the attempt is not benchmark data and says nothing about scientific convergence. Its derived Shared-QOS charge is `0.030868056` node-hours. Schema 4 uses a dense `UInt8` mask, cleans writer-owned temporary files on exceptions, rejects stale temporaries before submission, makes both login- and compute-node preflights execute the exact production writer/readback, and tests the analyzer against real writer output.
- 2026-08-25: benchmark job 57576411 completed all independent 2/4/8/16-thread steps. The independent resource conclusion selected two Julia threads, a four-logical-CPU solver step, 16 GiB, Shared QOS, and core binding. Its reconciled charge was `0.108715278` node-hours; scientific convergence and promotion remained outside the benchmark.
- 2026-08-25: theta/pi=0.175 job 57608599 failed before Julia because the 16-GiB memory-sized Shared allocation and the explicit four-CPU batch task produced conflicting Slurm task variables. It performed zero scientific updates and is charged a derived `0.0000868056` node-hours. The retry preserves every scientific setting and separates a 10-logical-CPU allocation from an exact, exclusive four-logical-CPU solver step; the five-physical-core maximum-charge forecast remains `0.46875` node-hours.
- 2026-08-25: the project owner granted standing authorization for guarded Phase 1 iDMRG submissions after a successful live Perlmutter `plan`. Do not request another submission approval; cancellation, deletion, pruning, threshold or lineage changes, and automatic advance remain outside that authorization.
- 2026-08-26: retry job 57611537 completed theta/pi=0.175 with native working-profile convergence but failed primary-forward promotion at overlap per site `0.9662443394 < 0.99`. A transfer-fixed-point conversion initially failed because phase alignment from one matrix pivot left a `5.267e-9` arbitrary phase. Full Hermitian-overlap phase alignment reduced the correction to `3.726e-15` without changing the `1e-9` guard, after which the branch rejection was independently established. The one-update VUMPS residual probe was not run after overlap failure. The state remains a numerical seed only; the next guarded point is theta/pi=0.1625 from the accepted 0.15 parent.
- 2026-08-28: independent YC6-1 period-6 job 57629467 timed out after accepting theta/pi through 0.3, rejecting direct 0.4, and contracting for 36 iterations at the adaptive 0.35 midpoint. Because the old worker persisted only terminal candidates, the 0.35 iterate was lost. The prepared continuation hash-pins accepted 0.3, preserves rejected 0.4 only as evidence, writes full-state checkpoints every five iterations and after growth stages, and handles Slurm's one-hour USR1 warning by checkpointing at the next completed outer iteration without making a scientific classification.
- 2026-08-29: heavy transient storage is generalized beyond iDMRG. Future YC6-1 VUMPS growth-stage, periodic, and pre-timeout checkpoints use a job-specific `$PSCRATCH` directory with the Slurm scratch license; home/project output keeps only compact hash-pinned resume controls plus durable terminal scientific states and provenance. The already-submitted continuation is not canceled or modified and may retain project-side checkpoints under its submitted worker; exclude that directory from routine sync-back.
- 2026-08-30: the synced YC6-1 continuation accepted theta/pi 0.325 and 0.3375 under the strict `1e-5` residual profile, then preserved an unclassified 0.35 pre-timeout checkpoint. The owner explicitly authorized an exploratory `1e-4` VUMPS outer residual gate for future YC6-1 recovery points. The prepared successor repeats 0.35 from the strict accepted 0.3375 parent, does not import or relabel the old-tolerance checkpoint/rejected states, retains all continuity and solver settings, and does not change YC8-1 or iDMRG thresholds.
- 2026-08-31: YC6 job 57768008 accepted theta/pi 0.35 under the separate `1e-4` profile, with state SHA-256 `23a5fc3ac5f33a1b928986d3152bf45712954129154428d643ddf8b117975857`, then developed a rapidly increasing residual at direct theta/pi 0.4 and was canceled. The accepted state remains an independent finite-size diagnostic and cannot promote the YC8-1 lineage.
- 2026-09-02: YC8 job 57801654 completed the fixed-theta chi-512-to-1024 growth profile but missed the `1e-4` VUMPS residual target at its 60-iteration cap. It restored iteration 52 at residual `4.860776365e-4`; candidate SHA-256 `4e3a5f406f61cb791ea98ef6b0dc6cfb108877eb5199d4dc71d204f150c0a9e6` remains rejected and no continuity or theta-advance decision was made.
- 2026-09-06: synchronized Slurm accounting showed that both 32-GiB YC8 jobs received 18 logical CPUs while their launcher ledgers assumed 16. Their corrected charges are `0.14408203125` and `2.43931640625` node-hours. The accounting guard must use the actual Shared-QOS allocation before another submission.
- 2026-09-06: the owner's standing authorization applies to guarded Project B submissions after a successful live plan, not only to the earlier iDMRG launcher. The owner runs all Perlmutter commands manually; provide the guarded plan and conditional submit commands without requesting repeated submission approval. Cancellation, deletion, pruning, threshold or lineage changes, and unguarded automatic advance remain outside that authorization.
- 2026-09-06: repository continuity was separated into durable `AGENTS.md` rules, rolling `PROJECT_STATE.md`, stable `ARCHITECTURE.md`, indexed plans and decisions, Git history, and a generic new-task prompt. Dated cross-device handoffs remain provenance rather than current state.
