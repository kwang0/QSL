# 009 - Compare three limited-relaxation scans through pi

Status: accepted; implementation prepared for manual execution.
Date: 2026-09-10.

## Context

Decision 008 found near-return of local observables but spectral memory and
growing staggered magnetization in the short forward-and-return test. The
owner now prioritizes the original Fig. 2/3 objective over another short loop:
use a fixed 0.1pi flux step and exactly three budgets, 2, 4 and 8 updates per
point, reaching theta=pi. This supersedes the unprepared 0.35-loop proposal,
without changing the interpretation of the completed evidence.

## Decision

Prepare three independent chi512 VUMPS scans from the SHA-verified accepted
theta/pi=0.15 parent. Use the initial half-step to 0.20 and then 0.30,...,1.00.
There is no new zero-flux preparation, fourth baseline, endpoint hold or return
leg. Preserve every iterate but analyze only origins and flux endpoints.
Compare charged correlation spectra and their momentum locations, together
with drift diagnostics. Continue the finite diagnostic schedule through native
and continuity gate failures; keep all states unaccepted.

The user additionally authorized 50 node-hours and asked that budget not cut
this job short. Add 50 to the project ceiling and make it available to Phase 1:
200 project hours, 190 automatic-submission hours (same 10-hour reserve),
70 Phase 1 hours. The three-arm shared-QOS allocation requests the 48-hour
scheduler maximum, costing at most 1.875 hours. Remove the proposed separate
16-hour solver cutoff. Preserve the existing near-timeout checkpoint signal,
queue/lock/accounting checks and numerical failure handling.

## Consequences and interpretation

The experiment tests whether qualitative Fig. 3 features survive this finite
relaxation protocol across a wide flux range and across update densities.
Larger flux steps are untested, and earlier data warn that additional updates
can amplify magnetic drift. Agreement among scans would be useful evidence;
reaching pi or attaining a small residual alone is insufficient.

The [paper](https://arxiv.org/pdf/1905.09837) reports actual excitation energies
in Fig. 2 and transfer correlation spectra in Fig. 3. These runs provide the
latter measurement on diagnostic chi512 states. Fig. 2 still needs the separate
embedded-window excited-state solver. Nothing here demonstrates the paper's
larger bond dimensions or reproduces its unpublished iteration stopping rule.

One allocation runs the three scientific scans sequentially, and attempts
later arms after an earlier step fails. Completion is explicit in the compact
summary; no automatic resubmission or accepted-lineage promotion is introduced.
The full-grid recipe and runtime are sealed separately from completed controls.
Only the explicitly authorized common budget policy changes among their pinned
inputs; historical controls and evidence are preserved at their Git revisions.

## Evidence and execution

- [Full-flux plan](../plans/FULLFLUX_CONTINUATION.md): exact schedule, resources,
  selected validation and owner-run commands.
- [Decision 008](008-roundtrip-continuation-outcome.md): completed short-loop
  evidence and limitations.
- [Decision 004](004-yc8-1-figure-reproduction-feasibility.md): measurement and
  bond-dimension requirements.
- [NERSC queue policy](https://docs.nersc.gov/jobs/policy/): shared-QOS wall-time
  limit and fractional-node charging.
