# Project B review: scientific directions and Perlmutter deployment

## Context

The user asked for a review (no changes yet) of `project_b_flux_dimensional_reduction` at two levels: (1) scientific directions that are interesting, reliable, and reportable; (2) the numerical implementation and its efficient deployment on Perlmutter. This file records the evidence-backed findings and the recommended course of action. Everything below is read-only analysis of the local checkout (local `output/` is a possibly stale mirror of Perlmutter, per `AGENTS.md`).

Where the project stands (local mirror, 2026-09-01):

| Lineage | Accepted through | Cost so far | Wall-clock per accepted point |
|---|---|---|---|
| YC8-1, chi 512, period 2 ("primary forward") | theta/pi = 0.15 (target crossing at 1.0) | ~12.6 of 15.3 Phase-1 node-h went to iDMRG detours | days to weeks (one 48 h job at a time) |
| YC6-1, chi 512, period 6 (legacy cell) | 0.35 under a relaxed 1e-4 gate; 0.4 diverges immediately | ~2.6 node-h | ~2 days per 0.0125-0.05 pi step at 780-1030 s/iteration |
| YC8-0 (four-flavor class) | never run | 0 | - |

Budget is not the constraint (about 16 of 150 node-hours used). Wall-clock, serialization (one job at a time, 48 h each), and the physics interpretation of the recurring "branch loss" are.

---

## Part 1. Scientific findings and directions

### 1.1 The recurring branch loss is most likely physical, not a solver defect

The project has treated every failure near theta/pi ~ 0.2 (YC8-1) and ~0.4 (YC6-1) as an outer-solver instability and responded with bisection, parallel VUMPS, one-site iDMRG, and a chi-1024 bridge. The local data support a different reading:

1. **The seeded theta=0 states are strongly dimerized along the helical direction.** Per-site energies stored in every state file (`observables/energy_terms`) alternate with a two-site pattern on both geometries:
   - YC8-1, chi 512, theta=0: e_site = (-0.447, -0.567), |e1 - e2| = 0.120 (same at chi 128: 0.132).
   - YC6-1, chi 512, period-6 cell, theta=0: e_site = (-0.413, -0.613) repeated three times, |e1 - e2| = 0.200.
   For YC(Ly)-1 every site has an identical bond set under the one-site screw translation (snake displacements are Ly*dcol + drow, source-independent), so a two-site energy pattern is genuine translation-symmetry breaking, not an MPO-grouping artifact. The YC6-1 "period-6" state is in fact period 2.
2. **A competing basin lies ~0.6% lower in energy.** The iDMRG result at theta/pi = 0.175 (job 57611537) has energy density lower by 0.00304 relative to the accepted 0.15 parent, entropy higher by 0.78, overlap per site 0.966 (`configs/phase1_yc8_1_multimetric_continuity.toml:60-73`). Hu, Gong, Zhu, Sheng (PRB 92, 140403, 2015) report that on YC8 cylinders at this J2 the odd sector lies 0.6% below the even sector. The match in magnitude suggests the "primary forward" lineage is the higher-energy cylinder sector.
3. **The dimerization weakens with flux and collapses where the branch is lost.** Along YC6-1: |e1 - e2| = 0.200 (theta=0) -> 0.171 (0.3) -> 0.159 (0.35); the rejected 0.4 candidate already has energy-term std 0.032 and entropy 2.26 (vs 1.90). The legacy chi-512 YC6-1 scan (`docs/data/legacy_yc6_1_flux_diagnostics.csv`) shows energy-term std dropping from 0.109 to 0.0013 for theta/pi >= 0.5, with the entropy maximum and correlation-length maximum at 0.4-0.5. The uniform state at 0.7-1.0 converged to 1e-5 without difficulty in the legacy run.
4. **The fidelity susceptibility rises smoothly toward the loss point** (computed from stored parent overlaps, chi_F = -2 ln f / dtheta^2 per site):
   - YC6-1 chi 512: 2.5e-3 (0->0.1), 2.8e-3, 3.5e-3, 4.5e-3, 5.8e-3, 8.9e-3 (0.3375->0.35).
   - YC8-1 chi 128: 5.7e-3 (0.227->0.234), 1.6e-2, 6.4e-2 (0.238->0.242), an 11x rise over 0.016 pi.
   - YC8-1 chi 512: 1.7e-3 (0->0.1), 1.8e-3 (0.1->0.15); then the iDMRG 0.175 state gives 11.1, a discontinuity of ~6000x, i.e. a different state, not a rough step on the same branch.
5. **The loss point moves to lower theta with higher chi** (0.246 at chi 128/192, ~0.2 at chi 512 on YC8-1), which is the project's own criterion for a finite-chi spinodal (`docs/YC6_1_DIAGNOSIS.md`), and every solver fails in the same window.

Interpretation: flux insertion drives the dimerized, higher-energy sector past its spinodal against the uniform lower-energy sector. The residual "divergence" is what a fixed-point iteration does when the local minimum flattens into a saddle. The overlap gate (0.99) cannot distinguish this from a solver defect, and neither can further bisection.

Caveat to test: the dimerized state could be a trap of the `alternating` (Neel-along-snake) product seed plus sequential VUMPS. A random-seed / uniform-seed preparation at theta=0 settles this cheaply.

### 1.2 Reportable directions, ranked

**D1. Characterize both theta=0 basins on YC8-1 period 2 (cheap, ~1-2 node-h, run in parallel).** Independent preparations: 2-3 random product seeds, a uniform seed, and the iDMRG 0.175 state continued back to theta=0. Compare E, dimerization D = |e1 - e2|, S, xi (Sz=0 and Sz=1), U(1) sector profile. Compare theta=0 energies to Hu et al. 2015/2019 YC8 values. Decide which basin is the DSL candidate (expected: the uniform, lower-energy one).

**D2. Flux response of the lower-energy uniform basin toward theta = pi (the actual Hu et al. measurement).** S(theta), sector-resolved xi(theta), and momentum-resolved transfer spectra at chi 512. Run each theta as an independent job seeded from the theta=0 uniform state (or short 2-3 point chains) so the campaign is embarrassingly parallel instead of a serial adiabatic chain. This delivers Fig. 3/Fig. 4-type results and the crossing location at chi 512 within ~5-10 node-h.

**D3. Spinodal and hysteresis map of the dimerized branch.** Forward from theta=0 (already have chi 128 and 512 points), reverse from the uniform basin, energy crossing theta*, and chi_F(theta) along each lineage (already stored, just needs a script). Reportable as a flux-driven dimerization (VBS) instability of the gapped cylinder, which is exactly the roadmap's "adiabatic collapse before theta_c" failure mode (`TRIANGULAR_J1J2_MPS_ROADMAP.md:186`) and connects to monopole/VBS physics.

**D4. c_eff ladders only after D2 locates a genuine low-gap flux, and only with xi >> Ly.** At chi 512 the stored correlation lengths are ~4.2-4.7 sites, smaller than Ly = 8; no central charge can be extracted there. This needs chi >= 2048, which in turn needs the kernel changes in Part 2.

**D5. Re-base YC6-1 on the minimal period-2 cell.** The period-6 state is period 2; period 6 costs 3x sites and 6x environment recomputation in sequential mode (Part 2), and blocks momentum labels. Verify by comparing the six site tensors, then re-prepare at period 2.

**D6. Add physics validation tests (none exist).** ED cross-check of the twisted OpSum on a small finite cylinder; Hermiticity; theta -> theta + 2 pi gauge equivalence of energies; theta -> -theta conjugation; a VUMPS convergence test that the residual actually decreases; a known-distinct-state overlap test.

### 1.3 Things to stop doing

- Bisecting to 0.00625 pi and adding solver variants at the loss point; the evidence is against a solver defect.
- Accepting reported science states at residual 1e-4 (the YC6-1 0.35 state was accepted at 9.84e-5, inside the residual range `YC6_1_DIAGNOSIS.md` used to condemn the legacy scan). Use 1e-4 for screening only.
- Running inconsistent gates across branches (overlap floor 0.99 vs 0.90; residual 1e-5 vs 1e-4; `restore_best_on_failure` true vs false); the 2026-08-30 decision log says YC8-1 keeps 1e-5 but the chi-1024 config uses 1e-4.
- Treating YC8-1 at chi 1024 with the current kernel as feasible: one outer iteration took 6965 s (job 57793343), so 100 iterations is 8 days per flux point.

---

## Part 2. Numerical implementation

### 2.1 Kernel cost structure (measured)

| Solver / state | s per sweep or iteration | Notes |
|---|---|---|
| ITensorInfiniteMPS VUMPS, YC8-1, chi 512, period 2, sequential | 284 (theta=0 growth) to 472 (finite flux) | 2 Julia threads, 4 logical CPUs |
| same, parallel update | 554-571 | not faster per iteration |
| same, YC6-1, chi 512, period 6, sequential | 776-1034 | 6 sites and 6x environment recomputation |
| same, YC8-1, chi 1024, period 2 | 6965 | one iteration in a 2 h window |
| MPSKit one-site iDMRG, YC8-1, chi 512, period 2 | ~90 (33423 s / 371 updates) | same thread count |

Root causes in the ITensorInfiniteMPS path (confirmed in pinned package source):
- `InfiniteSum{MPO}` represents the Hamiltonian as per-site finite MPOs padded to a common range of 16 sites in a 2-site cell (the cylinder-wrapping NNN bonds), not a compressed infinite MPO. Every environment solve contracts a 16-tensor chain.
- The sequential multisite update recomputes both environment linear solves once per site (`vumps_nonlocalham.jl:365-366`): 2x for period 2, 6x for the period-6 YC6-1 cell.
- Growth stages converge fully to `residual_tol` at every intermediate chi (`Optimization.jl` `grow_and_optimize`); the theta=0 chi-512 solve spent 189 of 306 iterations below chi 512.
- Checkpoint cadence 2 at chi 1024 rewrites a full state plus recomputes all observables (16-site `expect` and every Schmidt SVD) each time.
- The continuity gate's correlation-length fingerprint adds ~4 transfer eigensolves per accepted point.

### 2.2 Recommendation: make MPSKit the production optimizer

The project already has a validated, round-trip-checked U(1) bridge (`src/IDMRGBridge.jl`, `idmrg/src/ProjectBIDMRG.jl`) and MPSKit is already 3-5x cheaper per sweep on this model. MPSKit provides what the campaign has been missing:
- a compressed `InfiniteMPOHamiltonian` for the long-range cylinder terms;
- `VUMPS` with parallel updates and dynamic inner tolerances;
- `IDMRG2` and `changebonds` (`OptimalExpand`, `VUMPSSvdCut`) so bond growth and U(1) sector redistribution happen inside the solver (one-site fixed-space iDMRG cannot change sector multiplicities, which handicaps the current iDMRG comparison);
- `GradientGrassmann` as a variationally monotone fallback for hard steps, which is the correct tool to decide whether a branch still exists near a spinodal;
- sector-resolved `transfer_spectrum` / `correlation_length` for spectroscopy.
Keep the ITensors-side HDF5 schema and analysis; convert through the bridge.

Minimum-change alternative if staying on ITensorInfiniteMPS: expose `time_step` (finite imaginary-time TDVP, already supported by `tdvp_iteration`) as a damped pre-conditioner for hard steps; force `parallel` updates; add a chi schedule with a looser intermediate tolerance (e.g. 10x) and capped iterations per stage; checkpoint tensors only, without observable recomputation.

### 2.3 Threading and allocation

- The Phase 0 thread calibration was three iterations at chi 256 (`output/phase0_calibration/phase0_retry_80iter/summary.csv`); the "2 threads" conclusion should not be extrapolated to chi 512 period 6, chi 1024, or MPSKit. At chi 256, 4 threads was only 12% slower per iteration than 2 threads; at chi 1024 the blocks are large and few and BLAS threading (currently pinned to 1 with MKL on AMD Milan) is the lever. Re-benchmark 3 iterations at chi 512 and chi 1024 with 2/4/8/16 threads and BLAS 1/2/4 on the actual states (~0.2 node-h), and test OpenBLAS/BLIS against MKL on Milan.
- Memory: 1.4 GiB at chi 512 vs the 8 GiB request is fine; the 32 GiB / 16 CPU chi-1024 request is charged as 8 cores.
- GPUs are not worth it below chi ~2048 with U(1) block sparsity; revisit with MPSKit + CUDA for Phase 3 ladders after a benchmark.

### 2.4 Smaller code issues

- Type piracy on `KrylovKit.linsolve` for `ITensorInfiniteMPS.Aᴸ/Aᴿ` (`Optimization.jl:148-180`); the `custom_krylov` path engages only when settings differ from package defaults (`Optimization.jl:438-440`).
- `transfer_map_eigensolve` reseeds the global RNG (`TransferSpectra.jl:23`).
- `fixed_flux_optimizer_resume_requested` ignores its theta arguments (`Scan.jl:429-435`).
- Environments differ between the two packages (KrylovKit 0.10.2 vs 0.10.4, HDF5 0.17.2 vs 0.17.3, Julia 1.12.6 vs 1.12.7).
- The iDMRG package has no pre-timeout (USR1) handling at all.
- The chi-1024 bridge job received its USR1 pre-timeout signal 2 h 00 m into a 48 h request (`--signal=B:USR1@7200`, elapsed 2:00:43, exit 0). Most likely an operator-issued `scancel --signal=USR1 --batch` after the first 1.9 h iteration; if not, confirm the Slurm time limit with `sacct -j 57793343 -o Timelimit,Elapsed` before the next long submission.

---

## Part 3. Perlmutter deployment

### 3.1 Where the node-hours went

- Phase 1 has ~15.3 of its 20 node-hour ceiling spent (ledger in `docs/PHASES_0_TO_4.md` is stale: jobs 57690953 = 1.104, 57768008 = 0.334, 57793343 not entered). About 11.1 of those went to iDMRG for zero accepted points, 8.81 of them to one exclusive `regular`-QOS job (57500598) that averaged 4.76 CPUs of 128 (1.9% utilization, 9.6 GiB of 512).
- Four of the last ten jobs produced zero scientific iterations (spool-directory root, `Base.cputime()`, HDF5 BitVector, SLURM task-variable conflict). One 48 h YC6-1 job timed out with no checkpoint and lost 36 contracting iterations (0.2 node-h); a later one was killed with plain `scancel` and lost 3 iterations because no launcher exposes a graceful stop.
- VUMPS jobs at chi <= 512 cost ~0.13 node-h per accepted point (YC8-1) and ~0.5 (YC6-1 period 6). The chi-1024 bridge as configured would need ~18 node-h for 13 points at 10 iterations each (and 10 iterations is optimistic at 1e-4), i.e. it alone exceeds the Phase 1 ceiling and takes ~250 wall-hours serially.

### 3.2 Charging and allocation defects (concrete)

- `slurm/run_yc8_1_chi1024_bridge_cpu.sh:361-364` charges 8 of 128 cores for 16 CPUs + 32 GiB; Shared-QOS rounding gives ceil(32768/1952) = 17 logical -> 9 physical cores, and `worker.env` recorded `SLURM_CPUS_PER_TASK=18`. Every chi-1024 charge is ~11% low and the forecast should be 3.375, not 3.0. The YC6-1 launcher hardcodes its own formula; only `run_scan_cpu.sh:124-137` implements the general rule.
- Four disjoint ledgers with three copy-pasted "prior node-hours" constants (YC6 and YC8 launchers, the iDMRG control TOML, `run_scan_cpu.sh`'s baseline). Job-name globs for the one-job guard differ per launcher, so a running YC8 job is invisible to the iDMRG guard.
- No launcher measures Julia's RSS: `/usr/bin/time -v` wraps `srun` (reports 20 MB) and `sacct -X` drops MaxRSS. The 32 GiB chi-1024 request, which sets the entire charge, is unmeasured; chi 512 VUMPS peaked at 1.9 GiB, so chi 1024 plausibly fits in 16 GiB (8 CPUs + 16 GiB = 5 charged cores instead of 9, a 44% saving on every chi-1024 hour).
- The allocation is bigger than the solver step everywhere (18 logical CPUs held, 4 used at chi 1024; 10 held, 4 used for iDMRG). Since the charge is already paid, run 3-4 independent 4-CPU `srun --exact --exclusive` steps inside one allocation (different theta points, seeds, or chi rungs) for the same charge.
- Thread scaling measured on MPSKit iDMRG (job 57576411): 2 -> 16 Julia threads bought 4.3% wall time for 8x CPUs (effective CPUs 1.03 -> 1.47). The kernel is single-thread-bound at chi 512 with U(1) blocks. The chi-1024 launcher was nevertheless raised to 8 CPUs / 4 threads after the run without a measurement; revert unless a chi-1024 benchmark justifies it.
- `slurm/run_spectrum_cpu.sh` is a bare `#SBATCH` script with no account, QOS, constraint, or budget check.
- `run_scan_cpu.sh` (the "guarded Phase 1 launcher", 1104 lines with a 275-line embedded Julia validator that whitelists one historical job by SHA) hard-rejects chi > 512, tol outside [1e-6, 1e-5], and circumference != 8, so it can run neither active science config; two near-clone launchers were written instead. `src/Automation.jl` and `advance`/`advance-submit` are pinned to chi 512 and a 0.1-pi grid and no longer apply.

### 3.3 Sync and repository hygiene

- `core.autocrlf=true` with no `.gitattributes`; the tree is copied to Perlmutter byte-for-byte by Globus. Today all `slurm/*.sh` are LF, but one renormalize would ship CRLF batch scripts. Add `*.sh text eol=lf`.
- `latest_run.txt` is written by every launcher, never trusted, and currently stale in two of three run roots with two different home-path spellings (`/global/homes` vs `/global/u2`).
- 225 MB of pre-policy YC6-1 checkpoints under `output/science/yc6_1/` round-trip through every full-tree sync.
- 96 hardcoded SHA-256 constants and 19 job IDs live in launchers, generators, and configs; `AGENTS.md` and the docs carry per-job hashes and node-hour figures in prose. A single machine-readable ledger (`output/ledger.tsv`: job id, kind, config sha, parent sha, state sha, charge, outcome) would replace most of that and let one `reconcile` cover all run roots.

### 3.4 Deployment recommendations, in order of node-hours saved per unit of change

1. Fix RSS instrumentation (`srun ... /usr/bin/time -v julia`, non-`-X` sacct step query), then right-size chi-1024 memory to the measured peak.
2. Fix the 8-vs-9-core charge and unify charging/budget/reconcile into `slurm/lib/` shared by all launchers; one ledger.
3. Replace the one-job-at-a-time rule by "sum of active reservations <= ceiling" (already computed by `active_snapshot()` in `run_scan_cpu.sh`), and pack independent 4-CPU steps into one allocation or job array: reverse checks, chi ladders, independent theta preparations (Part 1, D1/D2), thread benchmarks.
4. Add a `stop` subcommand (`scancel --signal=USR1 --batch`) and USR1 handling to the iDMRG launcher; derive walltime from measured s/iteration x expected iterations x 1.3 instead of a constant 48 h.
5. Re-benchmark threads and BLAS at chi 512 and 1024 on real states (0.2 node-h) before spending on chi 1024; keep `regular` QOS off the table until >= 25 concurrent steps can fill a node.
6. GPUs: a 0.25 node-h probe reusing the iDMRG benchmark harness at chi 1024 is the most that is justified now; GPU hours come from a separate allocation and U(1) small blocks are the worst case.

---

## Part 4. Recommended sequence (nothing executed yet)

Cheap and decisive first, in roughly this order:

1. **Local, read-only analysis of existing artifacts (0 node-h):** a script that tabulates E, dimerization D = |e1 - e2|, S, xi, chi_F along every lineage from the stored HDF5 files (the numbers in Part 1 came from a throwaway version of this), and a check that the six YC6-1 period-6 tensors are period 2.
2. **Physics validation tests (0 node-h):** ED cross-check of the twisted Hamiltonian on a small finite cylinder, Hermiticity, theta -> theta + 2 pi energy equivalence, a VUMPS residual-decrease test, a known-distinct-state overlap test.
3. **D1 on Perlmutter (~1-2 node-h, parallel steps in one allocation):** independent theta=0 preparations on YC8-1 period 2 at chi 256/512 (random seeds, uniform seed, iDMRG-0.175 state continued to theta=0); compare energies to Hu et al.
4. **Kernel decision:** prototype MPSKit VUMPS/IDMRG2/GradientGrassmann on the same YC8-1 chi-512 state through the existing bridge; measure s/sweep and whether GradientGrassmann from the accepted 0.15 parent at theta/pi = 0.2 converges to a nearby state (branch exists) or drifts to the lower basin (spinodal). This single experiment settles Part 1.1.
5. **D2 campaign (5-10 node-h):** lower-energy basin flux response toward pi as independent per-theta jobs; spectra as separate postprocessing.
6. **D3 write-up** of the dimerized-branch spinodal map with the data already in hand plus a reverse sweep.
7. **Launcher consolidation and ledger** (Part 3), done alongside, not before, the science.

## Verification

- Steps 1-2 are verified by `julia --project=. -e 'using Pkg; Pkg.test()'` plus the new tests passing locally.
- Steps 3-5 are verified on Perlmutter by the existing `plan|submit|status|reconcile` cycle; each job must record measured RSS and s/iteration in its run package.
- The scientific claim in Part 1.1 is verified by step 4: monotone energy descent from the 0.15 parent at theta/pi = 0.2 that ends at overlap >= 0.99 refutes the spinodal reading; descent to the 0.6%-lower basin confirms it.
