# Project B architecture and authority map

This document describes the stable structure of Project B. It is intentionally
separate from `PROJECT_STATE.md`, which changes as runs complete.

## Authority layers

```text
Git-tracked code, controls, documentation, manifests
                         |
                         v
Perlmutter guarded launcher and Slurm allocation
             |                           |
             v                           v
project output: compact evidence    $PSCRATCH: heavy tensors
             |
             v
checksum sync to Windows for analysis and development
```

- Git is the exact code and documentation history.
- Git is also the preferred source transport between Windows and Perlmutter;
  Globus transports ignored run artifacts and selected data. A deliberate
  Git-free export can pass an explicit sealed-source audit, which establishes
  file identity without establishing commit history. Runtime data hashes
  remain mandatory in the full plan.
- Perlmutter is the live scheduler, accounting, run-artifact, and scratch
  authority.
- The project-side `output/` tree contains durable or synchronized compact
  evidence but is ignored by Git and may be stale on another device.
- `$PSCRATCH` holds large restart-only tensors and optimizer checkpoints. It is
  purge-eligible, is not part of routine synchronization, and must be checked
  before a resume.
- Chat is disposable working memory. A result or decision that future work
  needs must be distilled into one of the versioned layers above.

## Runtime environments

Project B deliberately has two Julia environments:

| Environment | Role | Main implementation |
|---|---|---|
| repository root | ITensor infinite-MPS VUMPS, bridge I/O, observables, spectra, plots | `src/`, `scripts/` |
| `idmrg/` | isolated MPSKit one-site iDMRG and diagnostic VUMPS/Grassmann pilot | `idmrg/src/ProjectBIDMRG.jl`, `idmrg/src/SolverPilot.jl`, `idmrg/scripts/` |

Both environments are pinned by their own `Project.toml` and `Manifest.toml`.
They exchange states through explicit, round-trip-validated bridge artifacts;
their dependency graphs are not merged.

The subtree `.gitattributes` pins Bash, Julia, TOML, and control-reference
files to LF so a Windows checkout can be synchronized directly to Perlmutter
without introducing shell-breaking CRLF endings. Existing dirty files are not
bulk-renormalized as part of this policy change.

## Control plane

1. A tracked or generated TOML control declares geometry, representation,
   optimizer, thresholds, schedule, immutable parent path and hash, output
   directory, and provenance.
2. A small `configs/*_active_control.ref`, when used, contains exactly a
   project-relative control path and its SHA-256. It is a pointer, not a copy
   of the control.
3. A launcher `plan` validates the control, referenced hashes, copied-worker
   execution, live queue, prior reconciliation, storage policy, and budget.
4. `submit` creates an immutable project-side job package and submits the
   worker. Direct `sbatch` is outside the supported workflow.
5. `status` consults the live queue or accounting. `reconcile` writes compact
   terminal accounting. `analyze` consumes synchronized evidence locally when
   the campaign provides it.

Because Slurm stages batch scripts outside the repository, every worker is
passed the validated absolute project root. It may not derive the project from
its staged `BASH_SOURCE` path.

The Phase 1 launchers share `scripts/lib/ProjectBAccounting.jl` through
`slurm/lib/project_b_resources.sh`. Allocation rows are deduplicated by job ID
across all declared run roots. Live reconciliation preserves original exports
and appends hash-backed evidence and corrections under `output/accounting/`.
Forecasts include memory rounding; charges use Slurm's allocated CPUs. A
common submission lock, all-Project-B queue check, unreconciled-job check,
Phase 1 ceiling, and project ceiling guard each submission. Other projects'
jobs do not count toward Project B's one-job rule. Julia RSS is measured
inside the `srun` step; accounting retains allocation and step rows.
Live history is queried in contiguous bounded date windows, preserving
whole-job rows and deduplicating boundary records by job ID. A failed window
fails the reconciliation rather than publishing a partial accounting total.

The pilot's `preflight` action runs context validation, live reconciliation,
the selected scratch audit and the full live plan in a child Bash process.
It stops on the first failed check and never submits. Linux hashes use the
system SHA-256 utility, with a streaming Julia fallback; scalar extraction
reuses a hash already verified during the same audit.

All Perlmutter commands, submissions and transfers are run manually by the
owner. Local code prepares the artifacts and commands; a local plan cannot
establish live scheduler or scratch facts.

## Scientific data plane

The main VUMPS flow is:

```text
accepted parent + immutable control
                 |
                 v
       optimizer iterate/checkpoint --------> $PSCRATCH
                 |
                 v
      converged candidate + diagnostics
                 |
        +--------+--------+
        |                 |
        v                 v
 accepted state       rejected state
 may seed theta       numerical seed only
```

Numerical convergence is evaluated before branch continuity. The continuity
policy is declared by the campaign and may combine overlap, entropy, local
energy and magnetization, Schmidt-distribution change, correlation lengths,
U(1) virtual sectors, and forward/reverse agreement. Failure of a numerical or
continuity gate does not, by itself, prove a physical endpoint.

The one-site iDMRG flow uses the same accepted-parent and immutable-provenance
boundary, but its native stopping quantities are MPSKit quantities. Conversion
to the ITensor bridge is an explicit analysis/promotion boundary rather than a
substitute convergence metric.

## Storage classes

The solver pilot has a distinct result schema. It exports AL, C and AR in
the pinned bridge basis, validates left/right isometries, center relations
and energy equality on import, then evaluates common ITensor observables.
It avoids reconstructing a right transfer fixed point from AL alone. Native
MPSKit Galerkin error and Grassmann gradient norm retain separate names.
Tensor checkpoints and candidate payloads stay in scratch; compact histories
and analyses stay in the project. No pilot result automatically changes the
accepted lineage.

| Class | Examples | Location | Routine sync |
|---|---|---|---|
| tracked source | code, TOML templates, docs, manifests | Git checkout | Git |
| compact run evidence | config snapshot/hash, job ledger, `sacct`, logs, scalar histories, state/checkpoint manifests | project `output/` | Globus checksum sync |
| durable scientific state | deliberately selected accepted/rejected bridge required for analysis or provenance | project `output/` | Globus checksum sync |
| transient heavy state | periodic optimizer checkpoints, serialized solver state, redundant full tensors | `$PSCRATCH` | excluded |
| local caches | `.julia/`, `tmp/` | each machine | excluded |

No path alone establishes authority. A restart requires a manifest role, exact
hash, compatible control, and current file presence on the machine that will
run it.

## Repository map

- `src/`: root Julia package, geometry, optimization, continuity, storage,
  scanning, spectroscopy, and iDMRG bridge logic.
- `idmrg/`: isolated MPSKit package and tests.
- `configs/`: immutable or template controls and active references.
- `scripts/`: preparation, validation, analysis, plotting, and the read-only
  cross-system context audit.
- `slurm/`: guarded Perlmutter launchers and worker scripts.
- `test/`: deterministic Julia and launcher regression tests.
- `docs/PROJECT_STATE.md`: current project state and priorities.
- `docs/plans/`: workstream index; detailed plans may remain in established
  top-level campaign documents to preserve links.
- `docs/decisions/`: decision index and future focused records.
- `output/`: ignored run evidence and selected data products.

## Cross-device lifecycle

1. On Perlmutter, finish or quiesce project-tree writers and reconcile terminal
   jobs.
2. Checksum-sync the non-dot project tree from Perlmutter to Windows with
   mirroring/deletion disabled. Do not include `$PSCRATCH` or `.julia`.
3. On Windows, run `scripts/audit_project_context.jl`, inspect Git state, and
   perform analysis or development with PowerShell-compatible commands.
4. Persist current conclusions in `PROJECT_STATE.md`, the relevant plan, and a
   decision record only where their semantic roles require it.
5. Commit and transfer tracked changes through Git. For an existing source
   export, follow [the Git adoption guide](PERLMUTTER_GIT_SYNC.md) without
   replacing its working files. Checksum-sync ignored artifacts separately.
6. Before remote execution, sync Windows to Perlmutter while no job writes the
   destination, then run the live guarded plan.

The generic bootstrap message in `NEW_TASK_PROMPT.md` works on either device
because it routes through repository-relative sources and begins with a
read-only audit. Historical cross-device handoffs remain evidence, not current
entry points.
