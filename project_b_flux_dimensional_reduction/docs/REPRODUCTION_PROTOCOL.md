# Hu-data reproduction protocol

## Scope

The first milestone is a controlled reproduction of the two ground-state data
products used by Hu et al. at `J2/J1=0.12`:

1. the physical `S^z=1` inverse-correlation-length spectrum versus spin flux
   (the left column of their Fig. 3); and
2. the half-cylinder entanglement entropy versus spin flux (their Fig. 4).

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
directions. A failed point is an optimization spinodal, not a data point. The
driver saves it as `rejected`, leaves the last accepted state untouched, and
either bisects the continuation interval or stops.

Acceptance gates for every plotted state are:

- final VUMPS residual no larger than the requested tolerance;
- no residual rebound or non-finite value;
- stable energy density, entropy, magnetization, and within-cell energy terms;
- an immutable HDF5 file containing the actual `psi` at that flux;
- agreement of branch identity under a smaller flux step and, where possible,
  reverse continuation.

## 2. Reproduce the Fig. 3 flux panel

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

## 3. Reproduce the Fig. 4 entropy response

The state file records all cut entropies, Renyi-2 entropies, and normalized
Schmidt probabilities. `plot_flux_summary.jl` plots the mean cut entropy above
the spectrum. Compare the complete flux dependence first; only fit the Dirac
response after the same branch passes the acceptance gates on both sides of the
crossing.

Hu's production dimensions were several thousand U(1) states (and up to 12288
for the shown correlation spectra), so `chi=512` is a pipeline check, not a
quantitative replication.

## 4. Measure the effective central charge

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

## 5. Completion matrix

| Paper/Project B quantity | Implemented artifact | Required validity check |
|---|---|---|
| Fig. 3 left, `1/xi` vs flux | physical-sector spectrum HDF5 | VUMPS and Krylov convergence |
| Fig. 3 YC-0 momenta | pure-TM `k2` plus mixed-TM `k1` | all stored translation checks pass |
| Fig. 3 YC-1 momenta | two-site pure-TM Eq. (4), two `k1` branches | minimal cell and uniform gauge |
| Fig. 4 entropy vs flux | state HDF5, all cuts and Schmidt values | same accepted basin |
| finite-entanglement `c_eff` | chi ladder plus scaling script | stable local slopes at large `xi` |
| spinodal/basin collapse | rejected state plus residual history | bracket versus chi, seed, and direction |
