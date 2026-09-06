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

The active execution plan is
[`YC8_1_CHI1024_BRIDGE.md`](YC8_1_CHI1024_BRIDGE.md). The allocation-wide plan
is [`PHASES_0_TO_4.md`](PHASES_0_TO_4.md). See
[`plans/README.md`](plans/README.md) for workstream status.

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

## Accounting state and known guard defect

The locally synced `sacct.tsv` files show that Slurm allocated 18 logical CPUs
to each 32-GiB YC8 bridge job, although their launcher ledgers record 16. The
two `charged_node_hours.txt` files therefore undercount those jobs. Using the
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

This accounting mismatch must be resolved in the launcher guard before another
YC8 submission. A live Perlmutter plan must recompute the ledger from remote
evidence; do not rely on these dated totals if another job has run.

## Current priorities

1. Correct and test the YC8 Shared-QOS accounting guard so it forecasts and
   reconciles the actually allocated CPU count and cannot exceed the Phase 1
   ceiling.
2. Decide the smallest scientifically justified chi-1024 anchor continuation
   from the contracting, hash-pinned checkpoint evidence. Do not advance theta
   until the fixed-flux anchor is numerically accepted and passes its declared
   continuity policy.
3. Update the active bridge plan with that decision and prepare a new immutable
   control only after the accounting and scratch checks pass.
4. Once an accepted `theta/pi=0.45` endpoint exists, run the planned reverse
   consistency check before generating the remainder of the full sweep.

## Known unknowns to establish remotely

- Whether any Project B job is currently queued or running.
- Whether the job-`57801654` scratch package and selected checkpoints still
  exist and match their recorded SHA-256 values.
- Whether later Perlmutter accounting exists beyond the synchronized files.
- Whether any selected scratch state has been promoted to durable storage
  since the last sync.

These are live-state questions. Use the relevant launcher `status`/`plan` and
small hash or file-presence checks on Perlmutter; do not infer them from chat or
`latest_run.txt`.

## Maintenance rule

After substantial work, update this file only when the objective, accepted
endpoint, latest trusted evidence, known issues, or priorities change. Put
detailed run histories in campaign documents or immutable output records,
stable design in `ARCHITECTURE.md`, and non-obvious rationale in
`docs/decisions/`.
