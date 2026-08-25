# Phase 1 iDMRG operator guide

> Status, 2026-08-24: the continuation described below ran as Perlmutter job
> `57500598` and is complete. Do not resubmit this control. Its native-only
> analysis is rejected because the MPSKit bond-matrix update norm remains above
> tolerance. The next action is the low-cost Shared-QOS resource benchmark in
> `docs/PHASE1_IDMRG_BENCHMARK.md`, not another full-node continuation.

The historical action was one theta/pi=0.2, YC8-1, period-2, U(1), chi-512
MPSKit iDMRG continuation.

The operator workflow used for that completed job was deliberately short:

```bash
cd /global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction
module load julia

bash slurm/run_idmrg_cpu.sh status
bash slurm/run_idmrg_cpu.sh reconcile
```

These commands are retained for provenance only; its reconciliation file is
already synced. Run `reconcile` only after `status` shows that a job has left the queue. Do
not put `set -e` or `set -euo pipefail` in the interactive SSH shell. A command
error then returns to the prompt instead of closing the connection.

The literal `submit` command is the project owner's complete explicit
authorization. There is no second acknowledgement variable. The default NERSC
account is `m4863`; an unusual future allocation can override it with
`PHASE1_ACCOUNT=...`. The launcher records the submitted job ID, so `status`
and `reconcile` need no ID. Explicit control paths and job IDs remain optional
diagnostic arguments.

## Active immutable package

The launcher reads `configs/phase1_idmrg_active_control.ref`, which pins both
the relative path and SHA-256 of the active control:

- package:
  `output/phase1_idmrg/yc8_1/theta_p0p20000000_resume_from_527afdf421e3/`;
- active control: `phase1_idmrg_control_v2.toml`;
- active control SHA-256:
  `67e258ee244ddaf397d9f493a09c1a30d4a0b1e0f4a3a001e954db8f287a89d0`;
- numerical-seed bridge:
  `rejected_idmrg_seed_to_mpskit_bridge.h5`;
- bridge SHA-256:
  `f0612ee36814a7830253d3bc0f80ebeee1031ff104f4075cb519e02ec7f4ef95`;
- isolated iDMRG manifest SHA-256:
  `33d5ca924f891d81c59911530884a2adbc748f742456fc4a08bb629b196b3ee0`;
- immutable accepted parent and overlap-reference SHA-256:
  `38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`;
- rejected numerical-seed SHA-256:
  `527afdf421e3411fb91f622ae0a5f8764d453f892c7752b2294913813749c8de`.

The earlier `phase1_idmrg_control.toml` remains untouched as superseded
provenance. Do not submit it after syncing the streamlined launcher because its
pinned launcher hash correctly no longer matches.

## The deleted old checkpoints are not inputs

The project owner deleted the job-57452187 checkpoints after an interrupted
Globus transfer made them untrustworthy. The active submission does not rely on
them.

The successor bridge contains the complete period-2 chi-512 tensors from the
final result of job `57452187`. Submission invokes `run_idmrg.jl` with the
control and result paths only, without the optional checkpoint-resume argument.
It constructs a fresh MPSKit solver from that immutable bridge. The launcher
also requires this new, distinct directory to be absent or empty:

`$PSCRATCH/QSL/project_b_flux_dimensional_reduction/phase1_idmrg/yc8_1/theta_p0p20000000_resume_from_527afdf421e3/checkpoints/`

The plan must print:

```text
startup source: immutable bridge only; no prior checkpoint
job 57452187 checkpoints required: no
```

The missing old checkpoints only prevent a mid-run restart of the old control.
They do not invalidate the completed first result, the tensor bridge, the
reconciled accounting, or this successor.

## Globus transfer before `plan`

Set the Perlmutter destination root to:

`/global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction/`

Copy these complete code directories from Mac to the matching Perlmutter
directories:

- `configs/`
- `docs/`
- `idmrg/`
- `scripts/`
- `slurm/`
- `src/`

Also copy these top-level files from Mac to the Perlmutter project root:

- `AGENTS.md`
- `Manifest.toml`
- `Project.toml`

For run data, make these Mac-to-Perlmutter selections:

| Source selection on Mac | Destination parent on Perlmutter |
|---|---|
| `output/phase1_idmrg/yc8_1/theta_p0p20000000_resume_from_527afdf421e3/` | `output/phase1_idmrg/yc8_1/` |
| `output/phase1_idmrg/yc8_1/theta_p0p20000000_from_38312fc996fe/analysis/` | `output/phase1_idmrg/yc8_1/theta_p0p20000000_from_38312fc996fe/` |

Also copy these three individual files from the first-run local package into
the matching first-run Perlmutter package:

- `idmrg_result_bridge.h5`
- `idmrg_result_lightweight.h5`
- `sacct-57452187.tsv`

The accepted theta/pi=0.15 parent should already be authoritative on
Perlmutter. If `plan` says it is missing, copy only that exact accepted state
file to its matching path under
`output/phase1_tests/yc8_1/parallel_update_p0p10000000_to_p0p15000000_chi512_f71fc084883e_b5ef48caaf7a/chi512/states/`.

Do not select any deleted or surviving `checkpoints/` directory, the whole
first-run package, the whole `output/` tree, or anything below `$PSCRATCH`.
There is no separate sync script or preflight block: the bare `plan` command is
the authoritative preflight and reports a missing or mismatched item without
closing the SSH connection.

## What `plan` and `submit` still guard

The short interface does not relax the scientific or budget controls. Before
submission, the launcher verifies the active-control hash, source and bridge
provenance, accepted-parent hash, rejected-seed hash, predecessor `sacct` hash,
MPSKit manifest, one-job limit, reconciled node-hour budgets, no active
`pb1-idmrg` job, and the live Perlmutter scratch root. It refuses existing
result, lightweight, job-ID, or nonempty new-checkpoint targets.

Job `57500598` used one exclusive CPU node, 128 Julia threads, BLAS thread
count 1, QoS `regular`, a 10-hour wall limit, and the Slurm scratch license.
The allocation ran `08:48:35` and therefore cost approximately
`8.809722222` node-hours. Detailed step accounting shows only `4.7586` average
CPUs and `9.63 GiB` MaxRSS, so this request was severely overprovisioned. Do
not reuse it. The next resource decision comes from the guarded 2/4/8/16-thread
Shared-QOS benchmark.

## Sync back and analyze

After `reconcile`, use Globus in the opposite direction:

- source on Perlmutter:
  `/global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction/output/phase1_idmrg/yc8_1/theta_p0p20000000_resume_from_527afdf421e3/`;
- destination parent on Mac:
  `/Users/kevin/Code/QSL/project_b_flux_dimensional_reduction/output/phase1_idmrg/yc8_1/`;
- direction: Perlmutter to Mac.

Do not select the new `$PSCRATCH` checkpoint directory during normal sync-back.
Then run locally:

```bash
cd /Users/kevin/Code/QSL/project_b_flux_dimensional_reduction
bash slurm/run_idmrg_cpu.sh analyze
```

Analysis remains local. It now evaluates native gates first and performs the
ITensor-side parent-overlap, observable, U(1)-sector, and common projected
stationarity checks only for a native-converged candidate.

## Scientific classification

Job `57452187` was scheduler/process successful (`COMPLETED`, exit `0:0`) but
scientifically nonconverged after 80 iterations. Its corrected final environment
error was `3.781953625e-5` against `1e-8`, and its corrected final-four
intensive-energy span was `6.930349628e-9` against `1e-9`. The environment
error was still contracting rather than plateaued, while energy stationarity
was not established. Its overlap per site with the immutable accepted parent
was `0.9999707484`, and its branch diagnostics passed, so its tensors are an
approved numerical seed only. They are not a new lineage parent.

Job `57500598` performed all 400 permitted iterations without changing the
model, symmetry, period, gauge, chi, algorithm, branch, or tolerances. Its
final-four period-normalized intensive energies span `1.2221335055e-12`, so the
`1e-9` energy gate passes, and chi 512 is maintained. Its MPSKit stopping value
is `2.3113487840e-6`, still above `1e-8`, so native convergence fails.

The legacy field name `environment_error` is misleading: pinned MPSKit source
defines this quantity as `norm(C_new - C_old)` after a complete unit-cell
sweep. It is neither discarded weight nor a VUMPS residual. It decreased
monotonically throughout the last 100 iterations and reached its run minimum
at iteration 400, so this is slow continued contraction, not a plateau. The
native-only analyzer therefore rejected the state without attempting the
unnecessary ITensor conversion that previously failed at a strict
canonicalization correction gate. Parent-overlap and branch-promotion checks
remain mandatory only after a future candidate passes native convergence.

After this immutable classification, the project owner selected a working
exploratory gate of bond-matrix update norm at most `1e-5` and final-four
energy span at most `1e-8`. Job `57500598` passes that working native gate.
The source control and original rejected analysis are not rewritten, and the
state is not promoted until overlap, common observables, U(1) sectors, and
primary-forward continuity pass. Future controls may predeclare the working
profile recorded in `configs/phase1_idmrg_working_convergence.toml`.
