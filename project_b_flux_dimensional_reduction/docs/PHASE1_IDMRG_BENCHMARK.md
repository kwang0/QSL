# Phase 1 iDMRG resource benchmark

No further full-node iDMRG continuation is prepared. Job `57500598` showed
that the previous 128-thread/regular-QOS request was severely oversized, so the
next authorized action is a small Shared-QOS benchmark only.

All three submitted benchmark attempts produced no valid timing result. Job
`57548405` failed after 11 seconds
because its Slurm-copied batch script incorrectly derived the project root from
`/var/spool/slurmd`. Job `57550459` reached the correct project and began the
2-thread step, then failed before state initialization because the benchmark
called the nonexistent Julia 1.12 API `Base.cputime()`. Job `57574096` completed
all five requested 2-thread updates, then failed while HDF5 serialized a packed
`BitVector`; its partial file contains metadata but no timing histories. All
immutable failed packages are preserved. The active pointer names a fourth,
locally validated package that fixes and tests all three code paths.

That schema-4 package subsequently ran as job `57576411` and completed every
2/4/8/16-thread step with exit `0:0`. Independent analysis selected two Julia
threads and a four-logical-CPU solver step by minimum projected Shared-QOS
node-hours per 100 iDMRG updates. The job charged `0.10871527777777777`
node-hours, bringing Phase 1 to `12.25235894158889` and Project B including
Phase 0 to `13.34679194158889` node-hours.

The first science use of that selection, job `57608599` at theta/pi=0.175,
failed after eight seconds before Julia. A 16-GiB memory request produced a
10-logical-CPU Shared allocation, while the old launcher declared a four-CPU
batch task; `srun` rejected conflicting `SLURM_CPUS_PER_TASK=9` and
`SLURM_TRES_PER_TASK=cpu=4`. The job performed zero scientific updates. Its
derived five-core charge is `0.00008680555555555556` node-hours, so the
carried-forward totals are `12.252445747144446` for Phase 1 and
`13.346878747144446` for Project B. The active science retry uses a distinct
immutable package, 10 allocation logical CPUs, an exact four-logical-CPU
solver step, and the same two Julia threads and 16-GiB/five-core charge ceiling.

That retry completed as job `57611537` in 33,423 seconds. With five charged
physical cores, it used `0.3626627604166666` node-hours, bringing Phase 1 to
`12.615108507561112` and Project B including Phase 0 to
`13.709541507561113` node-hours. It independently validates the benchmarked
two-thread/four-logical-CPU execution choice for science production. The state
passed its working native gate but failed the separate `0.99` parent-overlap
branch gate, so resource success does not imply scientific promotion.

The owner-facing commands remain short:

```bash
cd /global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction
module load julia

bash slurm/run_idmrg_benchmark_cpu.sh plan
bash slurm/run_idmrg_benchmark_cpu.sh submit
bash slurm/run_idmrg_benchmark_cpu.sh status
bash slurm/run_idmrg_benchmark_cpu.sh reconcile
```

Run `reconcile` only after `status` shows that the benchmark has left the
queue. Do not add `set -e` or `set -euo pipefail` to the interactive SSH
session. The literal `submit` command authorizes one benchmark allocation; it
cannot submit a scientific continuation.

The active benchmark pointer is
`configs/phase1_idmrg_benchmark_active_control.ref`. It pins:

- package:
  `output/phase1_idmrg/benchmarks/theta_p0p20000000_chi512_threads_retry_after_57574096_c7ef67c0e22b/`;
- control: `phase1_idmrg_benchmark_control.toml`;
- control SHA-256:
  `8fb5a1c0b99e5fa3c955f9e0e914913735e08fe64e90681a648d9ca339a05110`;
- native-only source analysis SHA-256:
  `eb7d1fa5b655f212ce30d88963d16900d0c9e2070f03014b7c1b32db05ba66c1`;
- detailed owner-provided job-57500598 accounting SHA-256:
  `2a84927780b8baf0bd8680c55a3f7c60192e074f76f7c30d4d36965d8bd29e79`.

## Failed attempts and corrective controls

Perlmutter log `logs/benchmark-57548405.out` contains:

```text
opening file "/var/spool/slurmd/idmrg/scripts/validate_benchmark_control.jl":
No such file or directory
```

The worker used `dirname "${BASH_SOURCE[0]}"`, but Slurm executes a copied batch
script below its spool directory. The allocation therefore exited `1:0` before
loading the model, seed, or benchmark runner. Reconciled evidence records
`FAILED`, 11 seconds, 32 logical CPUs, and zero result files. Its derived
Shared-QOS charge is approximately `0.000381944` node-hours.

The corrected path has four defenses:

1. `submit` passes the absolute project root as a worker argument;
2. the worker validates that explicit root and never derives it from its own
   location;
3. `plan` invokes the real worker in a non-writing preflight that loads the
   validator, control, and pinned seed;
4. the launcher test copies the worker to a temporary spool-like directory and
   requires that preflight to pass from there.

The second attempt proved that path/config validation alone was insufficient.
Perlmutter log `logs/benchmark-57550459.out` contains:

```text
UndefVarError: `cputime` not defined in `Base`
```

Julia 1.12 does not define that `Base` function. The final package therefore:

1. measures process CPU time with libuv `uv_getrusage` as user plus system CPU
   seconds instead of relabeling wall time;
2. makes `plan` execute the exact timing helper under the pinned Julia/MPSKit
   environment;
3. propagates the same resolved Julia binary into the nested worker preflight;
4. unit-tests monotonic process CPU timing under Julia 1.12.7;
5. exercises the real MPSKit iDMRG iterator/checkpoint path locally; and
6. makes `reconcile` and `analyze` print a recognized failure diagnosis before
   refusing invalid timing data.

Job `57550459` was `FAILED`, exit `1:0`, after 202 seconds with 32 allocated
logical CPUs. Its derived Shared-QOS charge is approximately `0.007013889`
node-hours. It completed no iDMRG update and created no result file.

The third attempt proved that a pre-solver-only preflight was still
insufficient. Perlmutter log `logs/benchmark-57574096.out` contains:

```text
MethodError: no method matching strides(::BitVector)
```

The real 2-thread MPSKit run completed its five requested updates and entered
`write_benchmark_result`, but HDF5 0.17.3 rejected the packed Boolean mask. The
job was `FAILED`, exit `1:0`, after 889 seconds. Its 2-thread step used four
logical CPUs for 791 seconds, recorded `14:31.541` TotalCPU, and peaked at
`7327392K` (6.99 GiB). The derived Shared-QOS charge is approximately
`0.030868056` node-hours. The partial
`results/benchmark_threads_2.h5.tmp` is hash-pinned as failure evidence; it has
no optimizer histories and is not salvageable timing data.

Schema 4 now writes the mask as dense `UInt8` values, removes a writer-owned
temporary file on any exception, and refuses stale temporary files. Both
`plan` and the compute-node batch worker execute the exact HDF5 writer and read
back schema, mask, and histories under Julia 1.12 with pinned MPSKit 0.13.13,
HDF5 0.17.3, and TensorKit 0.17.1. The analyzer test consumes files created by
the production writer instead of fabricated HDF5. The schema-4 control
hash-pins controls, logs, summaries, step accounting, and the third partial
file from all failed attempts; none can be overwritten or mistaken for valid
benchmark data.

## Why this benchmark is required

The owner-provided detailed `sacct` record for job `57500598` shows:

- allocation wall time: `08:48:35` on one exclusive CPU node;
- solver step: 128 allocated logical CPUs and `1-17:54:26` TotalCPU;
- average solver CPU use: `150866 / 31707 = 4.7586` CPUs;
- scheduler CPU efficiency: `150866 / (31707 * 128) = 3.72%`;
- peak solver RSS: `10096448K = 9.63 GiB`;
- charged regular-QOS time: `31715 / 3600 = 8.809722222` node-hours.

The full-node allocation exposed 256 logical CPUs, even though the solver step
requested 128 and averaged fewer than five active CPUs. This does not mean the
solver is numerically stuck; it means the resource request was not calibrated.
The reconciled Phase 1 total through this job is therefore approximately
`12.105379775` node-hours, and the Project B total including Phase 0 is
approximately `13.199812775` node-hours.

NERSC documents that a CPU node has 128 physical cores and two logical CPUs per
core, recommends `--cpu-bind=cores`, and charges Shared-QOS jobs only for the
physical-core fraction allocated. On Shared QOS, both requested logical CPUs
and requested memory determine the charged core count. See the official
[affinity guide](https://docs.nersc.gov/jobs/affinity/),
[Shared-QOS examples and formula](https://docs.nersc.gov/jobs/examples/#shared),
and [charging policy](https://docs.nersc.gov/jobs/policy/).

## Controlled design

All four settings restart independently from the exact rejected,
native-nonconverged job-57500598 result SHA-256
`c7ef67c0e22b32d581fec9ed3d4f86b14182db15a1f80688c88fc311eb326116`.
That tensor is a benchmark seed only. The accepted theta/pi=0.15 state SHA-256
`38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`
remains the lineage parent and overlap reference.

The single Shared-QOS allocation runs 2, 4, 8, and 16 Julia threads
sequentially. Each setting receives two Slurm logical CPUs per Julia thread and
`--cpu-bind=cores`, starts from the same tensor, performs one unranked warm-up
iteration plus four measured iterations, and writes only a small HDF5 timing
record. It writes no checkpoint and no full state. The allocation requests 32
logical CPUs, 16 GiB, and 90 minutes, so its fail-closed maximum is `0.1875`
node-hours. No benchmark result can trigger a science submission or promotion.
Including all three failed allocations, the retry control carries forward
approximately `12.143643664` Phase 1 node-hours and `13.238076664` total Project
B node-hours.

The local analyzer checks that every step completed, retained chi 512 and zero
one-site discarded weight, followed a consistent short numerical trajectory,
and stayed below 16 GiB. It combines per-iteration wall times with detailed
step `sacct` CPU and MaxRSS records, then selects the minimum projected
Shared-QOS node-hours per 100 iterations. A future scientific control may be
prepared only after this analysis is reviewed.

## Globus transfer before `plan`

Use the project owner's established full-tree checksum-sync cycle while no
project job is writing the directory:

1. Perlmutter-to-Mac sync the complete non-dot project tree and wait for it to
   finish;
2. make and validate local changes;
3. Mac-to-Perlmutter sync the complete non-dot project tree;
4. keep Globus destination mirroring/deletion disabled and use “sync only files
   where the checksum is different.”

Project roots are:

- Mac:
  `/Users/kevin/Code/QSL/project_b_flux_dimensional_reduction/`;
- Perlmutter:
  `/global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction/`.

Ignore dot directories such as `.git` and `.julia`. Never include anything
below `$PSCRATCH`; it is outside the normal project-tree sync. The retry package
depends on all three preserved failed-attempt evidence packages and the 32 MiB
source-result package, all of which are included by the non-dot full-tree sync.

The bare `plan` command now executes the actual worker preflight. Do not submit
unless it prints `worker preflight: passed with explicit project root` and live
Perlmutter checks pass.

## Globus sync-back and local analysis

After Perlmutter `reconcile`, repeat the complete non-dot project-tree checksum
sync in the Perlmutter-to-Mac direction and wait for completion.

Then run locally:

```bash
cd /Users/kevin/Code/QSL/project_b_flux_dimensional_reduction
bash slurm/run_idmrg_benchmark_cpu.sh analyze
```

The benchmark never writes scratch checkpoints, so there is no checkpoint
directory to copy. It neither reads nor validates any checkpoint from an older
job. If job-57500598 checkpoints still exist below `$PSCRATCH`, they are
optional recovery data and are excluded from routine Globus transfers.

## Latest scientific classification

The corrected local analysis of job `57500598` is native-only and rejected.
The final-four period-normalized energy span is
`1.2221335055e-12`, which passes the fixed `1e-9` gate. Chi 512 was maintained,
and one-site discarded weight remained exactly zero. The only failed native
gate is the MPSKit stopping value `2.3113487840e-6` versus `1e-8`.

MPSKit source defines this stopping value as `norm(C_new - C_old)` after a
complete iDMRG sweep. The old artifact field is named `environment_error`, but
it is not an environment residual and is not comparable to the VUMPS projected
residual. It decreased monotonically over the last 100 iterations and reached
its run minimum at iteration 400, so it is not plateauing. Because native
convergence already fails, ITensor conversion, parent overlap, observables,
sector comparison, and the common VUMPS probe are correctly skipped. They are
promotion gates for a future native-converged candidate, not prerequisites for
rejecting this one.

The project owner subsequently selected post-hoc working exploratory
thresholds of `1e-5` for the bond-matrix update norm and `1e-8` for the
final-four energy span. Job `57500598` passes this working native gate. Its
immutable original rejection is preserved, and no overlap, observable, U(1),
or branch-continuity promotion gate has yet been evaluated. The resource
benchmark remains useful for later flux points and does not depend on which
native threshold profile is used.
