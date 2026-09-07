# 002 - Diagnose the chi-1024 candidate before another continuation

Status: evidence review complete; successor experiments proposed
Date: 2026-09-06

## Recommendation

Repair accounting and inspect the existing fixed-flux candidate before spending
more on the chi-1024 bridge. Then use a small, matched solver experiment to
choose a continuation method. Preserve the accepted primary-forward parent,
the current numerical and continuity policies, and the one-job guard.

This assessment responds to
[`ancient-cooking-wombat.md`](../claude/ancient-cooking-wombat.md), whose run
snapshot predates completed job `57801654`. It does not create a launchable
control, select a new lineage parent, change a threshold, or establish a
physical spinodal. The existing bridge remains the authorized campaign;
the proposed solver comparison would need its own explicit campaign control.

## Evidence that changes the next-run decision

### The saved chi-1024 candidate has a substantial continuity warning

The accepted parent HDF5 was read directly and its full SHA-256 verified as
`38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`.
The synchronized candidate manifest names that same parent and candidate hash
`4e3a5f406f61cb791ea98ef6b0dc6cfb108877eb5199d4dc71d204f150c0a9e6`.

| Quantity at theta/pi = 0.15 | Accepted chi 512 | Rejected chi 1024, returned iteration 52 |
|---|---:|---:|
| Energy density | -0.507194159065897 | -0.5121627230317903 |
| Mean cut entropy | 2.3288520835887656 | 3.2646479577628575 |
| VUMPS projected residual | 9.1837732142842e-6 | 4.860776365225489e-4 |

The entropy difference is **0.9357958741740919**. Since
`max_i |S_candidate,i - S_parent,i| >= |mean(S_candidate) - mean(S_parent)|`,
the saved candidate cannot satisfy the declared fixed-flux maximum cut-entropy
jump of `0.35` in its present form. Permuting the cuts cannot remove this
mean-entropy difference.

This is a retrospective warning, not a newly executed continuity gate. The
official outcome remains numerical failure with continuity unevaluated. A
later converged tensor could differ, and an entropy increase on growing chi
does not by itself establish a basin change. However, another iteration-cap
extension needs a continuity rationale as well as a residual forecast.

Sources: `observables/von_neumann_entropies` in the accepted parent named by
`configs/phase1_yc8_1_multimetric_continuity.toml`; the candidate
`state_manifests/state_0001_theta_p0p15000000_chi1024_rejected_4e3a5f406f61.toml`
under `output/science/yc8_1/primary_forward_chi1024_parallel_bridge_20260831/seed_101/chi1024/`.
The candidate's full scratch HDF5 was not available for inspection here.

### The whole-run contraction fit conceals a weak late trend

The 60 iteration records in `logs/scan-57801654.out` were parsed independently.
Ordinary least squares of `log(residual)` against iteration gives:

| Window ending at iteration 60 | Log-residual slope per iteration | R-squared | Median seconds per iteration |
|---|---:|---:|---:|
| Last 10 | +0.00320287 | 0.385973 | 1403.34 |
| Last 20 | -0.00469581 | 0.397718 | 1449.43 |
| Last 30 | -0.01149866 | 0.786429 | 1490.36 |
| All 60 | -0.04047275 | 0.750829 | 1816.34 |

The log prints rounded residuals; the full-window fit reproduces the stored
outcome to that precision. The immutable `maximum_iterations_contracting`
classification and projected iteration `99.6173` remain intact, but that
projection is not a reliable estimate of the additional work now required.
The last ten iterations have a positive fitted slope. The terminal residual
is above the iteration-52 minimum.

The review's 6965-second chi-1024 timing came from the earlier one-iteration
job. The newer run averaged 2074.47 seconds over all 60 iterations and about
1432.25 seconds over the last ten. These are different trajectories and
resource profiles, not a controlled threading speedup measurement.

### The cited competing iDMRG candidate is not uniform in the stated diagnostic

The cited iDMRG analysis HDF5 was read directly and verified against SHA-256
`302b6db4a8e90d568dc61c82c2f8d2b37e588fa3125b69b5cced91752b99fe47`.

| State | Stored two-site energy terms | D = absolute difference |
|---|---|---:|
| Accepted chi-512 theta/pi = 0.15 | (-0.4493613434, -0.5650269747) | 0.1156656312 |
| Rejected iDMRG theta/pi = 0.175 | (-0.5801690035, -0.4402942233) | 0.1398747801 |

Thus the lower-energy candidate cited by the review has a larger alternating
energy pattern, with the strong/weak ordering reversed. This invalidates using
that artifact as evidence for a uniform competing basin. The two energies are
also evaluated at different fluxes; their difference is not a same-Hamiltonian
sector splitting.

A diagnostic should compare physical bond observables and translated
representatives with consistent U(1) charge conventions. Raw site-tensor
equality is gauge dependent. Neither a repeating six-site energy pattern nor
a change of strong/weak ordering alone identifies an entire MPS or a
topological sector. Keep the declared branch gate unchanged while studying
these possibilities.

## Which review recommendations survive

- **Accounting and RSS repairs are immediate requirements.** The two YC8
  jobs have `NCPUS=18`, while the launcher forecasts and reconciles with 16.
  NERSC's memory-based Shared-QOS rule gives nine physical cores for 32 GiB;
  a 48-hour reservation is `48 * 9 / 128 = 3.375` node-hours. The synchronized
  Phase 1 balance is about `2.23849`, so a full 48-hour successor does not fit.
  The current `/usr/bin/time` wraps `srun` and reports the launcher's roughly
  22 MiB RSS, not the Julia process. See
  [NERSC Shared-QOS allocation rules](https://docs.nersc.gov/jobs/examples/#shared).
- **MPSKit merits a controlled pilot.** The pinned local MPSKit 0.13.13 source
  contains VUMPS, IDMRG2, and GradientGrassmann, and the existing bridge reduces
  integration risk. Its faster one-site iDMRG sweeps do not establish faster
  convergence to an accepted state with another algorithm. Compare elapsed
  time and charged hours to declared numerical eligibility and common branch
  diagnostics, not unlike solver stopping quantities. See the
  [MPSKit algorithm documentation](https://quantumkithub.github.io/MPSKit.jl/stable/man/algorithms/).
- **Seed diversity is worthwhile, but the proposed product seeds are not
  independent enough.** `balanced_seed_states(2, ...)` can produce only
  Up/Dn and Dn/Up. Random balanced product seeds and the two-site block pattern
  add no new product configurations. A uniform spin product state would not
  provide the intended zero-magnetization U(1) preparation. Use explicitly
  validated, distinct entangled U(1) initial MPS or a separately labeled
  reverse preparation for a future basin experiment.
- **Independent physics tests would strengthen the code.** Existing tests
  already cover geometry, twist charges, momentum mappings, identical-state
  overlap, and bridge/convergence semantics; the blanket claim that there are
  no physics tests is too broad. Missing independent finite-Hamiltonian/ED,
  gauge-equivalence, and distinct-state checks remain useful. A `2*pi` gauge
  test should compare gauge-related Hamiltonians or full spectra, not demand
  periodicity of a single adiabatically labeled state.
- **Defer central-charge fits.** There is no validated large-correlation-length
  chi ladder. Also audit units before comparing xi with circumference:
  `TransferMatrix(psi.AL)` contracts the full MPS cell, while
  `normalized_spectrum` stores `-1/log(abs(lambda/lambda0))` without a period
  factor. Those raw lengths are in transfer-cell units, not automatically
  single-site or physical axial-distance units. Fixed-period log-ratio gates
  are unaffected by a common unit factor.
- **Several policy criticisms are stale.** The chi-1024 `1e-4` profile and
  multimetric continuity rule were explicitly campaign-scoped on August 31;
  they are not silent changes to the older chi-512 profile. Preserve their
  exploratory label and require tolerance sensitivity before quantitative
  publication claims. `.gitattributes` already enforces LF. Keep the two Julia
  environments isolated. Broad launcher consolidation, concurrency, GPU work,
  and YC6 cell reduction should follow the immediate diagnostic decision.

## Scientific interpretation

The review offers a useful hypothesis about a finite-cylinder instability, but
does not establish a spinodal, VBS phase, or even/odd sector assignment. The
project has a direct counterexample to treating every failure as physical:
changing sequential to parallel VUMPS recovered the accepted chi-512 0.15
state with essentially unchanged branch diagnostics.

Gradient descent ending in another basin does not prove that no nearby local
minimum exists; the starting point and optimization path matter. A nearby
converged state supports recoverability at that control, while a spinodal
claim needs reproducible bracketing, stability evidence, and direction/chi
comparisons.

Hu et al. (2019) explicitly preserve adiabatic evolution and exclude points
after its failure. Their supplement reports difficulty beyond about 0.3*pi
on YC6-1, while larger YC-1 cylinders can reach pi. Independent per-theta
minimizations therefore need branch validation before they can form the
requested reproduction trajectory.
See [Hu et al., 2019, main text and supplement](https://arxiv.org/abs/1905.09837).

The cited Hu et al. (2015) Table I lists YC8 splittings 0.0024 at J2=0.1 and
0.0018 at J2=0.125, approximately 0.46% and 0.35% of the even-sector energy
magnitude. It does not provide the claimed matched 0.6% benchmark at J2=0.12
for this flux/geometry control. Energy similarity alone cannot identify a
topological sector.
See [Hu et al., 2015, Table I](https://arxiv.org/abs/1504.00654).

## Ordered next steps

1. **Local operational repair.** Correct Shared-QOS forecasts and actual-CPU
   reconciliation; incorporate every terminal job across run roots without
   double counting. Preserve original accounting evidence and append explicit
   corrections. Make all launchers recognize all Project B jobs. Capture
   Julia RSS inside `srun` and retain step-level `sacct` data. Test memory
   rounding, cumulative ceilings, and copied-worker execution before transfer.
2. **Finish the zero-allocation evidence audit.** Tabulate accepted and rejected
   lineages with hashes, per-cut entropies, local bond patterns, U(1) support,
   residual histories, and correctly normalized overlaps/xi. Add focused
   independent physics checks. Treat fidelity susceptibility only on smooth,
   fixed-chi neighboring states, with flux measured in radians.
3. **Verify the smallest remote evidence before selecting any restart.** Read
   live status and updated accounting; obtain Julia-step RSS and hash-check
   job `57801654`'s returned candidate and iteration-52/60 checkpoints. Inspect
   the available checkpoint observables to locate the entropy change. Choose
   no restart from local modification times or the aggregate contraction label.
4. **Prepare one small matched solver pilot if those checks justify it.** First
   validate MPSKit VUMPS on the accepted theta/pi=0.15, chi-512 control through
   the existing bridge. Then use a separately declared fixed-chi difficult
   point, such as theta/pi=0.2 from that parent, with a bounded
   GradientGrassmann fallback. Hold virtual spaces fixed initially to isolate
   the optimizer; test IDMRG2/sector growth separately. A proposed total cap of
   at most 0.5 node-hours is a planning constraint, not a measured forecast or
   a prepared submission. Record native convergence, common observables,
   branch diagnostics, runtime, and RSS. Preserve the primary lineage.
5. **Choose the scientific successor from that evidence.** Continue a recovered
   branch with the declared continuity checks. If recovery fails, design a
   genuinely independent basin preparation and forward/reverse comparison;
   report a numerical recovery limit until physical branch loss is supported.
   Revisit a chi-1024 anchor resume only with evidence for both convergence and
   continuity. Full flux sweeps and production solver migration follow this
   decision, not the review's unverified cost estimates.

## Verification and limits

The owner subsequently authorized implementation. Current progress, validation
and the manual Perlmutter handoff are tracked in
[`../plans/REVIEW_FOLLOWUP_IMPLEMENTATION.md`](../plans/REVIEW_FOLLOWUP_IMPLEMENTATION.md).
The assessment below describes the original read-only review.

The context audit passed on Windows at Git `e8d0b4f`: both active reference
targets were present with matching SHA-256, and the only preexisting untracked
path was `docs/claude/`. A temporary Julia/HDF5 read-only analysis verified the
accepted 0.10/0.15 states and cited iDMRG analysis hashes, read their scalar
observables, checked the candidate manifest's parent, and independently fit
all 60 logged residuals. No new solver run or full test suite was needed for
this documentation assessment.

The local artifacts are the owner-reported completed/reconciled sync described
in `PROJECT_STATE.md`. A read-only SSH status attempt reached NERSC but could
not authenticate. Current queue, later accounting, full scratch tensors, and
restart hashes therefore remain live unknowns. No submission, cancellation,
scratch cleanup, or executable-control change was performed.
