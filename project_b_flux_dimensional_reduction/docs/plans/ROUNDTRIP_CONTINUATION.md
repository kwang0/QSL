# Short forward-and-return continuation

Owner authorized on 2026-09-09 after reviewing job 58082150. Prepare and test
locally, deliver source and sealed launch inputs through Git, and let the owner
execute the guarded Perlmutter commands. This is a finite diagnostic, with
no accepted-lineage promotion or production-tolerance change.

## Question and schedule

Can smaller relaxation budgets produce a reversible path beyond 0.20, with
agreement under flux-step refinement at **fixed updates per unit flux**?
The preceding experiment showed that keeping updates per point fixed while
halving the flux step increased accumulated relaxation and changed the state.
See [decision 006](../decisions/006-relaxation-continuation-outcome.md).

All arms start independently from the accepted chi512 theta/pi=0.15 parent:
`38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`.
The imported bridge and random seed 101 are the same as the completed trial.
No tensor from the previous job's scratch package is required.

Each arm follows **theta/pi = 0.15 to 0.25 and back to 0.15**. The turning
point is updated once. The return starts one flux step below the turning point
and carries that arm's actual outward endpoint; it never restarts from the
original parent or another arm. There are no endpoint holds or extra baseline
updates. The completed 0.15 baseline remains historical calibration evidence.

| Arm | Updates per point | Delta(theta/pi) | Updates per unit theta/pi | Outward updates | Full loop updates |
|---|---:|---:|---:|---:|---:|
| n2_grid1 | 2 | 0.025 | 80 | 8 | 16 |
| n1_grid2 | 1 | 0.0125 | 80 | 8 | 16 |
| n4_grid1 | 4 | 0.025 | 160 | 16 | 32 |
| n2_grid2 | 2 | 0.0125 | 160 | 16 | 32 |

Total: **96 VUMPS outer updates at 48 flux points**, plus four unoptimized
origins. These are not iDMRG sweeps. Keep U(1), YC8-1, period 2, uniform gauge,
J1=1, J2=0.12, fixed chi512 and the pinned MPSKit environment. Inner accuracy
uses the preceding experiment's kernel. Each flux change rebuilds environments
and resets the per-flux outer counter. No adaptive early stop, residual-minimum
substitution or step refinement is performed inside a run.

The finite schedule may advance from its diagnostic N-th endpoints without
passing the historical native or continuity gate. Every resulting artifact
remains `continuation_accepted=false`. An incomplete point is recorded and
cannot seed another point. USR1 or the global soft deadline requests a stop;
nonfinite outputs or a changed chi are errors.

## Measurements and interpretation

Save every completed canonical AL/C/AR payload to scratch and analyze every
iterate, including each arm's imported origin: **100 analyses if complete**.
Each analysis verifies payload hash, control, parent, history, U(1) basis,
canonical relations and MPSKit/ITensor energy equality. Compact output retains
energy, local energy terms, cut entropy, local magnetization and six leading
transfer eigenvalues in each physical Sz=0 and Sz=1 sector.

Compare every state to the accepted parent and its immediately preceding
diagnostic endpoint. Return states additionally compare to the same arm's
**outward endpoint at exactly the same flux**. At 0.15 that reference is the
imported origin. Store reference hashes and scalar observables explicitly so
these comparisons can be audited after compact-output sync.

The summary reports same-flux return/forward energy and entropy differences,
overlap, magnetization, local-energy alternation and charged-spectrum distance.
It also compares coarse/fine arms at equal update density and the two densities
on each grid. Spectrum distance is the symmetric nearest-complex-eigenvalue
set distance; it is not an eigenvector identity, physical mode assignment or
acceptance threshold. All requested-mode convergence flags remain visible.

The native gate still requires error <=1e-5 and a four-record energy span
<=1e-8 at unchanged flux. New output explicitly marks this gate **inapplicable
when fewer than four records exist**, rather than equating a one-update sample
to a failed fully converged solve. Neither inapplicability nor a continuity
pass grants scientific acceptance.

New momentum labels use the physical transfer charge q:
`2k1 = wrap(k + 2*q*theta/8)`, `k2 = wrap(4*k)`, with theta in radians and
`k1` defined modulo pi. This preserves the charged Sz=1 convention and removes
the charged shift from Sz=0. Raw ITensor QN labels remain 2*q. This correction
is confined to the new analysis path; completed-run code and records are
preserved. Inverse correlation lengths are per complete period-2 transfer
cell, not Fig. 2 excitation energies.

Evidence for usefulness requires agreement across both grid and update
density, plus small forward/return differences and controlled magnetization.
A nearly frozen state can appear reversible, so return agreement alone is
insufficient. Neither this diagnostic nor a residual turnaround establishes
a converged metastable minimum, a physical spinodal or the authors' stopping
rule. General-chi preparation and the separate Fig. 2 calculation remain open.

## Resources and storage

One Shared-QOS CPU allocation: ten allocated logical CPUs, four-CPU srun steps,
two Julia threads, one BLAS thread, 16G, **14-hour hard limit**, global 12-hour
soft solver deadline and USR1 at 13.5 hours. The maximum reservation is
**0.546875 node-hours**, below the 0.55 trial cap and synchronized Phase 1
balance 0.969947916667. After a full reservation, that balance would leave
0.423072916667; actual charge uses Slurm's allocated CPU count and runtime.
The live guard is still required; no phase budget is reassigned.

Expected wall time is approximately **6-10 hours**, with uncertainty from
frequent environment rebuilds and analyses. Ninety-six updates alone suggest
about five hours at the last measured chi512 rate. This is a resource forecast,
not an ETA to convergence. A long inner solve or analysis can overrun a soft
deadline. The summary and job.result explicitly report experiment completeness.

Compact output:
`output/mpskit_solver_pilot_jobs/roundtrip/TIMESTAMP_HASH/`.
Heavy data:
`$PSCRATCH/QSL/project_b_flux_dimensional_reduction/roundtrip/job_JOBID_HASH/`.
The 100 payloads require roughly four GiB before HDF5/filesystem overhead.
Scratch is purgeable. No full tensors are duplicated into project output.
All Project B launchers share the accounting root, submission lock and budget.

## Manual Perlmutter commands

The new active reference is `configs/roundtrip_continuation_active_control.ref`.
Its tracked sealed control arrives in the same Git pull as its pinned code.
Existing parent and bridge data are accessed through the canonical output link.
Control: `configs/controls/roundtrip_continuation_v1.toml`, SHA-256
`40088fc17091a0962b35de44b1f588124b8a302dbed2f8ce06769af7be64e8b7`.

```bash
cd ~/QSL-project-b &&
git pull --ff-only &&
cd project_b_flux_dimensional_reduction &&
bash slurm/run_roundtrip_continuation_cpu.sh preflight &&
bash slurm/run_roundtrip_continuation_cpu.sh submit &&
bash slurm/run_roundtrip_continuation_cpu.sh status
```

`preflight` runs the context audit, live reconciliation and full live `plan`,
including actual tests through a copied worker. Submission repeats the guards
under the common lock and rejects an already-submitted control. The `&&` chain
submits only after a successful live plan.

```bash
bash slurm/run_roundtrip_continuation_cpu.sh progress
```

This prints the run package, allocation/step accounting, scratch location and
recent log lines. Default selection is the greatest job ID recorded in job.tsv;
`RUN_ID=JOB_ID` selects a specific job. Use `tail -f` on the printed log path
for continuous output; Ctrl-C exits the viewer only.

After completion:

```bash
bash slurm/run_roundtrip_continuation_cpu.sh reconcile &&
bash slurm/run_roundtrip_continuation_cpu.sh analyze
```

`analyze` reads compact records and prints comparisons; it does not compute
tensors on a login node. Look for `EXPERIMENT_COMPLETE=true`, 100 analyses,
no missing outputs and no incomplete arms. Slurm completion alone does not
prove the entire diagnostic finished. Checksum-sync the new compact run
package and `output/accounting/` with Globus, mirroring and deletion disabled.
Do not transfer `.git` or the full scratch package.

## Validation record

- Schedule, parser and fixed policy: 88 assertions; sealed inputs and the
  retrospective Phase 1 guard: three assertions. The old relaxation control
  still validates with unchanged sources.
- Actual tiny-MPS VUMPS forward/return kernel and interrupted-path propagation:
  ten assertions. Canonical reader tests: nine; charge-aware momentum: 97.
- Compact summary: 15 assertions, including all 100 synthetic analysis records,
  same-flux return references, missing outputs and altered-hash rejection.
- Production full-chi512 analysis on an explicitly synthetic interrupted
  identity return: eight assertions. Both sectors' requested modes converge,
  energy agrees across libraries and the same-state return comparison passes.
  This fixture performs no optimization and is not a scientific trajectory.
- Mocked launcher tests pass through a copied worker: failures stop before
  submission, exact resource arguments, shared guard, duplicate control,
  greatest-ID selection and active-control tamper rejection.
- Actual local `plan` passes all tests through the copied worker. Its temporary
  control matches the final sealed control except for creation time, including
  every recipe setting and input hash. Local accounting is retrospective only.
- Real Git push/pull into an empty sparse checkout delivers the sealed control
  and all pinned source inputs. Missing tensors and changed source are rejected.
- The context audit validates all five control references; relative links in
  the updated documentation resolve, and the final Git diff passes review.

Owner-supplied September 9 output confirms the live preflight passed, including
input hashes, budget and copied-worker tests. The following `submit` repeated
the tests; the excerpt ends before a job ID. Submission, runtime and scientific
outcome remain unconfirmed. Future launcher revisions follow the minimal-testing
preference in `AGENTS.md`; this sealed control's runtime is unchanged. No remote
command or transfer is initiated by Codex.
