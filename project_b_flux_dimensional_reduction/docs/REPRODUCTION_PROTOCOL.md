# Hu-data reproduction protocol

## Scope

The owner's main reproduction target is Hu et al. Figures 2 and 3 at
`J2/J1=0.12`, with YC8-1 continued through `theta/pi=1`:

1. the excitation-energy gaps in physical `S^z=0` and `S^z=1` (Fig. 2); and
2. the physical `S^z=1` inverse-correlation-length spectrum versus spin flux
   and momentum (Fig. 3).

The first product needs an embedded finite-window excited-state calculation,
which is not implemented. Transfer eigenvalues are not substitutes for those
energy gaps. The second product has measurement code but no validated
production trajectory to pi. See
[the September 8 feasibility assessment](decisions/004-yc8-1-figure-reproduction-feasibility.md)
for the implementation and resource gaps. The previous scope named Fig. 3 and
the Fig. 4 entropy response; that entropy measurement remains a supporting
diagnostic, and central-charge fitting is a later Project B objective.

The package also implements the Project B finite-entanglement measurement
`S=(c/6) log(xi)+a` at the flux-induced crossing. The supplemental unit cells
and transfer matrices are implemented: even YC(Ly)-0 uses an `Ly`-site cell and
a mixed one-site circumference-translation transfer matrix, while YC(Ly)-1
uses a two-site cell and the pure-transfer Eq. (4) mapping. Momentum labels are
saved per mode together with numerical validity diagnostics.

## 1. Establish a trustworthy flux trajectory

Start with `configs/hu_yc8_1_forward.toml` (crossing at `theta/pi=1`) and
`configs/hu_yc8_0_forward.toml` (crossing at `theta/pi=2`). The schedules are
coarse away from the crossing and dense within `pi/8`, `pi/16`, and `pi/32`.

For each geometry, run at least two seed patterns and both continuation
directions. A failed point is a rejected numerical outcome; it does not by
itself establish a spinodal. The driver leaves the last accepted state untouched and
either bisects the continuation interval or stops.

Acceptance gates for every plotted state are:

- final VUMPS residual no larger than the requested tolerance;
- no residual rebound or non-finite value;
- stable energy density, entropy, magnetization, and within-cell energy terms;
- an immutable HDF5 file containing the actual `psi` at that flux;
- agreement of branch identity under a smaller flux step and, where possible,
  reverse continuation.

## 2. Implement the Fig. 2 gap measurement

There is currently no Project B gap launcher or validated measurement module.
The implementation must support an embedded window with infinite-MPS
environments, physical-charge targeting and a neutral excited state orthogonal
to the window ground state. Validate boundary-energy subtraction, window-size
sensitivity and convergence using independently solvable fixtures before any
large-chi calculation. Benchmark this separately from uniform optimization.
The existing spectrum command below produces correlation lengths only.

## 3. Reproduce the Fig. 3 flux panel

Optimize first; spectroscopy is deliberately separate because transfer solves
are expensive:

```bash
julia --project=. scripts/run_scan.jl configs/hu_yc8_1_forward.toml
julia --project=. scripts/run_spectrum.jl configs/hu_yc8_1_forward.toml
julia --project=. scripts/plot_flux_summary.jl configs/hu_yc8_1_forward.toml 1
```

The spectrum calculation solves one neutral transfer problem for normalization,
then the physical `S^z=1` problem (`ITensor QN("Sz",2)`). It stores the raw and
normalized complex eigenvalues, `1/xi`, `xi`, axial momentum, symmetry labels,
Krylov convergence metadata, `k1`, `k2`, the second YC-1 `k1` branch, and
per-mode momentum coverage/coherence. YC-0 files additionally store the mixed
transfer eigenvalue, translation fidelity, Schmidt translation phases, and
Schmidt-diagonality weight.

The plot uses scatter points. Eigenvalues are independently ordered at each
flux, so equal array ranks are not assumed to be continuous physical branches.
A reproduction requires the lowest physical `S^z=1` inverse correlation length
to decrease toward the predicted crossing and to decrease systematically with
increasing bond dimension.

## 4. Supporting Fig. 4 entropy response

The state file records all cut entropies, Renyi-2 entropies, and normalized
Schmidt probabilities. `plot_flux_summary.jl` plots the mean cut entropy above
the spectrum. Compare the complete flux dependence first; only fit the Dirac
response after the same branch passes the acceptance gates on both sides of the
crossing.

Hu's production dimensions were several thousand U(1) states (and up to 12288
for the shown correlation spectra), so `chi=512` is a pipeline check, not a
quantitative replication.

## 5. Later objective: effective central charge

Warm-start a true bond-dimension ladder at the crossing, for example:

```bash
julia --project=. scripts/run_chi_ladder.jl \
  configs/yc6_1_chi_ladder_at_pi.toml 256 512 1024 2048 4096
julia --project=. scripts/run_spectrum.jl \
  configs/yc6_1_chi_ladder_at_pi.toml
```

Then pass the resulting state paths to:

```bash
julia --project=. scripts/analyze_scaling.jl \
  configs/yc6_1_chi_ladder_at_pi.toml 1 STATE_256.h5 STATE_512.h5 STATE_1024.h5
```

The primary result is the adjacent-window estimator

```text
c_eff(chi_i,chi_j) = 6 [S_j-S_i] / [log(xi_j)-log(xi_i)].
```

Use only a stable large-`xi` window with `xi` comfortably larger than the
circumference. The dimensional-reduction targets are `c=1` for two nominally
gapless fermion flavors and at most `c=3` for four flavors. A drifting or absent
plateau is a result; do not force a global fit through preasymptotic points.

## 6. Completion matrix

| Paper/Project B quantity | Implemented artifact | Required validity check |
|---|---|---|
| Fig. 2, excitation gaps vs flux | **Not implemented:** embedded-window gap solver | converged parent, charge/orthogonality checks, boundary-energy and window validation |
| Fig. 3 left, `1/xi` vs flux | physical-sector spectrum HDF5 | VUMPS and Krylov convergence |
| Fig. 3 YC-0 momenta | pure-TM `k2` plus mixed-TM `k1` | all stored translation checks pass |
| Fig. 3 YC-1 momenta | two-site pure-TM Eq. (4), two `k1` branches | minimal cell and uniform gauge |
| Fig. 4 entropy vs flux | state HDF5, all cuts and Schmidt values | same accepted basin |
| finite-entanglement `c_eff` | chi ladder plus scaling script | stable local slopes at large `xi` |
| spinodal/basin collapse | rejected states and histories are diagnostic evidence only | converged approach, stability evidence, and checks versus chi, seed and direction |
