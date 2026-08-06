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
| 0 — correctness and resource calibration | 10 node-h | Initial seed failed narrowly; 80-iteration retry prepared | Correct minimal-cell timing, peak RSS, and one recommended threading configuration |
| 1 — cheap branch discovery | 20 node-h | Not started | Forward/reverse or second-seed basins and approximate critical fluxes |
| 2 — moderate-chi Hu reproduction | 35 node-h | Not started | Converged entropy response and momentum-resolved physical-Sz transfer flow |
| 3 — critical-point chi ladders | 60 node-h | Not started | Controlled `S = (c/6) log(xi) + a` analysis at selected crossings |
| 4 — one independent validation | 15 node-h | Not started | One decisive second route, seed, geometry, or width check |
| Protected contingency | 10 node-h | Unspent | Accounting lag, one failed job, or one result-changing extra point |
| **Hard total** | **150 node-h** |  | No submission may exceed this total |

Maintain a soft review at 120 node-hours and stop all automatic submission at
140 node-hours, leaving the protected 10-node-hour contingency untouched.

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

Gate to Phase 1:

- geometry, uniform-twist, unit-cell, HDF5, and transfer-matrix tests pass;
- the seed is converged and reports `mps_period=2`, `minimal_mps_period=2`;
- one threading configuration has a credible memory request with a 30% margin;
- total Phase 0 charge remains below 10 node-hours.

If an already-started queued job produced a six-site YC6-1 seed, it is a
compatible legacy supercell benchmark, not the corrected production benchmark.
Keep its timing, but rerun the minimal-cell calibration before Phase 1.

### Updating the already-submitted Phase 0 jobs

The submitted Slurm wrapper reads the Julia payload from
`slurm/phase0_calibrate_cpu.sh` and loads this Julia project at job start. To
apply the correction to jobs that are still pending:

1. keep the same absolute remote project and script paths;
2. overwrite the remote `src/` directory and `slurm/phase0_calibrate_cpu.sh`
   with this version;
3. preserve `output/phase0_calibration/`, especially its `run.env`, `jobs.tsv`,
   and logs;
4. do not resubmit the matrix merely because the files were updated.

After the seed completes, inspect `metrics/seed.result`. A corrected run says
`mps_period=2` and `unit_cell_status=minimal`. A value of six means the seed had
already loaded the previous code. The queued benchmark workers remain able to
time that state, but the result is not a minimal-cell production calibration.
Because the queued report shell itself was captured at submission, rerun
`bash slurm/phase0_calibrate_cpu.sh report RUN_ID` after completion to include
the new unit-cell warning and metadata in `recommendation.txt`.

## Phase 1 — cheap branch discovery

Use chi=64–256 and only two independent preparations: forward continuation and
either reverse continuation or a second seed.

Initial sparse flux points:

- YC8-1: `theta/pi = 0, 0.5, 0.75, 0.875, 1.0`;
- YC8-0: `theta/pi = 0, 1.0, 1.5, 1.75, 2.0`.

Optimize first and skip transfer spectroscopy for rejected states. Abort a
point when the residual rebounds repeatedly or stagnates far above tolerance.
Use roughly `1e-5`–`1e-6` while scouting; reserve `1e-8` for accepted production
states whose observables have stabilized.

Gate to Phase 2:

- both sides of each proposed crossing are reached on a controlled branch;
- at least two preparation routes agree or their hysteresis is explicitly mapped;
- no feature is inferred from an unconverged checkpoint.

## Phase 2 — moderate-chi Hu reproduction

- Densify flux only near the crossing, using adaptive interval halving.
- Use chi=256, 512, 1024 only where the lower-cost scans justify it.
- Run transfer spectroscopy only on accepted immutable states.
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
- energy, entropy, and correlation lengths are stable across continuation route.

## Phase 3 — high chi only at selected critical fluxes

Run `chi = 128, 256, 512, 1024` ladders at the selected `theta_c`, not over the
whole trajectory. Admit chi=2048 only after a node-hour review and only with
restart safety.

Promote to the next chi only if:

- the VUMPS residual passes;
- both continuation directions retain the same branch;
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
chi, seed/direction, requested CPUs and memory, wall time, peak RSS, charged
node-hours, final residual, accepted/rejected status, entropy, and leading
correlation length. Do not promote automatically to a higher phase or chi.

| Date | Phase | Job IDs | Estimated node-h | Charged node-h | Decision / result |
|---|---:|---|---:|---:|---|
| 2026-08-05 | 0 | Seed 56334122 and dependent matrix | Run report | Pending | Correct two-site seed reached residual 1.3047e-5 after 60 chi=256 iterations; downstream failures were consequential |
| 2026-08-05 | 0 | Retry not yet submitted | <=8.5664 plus failed-run charge | Not submitted | Preserve 1e-5 gate; increase per-stage ceiling to 80 because the final residual was decreasing monotonically and should cross near iteration 64 |

## Decision log

- 2026-08-05: hard Project B limit fixed at 150 node-hours.
- 2026-08-05: Hu unit-cell convention adopted: even YC(Ly)-0 uses `Ly`; YC(Ly)-1 uses two sites.
- 2026-08-05: uniform twist gauge is the production default; seam-gauge files remain readable as legacy artifacts.
- 2026-08-05: full-cell phases are never silently unfolded; momentum resolution requires the geometry's minimal cell.
- 2026-08-05: the first corrected chi=256 seed stopped at 1.3047e-5 after 60 final-stage iterations. The retry keeps the 1e-5 gate and raises the ceiling to 80; a looser calibration tolerance was rejected because the residual was converging smoothly.
