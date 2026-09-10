# Project B current state

Last updated: 2026-09-10 (America/Los_Angeles)

This is the rolling state summary for a fresh Codex task. It records where the
project is now, not the full history. Git holds exact implementation history;
the linked campaign documents hold detailed evidence and rationale; Perlmutter
remains authoritative for live jobs and scratch data.

## Current objective

Reproduce Hu et al. Figure 2 excitation gaps and Figure 3 momentum-resolved
correlation spectra, with YC8-1 continued through `theta/pi=1`. The owner
reaffirmed this objective on September 8. The former protocol's Fig. 3/Fig. 4
scope omitted the separate Fig. 2 excited-state measurement, which is not
implemented. Entropy and central-charge measurements remain supporting/later
work. The existing primary-forward lineage is accepted only through 0.15 at
chi512; its fixed-flux chi1024 growth failed and no chi1024 theta continuation
has begun.

The bounded limited-relaxation experiment authorized on September 8 is now
complete, reconciled, synchronized and reviewed:
[`plans/RELAXATION_CONTINUATION.md`](plans/RELAXATION_CONTINUATION.md).
It compares VUMPS iteration budgets 8/16/32, flux steps 0.025/0.0125 from the
accepted 0.15 parent through 0.20, a fixed-flux baseline and endpoint holds.
These explicitly diagnostic paths may advance without passing the historical
native gate. They cannot promote or replace the accepted lineage. See
[`decisions/005-bounded-relaxation-continuation.md`](decisions/005-bounded-relaxation-continuation.md).
The completed run's `configs/controls/relaxation_continuation_v1.toml` has SHA-256
`3e790f71089c87645fced05f1e7a0e7c3a49d78d5a6f5b73db19cfd0d7262fef`
and is referenced by `configs/relaxation_continuation_active_control.ref`.
Job **58082150** completed all 464 updates and 50 selected-state analyses.
Short paths preserve continuity through 0.20, with six charged inverse
correlation lengths agreeing within 0.271% across 8/coarse, 8/fine and
16/coarse endpoints. Longer paths and two fixed-flux holds undergo substantial
changes. Equal-total-update comparisons show accumulated relaxation is a
major factor. No native gate passes and no state is promoted. See
[`decisions/006-relaxation-continuation-outcome.md`](decisions/006-relaxation-continuation-outcome.md).
Actual charge is 0.983995225694 node-hours; the Phase 1 balance after that job
was 0.969947916667. Do not rerun the completed control.

The short forward-and-return comparison is complete, reconciled, synchronized
and reviewed as job **58131989**:
[`plans/ROUNDTRIP_CONTINUATION.md`](plans/ROUNDTRIP_CONTINUATION.md), with the
rationale in [decision 007](decisions/007-test-flux-return-at-matched-relaxation.md)
and outcome in [decision 008](decisions/008-roundtrip-continuation-outcome.md).
Four independent accepted-parent starts follow theta/pi=0.15 to 0.25 to 0.15.
Coarse/fine steps 0.025/0.0125 use paired budgets 2/1 and 4/2, keeping updates
per unit flux fixed within each pair. All 96 updates and 100 analyses completed.
Every continuity comparison passes, and matched coarse/fine charged inverse
lengths agree within 0.2745%. Energy and entropy approximately return, but
charged inverse lengths retain 0.855-1.121% offsets at the returned origin.
Staggered magnetization grows at every update and reaches about 6e-4 in the
32-update loops, versus 4e-5 in the 16-update loops. The earlier fixed-flux
baseline also grows magnetization. This supports short limited-relaxation
continuation with accumulated drift; it does not establish adiabaticity or a
stationary metastable branch. All states remain diagnostic; no native gate passes.

Completed runtime: `slurm/run_roundtrip_continuation_cpu.sh` and tracked control
`configs/controls/roundtrip_continuation_v1.toml`, SHA-256
`40088fc17091a0962b35de44b1f588124b8a302dbed2f8ce06769af7be64e8b7`,
selected by `configs/roundtrip_continuation_active_control.ref`.
Actual wall time was 5:07:03 with ten logical CPUs and 16G; charge was
0.199902343750 node-hours, leaving Phase 1 **0.770045572917**. All 61 input
pins, compact replay and independent scalar/spectrum/accounting checks pass.
All six requested modes converge in both spin sectors for all 100 analyses.
Compact run: `output/mpskit_solver_pilot_jobs/roundtrip/20260909T225809Z_40088fc17091/`.
Review: `output/review_followup/roundtrip_58131989_review_20260910/`.
Do not resubmit this control. Decision 008 proposes a lower-density 2/coarse
and 1/fine loop to 0.35, independently starting from the accepted 0.15 parent;
it is not prepared or sealed. Larger flux may amplify drift despite the same
32-update loop budget already explored here. Future launcher revisions follow
the minimal-testing preference in `AGENTS.md`.

The completed earlier diagnostic sequence is
[`plans/REVIEW_FOLLOWUP_IMPLEMENTATION.md`](plans/REVIEW_FOLLOWUP_IMPLEMENTATION.md):
the matched chi512 MPSKit pilot and chi1024 audit are reconciled, synchronized
and reviewed. The bounded fixed-flux solver calibration proposed in
[`decisions/003-solver-pilot-outcome.md`](decisions/003-solver-pilot-outcome.md)
remains a possible diagnostic after the completed forward-and-return test.
The broader recommended path centers
on general-chi sparse I/O, tested bond growth and zero-flux preparation,
followed by a validated trajectory and the missing gap calculation; see
[`decisions/004-yc8-1-figure-reproduction-feasibility.md`](decisions/004-yc8-1-figure-reproduction-feasibility.md).
That high-chi assessment is not itself a prepared experiment or a
budget/lineage change.
The existing bridge campaign remains
[`YC8_1_CHI1024_BRIDGE.md`](YC8_1_CHI1024_BRIDGE.md). The allocation-wide plan
is [`PHASES_0_TO_4.md`](PHASES_0_TO_4.md). See
[`plans/README.md`](plans/README.md) for workstream status.

The earlier pilot's implementation and validation are complete. Its sealed control is
`configs/controls/solver_pilot_control_v2.toml`, SHA-256
`969b69b1c40d3a70e07c58fe9b12d123564781c5f40b9a4058b74f4382278818`,
selected by `configs/mpskit_solver_pilot_active_control.ref`. The initial
control and its full chi512 cross-library validation are preserved. This
revision fixes operational preflight failures without changing the scientific
recipe, except for its new audit report path. The revised copied worker passes.
Pilot job `58005544` is complete and reconciled. All three native gates
failed; GradientGrassmann at 0.20 preserved continuity, while VUMPS there
failed it. No candidate is eligible for promotion. The baseline's late error
flattening and gradient run's final upturn motivated the earlier calibration
recommendation. Production advance remains unvalidated; the bounded
limited-relaxation paths are explicitly diagnostics, now reviewed in decision 006.

Local chi512 validation of the new reader/spectrum path passes. The unchanged
payload agrees in energy between MPSKit and ITensor to `2.22e-15`; importing
and recanonicalizing the historical AL bridge changes the original parent's
energy by `7.94e-8`, inside the existing `1e-6` tolerance. All requested six
transfer modes converge in both spin sectors. This validates measurement and
preparation consistency, not a new optimized state or a scientific endpoint.

The owner uses Git push/pull for locally prepared source and launch inputs,
including compact sealed controls. The follow-up branch is
`codex/project-b-review-followup`; inspect Git for its publication and commit
status. The clean sparse worktree `~/QSL-project-b` tracks that branch; its
Project B output links to the canonical
`~/QSL/project_b_flux_dimensional_reduction/output`. The original `~/QSL`
checkout on `main` preserves unrelated modified, missing and untracked files.
Run Project B commands from
`~/QSL-project-b/project_b_flux_dimensional_reduction`; both source directories
share output but execute different code. The stale checkout caused the earlier
unbounded accounting-date query; reconciliation from the clean worktree has
now succeeded. Git supplies the exact 7,255-byte sealed control under
`configs/controls/`, with no separate control transfer. Existing parent/bridge
tensors remain accessible through the output link; preflight generates live
accounting and scratch-audit evidence on Perlmutter.

Standing owner authorization: publish tested Project B source, tests,
documentation and compact prepared launch inputs to `https://github.com/kwang0/QSL.git` on
`codex/project-b-review-followup`, including future updates to that branch.
Heavy scientific payloads and generated run evidence remain excluded.
Perlmutter commands and transfers continue
to be executed manually by the owner.

## Non-negotiable scientific state

- Model and representation: triangular-lattice `J1=1`, `J2=0.12`, YC8-1,
  minimal period-2 MPS, U(1)-conserving complex tensors, uniform twist gauge.
- Scientific object: the labeled primary-forward metastable branch, not a
  pointwise minimum-energy envelope.
- Accepted lineage parent and overlap reference:
  `theta/pi=0.15`, chi 512, SHA-256
  `38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`.
- Rejected VUMPS and iDMRG tensors, including contracting checkpoints, remain
  numerical seeds or diagnostics. None replaces the accepted parent.
- The chi-1024 bridge uses the predeclared `1e-4` VUMPS projected-residual gate
  and the multimetric continuity policy in
  `configs/phase1_yc8_1_multimetric_continuity.toml`. These are campaign-scoped
  numerical rules, not physical phase-boundary criteria.

## Latest bounded-relaxation evidence

The owner-confirmed completed sync contains job **58082150** under
`output/mpskit_solver_pilot_jobs/relaxation/20260908T200715Z_3e790f71089c/`.
All seven arms, 19 points, 464 updates, six holds and 50 selected analyses are
complete. All 41 sealed source/data inputs match. Iteration journals,
checkpoint/seed chains, analysis provenance, scalar continuity differences,
native gates and spectrum identities pass independent replay. Six requested
transfer modes converge in both Sz sectors for every selected state. Maximum
cross-library energy difference is 1.677e-13; canonical errors pass. Full
scratch payloads were checked during remote analysis, not rehashed locally.

At 0.20, 8/coarse, 8/fine and 16/coarse preserve parent continuity, with
maximum entropy changes 0.009395, 0.009736 and 0.009712. Their charged spectra
agree closely. The equal-work 8/fine and 16/coarse pair uses 32 updates and
agrees within 0.0801% in all six charged inverse lengths. Both change strongly
after a further 16 updates at fixed flux. The 8/coarse hold remains continuous
after 32 total updates. Paths with 64 or more updates at 0.20 have energy near
-0.5102, reversed local-energy alternation and entropy changes near 0.85.
This supports a useful transient before substantial further relaxation; it
does not establish a physical spinodal or a converged metastable branch.

The 0.15 baseline also turns upward: error minimum 4.1815e-5 at update 16,
then 1.6862e-4 at 32, while sampled continuity still passes. No selected MPS
passes the native gate. The smallest late errors can belong to states far
from the original parent, so a residual minimum alone cannot select lineage.

Runtime was 90685 seconds (25:11:25), with ten allocated logical CPUs, 16G,
peak solver RSS 10.315 GiB and all fourteen steps successful. Live
reconciliation at `2026-09-09T21:40:03.654` is backed by evidence SHA-256
`6f5c0f239fce858b0c79d8fe1bfa500793afe714906a6adf9b627b714a4e1cc1`.
The charge is 0.983995225694 node-hours. Detailed tables, limitations, figures
and reproduction commands are in decision 006; generated review outputs are
under `output/review_followup/relaxation_58082150_review_20260909_v2/`.

Known measurement limitation: v1 applies the charged-sector theta shift to
both Sz=0 and Sz=1 momentum labels. Interpret only Sz=1 mapped momenta from
this run; neutral raw eigenvalues and inverse lengths remain usable. A
charge-aware mapping is implemented and tested in the new forward-and-return
analysis path. Its new control preserves the completed run's pinned runtime
and recorded labels.

## Earlier pilot evidence

The owner-confirmed completed checksum sync records job `58005544` COMPLETED,
exit `0:0`, elapsed 26224 seconds
(7:17:04), 10 allocated logical CPUs and 16G requested memory. All six solver
and analysis steps completed. Peak solver RSS is approximately 9.54 GiB.
Live reconciliation at `2026-09-07T22:56:19.045` confirms its charge of
0.284548611111 node-hours. Its evidence SHA-256 is
`bd41ae3fe55d5a1cd50a2da55122f3022fe9d5cc04030c8d895c452c022ac5b5`.

Local run records are present under
`output/mpskit_solver_pilot_jobs/20260907T023735Z_969b69b1c40d/`.
The control snapshot and all 38 source/data inputs match their pinned hashes.
All three analysis HDF5 hashes match their summaries, and complete stage
histories match the TSV journals. Recomputed native gates, continuity scalar
jumps and actual-CPU accounting agree with the recorded results. The local
scratch-audit report verifies its required hashes and pinned audit code;
this records the past audit, not current scratch availability.

| Stage | Final iteration | Native error | Native gate | Continuity |
|---|---:|---:|---|---|
| baseline VUMPS, 0.15 | 18 | 4.2935069069e-5 | fail | pass |
| difficult VUMPS, 0.2 | 58 | 4.6000949334e-3 | fail | fail |
| difficult GradientGrassmann, 0.2 | 49 | 2.8848721924e-5 | fail | pass |

All stages record `graceful_stop`; the worker records no pretimeout request.
Their elapsed times are consistent with the stage time budgets. All three
cross-library energy checks pass, but none is eligible for promotion.
Difficult-point VUMPS has overlap 0.9734593 and maximum cut-entropy jump
0.8102766; GradientGrassmann has overlap 0.99997046 and jump 0.00896131.
The latter reached gradient norm `1.7678837134e-5` at iteration 44 before
ending 63.18% above that minimum. Baseline VUMPS flattens near `4.2e-5` in
the observed window. Their energy-window tests pass, but native errors do not.
No reliable time-to-convergence estimate follows from these late histories.
The accepted parent's ITensor residual is a distinct quantity; these new
MPSKit gate failures do not retroactively invalidate that accepted state.

The full review and tracked figure are in
[`decisions/003-solver-pilot-outcome.md`](decisions/003-solver-pilot-outcome.md).
Reproducible JSON, CSV, accounting and PNG/SVG outputs are under
`output/review_followup/pilot_58005544_review_20260907/`.

## Previously synchronized chi1024 bridge evidence

The owner reported the latest run complete, reconciled, and synchronized. The
copied Perlmutter evidence for job `57801654` records:

- scheduler outcome: `COMPLETED`, exit `0:0`, elapsed `124893` seconds;
- allocation: one node, `NCPUS=18`, 32 GiB request;
- operation: fixed-flux chi 512 to 1024 growth at `theta/pi=0.15`;
- 60 outer iterations with a target VUMPS residual of `1e-4`;
- lowest residual `4.860776365225489e-4` at iteration 52;
- terminal residual `4.970008632297692e-4` at iteration 60;
- contracting classification, projected target iteration `99.6173`, and
  restoration of the iteration-52 state;
- scientific outcome: `fixed_flux_expansion_numerical_failure`; continuity
  metrics were not evaluated because the numerical gate failed;
- rejected candidate SHA-256
  `4e3a5f406f61cb791ea98ef6b0dc6cfb108877eb5199d4dc71d204f150c0a9e6`;
- final periodic checkpoint SHA-256
  `fa4d7f01dbb7e10deb1c37bab659c07a9dba60fe63ba3e3db34c705c102b3e9b`.

The 60-iteration attempt failed its declared residual target. The stored
whole-run contracting classification conceals a weak late trend and a final
error above the iteration-52 minimum. It is not a physical endpoint or an
official branch rejection, and it accepted no new lineage state.

The synchronized owner-run scratch audit
`output/review_followup/checkpoint_audit_57801654_v2.toml` verifies the candidate
and checkpoints 52/60. It directly measures maximum cut-entropy jumps of
`1.0086554063` and `1.0089133947`, exceeding the fixed-flux bound `0.35`.
This strengthens the earlier mean-entropy warning without changing the
original outcome or declaring a physical basin change. The selected late
checkpoints do not locate the onset of the change. Present scratch availability
still requires a remote check before any restart.

Compact evidence:

- `output/yc8_1_chi1024_bridge_jobs/20260901T021845Z-yc8-1-chi1024-forward_bridge/`
- `output/science/yc8_1/primary_forward_chi1024_parallel_bridge_20260831/seed_101/chi1024/scan_outcome.toml`
- `output/science/yc8_1/primary_forward_chi1024_parallel_bridge_20260831/seed_101/chi1024/state_manifests/`

The full candidate and optimizer checkpoints are recorded below Perlmutter
`$PSCRATCH` in job package `job_57801654_5ffb4c3d1522`; their present existence
must be checked remotely before a resume or cleanup decision.

## Other workstreams

### YC6-1 legacy-period-6 diagnostic

This remains an independent finite-size diagnostic and cannot promote the
YC8-1 lineage. Job `57768008` accepted `theta/pi=0.35` under the separately
authorized YC6-only `1e-4` profile, with residual `9.840437e-5`, overlap per
site `0.9999931017`, and state SHA-256
`23a5fc3ac5f33a1b928986d3152bf45712954129154428d643ddf8b117975857`.
The following direct `0.4` optimization diverged and the allocation was
canceled. That post-0.35 trajectory and its checkpoints are numerical evidence
only. This workstream is paused while the main YC8-1 path is pursued.

### iDMRG branch probe

Job `57611537` at `theta/pi=0.175` passed its predeclared exploratory native
iDMRG convergence profile but failed the then-declared branch-continuity test;
its tensor remains a numerical seed. The guarded midpoint control at
`theta/pi=0.1625` still points to the accepted `0.15` parent and has not been
promoted into the current main execution path.

The local copies named by both active references exist and match their pinned
hashes as of this update:

| Reference | Target | SHA-256 | Role |
|---|---|---|---|
| `configs/phase1_idmrg_active_control.ref` | `output/phase1_idmrg/yc8_1/theta_p0p16250000_from_38312fc996fe_working_shared16g_after_57611537/phase1_idmrg_sweep_step_control.toml` | `35fe2a21c4c68074bc43a2dc113e8e3256e8ad0ed6a59360f1c3f28c3f9e5ec6` | Prepared iDMRG midpoint, not the current main campaign |
| `configs/phase1_idmrg_benchmark_active_control.ref` | `output/phase1_idmrg/benchmarks/theta_p0p20000000_chi512_threads_retry_after_57574096_c7ef67c0e22b/phase1_idmrg_benchmark_control.toml` | `8fb5a1c0b99e5fa3c955f9e0e914913735e08fe64e90681a648d9ca339a05110` | Completed resource-calibration control |

Always rerun the context audit after a transfer; table entries are a dated
state record, not a replacement for hash validation.

## Accounting state and completed guard repair

Live post-roundtrip reconciliation is synchronized and validated. The accounting
audit deduplicates 31 Phase 1 allocations, applies the append-only corrections
for the two older 18-CPU YC8 bridge jobs and includes all three diagnostic jobs:

| Job | Status | Charge used here (node-hours) |
|---:|---|---:|
| Phase 1 through `57801654` | corrected actual-CPU total | `17.761508246528` |
| `58005544` | completed matched MPSKit pilot | `0.284548611111` |
| `58082150` | completed bounded relaxation comparison | `0.983995225694` |
| `58131989` | completed forward-and-return comparison | `0.199902343750` |
| **Phase 1 total** | | **`19.229954427083`** |

The corresponding Project B total including Phase 0 is
`20.324387427083` node-hours (Phase 0 remains an estimate). The Phase 1
ceiling leaves **`0.770045572917` node-hours** at this reconciliation.
Job 58131989 reconciliation at `2026-09-10T23:20:59.307` uses evidence SHA-256
`eed1442c7ea22f74e0396b101dc6338d729f29986ff03be556739ecf6e5faa83`. A nominal
48-hour 16-CPU forecast of 3.0 node-hours is not conservative when Slurm grants
18 CPUs; the full-limit charge would be 3.375 node-hours.

The shared accounting guard now derives charges across all Phase 1 run roots
from allocated CPUs, with append-only corrections for both YC8 charge files.
The independent sum and existing local accounting guard agree. A live
Perlmutter plan must reconcile later jobs or changed accounting before
submission. Original exports, controls and charge files are preserved.

## Current priorities

1. Consider decision 008's next bounded range test: the matched lower-density
   2/coarse and 1/fine pair from accepted 0.15 through 0.35 and back. This is a
   proposal, not a prepared successor. Track spectral memory and staggered
   magnetization, which grows even on the return and at unchanged flux.
   Increasing updates merely to lower residuals worsens the magnetic drift.
   If drift strengthens, prioritize symmetry/preparation and general-chi
   diagnosis over repeated longer relaxation. The accepted parent is unchanged;
   neither completed experiment establishes an adiabatic path to pi.
2. Design a tested general-chi growth and sparse checkpoint route, with a
   separately labeled theta=0 preparation study and comparable chi512/1024/2048
   resource measurements. The present MPSKit integration contains fixed-512
   and fixed-parent-basis assumptions. The ITensor route has expansion code
   but has not demonstrated a successful accepted chi1024 trajectory.
3. Establish a converged family and an affordable full 0-to-pi continuation
   before selected higher-chi production points. Nominal chi alone is not an
   established explanation for the endpoint: the paper reports YC8-1 at pi even
   at m=1024, without specifying the preparation history of that table entry.
   Preserve all existing lineage records and declared gates.
4. Implement and validate the separate Fig. 2 embedded-window excited-state
   calculation; validate and benchmark Fig. 3 spectra on accepted states.
   Treat the two measurements as distinct products. Defer central-charge fits
   and expansion to other geometries until the main reproduction is credible.
5. Prepare a concrete production budget from those measurements. The current
   Phase 1 balance is 0.770045572917 node-hours. Arithmetic headroom below the
   full 150-hour project ceiling is 129.675612572917, but phase allocations
   are not automatically reassigned. No current benchmark establishes an
   affordable chi6144/12288 run. A successor needs a fresh live guard and a
   reservation within the remaining allowance.

The .15 calibration and .1625 midpoint in decision 003 remain bounded
diagnostic options. Neither automatically changes the production solver,
accepted parent or phase budget. Do not rerun the completed pilot control.

## September 6 review findings

The assessment of `docs/claude/ancient-cooking-wombat.md` is recorded in
[`decisions/002-review-followup-diagnostics.md`](decisions/002-review-followup-diagnostics.md).
It uses the synchronized evidence retrospectively; live SSH authentication
was unavailable.

- The accepted chi-512 parent's mean cut entropy is `2.3288520835887656`;
  the returned chi-1024 candidate manifest records `3.2646479577628575`.
  Their difference, `0.9357958741740919`, lower-bounds the maximum per-cut
  jump and exceeds the declared fixed-flux bound `0.35`. This is a diagnostic
  warning about that unconverged tensor, not a retroactive continuity decision
  or proof of a basin change.
- The last ten logged residuals have a positive log-linear slope, while the
  last twenty have a weak negative fit (`R^2=0.398`). The immutable whole-run
  contracting classification is retained; its projected iteration `99.6173`
  is insufficient justification for another cap extension.
- The cited rejected iDMRG candidate at `theta/pi=0.175` has alternating local
  energy terms with difference `0.1398747801`, versus `0.1156656312` for the
  accepted 0.15 parent. It does not establish the review's proposed uniform
  lower-energy basin. Spinodal and topological-sector interpretations remain
  hypotheses.

## Remaining unknowns

- Recheck the queue immediately before any successor submission. The synced
  reconciliation records all three diagnostic jobs complete; it is not a live
  queue snapshot. Queued `lmf1-*` jobs belong to another project.
- Whether the job-`57801654` scratch package and selected checkpoints still
  exist and match their recorded SHA-256 values.
- Whether later Perlmutter accounting exists beyond the synchronized files.
- Whether any selected scratch state has been promoted to durable storage
  since the last sync.
- Whether the job-58082150 scratch states needed for any new diagnostic still
  exist and match their compact hashes.

The bounded comparison demonstrates a short interval with close spectra,
followed by large changes under further relaxation. The completed return test
extends diagnostic reach to 0.25 and shows near-return of local observables,
with percent-level spectral memory and monotonically growing staggered
magnetization. Whether a longer continuation remains useful, and whether that
disturbance is physical, variational or algorithmic, remains unresolved. The
0.15 baseline's upturn remains unexplained. These diagnostics identify neither
a specific inner-solver error nor a physical spinodal or topological sector.

The owner also supplied step-level sacct for 57801654: the Julia step used
8 logical CPUs for 124833 seconds and reported MaxRSS=2776996K (about
2.65 GiB), while the allocation held 18 CPUs. The launcher status now
suppresses the expected missing-job warning from squeue after completion and
shows step accounting. The owner always executes Perlmutter work manually;
the completed command sequence remains in the follow-up plan for reference.

These are live-state questions. Use the relevant launcher `status`/`plan` and
small hash or file-presence checks on Perlmutter; do not infer them from chat or
`latest_run.txt`.

## Maintenance rule

After substantial work, update this file only when the objective, accepted
endpoint, latest trusted evidence, known issues, or priorities change. Put
detailed run histories in campaign documents or immutable output records,
stable design in `ARCHITECTURE.md`, and non-obvious rationale in
`docs/decisions/`.
