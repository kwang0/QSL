# Project B current state

Last updated: 2026-09-06 (America/Los_Angeles)

This is the rolling state summary for a fresh Codex task. It records where the
project is now, not the full history. Git holds exact implementation history;
the linked campaign documents hold detailed evidence and rationale; Perlmutter
remains authoritative for live jobs and scratch data.

## Current objective

Reach a trustworthy full `theta/pi` sweep of the YC8-1 primary-forward state as
quickly as the numerical and allocation guards allow. The immediate scientific
blocker is convergence of the fixed-`theta/pi=0.15` growth from chi 512 to chi
1024. No chi-1024 theta continuation has begun.

The immediate execution plan is
[`plans/REVIEW_FOLLOWUP_IMPLEMENTATION.md`](plans/REVIEW_FOLLOWUP_IMPLEMENTATION.md):
repair accounting, audit the chi1024 evidence, and run a bounded matched
chi512 MPSKit solver diagnostic. The longer-term campaign remains
[`YC8_1_CHI1024_BRIDGE.md`](YC8_1_CHI1024_BRIDGE.md). The allocation-wide plan
is [`PHASES_0_TO_4.md`](PHASES_0_TO_4.md). See
[`plans/README.md`](plans/README.md) for workstream status.

Local implementation and validation are complete. The sealed pilot control is
`configs/controls/solver_pilot_control_v2.toml`, SHA-256
`969b69b1c40d3a70e07c58fe9b12d123564781c5f40b9a4058b74f4382278818`,
selected by `configs/mpskit_solver_pilot_active_control.ref`. The initial
control and its full chi512 cross-library validation are preserved. This
revision fixes operational preflight failures without changing the scientific
recipe, except for its new audit report path. The revised copied worker passes.
Remaining steps require the owner's manual Perlmutter reconciliation, scratch
audit, successful live plan and pilot execution.

The first remote attempt failed context validation because the transferred
tree lacks `.git`, and reconciliation because the accounting date range was
too wide. Ctrl-C interrupted later hashing/compilation; no successful scratch
audit, live plan or pilot submission has been established. The new `preflight`
action stops at the first failure, uses 28-day accounting windows and audits
the candidate plus checkpoints 52 and 60 with visible progress.

The owner uses Git push/pull for locally prepared source and launch inputs,
including compact sealed controls. The follow-up branch is
`codex/project-b-review-followup`; inspect Git for its publication and commit
status. The owner has now initialized Git in `~/QSL`, fetched both upstream
branches and attached `main` without overwriting working files. The export
shows missing, modified and untracked files across several projects; these
differences are preserved. The owner completed the clean sparse worktree at
`~/QSL-project-b`, including the link to the original Project B output, and
reported a clean worktree tracking the published branch. Its first preflight
stopped before any live checks or submission because the control was missing
from ignored output. The control now lives in tracked `configs/controls/`,
and the active reference selects it there. Its 7,255 bytes and SHA-256 are
unchanged; the original output copy remains immutable. The next step is
`git pull --ff-only` in `~/QSL-project-b`, then the guarded sequence from its
Project B directory. Git supplies all newly prepared pilot inputs. Existing
parent/bridge tensors remain accessible through the output link; preflight
generates live accounting and scratch-audit evidence on Perlmutter.

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

## Latest authoritative run evidence synced locally

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

The run therefore says only that the 60-iteration chi-growth attempt did not
meet its declared residual target while still improving. It is not a physical
endpoint or branch rejection, and it accepted no new lineage state.

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

The locally synced `sacct.tsv` files show that Slurm allocated 18 logical CPUs
to each 32-GiB YC8 bridge job, although their launcher ledgers record 16. The
two original `charged_node_hours.txt` files therefore undercount those jobs. Using the
actual `NCPUS=18` values gives:

| Job | Status | Charge used here (node-hours) |
|---:|---|---:|
| baseline through `57629467` | prior tracked total | `13.740251736728` |
| `57690953` | completed YC6 strict continuation | `1.104309896000` |
| `57768008` | canceled YC6 relaxed continuation | `0.333548177000` |
| `57793343` | completed pre-timeout YC8 chi growth | `0.144082031250` |
| `57801654` | completed 60-iteration YC8 chi growth | `2.439316406250` |
| **Phase 1 total** | | **`17.761508247228`** |

The corresponding Project B total including Phase 0 is
`18.855941247228` node-hours. The Phase 1 ceiling leaves approximately
`2.238491752772` node-hours before any later remote correction. A nominal
48-hour 16-CPU forecast of 3.0 node-hours is not conservative when Slurm grants
18 CPUs; the full-limit charge would be 3.375 node-hours.

The shared accounting guard now derives charges across all Phase 1 run roots
from allocated CPUs, with append-only corrections for both YC8 charge files.
Its unrounded local total is 17.761508246528 node-hours, leaving
2.238491753472. A live Perlmutter plan must reconcile later jobs or changed
accounting before submission. Original exports, controls and charge files are
preserved.

## Current priorities

1. Complete the owner's manual Perlmutter reconciliation and hash-verified
   scratch audit using the follow-up plan's single `preflight` command after
   pulling the source and tracked launch control. Local implementation includes
   memory-rounded accounting, Julia RSS, step accounting, physics tests and a
   reproducible scalar audit. No remote commands are run by the agent.
2. Run the guarded matched chi512 MPSKit pilot after a successful live plan:
   VUMPS at 0.15, then VUMPS and GradientGrassmann at 0.2, independently from
   the accepted parent. Its 12-hour Shared-QOS reservation is 0.46875 node-hours.
   All outputs remain diagnostic until reviewed.
3. Compare native convergence, common-representation continuity, runtime and
   RSS before choosing a scientific successor. The chi1024 entropy warning and
   weak late residual trend remain unresolved; no theta advance or parent
   change follows automatically.
4. Once an accepted `theta/pi=0.45` endpoint exists, run the planned reverse
   consistency check before generating the remainder of the full sweep.

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

## Known unknowns to establish remotely

- Recheck the queue immediately before submission. The owner's September 6
  live snapshot contained no Project B job; queued `lmf1-*` jobs belong to
  another project.
- Whether the job-`57801654` scratch package and selected checkpoints still
  exist and match their recorded SHA-256 values.
- Whether later Perlmutter accounting exists beyond the synchronized files.
- Whether the owner has pulled the tracked v2 control and completed preflight.
  The owner has confirmed the clean source worktree and output link.
- Whether any selected scratch state has been promoted to durable storage
  since the last sync.

The owner also supplied step-level sacct for 57801654: the Julia step used
8 logical CPUs for 124833 seconds and reported MaxRSS=2776996K (about
2.65 GiB), while the allocation held 18 CPUs. The launcher status now
suppresses the expected missing-job warning from squeue after completion and
shows step accounting. The owner always executes Perlmutter work manually;
the command handoff is in the active follow-up plan.

These are live-state questions. Use the relevant launcher `status`/`plan` and
small hash or file-presence checks on Perlmutter; do not infer them from chat or
`latest_run.txt`.

## Maintenance rule

After substantial work, update this file only when the objective, accepted
endpoint, latest trusted evidence, known issues, or priorities change. Put
detailed run histories in campaign documents or immutable output records,
stable design in `ARCHITECTURE.md`, and non-obvious rationale in
`docs/decisions/`.
