# Three limited-relaxation scans through pi

Status: job 58179916 complete, reconciled, synchronized and reviewed.
Updated: 2026-09-11. Do not resubmit the completed control.
Rationale: [decision 009](../decisions/009-full-flux-qualitative-scans.md).

Outcome: [decision 010](../decisions/010-fullflux-continuation-outcome.md).
All 126 updates and 30 analyses completed in 7:14:28, costing 0.282855902778
node-hours and leaving Phase 1 50.487189670139. Every requested transfer mode
converged, but no native gate passed. The 2-update path has partial softening;
4/8 updates develop magnetic drift earlier and end at similar magnetized
states. This does not establish stable qualitative Fig. 3 reproduction.
Absolute M/K assignments need the signed momentum calibration described in
the outcome. The schedule and commands below document the completed run.

## Scientific schedule

Run exactly three independent chi512 VUMPS paths from the accepted YC8-1
period-2 U(1) parent at theta/pi=0.15. The parent SHA-256 is
`38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`.
Each path imports that parent anew, takes a first half-step to 0.20, then uses
the requested 0.10 grid: 0.30, 0.40, ..., 1.00. This preserves the verified
lineage and reaches the paper's positive-flux endpoint; it does not supply
new 0.00 or 0.10 points. There is no return leg, hold or fourth baseline run.

| Arm | VUMPS updates per flux point | Flux endpoints | Total updates |
|---|---:|---:|---:|
| n2 | 2 | 9 | 18 |
| n4 | 4 | 9 | 36 |
| n8 | 8 | 9 | 72 |

One update means the existing MPSKit VUMPS outer iteration, not an iDMRG
sweep or an inner Krylov iteration. The last iterate at each point seeds
the next point. Native convergence and continuity failures are recorded but
do not prevent this explicitly diagnostic advance. No tolerance is relaxed,
no residual minimum replaces the endpoint, and no state is automatically
accepted into the primary-forward lineage. A numerical exception, nonfinite
record, changed chi, or incomplete point stops that arm. The worker attempts
the other independent arms even after an earlier solver/analysis step fails.

Every update has a canonical AL/C/AR checkpoint in scratch and a compact
hash/history record. Analyze each arm's imported origin and each flux endpoint:
30 analyses for a complete run, rather than measuring every iterate. A stopped
point's last available iterate may be measured but is explicitly incomplete.
Each analysis includes energy, cut entropies, local energy and magnetization,
accepted-parent and previous-flux continuity, and six transfer modes in each
of Sz=0 and Sz=1 with the existing charge-aware momentum map. The 2-update
points cannot meet the existing four-iteration native-gate window; their
gate is marked inapplicable as well as not passed.

These data support qualitative Fig. 3 comparisons across update budgets,
including softening, momentum locations and magnetic drift. Inverse lengths
are reported per complete period-2 transfer cell. They are not Fig. 2
excitation energies. The separate embedded-window excited-state calculation
remains required for Fig. 2; chi512 and six modes also limit comparison with
the paper's much larger bond dimensions and richer spectra. See
[decision 004](../decisions/004-yc8-1-figure-reproduction-feasibility.md).

## Resources and authorization

The owner authorized 50 additional project node-hours on September 10 and
directed that the old balance must not cut this job short. The tracked common
accounting policy now sets Phase 1 to 70, the project to 200, and the automatic
submission ceiling to 190 node-hours, preserving the existing 10-hour project
reserve. The extra 50 are available to Phase 1. Historical charges are unchanged:
19.229954427083 Phase 1 hours spent, with 50.770045572917 remaining in the
latest synchronized reconciliation. Live preflight must verify later usage.

All three scans execute sequentially in one shared-QOS allocation, preserving
the project's one-active-job rule. Request 10 logical CPUs, 16G, four CPUs per
solver/analysis step, two Julia threads and one BLAS thread. Request **48 hours**,
the current [NERSC shared-QOS maximum](https://docs.nersc.gov/jobs/policy/).
The full-limit reservation is **1.875 node-hours**. There is no separate
16-hour solver cutoff: the global deadline matches the allocation, with the
existing 30-minute Slurm pretimeout signal for checkpoint preservation.
No node-hour balance is polled to stop a running solver.

The earlier roundtrip's measured cost suggests roughly 6-10 hours for this
126-update, 30-analysis workload. This is an extrapolation from low flux;
high-flux iteration and spectrum costs are unmeasured. The larger wall-time
request provides headroom, not a completion guarantee. Scheduler timeout,
memory exhaustion, or a numerical exception may still leave a partial run.
Retained checkpoints permit diagnosis and a separately prepared continuation
if needed; this launcher does not automatically resubmit or resume.

Scratch payloads are expected to occupy roughly 5 GiB. Compact output lives at
`output/mpskit_solver_pilot_jobs/fullflux/TIMESTAMP_CONTROLHASH/`; heavy states
live at `$PSCRATCH/QSL/project_b_flux_dimensional_reduction/fullflux/job_JOBID_HASH/`.

## Controls and minimal validation

`configs/fullflux_continuation.toml` is the recipe;
`configs/fullflux_continuation_active_control.ref` selects the tracked sealed
control under `configs/controls/`. It pins source, environments, accounting
policy and the existing accepted parent/bridge. Git pull delivers all new
launch inputs. No new scientific payload transfer is needed.

The new modules reuse the previously tested fixed-update kernel, path driver,
canonical reader and charge-aware spectrum code. Targeted local validation
covers compact replay and failure detection, a copied-worker plan, one real
chi512 import/measurement with zero optimization updates, and source delivery
from a clean Git checkout without ignored output. Perlmutter preflight runs
no numerical fixtures: only the brief copied-worker Julia/manifest smoke,
input hashes, context, live reconciliation and submission guards.

Local validation completed September 10: all seven focused compact-result
checks passed; the copied-worker local plan passed against a 1.875-hour
reservation and the 50.770045572917-hour balance. A real chi512 origin was
imported, exported and measured with zero VUMPS updates. Cross-library energy
difference was 2.22e-15, maximum canonical error 3.51e-15, parent continuity
passed, and all six requested modes converged in each spin sector. Compact
replay correctly classified this deliberately stopped fixture as incomplete.
A local Git push/pull fixture delivered the sealed inputs into an empty sparse
checkout; missing tensors and changed runtime source were rejected. All six
active control references matched the context audit. No remote solver test or
job has been run by the local agent.

The budget authorization changes `configs/project_b_accounting.toml`, which
older controls pinned. Their snapshots and all scientific runtimes remain
unchanged. Historical input validation against the current checkout will
therefore report that policy mismatch; use the historical Git revision for
exact old-control replay. Do not reseal or resubmit completed controls.

## Manual Perlmutter handoff

Run in the clean source worktree, whose output link already exposes the inputs:

```bash
cd ~/QSL-project-b &&
git pull --ff-only &&
cd project_b_flux_dimensional_reduction &&
bash slurm/run_fullflux_continuation_cpu.sh preflight &&
bash slurm/run_fullflux_continuation_cpu.sh submit &&
bash slurm/run_fullflux_continuation_cpu.sh status
```

Preflight performs the required live plan; submit rechecks integrity, lock,
queue and budget. The copied worker runs from an explicit absolute root.
For detailed progress:

```bash
bash slurm/run_fullflux_continuation_cpu.sh progress
```

This shows Slurm step accounting, recorded step exit codes and the last 40 log
lines, including arm, theta/pi, update number, Galerkin error and energy. After
the allocation is terminal:

```bash
bash slurm/run_fullflux_continuation_cpu.sh reconcile &&
bash slurm/run_fullflux_continuation_cpu.sh analyze
```

Completion requires `EXPERIMENT_COMPLETE=true`, 30 analyzed states, all three
theta/pi=1 endpoints, and zero failed steps. `COMPLETED` in Slurm alone does
not establish scientific completion or convergence. Native/continuity failures
remain visible even for a fully executed schedule. `RUN_ID=JOB_ID` selects a
particular recorded job; otherwise the greatest job ID is used.

Checksum-sync the new compact `fullflux/` run package and `output/accounting/`
back to the existing local output tree with Globus, keeping mirroring/deletion
off and excluding source, `.git` and scratch. The compact spectra suffice for
review; do not transfer all 129 heavy origin/iterate payloads routinely.

## Completed review and successor

Execution, live reconciliation, owner-confirmed sync, compact replay and local
comparison are complete. The review validates all 73 pinned inputs and all
six Slurm steps without rerunning optimization or a numerical test suite.
The next priority is a small signed momentum calibration, then improved
preparation and general-chi growth, not another larger chi512 update budget.
See decision 010 for the reproducible review command and plots.
