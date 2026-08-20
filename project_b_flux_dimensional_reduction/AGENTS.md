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

## Branch and budget safety

- Preserve the labeled primary-forward metastable lineage. Never replace it
  with a lower-energy competing basin solely because that basin has lower
  energy.
- Require remote evidence before declaring a branch endpoint, changing a
  convergence/continuity gate, or selecting the next restart parent.
- Use the guarded `slurm/run_scan_cpu.sh plan|submit|status|reconcile` workflow;
  do not bypass its one-job and node-hour checks.
- For the dedicated YC8-1 chi-512 campaign, prefer launcher 2.5.0
  `advance|advance-submit` after a terminal run. The automatic policy may
  resume infrastructure failures from an accepted hash, continue remaining
  nominal targets, bisect only to `0.05*pi`, or retry a demonstrably
  contracting corrector up to 720 iterations. It must stop for continuity
  loss, inner-solver failure, a failure at the step floor, unsupported
  scheduler failure, changed evidence, or any proposed solver/chi/tolerance
  change. `advance-submit` is an explicit submission authorization, not a
  background daemon.
- When a launcher command omits `RUN_ID`, resolve the greatest job ID recorded
  in remote `job.tsv` files rather than trusting `latest_run.txt`; the latter
  may have been overwritten by a stale local-to-Perlmutter sync.
