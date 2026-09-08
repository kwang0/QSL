# 004 - Recenter YC8-1 work on Figures 2 and 3

Status: requirements assessment complete; revised execution proposed
Date: 2026-09-08

## Objective and missing deliverables

The owner identifies reproduction of Hu et al. Figures 2 and 3 as the main
goal. The existing protocol instead names Figure 3 and Figure 4 as its first
milestones. Preserve the entropy and scaling implementation, but make that
scope mismatch explicit. Recovering the current chi512 lineage is an
intermediate diagnostic, not the completion criterion for this reproduction.

| YC8-1 paper target | Reported m | Required product | Project implementation |
|---|---:|---|---|
| Figure 2 | 6144 | Excitation gaps in Sz=0 and Sz=1 versus flux | Missing embedded-window excited-state solver |
| Figure 3 | 12288 | Sz=1 inverse correlation lengths and momenta | Transfer spectroscopy implemented; production trajectory and scaling unvalidated |

The supplement's gap procedure uses a 64-site window between fixed infinite
environments, targeting the lowest Sz=1 and first excited Sz=0 states and
subtracting the bulk energy. Table II also reports YC8-1 at theta=pi with
m=1024 and truncation error 6.5e-5. Our two-site period matches their geometry.
Source: [Hu et al., captions, Table II and gap-measurement supplement](https://arxiv.org/pdf/1905.09837).

Thus large bond dimension is necessary to assess quantitative convergence,
but the paper itself does not support treating m=6144 as a universal minimum
for reaching pi. Nominal bond dimension alone is not an established
explanation for our early failure.
Matching a dimension also does not guarantee matching the state preparation
or its continuation history. The table does not specify that history for
each entry, so it cannot guarantee a fixed-chi1024 continuation from zero.

## What the present code establishes

- The Hamiltonian, geometry, uniform gauge and physical charge conventions
  have independent local checks. No current evidence identifies the period-2
  representation as the obstacle.
- The accepted chi512 endpoint is theta/pi=0.15. The attempted chi1024 growth
  there failed numerically and shows a large entropy change. The solver pilot
  produced no numerically eligible candidate. Preserve these classifications.
- The MPSKit integration is deliberately fixed-space. `build_state` in
  `idmrg/src/ProjectBIDMRG.jl` requires every bond dimension to equal 512;
  convergence, benchmark and result paths also contain fixed-512 assumptions.
  Its one-site IDMRG and the VUMPS/Grassmann pilot do not grow virtual spaces.
- The ITensor route does have `subspace_expansion` in
  `src/Optimization.jl`. The missing capability is a demonstrated stable,
  affordable growth trajectory, not an absence of all growth code.
- The pinned MPSKit source contains `IDMRG2` and `OptimalExpand`. A tested
  integration could use two-site growth or controlled expansion followed by
  fixed-space refinement, recording achieved dimensions, changing U(1)
  multiplicities and genuine truncation diagnostics where available.
  [MPSKit algorithm documentation](https://quantumkithub.github.io/MPSKit.jl/stable/man/algorithms/).
- The current bridge uses dense arrays and permutations, including
  `convert(Array, tensor)` in imports and exports. It also assumes the original
  parent's charge basis. Growth needs a new schema that records the actual
  new spaces and preserves sparse storage through checkpoint/restart.
- `src/TransferSpectra.jl` applies the transfer operator through Arnoldi rather
  than constructing a full dense transfer matrix. The physical Sz=1 sector
  and YC8-1 momentum mapping already exist. They still need production-state
  convergence, a resource benchmark and consistent transfer-cell units.
- No embedded-window gap driver, infinite-environment boundary assembly or
  neutral excited-state targeting exists in the project source. Inverse
  correlation length must not be relabeled as an energy gap; the two
  measurements have different normalizations and numerical requirements.

The available libraries support ingredients for growth, not a completed
high-chi implementation. Changing `chi` in a current MPSKit control would
fail existing assumptions rather than create the proposed production route.

## Preparation and scientific interpretation

The current lineage controls establish continuity relative to one prepared
low-chi state. They do not establish that its zero-flux ancestor is the
quantitatively converged state family needed for the target figures.

Recommend a separately labeled preparation study at theta=0, with independent
entangled U(1) starts and gradual chi growth. Compare energies, local bond
observables, entanglement spectra and correlation spectra as chi increases.
Then follow a validated family in flux, refining the step and chi where
convergence requires it. Starting growth at zero flux is a diagnostic choice
to separate preparation/growth trouble from flux-induced trouble; success is
not assumed. Do not merge competing preparations into a pointwise energy
envelope or overwrite the existing parent.

A chi-growth entropy change is not interchangeable with a fixed-chi flux
jump. Existing campaign thresholds remain intact; the new preparation study
needs its own declared comparison policy. The brief fixed-flux calibration
recommended in decision 003 can resolve a local solver question, but does not
by itself provide the high-chi preparation or the missing measurement.

## Hardware feasibility and cost limits

Perlmutter CPU nodes provide 128 physical cores and 512 GB of RAM. These make
chi6144 a reasonable engineering target and chi12288 plausible in principle,
but do not establish that this implementation fits memory or time limits.
This is a feasibility judgment, not a measured production forecast.
[NERSC CPU-node specifications](https://docs.nersc.gov/systems/perlmutter/architecture/#cpu-nodes).

At fixed physical/MPO dimensions and a similar block layout, a useful stress
model is quadratic tensor storage and cubic contraction/factorization work.
Relative to chi512, that model gives:

| chi | Quadratic storage factor | Cubic work factor | Current dense canonical export (GiB) |
|---:|---:|---:|---:|
| 1024 | 4 | 8 | 0.15625 |
| 2048 | 16 | 64 | 0.625 |
| 4096 | 64 | 512 | 2.5 |
| 6144 | 144 | 1728 | 5.625 |
| 12288 | 576 | 13824 | 22.5 |

The last column is an exact uncompressed payload calculation for two sites
with equal dimensions, ComplexF64, and all AL/C/AR tensors:
`2 * (2*chi^2 + chi^2 + 2*chi^2) * 16 / 2^30`.
It excludes environments, Krylov vectors, copies and optimizer workspaces.
It describes the present dense export, not the minimum sparse MPS storage or
peak solver RSS. The power-law columns are assumptions, not fitted timings;
U(1) sector distributions, MPO layout, iteration count and threading change
both constants and effective scaling.

The chi512 MPSKit pilot measured 8.33-9.54 GiB peak solver RSS and roughly
179-206 seconds per late iteration with two Julia threads. The older
chi1024 ITensor allocation reports about 2.65 GiB in its solver step and about
24 minutes per late iteration. Different backends, algorithms and states make
those measurements unsuitable for a single fitted scaling law. In particular,
neither multiplying all RSS by chi squared nor assuming ideal 64-fold thread
speedup is a reliable capacity estimate.

Before a production run, benchmark live tensor/environment memory, sparse
contractions, SVD/QR, inner Krylov work, checkpoint I/O and the transfer solve
at chi512/1024/2048 on the same backend. Retune block threading versus BLAS
threading as blocks grow. Allocating more Slurm CPUs alone does not change
the Julia/BLAS execution settings. The project has no implemented MPI or GPU
execution path; additional nodes/GPUs do not automatically accelerate one
state. A CPU route should be measured before proposing such a port.

The latest synchronized accounting leaves 1.953943142361 Phase 1 node-hours.
There is 130.859510142361 node-hours of arithmetic headroom below the 150-hour
project ceiling, but phase allocations are not automatically reassigned and
this is not a live NERSC allocation balance. A full reproduction at the target
dimensions has not been shown to fit that total. It needs a measured production
budget, including the gap calculation and spectra, rather than a forecast
from one short ground-state update.

## Proposed order of work

1. Implement and test general-chi sparse state I/O plus one controlled MPSKit
   growth route. Keep the old sealed runtime and results reproducible through
   their controls; prepare a new control for any edited pinned source.
2. Establish and benchmark converged theta=0 states at chi512, 1024 and 2048.
   Require restart reproducibility and same-chi independent-preparation checks.
   Compare observables across chi before selecting a family for flux insertion.
3. At the affordable dimensions, attempt a coarse full 0-to-pi trajectory with
   adaptive steps, then selected chi4096/6144 points. Use a chi12288 production
   target only after measured memory/time and observable changes justify it.
   All points plotted as a continuation must pass their declared gates.
4. Implement the separate Figure 2 window calculation, first on tiny solvable
   fixtures and then a low-chi cylinder. Verify the neutral excited state's
   orthogonality, charge targeting, boundary-energy convention and window
   convergence. Benchmark it independently from the uniform solver.
5. Produce Figure 3 from accepted states and both Figure 2 gap sectors from
   the validated window solver. Compare selected fluxes across chi and show
   the finite-chi rounding near the endpoint. Defer central-charge fitting
   and other geometries until the requested figures have a defensible basis.

This order revises the proposed emphasis, not executable controls, accepted
lineage, numerical thresholds or budget permissions. No remote run is
prepared or submitted by this assessment. A larger production allocation or
reassignment of phase budgets requires a concrete costed plan and owner
direction.

## Verification

The context audit passes at the reviewed source revision; all three active
control references match and the local output is retrospective evidence only.
Source inspection checked the fixed-512 paths, dense bridge conversions,
ITensor expansion, pinned MPSKit growth algorithms and matrix-free transfer
solve. All scaling-table entries were calculated directly. This is a
documentation assessment: no high-chi allocation, new solver benchmark or
excited-state calculation has been run, and no runtime source was modified.
