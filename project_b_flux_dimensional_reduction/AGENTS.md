# Project B operating rules

These instructions apply to every task under this directory. They contain
durable rules only. Current jobs, hashes, endpoints, open questions, and next
priorities belong in `docs/PROJECT_STATE.md`.

## Resume contract

Before substantive work in a fresh task or on a different computer:

1. Read `docs/PROJECT_STATE.md` and `docs/ARCHITECTURE.md` completely.
2. Run `julia --startup-file=no scripts/audit_project_context.jl` from this
   directory and report its Git, control-reference, and local-mirror findings.
   For a deliberate Git-free source export, use the active plan's explicit
   `--source-export CONTROL` mode. It validates sealed source hashes without
   claiming Git history; the full plan must still validate data hashes.
3. Read the active plan and decision sources linked from the project-state
   file. Read older phase documents only when the state file routes to them.
4. Establish any live scheduler or scratch fact on Perlmutter before relying
   on it. The local `output/` tree is only a possibly stale mirror.

Do not ask the project owner to reconstruct an old conversation. Conversation
history is working memory, not project authority. Preserve every existing
worktree change unless the owner explicitly asks to discard it.

## Operating environments and authority

- The owner's local computer is Windows and its interactive shell is
  PowerShell. Do not assume `bash` is installed locally.
- Perlmutter is a separate Linux system. Commands under `slurm/` are Bash
  commands for the owner's interactive Perlmutter SSH shell. Clearly label
  local and remote commands.
- The owner always runs Perlmutter commands manually. Do not initiate SSH,
  remote commands, jobs, or transfers. Prepare tested commands for the owner
  and request the smallest required output while continuing local work.
- Never put `set -e` or `set -euo pipefail` in commands intended for that
  interactive SSH shell. A normal missing-file check must not terminate the
  connection.
- Perlmutter is authoritative for the live queue, job state, scheduler
  accounting, scratch contents, run directories, logs, and newly generated
  artifacts. A user-confirmed, completed checksum sync makes the copied files
  valid retrospective evidence; it does not make the local machine a live
  scheduler or scratch authority.
- Git is authoritative for exact code and documentation history. Do not copy
  commit history into the rolling state file; inspect Git when exact history
  matters.
- Before a decision based on a recent run, obtain the smallest relevant remote
  evidence: normally launcher `status`, `reconcile`, or `plan` output plus the
  terminal outcome/log and any proposed restart hash. Never change a restart
  parent from an unverified local path or modification time.

## Scientific invariants

- Preserve the labeled primary-forward metastable lineage. A lower-energy
  competing basin never replaces it automatically.
- The controlled main representation is U(1)-conserving YC8-1 with the minimal
  period-2 MPS and uniform twist gauge. Algorithm, geometry, unit cell, bond
  dimension, gauge, and tolerance choices are campaign-scoped and may not be
  generalized silently.
- The exact current accepted parent and all current candidate hashes are in
  `docs/PROJECT_STATE.md` and their immutable artifacts. Changing the lineage
  parent requires explicit owner direction and hash verification on
  Perlmutter.
- Rejected VUMPS or iDMRG states and optimizer checkpoints remain explicitly
  labeled numerical seeds or diagnostics. They do not become accepted lineage
  parents merely because they have lower energy or help a later optimizer.
- A scientific promotion requires the numerical gate and the campaign's
  declared branch-continuity policy. Preserve forward/reverse comparisons and
  all U(1)-resolved diagnostics required by that policy.

## Numerical vocabulary

- A VUMPS projected residual, an iDMRG bond-matrix update norm, discarded
  weight, and an inner-Krylov residual are different quantities. Never rename,
  compare, or substitute one for another without an explicit derivation.
- MPSKit one-site iDMRG stops on `norm(C_new - C_old)` after a complete sweep.
  The legacy HDF5 field `environment_error` is retained only for compatibility
  and must not be described as an environment residual.
- One-site fixed-space iDMRG has zero discarded weight by construction; zero
  does not establish convergence.
- Native iDMRG convergence uses the period-normalized superblock-energy
  increment, not cumulative `IDMRGState.energy`.
- Continuity thresholds are numerical trust-region rules, not physical phase
  boundaries. Their provenance and scope must stay attached to the relevant
  control and decision document.

## Mutations, launchers, and budget guards

- Use the concise guarded launcher interface documented by the active plan:
  `preflight` where provided, `plan`, `submit`, `status`, `reconcile`, and
  `analyze`. Do not bypass its
  one-job, immutable-output, control-hash, or node-hour checks with direct
  `sbatch`.
- A successful live `plan` is the required preflight immediately before a
  submission. Local `plan` output validates structure only; it is not live
  Perlmutter accounting.
- The project owner has standing authorization for guarded Project B
  submissions after a successful live plan, including the Phase 1 iDMRG and
  campaign launchers. Provide the owner both guarded `plan` and `submit`
  commands with submission conditional on a successful live plan; the owner
  executes them manually. Do not request another submission approval or add
  a redundant acknowledgement variable. This does not
  authorize cancellation, deletion, pruning, threshold changes,
  lineage-parent changes, or an unguarded automatic advance.
- Honor any later standing authorization recorded in
  `docs/PROJECT_STATE.md`. Do not infer broader authority from an older prompt
  or historical handoff.
- When no `RUN_ID` is supplied, resolve the greatest job ID recorded in remote
  `job.tsv` files rather than trusting `latest_run.txt`, which a stale sync can
  overwrite.
- Reconcile every terminal predecessor and use Slurm's actually allocated CPU
  count for Shared-QOS charge calculations. Stop if the live budget guard and
  the compact accounting evidence disagree.
- Slurm executes a copied batch script from a spool directory. Workers must
  receive and validate the absolute project root and must never infer it from
  their own `BASH_SOURCE`. A launcher preflight must execute the copied worker
  path, not merely inspect its source.

## Storage and synchronization

- Route heavy transient solver data to Perlmutter `$PSCRATCH`: VUMPS/iDMRG
  checkpoints, serialized optimizer objects, and large restart-only tensors.
  Request the Slurm `scratch` license when a job uses it.
- Keep only compact controls, manifests, hashes, scalar histories, logs,
  accounting, and deliberately selected durable scientific states in the
  project tree. Do not create redundant full-state copies under `output/`.
- Scratch is purge-eligible and not backed up. Before removing a scratch
  package, deliberately promote any reviewed state needed for continuation or
  publication and verify its hash and compact manifest.
- Use Git push/pull for local-to-Perlmutter source, documentation and prepared
  launch inputs. Store compact sealed controls under `configs/controls/` and
  track any other compact manifests needed to launch, together with their
  references. Verify delivery from a Git checkout without local ignored output
  before handing off a run. Preserve the existing remote directory when
  adopting Git; do not use a hard reset or a forced checkout to align it.
- A separate source worktree may link to the canonical ignored `output`
  directory. Such worktrees share the same evidence, submission lock and
  project budget; they are not independent campaigns. Keep the repository
  holding their common Git metadata and the canonical output directory intact.
- Use checksum-verified Globus transfers when run results or selected durable
  scientific data are needed on the other computer. Keep destination
  mirroring/deletion off; exclude tracked source, `.git`, other dot directories,
  `.julia`, and `$PSCRATCH`. A source export may use checksum sync during Git
  setup. Do not substitute `rsync` unless requested. A prepared launch control
  must arrive through Git; routine local-to-Perlmutter updates must not depend
  on a separate control transfer. Live reconciliation generates accounting
  evidence on Perlmutter before the guarded plan.
- A job already submitted under an older storage policy is not canceled just
  to migrate its checkpoint path. Apply the policy to its successor.

## Environments and implementation boundaries

- The root `Project.toml`/`Manifest.toml` are the ITensor/VUMPS environment.
  `idmrg/Project.toml`/`idmrg/Manifest.toml` are the isolated MPSKit iDMRG
  environment. Do not merge them.
- Preserve immutable control snapshots, state hashes, rejected classifications,
  original versus exploratory convergence profiles, and accounting evidence.
- Validate changes in proportion to risk. At minimum, inspect the final diff
  and run the relevant Julia or launcher tests. Report every check that could
  not be run locally.

## Durable documentation roles

- `AGENTS.md`: stable behavior, invariants, and safety rules. Do not add dated
  job history here.
- `docs/PROJECT_STATE.md`: rolling objective, current endpoints, live unknowns,
  known issues, and ordered priorities. Update it after substantial work that
  changes any of those facts.
- `docs/ARCHITECTURE.md`: stable module, environment, authority, and data-flow
  design. Update it only when the design changes.
- `docs/decisions/`: index and records explaining non-obvious durable choices.
- `docs/plans/`: index of active, paused, and completed execution plans. Keep
  discoveries and checklist progress in the relevant plan, not in chat alone.
- Git: exact implementation history. Use focused commit messages; do not
  duplicate diffs in documentation.
- `docs/NEW_TASK_PROMPT.md`: generic bootstrap text for a fresh conversation or
  device. It must point to current repository sources and must not embed a
  soon-stale job status.

At the end of substantial work, update only the semantic layer that changed.
Persist durable discoveries and decisions; omit transient debugging narration.
