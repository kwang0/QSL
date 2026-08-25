# Phase 1 iDMRG library decision

Decision date: 2026-08-22. This comparison was completed before the first
iDMRG result. The selected production solver is **MPSKit 0.13.13 one-site
iDMRG**, isolated from the existing ITensor Julia environment and connected by
a schema-explicit, round-trip-checked HDF5 bridge.

## Decision

| Requirement | ITensor Julia ecosystem | TeNPy 1.1 | MPSKit 0.13.13 |
|---|---|---|---|
| Genuine maintained iDMRG | No current true iDMRG implementation; the infinite package supplies VUMPS/TDVP | Mature one- and two-site infinite DMRG | Current `IDMRG` and `IDMRG2` implementations |
| U(1), complex tensors, period 2 | Existing Project B representation is exact | Supported, but requires Python tensor/model conversion | Supported through TensorKit; period-2 `InfiniteMPS` is native |
| Accepted-state import risk | None, but no solver | Highest: ITensor to NumPy/npc plus an independently reimplemented model | Moderate and explicitly testable: ITensor QN sectors to TensorKit U(1) sectors |
| Diagnostics/restart | Existing VUMPS diagnostics only | Strong public simulation/checkpoint/resume support | Native environment/center error and update history; Project B adds immutable periodic serialized checkpoints |
| Perlmutter CPU compatibility | Existing stack works | Linux/x86_64 and normal CPU Python stack are compatible | Normal Julia CPU stack; no service or login-node computation required |
| Reproducibility | Existing manifest | Python environment must be added and pinned | Separate exact Julia manifest pins MPSKit 0.13.13 and TensorKit 0.17.1 |
| Branch-fidelity verdict | Solver unavailable | Rejected for the first control because conversion/model risk is avoidable | **Selected** |

The ITensor documentation itself distinguishes infinite DMRG/VUMPS from the
implemented finite DMRG workflow and states that ITensor does not currently
provide true periodic DMRG. The current `ITensorInfiniteMPS.jl` dependency in
this repository is therefore not silently relabeled as iDMRG. See the
[ITensor DMRG FAQ](https://github.com/ITensor/ITensorMPS.jl/blob/main/docs/src/faq/DMRG.md)
and the [ITensorInfiniteMPS source](https://github.com/ITensor/ITensorInfiniteMPS.jl).

TeNPy is a production/stable package with a mature infinite-DMRG engine,
charge-conserving tensors, and checkpoint/resume machinery. It is a credible
alternative, not a straw candidate. The relevant primary sources are the
[DMRG engine API](https://tenpy.readthedocs.io/en/stable/reference/tenpy.algorithms.dmrg.DMRGEngine.html),
[simulation/checkpoint documentation](https://tenpy.readthedocs.io/en/latest/intro/simulations.html),
[charge-conservation documentation](https://tenpy.readthedocs.io/en/latest/intro/npc.html),
[official infinite-DMRG example](https://github.com/tenpy/tenpy/blob/main/examples/d_dmrg.py),
and [upstream releases](https://github.com/tenpy/tenpy/releases). It was not
selected because the branch-sensitive first control would require both a
cross-language state conversion and an independent Python reconstruction of
the long-range period-2 YC8-1 Hamiltonian. Its checkpoint advantage does not
outweigh those two extra scientific equivalence risks here.

MPSKit has genuine one- and two-site infinite DMRG in the current source, a
native period-2 infinite MPS, and TensorKit U(1) block spaces. See the
[IDMRG implementation](https://github.com/QuantumKitHub/MPSKit.jl/blob/main/src/algorithms/groundstate/idmrg.jl),
[stable MPSKit documentation](https://quantumkithub.github.io/MPSKit.jl/stable/),
[release history](https://github.com/QuantumKitHub/MPSKit.jl/releases), and
[TensorKit symmetric-tensor documentation](https://quantumkithub.github.io/TensorKit.jl/stable/man/tensors/).
This gives the first control a real iDMRG algorithm while keeping the state and
model conversion inside Julia.

## Environment isolation

MPSKit is not added to the repository's root `Project.toml`. The pinned root
ITensor stack resolves `VectorInterface` 0.5, whereas TensorKit 0.17.1 in the
selected MPSKit stack resolves `VectorInterface` 0.6. Mixing them in one Julia
process is therefore both dependency-incompatible and harder to audit.

The isolated `idmrg/Project.toml` and `idmrg/Manifest.toml` are the production
environment. The root process owns ITensor state I/O and Project B observables;
the isolated process owns TensorKit conversion and iDMRG. Their HDF5 bridge
records:

- the accepted parent path and SHA-256;
- every left-canonical tensor in explicit left/physical/right axis order;
- the charge of every basis vector, not merely unordered sector counts;
- every period-2 bond, coupling, anisotropy, and uniform-twist charge;
- the ITensor parent energy under the target theta/pi=0.2 Hamiltonian.

On import, each axis is permuted into TensorKit's actual sector order and then
permuted back. The dense tensor must round trip at relative tolerance `5e-13`.
Before any solver update, the MPSKit target-Hamiltonian energy density must
agree with ITensor within absolute tolerance `1e-6`. The locally measured
difference is `7.97e-8`; the looser gate accommodates independent infinite-MPO
environment solves while still rejecting the source/target-axis twist error,
which shifted the energy by `2.00e-3`. Either gate failure aborts the run.

## Algorithm and convergence semantics

The first control uses one-site iDMRG at fixed chi 512. This is intentional:
it preserves the accepted parent's virtual spaces and isolates the outer
optimization algorithm. There is no two-site SVD truncation, so discarded
weight is **exactly zero by construction**. That zero is recorded with its
semantics and is not a quality claim. In particular, it is never compared to
or called the VUMPS projected residual.

The native criteria were fixed before the result:

1. at least four complete iDMRG iterations;
2. MPSKit bond-matrix update norm at most `1e-8`;
3. energy-density span at most `1e-9` over the final four iterations;
4. achieved maximum bond dimension exactly 512 throughout that window;
5. finite histories and a valid immutable checkpoint chain.

For pinned MPSKit 0.13.13, the one-site iterator computes its reported
superblock increment as `DeltaE = (E_new - E_old) / 2`. In this period-2
control, the intensive history used by criterion 3 is that reported increment
divided by the MPS period. The growing `IDMRGState.energy` is a cumulative
superblock quantity and is retained only as a diagnostic; its value divided by
the period must not be used as the stationarity history. This distinction was
discovered while reconciling the first production trajectory. It corrects the
recorded semantics without loosening the predeclared `1e-9` span threshold.

The same pinned iterator defines its stopping value after a sweep by retaining
the old center matrix `C_old` and evaluating `norm(C - C_old)` (or the
common-subspace version if the spaces differ). See the upstream
[iDMRG implementation](https://github.com/QuantumKitHub/MPSKit.jl/blob/main/src/algorithms/groundstate/idmrg.jl)
and the pinned [v0.13.13 release](https://github.com/QuantumKitHub/MPSKit.jl/releases/tag/v0.13.13).
Project B originally serialized this under `environment_error`; that path is
retained for compatibility, but the value is not an environment residual.

Scientific continuation eligibility then separately requires overlap per site
at least `0.99` against the accepted theta/pi=0.15 state, common energy,
entropy, magnetization, Schmidt, and U(1)-sector diagnostics, and an immutable
accepted/rejected output. A one-iteration sequential-VUMPS probe is recorded as
a common projected-stationarity diagnostic, but its returned tensor is
discarded and it is not an iDMRG convergence variable.

## Known limitation

MPSKit 0.13.13 does not expose a stable per-iteration public callback for
IDMRG; the upstream discussion is tracked in
[issue 503](https://github.com/QuantumKitHub/MPSKit.jl/issues/503). Project B
therefore pins the exact version and uses the package's internal `IDMRGState`
and `IterativeSolver`. The first control checkpointed every five iterations;
the continuation checkpoints every 20 iterations and at native convergence.
Each checkpoint
stores the exact serialized solver state, full histories, control hash, bridge
hash, and MPSKit version. Resume is deliberately refused under another
MPSKit/control/bridge version. This is a controlled integration cost, not an
API-stability guarantee.

## First production outcome and continuation decision

Perlmutter job `57452187` completed successfully at the scheduler/process
level after 6,567 seconds, but its 80-iteration candidate did not meet the
predeclared iDMRG-native gates. The corrected final four-iteration intensive
energy span is `6.930349628e-9`, and the final bond-matrix update norm is
`3.781953625e-5`; both exceed their respective `1e-9` and `1e-8` thresholds.
Discarded weight remains exactly zero only because this is fixed-space
one-site iDMRG and is not evidence of convergence.

The independent ITensor-side analysis nevertheless finds parent overlap per
site `0.9999707484`, unchanged U(1) sector multiplicities, mean entropy change
`+0.0077082662`, magnetization RMS jump `9.472047e-5`, and energy-term RMS
jump `0.002368042`. The state is therefore a smooth primary-forward numerical
seed, but it remains explicitly rejected/nonconverged and cannot replace the
accepted theta/pi=0.15 lineage parent. Continuing from its tensors is the
lowest-risk scientific next step because it changes only optimizer progress,
not the branch, model, symmetry, gauge, period, or chi.

Late-iteration fits from the first job motivated a guarded successor with up
to 400 additional iterations. Perlmutter job `57500598` completed all 400:
the final-four intensive-energy span improved to `1.222133506e-12`, but the
bond-matrix update norm remained `2.311348784e-6`. It decreased monotonically
over the last 100 iterations and reached its run minimum at iteration 400, so
the result is slowly contracting rather than plateaued, but it remains
native-nonconverged under the unchanged `1e-8` gate.

After reviewing job `57500598`, the project owner selected a working
exploratory profile for subsequent decisions: bond-matrix update norm at most
`1e-5` and final-four intensive-energy span at most `1e-8`. The completed
job passes both working thresholds. This is explicitly a post-hoc sensitivity
classification, not a rewrite of its immutable predeclared control and not a
branch promotion. The exact policy is pinned in
`configs/phase1_idmrg_working_convergence.toml`; future controls may predeclare
that profile, while overlap, observables, U(1) sectors, and primary-forward
continuity remain required.

Because native failure is decisive, current analysis now skips ITensor
canonicalization and all promotion-only branch diagnostics for this result.
Detailed `sacct` also showed that the 128-thread exclusive-node request was
severely oversized. A guarded 2/4/8/16-thread Shared-QOS benchmark must run
before any further continuation. Heavy serialized scientific checkpoints are routed to
Perlmutter scratch; the home package receives the restartable final bridge and
an automatically generated lightweight manifest/history artifact. Scratch is
working storage rather than an archive, so accepted scientific states and
their compact provenance remain in home/local durable copies.

## Revisit conditions

Reconsider TeNPy if MPSKit fails on Perlmutter for a library-specific reason,
if its serialized restart cannot be restored under the exact pinned stack, or
if the cross-stack Hamiltonian equivalence gate cannot be made exact. Do not
switch merely because another seed reaches lower energy; branch identity and
the accepted theta/pi=0.15 lineage remain the governing scientific controls.
