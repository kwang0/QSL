# Triangular-lattice $J_1$-$J_2$ MPS/DMRG research roadmap

Research snapshot: 2026-08-03

Primary target: $J_1=1$, $J_2/J_1\simeq0.12$ on infinite and long triangular-lattice cylinders

Computing target: NERSC Perlmutter

## Executive recommendation

The best program is no longer just “reproduce Hu et al. at larger bond dimension.” The 2019 state should be treated as a well-defined **Dirac-spin-liquid-like variational basin** whose relationship to the true cylinder ground state is unsettled. Two independent 2026 MPS/DMRG studies report nearly degenerate but locally and dynamically distinct cylinder states, and the lower-energy state is not the Hu-like state. The flagship project should therefore be:

> Build a controlled atlas of competing cylinder minima versus circumference, cylinder shift, spin flux, $J_2$, and initialization; then identify each state using flux-tuned central charge, symmetry-resolved transfer spectra, local reduced density matrices, and, selectively, dynamics.

The most promising publishable tracks, in recommended order, are:

1. **Competing-state and domain-wall atlas** — highest urgency and strongest match to the present code.
2. **Flux-tuned dimensional reduction of the DSL** — extract the effective 1+1D central charge and operator content at the flux-induced Dirac crossings.
3. **Singlet-monopole spectroscopy through dimer response** — distinguish a DSL basin using the predicted $X$-point spin-Peierls susceptibility.
4. **Gutzwiller-MPS-to-DMRG bridge** — use projected parton states as controlled seeds and as a nonorthogonal low-energy basis, rather than reporting raw global overlaps alone.
5. **State-resolved dynamics** — compare $K$- and $M$-point spectral weight only after the ground-state basins are under control.
6. **Magnetic-field/anisotropy extensions** — scientifically timely, but best pursued after the zero-field state-selection problem is understood.

The first three tracks share almost all of the required ground-state infrastructure, so they form a coherent program rather than unrelated projects.

## 1. What Hu et al. actually established

[Hu et al. (2019)](https://arxiv.org/abs/1905.09837) used infinite-cylinder DMRG near $J_2/J_1=0.12$ and inserted a physical spin flux $\theta$. In a fermionic $U(1)$ DSL description, spin-up and spin-down partons acquire opposite boundary twists, while an emergent flux selects the parton boundary sector. The quantized transverse momenta can therefore be swept through the Dirac nodes.

Their principal numerical signatures were:

- transfer-matrix gaps that approach zero linearly at the expected flux and momenta;
- spin-triplet bilinear modes near the $M$ points and monopole modes near the $K$ points;
- the universal flux dependence of the entanglement entropy expected from four Dirac fermions;
- consistent behavior across several YC$L_y$-$n$ compactifications.

For the geometry convention in that work, the important dimensional-reduction prediction is:

- if both $L_y$ and the cylinder shift $n$ are even, the Dirac crossing occurs at $\theta_c=2\pi$ and all four fermion flavors are nominally gapless;
- in the other cylinder classes, crossings occur at $\theta_c=\pi$ or $3\pi$ and only two flavors are nominally gapless.

The calculation was already demanding: the main results used $U(1)$ bond dimensions of several thousand, reaching roughly $m=12{,}288$ for some observables. The supplement used an $SU(2)$ calculation as large as $m^*=8192$ multiplets, quoted as roughly $m\simeq32{,}000$ in an equivalent $U(1)$ calculation.

### Important correction about central charge

Central charge was **not absent** from the 2019 work. The supplement attempted finite-entanglement scaling at zero flux on YC8-0 using

$$
S = \frac{c}{6}\ln \xi + a,
$$

along with less reliable fits versus bond dimension. Its effective fitted $c$ drifted downward with increasing bond dimension, and the authors argued for $c\to0$ at zero flux. That is not inconsistent with a 2D DSL: at a fixed finite circumference and a generic flux, no transverse momentum need hit a Dirac node, so the asymptotic quasi-1D system is gapped and has $c=0$.

The sharper open question is therefore **not** “what is the central charge at zero flux?” It is:

> When flux forces one or both Dirac cones onto the cylinder momentum grid, does the optimized state realize the expected critical 1D theory, and what modes survive the gauge constraint and interactions?

## 2. Why the problem is newly open in 2026

The literature does not currently support treating “the intermediate phase is a DSL” as settled.

| Work | Main result relevant here | Consequence for this project |
|---|---|---|
| [Zhu and White (2015)](https://arxiv.org/abs/1502.04831) | Finite-cylinder DMRG supported a nonmagnetic, apparently gapped phase. | Establishes the older gapped-QSL interpretation that must still be discriminated. |
| [Iqbal et al. (2016)](https://arxiv.org/abs/1601.06018) | Optimized projected-fermion states favored the $U(1)$ DSL; a few Lanczos steps made its energy competitive with DMRG. | Motivates using Gutzwiller states as more than qualitative cartoons. |
| [Hu et al. (2019)](https://arxiv.org/abs/1905.09837) | Flux insertion, transfer spectra, and entropy response supported a DSL cylinder state. | Defines the replication target and the HE/DSL-like basin. |
| [Gong et al. (2019)](https://par.nsf.gov/servlets/purl/10139302) | Gave the cylinder mode-counting rule $c=2-1=1$ for one crossed cone per spin and $c\leq3$ when both cones are crossed. | Supplies quantitative targets for flux-tuned finite-entanglement scaling. |
| [Jiang and Jiang (2023)](https://arxiv.org/abs/2203.10216) | Parallel $SU(2)$ DMRG on $L_y=6$–12 favored a gapped $J_1$-$J_2$ state with $c\simeq0$ on long cylinders and showed how short-cylinder fits can strongly overestimate $c$. | Central-charge claims require long systems or controlled infinite-MPS scaling and careful boundary removal. |
| [Sherman, Dupont, and Moore (2023)](https://harvest.aps.org/v2/journals/articles/10.1103/PhysRevB.107.165146/fulltext) | MPS dynamics found low-energy weight at both $K$ and $M$ consistent with DSL expectations, albeit at limited circumference and bond dimension. | Provides a dynamical diagnostic, but not a substitute for state-selection control. |
| [Seifert et al. (2024)](https://www.nature.com/articles/s41467-024-51367-w) | Field theory plus triangular-lattice DMRG found a singular $X$-point response to a $\sqrt{12}\!\times\!\sqrt{12}$ distortion coupled to singlet monopoles. | Gives a ground-state-only probe of an operator not resolved in Hu's spin-triplet spectrum. |
| [Budaraju et al. (2025)](https://arxiv.org/abs/2410.18747) | Constructed projected $Q$-monopole states; singlet and triplet $Q=1$ monopoles become gapless in the thermodynamic limit. | Supplies explicit Gutzwiller excitations for an MPS overlap/subspace program. |
| [Jiang et al. (2026)](https://arxiv.org/abs/2602.14892) | Found two initialization-dependent states on widths 6–9. The higher-energy state is DSL-like; the lower-energy state resembles the $J_2=0$ state statically and dynamically. | Makes competing-basin control the top priority. |
| [Kovalska et al. (2026)](https://arxiv.org/abs/2603.08650) | On YC6, two nearly orthogonal states have different local correlations and qualitatively different spectra, inconsistent with interpreting them as merely two sectors of one gapped $\mathbb Z_2$ phase. | Calls for local-state distances, basin tracking, and not just energy comparison. |
| [Ma et al. (2026)](https://arxiv.org/abs/2606.31021) | Finite-$D$ PEPS optimization found condensed spinons and confined visons in its best symmetric ansatz, ruling out that ansatz's $\mathbb Z_2$ topological order and favoring a gapless/critical interpretation, most naturally a DSL. | Independent tensor-network evidence supports gaplessness but does not resolve the cylinder minima. |
| [Bader et al. (2026)](https://journals.aps.org/prb/abstract/10.1103/rwhz-jf5b) and [Wang et al. (2026)](https://arxiv.org/abs/2601.14458) | Magnetic field produces a finite monopole density near the QSL regime and motivates finite-emergent-flux projected states with chirality and unusual correlations. | Provides a natural later extension for the existing Gutzwiller flux machinery. |

The apparently contradictory results can plausibly coexist if different algorithms, boundaries, and initial states converge to different low-lying basins. Resolving that mechanism is more valuable than producing another single-trajectory energy curve.

## 3. Present repository: strengths and missing controls

### What is already in place

The repository contains a substantial base for this program:

- `ground_state_search_flux_threaded_vumps.jl` implements generalized YC$L_y$-$n$ bonds, seam twists, infinite VUMPS, flux continuation, HDF5 checkpoints, energy, cut entropies, and a neutral transfer spectrum.
- `add_vumps_transfer_sector_spectrum.jl` can add a fixed charge/$S^z$ transfer sector after optimization.
- `ground_state_search_flux_threaded.jl` and the other finite-DMRG drivers provide a complementary long-cylinder route.
- `plot_bond_dimension_convergence.jl` already handles finite-DMRG convergence diagnostics including energy variance, truncation error, and entropy.
- `triangular_gutzwiller_mps.jl` is unusually capable: it includes XC and generalized YC geometries, a $U(1)$ $\pi$-flux DSL, two $\mathbb Z_2$ BdG states, physical spin twist $\theta$, emergent flux $\phi$, and MPS compression.
- `ground_state_search_gutzwiller.jl` and `plot_u1_overlaps.jl` already compute projected-state energies, raw overlaps, and overlap per site.

### What currently prevents a decisive physics result

1. **Only one main iVUMPS basin is seeded.** The current infinite-state initialization is an alternating product state followed by forward flux continuation. There is no standard bank of DSL, $\mathbb Z_2$, 120-degree, stripe, even/odd, reverse-flux, and randomized seeds.
2. **Odd circumferences are blocked in the conserved-$S^z$ path.** A one-ring unit cell with odd $L_y$ cannot have total $S^z=0$. A two-ring unit cell is needed to study the width-7 and width-9 cases emphasized in 2026 work without dropping the useful $U(1)$ symmetry.
3. **The transfer spectrum is not yet operator-complete.** The main trajectory computes a generic/neutral spectrum; a postprocessor adds one selected $S^z$ sector. There is not yet a unified classification by $S^z$ (or total $S$ in an $SU(2)$ backend), transverse momentum, reflection, and operator channel.
4. **Local order diagnostics are sparse in the iVUMPS path.** Bond energy, magnetization, dimer, chirality, and structure-factor fingerprints are needed to tell two locally distinct states apart.
5. **Expensive spectroscopy is coupled to every flux step.** The default run asks for 16 transfer eigenvalues after every optimization step. Most of those solves are unnecessary during coarse continuation.
6. **The current scale is still exploratory.** The launcher defaults to $\chi=512$; the available iVUMPS results inspected here are at $\chi=64$ and $512$, far below the several-thousand-state Hu calculations and modern $SU(2)$ calculations.
7. **The Gutzwiller comparison optimizes the DMRG state independently.** It loads a fixed $U(1)$ state but starts the DMRG search separately, so it does not yet test which DMRG basin the projected state selects.
8. **No repo-local `Project.toml`/`Manifest.toml` was found.** Exact package and algorithm reproduction therefore depends on the ambient Julia environment.

## 4. Project A — competing-state and domain-wall atlas

### Scientific question

Are the low- and high-energy cylinder states:

- finite-$\chi$ versions of one state,
- topological/superselection sectors of one phase,
- two distinct thermodynamic phases separated by a very small energy density,
- or a width-dependent crossover between a DSL and proximate 120-degree order?

### Protocol

Build a versioned seed bank for every target geometry:

- Hu-like forward-flux state;
- reverse-flux state;
- continuation from $J_2=0$ and a 120-degree-pinned finite cylinder;
- continuation from the stripe phase at large $J_2$;
- $U(1)$ DSL Gutzwiller MPS with $\phi=0,\pi$;
- the two implemented $\mathbb Z_2$ Gutzwiller MPS states;
- several randomized low-entanglement states;
- finite-cylinder even/odd edge-spin sectors when applicable.

Run hysteresis scans in both $J_2$ and $\theta$, preserving every converged branch rather than retaining only the lowest energy found in a single scan. Start with YC6 and YC8, then add YC7/YC9 after implementing a two-ring unit cell, and proceed to YC10/YC12 only when the convergence model is credible.

For every branch, record:

- energy density, VUMPS residual or energy variance, and truncation data;
- ring-resolved bond energies, 120-degree and stripe structure-factor proxies, dimerization, and scalar chirality;
- entanglement entropy and full Schmidt values on each inequivalent cut;
- leading correlation lengths in spin, singlet/dimer, and chirality sectors;
- transverse momentum and available discrete symmetries of transfer eigenvectors;
- fidelity per ring and local reduced-density-matrix distance between branches.

Global overlaps are expected to vanish exponentially with cylinder length even for locally similar states. The more informative comparisons are the fidelity density and trace/Bures distances between reduced density matrices on one ring, two adjacent rings, and selected triangles.

### Decisive domain-wall calculation

On a long finite cylinder, initialize one half in the low-energy basin and the other half in the Hu/DSL-like basin, then optimize while monitoring the interface.

- If one state deterministically invades the other, the result estimates the bulk energy preference and the metastability barrier.
- If a stable interface survives, its excess energy gives an interface tension and its quantum numbers may identify a confined spinon or sector-changing defect.
- If local distinctions shrink rapidly with width while only a global sector label remains, the topological-sector interpretation becomes more plausible.

This test is inexpensive compared with full dynamics and directly addresses the central 2026 controversy.

### Success criterion

A publishable result is a width- and $\chi$-controlled statement about whether local differences, energy splitting, and interface tension vanish or survive. “We found two energies” is not enough; the basin map and state-distance scaling are the result.

## 5. Project B — flux-tuned dimensional reduction and central charge

### What central charge means here

This is an **effective 1+1D central charge of a fixed-circumference cylinder**, not a central charge assigned directly to the 2+1D bulk. At generic flux, transverse quantization gaps the cylinder and $c=0$ is expected. At a special $\theta_c$, one or two Dirac cones cross the allowed momentum lines and produce gapless 1D modes.

Before interactions, every left/right complex-fermion channel contributes one unit of $c$. The emergent $U(1)$ gauge constraint removes the total spinon-density mode. The natural targets are therefore:

- **two gapless fermion flavors:** $c=2-1=1$;
- **four gapless fermion flavors:** $c\leq4-1=3$.

The second value is an upper bound, not a promise: allowed interactions, backscattering, compact gauge fluctuations, or a transition to another basin can reduce or eliminate modes. That is precisely why the measurement is interesting.

### Numerical protocol

1. Select one geometry from the two-flavor class and one even-even geometry from the four-flavor class.
2. Obtain both competing basins at $\theta=0$ and continue each toward its predicted $\theta_c$ from both flux directions.
3. Use a dense grid only near $\theta_c$: for example $\delta\theta/\pi=\pm\{1/4,1/8,1/16,1/32,0\}$ after a coarse scan locates the low-gap region.
4. At each selected flux, run a true $\chi$ ladder with warm starts, initially $\chi=256,512,1024,2048,4096$ in the $U(1)$ code and higher only if measured scaling permits it.
5. Measure $S$, the leading physical correlation length $\xi$, Rényi entropies if accessible, Schmidt spectra, and sector-resolved transfer eigenvalues.
6. Fit local slopes

   $$
   c_{\mathrm{eff}}(\chi_i,\chi_{i+1}) = 6\,\frac{S_{i+1}-S_i}{\ln\xi_{i+1}-\ln\xi_i},
   $$

   instead of fitting $S$ directly against $\ln\chi$. Require a stable window with $\xi\gg L_y$, converged local observables, and no basin jump.
7. Perform joint scaling in $\delta\theta$ and $\xi$; a finite physical mass should appear through a crossover controlled by $\xi |\delta\theta|$ up to a nonuniversal velocity/metric factor.
8. Compare transfer-level degeneracies and quantum numbers with the candidate $c=1$ or $c\leq3$ theories. A value of $c$ alone is not an identification.

### Failure modes and how to make them informative

- **Adiabatic collapse before $\theta_c$:** bracket the crossing from both sides, seed directly from a Gutzwiller DSL at the target flux, and report the spinodal line versus $\chi$ and geometry. The collapse itself measures competition between the DSL basin and the alternative state.
- **Finite-$\chi$ pseudogap:** demand that the relevant inverse correlation length decreases systematically with $\chi$ and use multiple transfer sectors.
- **No stable $c$ plateau:** report mode-selective gapping from the transfer spectrum rather than forcing a central-charge fit.
- **Large short-$\xi$ apparent $c$:** discard it. Both the Hu supplement and later long-cylinder work show that preasymptotic fits can be badly misleading.

### Stronger physics target: operator content

The full dimensional-reduction project should track which 2+1D DSL operators become the lowest 1D fields:

- spin-triplet bilinears at $M$;
- spin-triplet monopoles at $K$;
- spin-singlet bilinears at $M$;
- spin-singlet monopoles/VBS fields at the three $X$ points;
- conserved currents and the stress-tensor sector near zero momentum.

Resolve transfer eigenvalues by $S^z$ or total $S$, transverse momentum, reflection where available, and translation along the cylinder. Fit each inverse correlation length near $\theta_c$ rather than only plotting an undifferentiated cloud of eigenvalues. This turns “we see a cone” into a numerical operator dictionary for compactified QED$_3$.

## 6. Project C — singlet-monopole and spin-Peierls response

[Seifert et al.](https://www.nature.com/articles/s41467-024-51367-w) predict that a longitudinal distortion at the three $X$ points couples linearly to the spin-singlet monopole. On a circumference $L_y$ cylinder, the small-distortion energy response scales schematically as

$$
\Delta e_X(\delta)=-A_X(L_y)\delta^2+\cdots,\qquad
A_X(L_y)\propto L_y^{3-2\Delta_\Phi},
$$

where $\Delta_\Phi$ is the singlet-monopole scaling dimension. Generic $K$- or $M$-point distortions should not show the same divergent size dependence.

The published work established the basic effect. A meaningful extension is to make it **state- and flux-resolved**:

1. implement the $X_1,X_2,X_3$ bond modulations and the full $\sqrt{12}\times\sqrt{12}$ pattern in an enlarged iMPS unit cell;
2. apply $\delta$ and $-\delta$ with at least four small magnitudes to remove odd and higher-order contamination;
3. measure $A_X(L_y,\chi,\theta)$ for the low- and high-energy basins separately;
4. use $K$ and $M$ modulations as controls;
5. test whether the DSL-like basin shows growing $X$ response while the low-energy basin cuts it off through a gap or weak order;
6. compare the exponent inferred from the response with the singlet transfer correlation length and with projected monopole states.

This project is lower risk than real-time dynamics, directly targets the least explored Hu operator channel, and can distinguish the two competing states using ground-state calculations alone.

## 7. Project D — Gutzwiller MPS as a microscopic bridge

### Do not center the project on the raw overlap

For $N=L_xL_y$ sites, a perfectly meaningful local match can still have

$$
|\langle\psi_G|\psi_D\rangle|\sim e^{-Nf}
$$

and hence a vanishing raw overlap. The existing `plot_u1_overlaps.jl` correctly also evaluates an overlap per site, but a serious comparison should report:

- fidelity per site or per ring and its $L_x\to\infty$ limit;
- energy and energy variance of the Gutzwiller MPS;
- local reduced-density-matrix distances;
- spin, dimer, and chirality correlators;
- symmetry-resolved transfer spectra;
- independent extrapolations in Gutzwiller compression dimension $\chi_G$ and DMRG dimension $\chi_D$.

### D1. Basin seeding

Use every projected state as an actual DMRG initial state, not only as a post-hoc overlap target. Compare:

- $U(1)$ DSL with optimized $t_2/t_1$, chemical potential, $\phi$, and $\theta$;
- the implemented $\mathbb Z_2$ 0-flux and $\pi$-flux states with optimized pairing;
- 120-degree and stripe reference MPSs.

Record the initial energy/variance, final basin label, energy gained during DMRG, and the fidelity-density trajectory. This directly tests which parton ansatz is adiabatically connected to which numerical minimum.

### D2. Nonorthogonal projected-state subspace

Construct a basis $\{|\phi_i\rangle\}$ containing:

- optimized DSL ground states in both emergent-flux sectors;
- low-energy particle-hole bilinears;
- $Q=1$ singlet and triplet monopoles following [Budaraju et al.](https://arxiv.org/abs/2410.18747);
- selected boundary-twist states;
- the two $\mathbb Z_2$ states.

Contract

$$
N_{ij}=\langle\phi_i|\phi_j\rangle,\qquad
H_{ij}=\langle\phi_i|H|\phi_j\rangle,
$$

discard numerically null directions of $N$, and solve $Hv=ENv$. This “projected configuration interaction” calculation can answer whether a compact set of parton operators spans the DMRG low-energy space and which monopole/bilinear combinations correspond to transfer-matrix levels.

### D3. MPO-Lanczos improvement

Apply one or two compressed Krylov steps,

$$
|\psi(\alpha,\beta)\rangle \propto (1+\alpha H+\beta H^2)|\psi_G\rangle,
$$

and optimize the coefficients in the small nonorthogonal basis. Track energy versus variance and fidelity density to each DMRG basin. This is the MPS analogue of the successful few-Lanczos-step VMC strategy and is more interpretable than simply allowing unconstrained DMRG to erase the trial state.

### D4. Selective dynamics

After identifying the matching basin, compute the Gutzwiller-MPS dynamical structure factor with the same TDVP/correction-vector conventions used for DMRG. A common broadening, time window, momentum convention, and finite-size geometry are essential. The key comparison is the relative low-energy weight at $K$ and $M$, not visual resemblance between differently broadened plots.

### D5. Magnetic-field extension

The existing $\theta,\phi$ machinery is well suited to the 2026 proposal of finite-emergent-flux Gutzwiller states in a Zeeman field. A later project can compare their predicted staggered scalar chirality, 120-degree quasi-long-range correlations, and spin-nematic channel with field-dependent DMRG. This is timely, but it should follow the zero-field validation of the projected-state pipeline.

## 8. Project E — dynamics, once the states are identified

The dynamical question is not merely whether a continuum exists. Compute $S(\mathbf q,\omega)$ for **both** basins with identical numerical resolution and ask:

- Does the Hu-like state retain low-energy weight at both $K$ (monopoles) and $M$ (bilinears)?
- Does the lower-energy state become $K$-dominated and continuously resemble the $J_2=0$ 120-degree state?
- Does the $M$ threshold close under the same flux at which the transfer bilinear gap closes?
- Are the two states separated by spectral-weight transfer or by a true gap closing as $J_2$, $L_y$, or $\theta$ changes?

Use transfer spectroscopy first to select momenta and energy windows. Then run correction-vector DMRG, tangent-space/Krylov dynamics, or TDVP only at those points. This reduces the most expensive part of the program by an order of magnitude relative to scanning the full Brillouin zone blindly.

## 9. Perlmutter strategy

### Hardware reality

Current [NERSC documentation](https://docs.nersc.gov/systems/perlmutter/architecture/) lists each CPU node as two 64-core AMD EPYC 7763 processors with 512 GB RAM and eight NUMA domains total. GPU nodes contain one 64-core EPYC and four A100 GPUs, with 256 GB host memory. NERSC's [affinity guide](https://docs.nersc.gov/jobs/affinity/) distinguishes 128 physical/256 logical CPUs on a full CPU node.

The present launcher requests one shared CPU node allocation with 64 CPUs, 128 GB, 32 Julia threads, BLAS=1, Strided=1, and block-sparse threading off. That is a reasonable conservative pilot configuration, not an optimized production choice.

Perlmutter is newer than the machines used in 2019, but 2D MPS cost still grows approximately as $O(\chi^3)$ in time, $O(\chi^2)$ in memory, and exponentially with circumference at fixed accuracy. Hardware alone will not turn a controlled YC8 calculation into a controlled YC16 calculation. The largest algorithmic multipliers are:

1. non-Abelian $SU(2)$ symmetry;
2. avoiding convergence to the wrong state;
3. measured use of block-sparse threading and NUMA locality;
4. separating optimization from expensive transfer/dynamical postprocessing;
5. operator-level/MPI parallel DMRG for widths that exceed one node.

### Benchmark before production

Add a benchmark mode that times, allocates, and records peak memory separately for:

- MPO/environment construction;
- one VUMPS update or one DMRG half sweep;
- dominant tensor contractions and decompositions;
- neutral and fixed-sector transfer eigensolves;
- HDF5 checkpoint I/O.

On one representative converged YC6 state at $\chi=512$ and $1024$, compare:

- one socket versus a full CPU node;
- Julia threads $1,8,16,32,64,128$;
- block-sparse threading on/off with BLAS=Strided=1;
- a small set of BLAS-threaded dense configurations with Julia/block-sparse threading reduced;
- core versus thread placement and first-touch behavior across NUMA domains.

[ITensors.jl's threading guide](https://itensor.github.io/ITensors.jl/v0.3/Multithreading.html) explicitly warns that Julia/Strided, BLAS, and block-sparse threading compete; it recommends benchmarking one main layer rather than enabling all of them. Store the benchmark result in HDF5/CSV and select job settings by measured time-to-solution, not CPU utilization alone.

Fit empirical models

$$
T(\chi)=a\chi^p,\qquad M(\chi)=b\chi^q
$$

for each geometry and algorithm. Only then convert the proposed run matrix into node-hours. A priori node-hour estimates would be false precision.

### CPU versus GPU

The production $U(1)$ calculation is block sparse. Current [ITensors.jl GPU documentation](https://itensor.github.io/ITensors.jl/v0.6/RunningOnGPUs.html) says dense CUDA tensor operations are well supported, while QN/block-sparse operations remain under active development and may be slower or incomplete. Four GPUs also do not accelerate a single MPS automatically.

Run one controlled single-A100 benchmark for a dense, no-QN YC6 state if desired. Do not plan the production allocation around GPUs unless it beats the symmetry-preserving CPU calculation at equal accuracy. Using all four A100s would require an explicit distributed-tensor or distributed-state algorithm, not only different Slurm flags.

### High-impact code changes before spending a large allocation

1. Add `optimize_only` and `spectrum_only` modes; default to no transfer eigensolve during coarse flux scans.
2. Add an adaptive flux schedule and direct single-$\theta$ warm starts.
3. Add seed/basin labels, reverse continuation, and checkpoint branching.
4. Add a two-ring unit cell for odd circumference with conserved $S^z$.
5. Add local bond, magnetic, dimer, and chirality observables.
6. Store the MPS and converged environments once; run sector spectra as embarrassingly parallel postprocessing jobs.
7. Pin a Julia project and manifest; store the git commit, package versions, random seed, node type, thread settings, initial-state provenance, and convergence residual in every output file.
8. Evaluate a mature non-Abelian $SU(2)$ backend. This is a substantial migration, not a one-line change, but the effective-state reduction demonstrated in modern DMRG is likely more valuable than raw node speed.
9. If YC10/12 remains dominant-cost limited after $SU(2)$ and single-node tuning, evaluate operator-level MPI distribution following the parallel-DMRG strategy, rather than attempting generic multi-node shared memory.

### Staged production campaign

**Stage 0 — correctness and profiling**

- small finite systems cross-checked between finite DMRG, infinite bond tables, and exact diagonalization where feasible;
- twist periodicity and seam orientation tests for several YC shifts;
- CPU threading/NUMA and one optional GPU benchmark;
- reproducible Julia environment and metadata schema.

**Stage 1 — Hu replication and basin discovery**

- YC6 and YC8, representative shift classes;
- $\chi=256$–$2048$ initially;
- forward/reverse flux and at least four physically distinct seeds;
- optimization-only scans, then selected transfer spectra;
- require replication of the expected flux-closing momenta and entropy response before scaling up.

**Stage 2 — decisive scaling**

- targeted $\chi=4096+$ points near predicted $\theta_c$;
- odd widths after the two-ring implementation;
- state-distance and interface calculations;
- central-charge local slopes and singlet $X$-response.

**Stage 3 — width and dynamics frontier**

- YC10/12 only for the few observables that discriminated states at smaller width;
- operator-level parallel/SU(2) code if justified by profiling;
- selected $K$, $M$, and $X$ dynamical calculations for both basins.

## 10. Concrete first 90-day plan

### Weeks 1–2: make replication auditable

- pin the Julia environment;
- add geometry/twist regression tests;
- split optimization from transfer postprocessing;
- write benchmark and run-metadata output;
- reproduce one small-$\chi$ existing trajectory exactly from a clean checkout.

### Weeks 3–5: reproduce the 2019 fingerprints

- run one two-flavor and one four-flavor geometry at $\chi=256,512,1024,2048$;
- confirm the predicted flux location, $K/M$ transfer momenta, and entropy trend;
- compare forward/reverse trajectories and record spinodal collapse;
- do not claim reproduction until the state and observables converge across at least two continuation routes.

### Weeks 6–8: expose the competing minima

- add 120-degree, stripe, random, and Gutzwiller seeds;
- scan $J_2=0.08$–$0.18$ coarsely and refine where branches exchange energy;
- compute local reduced-density-matrix distances and fidelity per ring;
- perform the first finite-cylinder interface calculation.

### Weeks 9–12: start the two most discriminating measurements

- central-charge ladder near one predicted Dirac crossing in each geometry class;
- $X$-, $K$-, and $M$-distortion response for both main basins;
- choose the next allocation campaign based on which observable shows a stable, branch-dependent signal.

## 11. Go/no-go criteria

Continue to expensive width/dynamics runs only if all of the following hold:

- geometry and twist tests pass;
- branch identity survives changes in $\chi$, seed, and sweep direction;
- energy comparisons are extrapolated using residual/variance or truncation error, not raw finite-$\chi$ values;
- central-charge fits use $S$ versus $\ln\xi$ with a stable local-slope window;
- transfer levels carry resolved physical quantum numbers;
- raw overlaps are accompanied by fidelity density and local-state distances;
- wall time and memory scaling are measured for the exact geometry and observable.

Stop or redirect a track if:

- the target state cannot be held near $\theta_c$ under any direct or two-sided seed;
- the apparent central charge drifts monotonically without a controlled scaling window;
- local differences between basins disappear rapidly with $\chi$ before any width scaling;
- the $X$ response does not separate from $K/M$ controls after convergence;
- dynamics would be run on a state whose basin identity is still ambiguous.

## Bottom line

The most meaningful contribution is a **state-controlled compactification study**: determine which variational phase is selected by each cylinder, boundary sector, and initialization; use flux to switch on a known number of Dirac channels; and identify those channels through central charge and operator-resolved transfer spectra. The Gutzwiller code then supplies both physically informed seeds and explicit monopole/bilinear basis states. Perlmutter makes this program practical, but algorithmic state control, $SU(2)$ symmetry, and selective postprocessing will matter much more than a simple increase in requested cores or GPUs.
