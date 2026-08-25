# Project B operating rules

These instructions apply to every task under this directory.

## Perlmutter is the run-data authority

- Treat the local checkout as a possibly stale or partial mirror of Perlmutter.
  Never assume local `output/`, `output/phase1_jobs/`, logs, HDF5 states,
  `latest_run.txt`, job ledgers, or reconciled charges reflect the latest remote
  run.
- Perlmutter is authoritative for scheduler state, run directories, artifacts,
  state hashes, logs, residual histories, and `sacct` accounting.
- A local artifact may be used for code compatibility tests or retrospective
  analysis only. Label that evidence as local and potentially stale; do not use
  it to infer the current remote endpoint or whether a remote artifact exists.
- Before making a decision that depends on a recent run, ask the user for the
  minimal relevant Perlmutter evidence or ask them to sync the relevant files.
  Typical evidence includes `run_scan_cpu.sh status`, `reconcile` or `plan`
  output, `scan_outcome.toml`, the job log tail, and `sha256sum` for a proposed
  restart parent.
- Do not change a restart parent path or pinned SHA-256 based only on the local
  mirror. Use a hash reported from Perlmutter or explicitly supplied by the
  user.
- Local launcher `plan` output validates parsing and safeguards only. Its job
  ledger and budget fields are not live Perlmutter accounting.
- Remind the user that local code/config changes must be synchronized to
  Perlmutter before a remote `plan` or `submit`.
- The project owner normally transfers the complete non-dot project tree with
  Globus checksum sync. The established cycle is Perlmutter-to-Mac first, wait
  for completion, make local changes while no project job is writing the tree,
  then Mac-to-Perlmutter before remote `plan`. Keep destination mirroring or
  deletion disabled, ignore dot directories such as `.git` and `.julia`, and
  never include `$PSCRATCH` in the routine project-tree transfer. State the
  direction and these conditions rather than requiring a long per-subdirectory
  selection list. Do not substitute an `rsync` command unless requested.
- Never put `set -e` or `set -euo pipefail` in commands intended for the
  owner's interactive Perlmutter SSH shell: an ordinary missing-file error can
  terminate the whole connection. Run a non-exiting preflight first, print
  every missing path, and give the mutating command only after the complete
  Globus code-and-data transfer list has been stated.
- Route heavy iDMRG solver checkpoints to the operator's Perlmutter
  `$PSCRATCH`, request the Slurm `scratch` license, and keep only compact
  manifests/histories plus the restartable final bridge in the home-side
  package. Scratch is temporary, purge-eligible, and not backed up; accepted
  states and immutable provenance must also have durable home/local copies.
  Normal sync-back excludes checkpoint directories unless a particular
  interrupted-run checkpoint is explicitly needed.

## Branch and budget safety

- Preserve the labeled primary-forward metastable lineage. Never replace it
  with a lower-energy competing basin solely because that basin has lower
  energy.
- Require remote evidence before declaring a branch endpoint, changing a
  convergence/continuity gate, or selecting the next restart parent.
- Use the guarded `slurm/run_scan_cpu.sh plan|submit|status|reconcile` workflow;
  do not bypass its one-job and node-hour checks.
- For the dedicated YC8-1 chi-512 campaign, use launcher 2.7.0
  `advance|advance-submit` after a terminal run. The automatic policy may
  resume infrastructure failures from an accepted hash, continue remaining
  nominal targets, bisect only to `0.05*pi`, or retry a demonstrably
  contracting corrector up to 720 iterations. It must stop for continuity
  loss, inner-solver failure, a failure at the step floor, unsupported
  scheduler failure, changed evidence, or any proposed solver/chi/tolerance
  change. `advance-submit` is an explicit submission authorization, not a
  background daemon.
- Parallel VUMPS is approved only for the SHA-pinned YC8-1 chi-512 lineage.
  Final-control job `57337312` converged at theta/pi=0.15 from the accepted
  theta/pi=0.1 parent while the otherwise identical sequential update failed.
  The promoted root is accepted state SHA-256
  `38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`,
  generated through `scripts/prepare_phase1_chi512_parallel_continuation.jl`.
  Launcher 2.7.0 requires the pinned successful-control config, decision, and
  state hashes for the root and an immutable automatic decision for every
  descendant. Do not generalize parallel updates to another branch, chi, or
  geometry. Numerical recovery remains bounded at a 0.05*pi step; an exhausted
  recovery triggers iDMRG review, while scheduler/process failure is
  inconclusive.
- When a launcher command omits `RUN_ID`, resolve the greatest job ID recorded
  in remote `job.tsv` files rather than trusting `latest_run.txt`; the latter
  may have been overwritten by a stale local-to-Perlmutter sync.
- For iDMRG, the accepted theta/pi=0.15 SHA-256
  `38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`
  remains both lineage parent and overlap reference. A nonconverged iDMRG
  result may be used only as an explicitly labeled numerical seed after its
  branch diagnostics pass; it does not become the lineage parent. Native
  convergence uses the period-normalized MPSKit superblock-energy increment,
  not cumulative `IDMRGState.energy`. The MPSKit `IDMRG` stopping value is
  `norm(C_new - C_old)` after a complete sweep; the legacy HDF5 name
  `environment_error` is retained for compatibility but must not be described
  as an environment residual. Discarded weight is identically zero for
  fixed-space one-site iDMRG rather than a VUMPS residual.
- Keep the project-owner iDMRG workflow at the launcher level:
  `bash slurm/run_idmrg_cpu.sh plan|submit|status|reconcile` on Perlmutter and
  `bash slurm/run_idmrg_cpu.sh analyze` locally after Globus sync-back. The
  literal `submit` command is the complete explicit authorization; do not add
  a second acknowledgement variable or require the owner to repeat the control
  path, account, or job ID. The active control reference is
  `configs/phase1_idmrg_active_control.ref`, the default account is `m4863`, and
  a successful submit records `job_id.txt`. Preserve optional explicit
  control/job arguments for diagnosis.
- Keep the resource calibration equally concise:
  `bash slurm/run_idmrg_benchmark_cpu.sh plan|submit|status|reconcile` on
  Perlmutter and `bash slurm/run_idmrg_benchmark_cpu.sh analyze` locally. The
  benchmark is one Shared-QOS allocation containing independent 2-, 4-, 8-,
  and 16-thread restarts from the same rejected job-57500598 tensor. It writes
  no checkpoints or full states and cannot submit or promote a scientific
  continuation. Do not prepare another full-node iDMRG job before this
  benchmark is reconciled and analyzed.
- Slurm copies a submitted batch script to a spool directory, so a batch worker
  must never infer the repository root from its own `BASH_SOURCE`. Pass the
  absolute project root as a validated worker argument, set the job working
  directory explicitly, and make `plan` invoke the actual worker in preflight
  mode. Regression tests must execute a copied worker from a temporary
  spool-like directory. An executable worker preflight, not source inspection
  alone, is required before a benchmark package is eligible for submission;
  `plan` runs it on the login node and the batch worker repeats it on the
  compute node before any benchmark step.
- Benchmark preflight must execute every runtime helper used before the first
  solver update and the exact HDF5 result writer/readback used after the last
  update under the pinned Julia minor and package versions. Do not call
  undocumented or unverified `Base` timing internals. Process CPU measurements
  currently use libuv `uv_getrusage` (user plus system CPU time); measured masks
  are dense `UInt8` arrays, never packed `BitVector`s. The launcher must pass
  the exact Julia binary it validated into the nested worker preflight. Jobs
  `57548405` and `57550459` are immutable zero-update infrastructure failures.
  Job `57574096` completed the five requested 2-thread solver updates but failed
  while HDF5 serialized the timing result, so its partial `.h5.tmp` contains no
  timing histories and is also not benchmark data. Never reuse a package with a
  job ID, result, or stale temporary file; prepare a fresh hash-pinned package.
- Whenever a new iDMRG package is prepared, validate its immutable control
  locally and then update both lines of
  `configs/phase1_idmrg_active_control.ref` (relative control path and exact
  SHA-256). Never infer the active control from modification time or an
  unvalidated directory scan.
- The project owner deleted the untrustworthy job-57452187 serialized
  checkpoints after canceling their Globus transfer. The prepared successor is
  deliberately independent of them: it starts from the hash-pinned final
  result tensor bridge, passes no checkpoint-resume argument, and requires a
  distinct empty PSCRATCH checkpoint directory. Do not reconstruct, transfer,
  or require the deleted checkpoints.
- Job `57500598` used PSCRATCH for its heavy checkpoints, so normal home/local
  copies contain only the roughly 32 MiB pair of result and numerical-seed
  bridges plus small metadata. Its solver step averaged only about 4.76 CPUs,
  peaked at about 9.63 GiB RSS, and ran inside an exclusive full CPU-node
  allocation. This is resource-overallocation evidence and is scientifically
  separate from convergence policy.
- On 2026-08-24, after reviewing job `57500598`, the project owner selected a
  working exploratory iDMRG gate of bond-matrix update norm at most `1e-5` and
  final-four intensive-energy span at most `1e-8`. Preserve the completed
  job's immutable `1e-8`/`1e-9` control and original rejected classification;
  record the relaxed pair as the post-hoc
  `phase1_exploratory_working_20260824` profile. Job `57500598` passes this
  working native gate, but this does not promote it: accepted-parent overlap,
  observables, U(1) sectors, and primary-forward branch continuity must still
  be evaluated. Future controls may use the working pair only when it is
  predeclared with the exact profile and decision provenance in
  `configs/phase1_idmrg_working_convergence.toml`.
