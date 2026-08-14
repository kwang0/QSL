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
- Phase 1 states encode geometry, branch, independent preparation, direction,
  seed, chi, flux, accepted-parent SHA-256, and full flux ancestry.
- A contracting rejected state may be used only through the separate,
  SHA-pinned optimizer-checkpoint field at the identical flux; it never
  replaces the accepted continuation parent.
- The exact VUMPS residual history is stored, and unconverged points cannot seed
  later flux points.
- A numerically converged child must also pass a gauge-invariant mixed-transfer
  overlap gate against its immutable parent before it can seed the next flux.
  Energy, entropy, local-observable, and Schmidt-spectrum jumps are stored with
  that decision for audit.
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

For the sparse Phase 1 scout, use one of the four
`configs/phase1_yc8_*_chi128.toml` files. On Perlmutter, inspect and submit one
pilot through the guarded launcher:

```bash
bash slurm/run_scan_cpu.sh plan configs/phase1_yc8_1_forward_chi128.toml
bash slurm/run_scan_cpu.sh submit configs/phase1_yc8_1_forward_chi128.toml
bash slurm/run_scan_cpu.sh status
bash slurm/run_scan_cpu.sh reconcile
```

For a live run whose residual has been manually confirmed to plateau, use an
explicit run ID so cancellation is preserved as a numerical-failure artifact:

```bash
run_dir=$(tr -d '\r\n' < output/phase1_jobs/latest_run.txt)
bash slurm/run_scan_cpu.sh cancel-plateau "$(basename "$run_dir")"
```

See [`docs/PHASE1_PLATEAU_DIAGNOSTICS.md`](docs/PHASE1_PLATEAU_DIAGNOSTICS.md)
for the current fixed-flux chi-192 optimizer resume, exact Perlmutter submission
steps, inner-Krylov diagnostics, and U(1)-sector comparisons.

Direct `sbatch` use is intentionally unsupported. The submit path fixes the
calibrated compute setting at two Julia threads, a four-CPU scan step, and 8 GiB;
allows only one Phase 1 pilot at a time; includes active Project B reservations
in the forecast; and refuses another job until the previous pilot is reconciled
with `sacct`. It also refuses a configuration whose output directory already
contains immutable state artifacts, preventing a retry from spending compute
only to collide with an existing deterministic filename.

Phase 1 continuation uses two independent gates. The configured VUMPS residual
checks numerical stationarity; it does not select the global minimum and does
not by itself establish branch identity. Every child of an accepted state must
also have mixed-transfer overlap per site at least `0.99` with that parent.
The independently prepared first point has no parent, so only the numerical
gate applies there. A failed overlap gate triggers the same interval refinement
as a residual failure, but is classified separately as a possible basin jump.

When adaptive continuation reaches `minimum_step_over_pi` without satisfying a
gate, the scan writes an immutable `scan_outcome.toml` and exits normally.
A same-flux increase in bond dimension is classified separately: if the
expanded state is not accepted, `scan_outcome.toml` records a
`project_b_fixed_flux_expansion_outcome` rather than inventing a zero-width
continuation bracket.
An isolated retry from a contracting rejected MPS is classified separately as
`project_b_fixed_flux_optimizer_resume_outcome` and records the accepted parent,
numerical checkpoint, and new candidate as three distinct immutable artifacts.
Residual failure is `numerical_continuation_loss_bracketed`; overlap failure is
`branch_continuity_loss_bracketed`. Neither classification alone establishes a
physical endpoint.

The reconciled YC8-1 recovery has accepted the chi-128 primary-forward branch
through `theta/pi=0.2421875`. Fixed-flux job `56890262` expanded that accepted
parent to chi 192; after the expansion transient, its residual decreased on
every iteration from 83 through the 360-iteration cap and ended at
`2.332663e-5`. The final trend projects the unchanged `1e-5` gate near
cumulative iteration 484, so the next isolated test resumes the rejected
chi-192 MPS for at most 180 additional iterations at the same theta. Generate
it on Perlmutter with `scripts/prepare_phase1_fixed_flux_resume.jl`; keep the
accepted chi-128 file as `initial_state_file` and the rejected chi-192 file only
as `optimizer_checkpoint_file`.

The launcher passes the submission-side absolute project directory into the
private worker entry point. This is required because Slurm executes a staged
copy of the batch script under `/var/spool/slurmd`; that staging directory is
not a Julia project and must never be used to derive `--project` or script
paths.

On Shared QOS, the 8-GiB request can raise `SLURM_CPUS_PER_TASK` from the four
requested scan-step CPUs to five, with `sacct` reporting six allocated logical
CPUs after core rounding. This is expected: the scan still runs with four CPUs,
Julia still uses two threads, and all values from four through six have the same
budgeted charge of three physical cores.

After both preparations have artifacts, compare them without constructing a
pointwise minimum-energy envelope:

```bash
julia --project=. scripts/compare_phase1_branches.jl \
  output/phase1/yc8_1/primary_forward/seed_101/chi128/states \
  output/phase1/yc8_1/competing_reverse/seed_102/chi128/states \
  output/phase1/yc8_1/branch_comparison.tsv
```

The table reports both labeled states, their residuals and local observables,
and energy/entropy differences. A lower competing energy is recorded but never
used to replace the primary threaded branch.

## Tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
PROJECT_B_RUN_VUMPS_SMOKE=1 julia --project=. test/runtests.jl
bash test/test_phase1_launcher.sh
```

The normal suite tests minimal/supercell geometry, uniform twist charges,
configuration, momentum formulas, identical-state mixed-transfer fidelity,
central-charge analysis, diagnostics, and a schema-v6 infinite-MPS HDF5 round
trip. The opt-in test also performs one VUMPS iteration and neutral plus
physical-`S^z=1` transfer eigensolves. The shell regression runs a staged copy
of the Phase 1 launcher and verifies that it still invokes the original Julia
project rather than Slurm's spool directory.

## Directory map

- `src/`: package implementation.
- `configs/`: Phase 1 branch scouts, later-phase Hu templates, pilots, and
  chi-ladder inputs.
- `scripts/`: scan, branch comparison, spectrum, plotting, scaling, and
  legacy-diagnosis drivers.
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
