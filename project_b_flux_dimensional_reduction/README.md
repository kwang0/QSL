# Project B: flux-tuned dimensional reduction

This is an isolated implementation of Project B from the repository roadmap.
Nothing outside this directory is imported or modified at runtime; the relevant
YC geometry, Hamiltonian, VUMPS loop, state storage, transfer spectroscopy,
finite-entanglement scaling, plotting, and diagnostics were refactored into one
small Julia package.

The immediate diagnosis of the existing YC6-1 result is in
[`docs/YC6_1_DIAGNOSIS.md`](docs/YC6_1_DIAGNOSIS.md). The feature near
`theta=0.4 pi` is an unconverged optimization/basin jump, not the expected
Dirac crossing.

## What changed relative to the legacy workflow

- Every selected flux has an immutable HDF5 state artifact containing `psi`.
- The exact VUMPS residual history is stored, and unconverged points cannot seed
  later flux points.
- Failed continuation intervals can be bisected automatically.
- Expensive transfer spectroscopy is a separate postprocessing job.
- One neutral solve normalizes all requested physical sectors; physical
  `S^z=1` is correctly mapped to `QN("Sz",2)`.
- Hu-compatible MPS cells are selected automatically: even YC(Ly)-0 uses `Ly`
  sites and YC(Ly)-1 uses the minimal two-site repeat.
- The production twist is distributed uniformly, preserving the translation
  symmetry used in the supplemental momentum formulas.
- YC(Ly)-0 spectra use a mixed one-site translation transfer matrix for `k1`;
  YC(Ly)-1 spectra use the two-site pure-transfer Eq. (4) mapping and retain
  the pi-shifted `k1` branch.
- Spectra are plotted as scatter points, not rank-connected pseudo-branches.
- Entropy, Renyi-2 entropy, Schmidt probabilities, energy nonuniformity, and
  magnetization are saved together with the state.
- A warm-started chi ladder and local `c_eff` estimator implement the central
  Project B measurement.

The environment is pinned by `Project.toml` and `Manifest.toml`, including the
exact Git tree of the unregistered `ITensorInfiniteMPS.jl` dependency. That
package describes itself as work in progress, so the optional smoke test covers
the internal VUMPS and transfer-matrix APIs used here.

## Setup

From this directory:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using TriangularJ1J2ProjectB'
```

For the low-cost YC6-1 pipeline:

```bash
julia --project=. scripts/run_scan.jl configs/pilot_yc6_1.toml
julia --project=. scripts/run_spectrum.jl configs/pilot_yc6_1.toml
julia --project=. scripts/plot_flux_summary.jl configs/pilot_yc6_1.toml 1
julia --project=. scripts/plot_momentum_spectrum.jl configs/pilot_yc6_1.toml 1
```

Production configuration templates for YC8-0 and YC8-1 are in `configs/`.
Read [`docs/REPRODUCTION_PROTOCOL.md`](docs/REPRODUCTION_PROTOCOL.md) before a
large run; it defines the convergence gates and paper-to-artifact mapping.
The allocation-bounded, cross-chat plan is maintained in
[`docs/PHASES_0_TO_4.md`](docs/PHASES_0_TO_4.md).

## Tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
PROJECT_B_RUN_VUMPS_SMOKE=1 julia --project=. test/runtests.jl
```

The normal suite tests minimal/supercell geometry, uniform twist charges,
configuration, momentum formulas and mixed-transfer construction,
central-charge analysis, diagnostics, and an actual infinite-MPS HDF5 round
trip. The opt-in test also performs one VUMPS iteration and neutral plus
physical-`S^z=1` transfer eigensolves.

## Directory map

- `src/`: package implementation.
- `configs/`: pilot, Hu-geometry, and chi-ladder inputs.
- `scripts/`: scan, spectrum, plotting, scaling, and legacy-diagnosis drivers.
- `slurm/`: CPU launchers; optimization and spectroscopy are separate jobs.
- `test/`: deterministic tests and opt-in numerical smoke test.
- `docs/`: reproduction protocol and evidence-backed diagnosis.
- `output/`: generated states, spectra, logs, and plots (ignored by Git).

## Momentum validity boundary

Full `(k1,k2)` labels are emitted only for a paper-compatible minimal cell. For
YC(Ly)-0, every mode must also pass mixed-transfer translation fidelity,
Schmidt-basis diagonality, mode-weight coverage, and phase-coherence checks.
Supercell and unsupported-shift spectra retain their raw transfer phase but are
explicitly marked unresolved; the code never guesses a phase unfolding.
