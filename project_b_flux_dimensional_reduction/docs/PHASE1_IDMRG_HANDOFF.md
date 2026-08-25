# Phase 1 iDMRG handoff

> Status update, 2026-08-23: this file remains the immutable pre-run handoff.
> First iDMRG job `57452187` has since been reconciled and analyzed; it stayed
> on the primary branch but failed native convergence. The guarded
> scratch-backed successor and current operator commands are in
> `docs/PHASE1_IDMRG_CONTROL.md` and `docs/PHASE1_IDMRG_STORAGE.md`.
>
> Cross-device update, 2026-08-25: the current operational handoff is
> `docs/PHASE1_CROSS_DEVICE_HANDOFF.md`, with a copyable new-chat bootstrap in
> `docs/PHASE1_CROSS_DEVICE_NEW_CHAT_PROMPT.md`. Read those files rather than
> treating this historical pre-run snapshot as current status.

## Purpose

Phase 1 has exhausted the approved YC8-1, chi-512 parallel-VUMPS recovery.
The next task is to select a well-maintained iDMRG implementation that is
compatible with Perlmutter, integrate it without weakening branch provenance,
and prepare one controlled `theta/pi=0.2` comparison. Do not submit a job while
implementing unless the project owner explicitly asks for submission.

This handoff is intentionally self-contained. Read `AGENTS.md` first; it is the
authoritative operating contract for local-versus-Perlmutter evidence, branch
lineage, budget safety, and the existing guarded launcher.

## Current scientific decision

The VUMPS campaign should not receive another automatic or manual VUMPS retry.
Promoted parallel-VUMPS job `57392725` reached the approved `0.05*pi` step
floor on the interval from `theta/pi=0.15` to `0.2` and stopped with
`numerical_divergence_not_physical_endpoint`. The reconciled scheduler state
was `COMPLETED`, the worker exit code was zero, and the allocation cost
`0.166842448` node-hours. This was a guarded scientific stop, not an
infrastructure failure.

At `theta/pi=0.2`, the VUMPS residual decreased from `4.348976e-4` to a minimum
of `1.1923679290224237e-5` at iteration 15, missing the fixed `1e-5` gate by
19.24 percent. It then increased to `1.0306140572661495e-3` at iteration 46.
Best-iterate restoration correctly saved iteration 15 as a **rejected
diagnostic**, and all 276 recorded inner Krylov solves converged. No targets
from `0.3` through `1.0` were attempted.

A read-only retrospective comparison of the restored `0.2` candidate against
the accepted `0.15` parent found:

- mixed-transfer overlap per site `0.9999746790358569` (gate `0.99`);
- energy-density change `+1.250026265442461e-5`;
- mean-entropy change `+0.008073718223907456`;
- maximum cut-entropy jump `0.009208169577808789`;
- mean Schmidt-distribution total variation `0.0030527250415827833`;
- no new or removed virtual U(1) sectors and no multiplicity changes on either
  bond.

These diagnostics strongly favor an outer-VUMPS fixed-point instability over
a physical endpoint or demonstrated branch jump. They do **not** make the
`0.2` tensor acceptable for continuation, because it failed the residual
gate.

## Immutable provenance

The authoritative accepted continuation parent remains `theta/pi=0.15`:

- local synced path:
  `output/phase1_tests/yc8_1/parallel_update_p0p10000000_to_p0p15000000_chi512_f71fc084883e_b5ef48caaf7a/chi512/states/state_0001_yc8-1_primary_forward_chi512_legacy_0p1_independent_theta0_alternating_chi512_forward_seed101_chi512_theta_p0p15000000_accepted_aca60c183c9d.h5`;
- Perlmutter path recorded in the artifacts:
  `/global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction/output/phase1_tests/yc8_1/parallel_update_p0p10000000_to_p0p15000000_chi512_f71fc084883e_b5ef48caaf7a/chi512/states/state_0001_yc8-1_primary_forward_chi512_legacy_0p1_independent_theta0_alternating_chi512_forward_seed101_chi512_theta_p0p15000000_accepted_aca60c183c9d.h5`;
- SHA-256:
  `38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`.

The restored but rejected `theta/pi=0.2` diagnostic is:

- local synced path:
  `output/phase1/yc8_1/chi512_parallel_promoted_from_p0p15000000_38312fc996fe/seed_101/chi512/states/state_0001_yc8-1_primary_forward_chi512_legacy_0p1_independent_theta0_alternating_chi512_forward_seed101_chi512_theta_p0p20000000_rejected_91757de84243.h5`;
- SHA-256:
  `f59dd18f29004d259a3d94e7bedadd99a7fcb88b1ba960fb7e357dd8e645e7c0`.

It may be tested as a numerical optimizer seed, but it must remain labeled
rejected. The accepted `0.15` state must remain the lineage parent and overlap
reference in every resulting artifact.

Canonical run evidence:

- `output/phase1_jobs/20260822T004151Z-yc8-1-primary_forward_chi512_legacy_0p1-512/logs/scan-57392725.out`;
- `output/phase1/yc8_1/chi512_parallel_promoted_from_p0p15000000_38312fc996fe/seed_101/chi512/scan_outcome.toml`;
- `output/phase1_jobs/20260822T004151Z-yc8-1-primary_forward_chi512_legacy_0p1-512/automatic_advance.toml`;
- `output/phase1_jobs/20260822T004151Z-yc8-1-primary_forward_chi512_legacy_0p1-512/sacct.tsv`.

The project owner explicitly reported that these artifacts were freshly synced
from Perlmutter on 2026-08-22. Future runs still require fresh Perlmutter
evidence under `AGENTS.md`; do not assume the local mirror remains current.

## Repository state to preserve

At handoff time the checkout contains uncommitted Phase 1 launcher,
automation, test, and documentation changes. Inspect `git status` before
editing and preserve all user/existing work. In particular, launcher 2.7.0 and
the parallel-promotion files encode the evidence above and must not be removed
merely because the next solver is iDMRG.

The current Julia environment uses Julia 1.12 and depends directly on
`ITensors`, `ITensorMPS`, and `ITensorInfiniteMPS`; see `Project.toml` and
`Manifest.toml`. Existing state artifacts serialize an
`InfiniteCanonicalMPS` with U(1)-symmetric ITensor indices. Library selection
must account for conversion fidelity rather than comparing solver names in
isolation.

## Required library-selection research

Before implementation, compare actively maintained iDMRG options using current
primary sources: official documentation, upstream repositories, release
metadata, and method papers. At minimum investigate the current ITensor Julia
ecosystem, TeNPy, and any actively maintained Julia alternative that genuinely
implements infinite DMRG rather than only finite DMRG or VUMPS.

The decision should explicitly score:

1. a production-quality one-site or two-site iDMRG implementation;
2. U(1)-block-sparse tensors and complex Hamiltonians;
3. a period-2 infinite unit cell for the YC8-1 mapping and uniform twist gauge;
4. ability to import the accepted ITensor state, or a validated representation
   conversion that preserves physical basis, charge conventions, gauge, and
   branch identity;
5. convergence, truncation, checkpoint, and restart diagnostics;
6. CPU operation on Perlmutter's x86_64 Linux nodes without login-node work or
   unsupported services;
7. reproducible dependency pinning and long-term maintenance;
8. integration cost and the ability to write Project B's immutable HDF5
   provenance and observables.

Do not choose a library solely because it is in the current language. If the
best implementation is Python-based, first prove that state/model conversion
is exact enough for this branch-sensitive comparison. Conversely, avoiding a
cross-language conversion is a major advantage only if the Julia solver is a
real, sufficiently tested iDMRG implementation.

## First controlled iDMRG target

The first scientific run should be isolated to `theta/pi=0.2`, YC8-1,
`J1=1`, `J2=0.12`, `Delta1=Delta2=1`, `Bz=0`, uniform twist gauge, period 2,
and nominal chi 512. It should start from or be rigorously derived from the
accepted `0.15` parent. A separate diagnostic initialization from the restored
`0.2` VUMPS tensor is permissible only if provenance distinguishes the two.

Define iDMRG-native convergence criteria before seeing the result. At minimum
record energy-density stability, discarded weight and achieved bond
dimensions, sweep/update history, environment convergence, and checkpoint
provenance. Where technically meaningful, evaluate the resulting state with a
common stationarity or projected-residual diagnostic. Do not equate iDMRG
discarded weight numerically with the VUMPS residual.

Scientific acceptance must additionally preserve the existing branch checks:

- parent overlap per site at least `0.99`, evaluated against accepted `0.15`;
- smooth energy, entropy, magnetization, and Schmidt-spectrum changes;
- sector-resolved virtual U(1) diagnostics;
- immutable state hashes and explicit accepted/rejected status;
- no replacement of the primary-forward metastable lineage merely because a
  different basin has lower energy.

## Implementation and handoff deliverables

1. Write a source-backed library decision with limitations and conversion
   risks.
2. Add an isolated iDMRG solver path; preserve the existing VUMPS path.
3. Add a one-point chi-512 config/generator pinned to the accepted parent hash.
4. Add restartable checkpoints and schema-explicit diagnostics.
5. Extend the guarded Slurm workflow with plan/submit/reconcile support and
   fail-closed resource/budget checks. Do not make iDMRG an unattended solver
   transition.
6. Add unit, parser, state-conversion, and launcher regression tests.
7. Update `PHASES_0_TO_4.md` and add exact Perlmutter synchronization,
   generation, planning, submission, monitoring, reconciliation, and analysis
   commands.
8. Validate locally in proportion to risk, but clearly distinguish parser or
   conversion tests from a live Perlmutter scientific run.

The new task should implement through a locally validated, documented
submission package, then stop for the project owner's explicit remote
submission authorization.
