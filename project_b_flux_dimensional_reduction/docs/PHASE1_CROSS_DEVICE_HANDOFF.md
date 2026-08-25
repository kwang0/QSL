# Project B Phase 1 cross-device handoff

Snapshot date: 2026-08-25 (America/Los_Angeles)

This is the current handoff for continuing Project B on another device through
GitHub. It supersedes `docs/PHASE1_IDMRG_HANDOFF.md` as the operational entry
point; that older file remains the immutable pre-iDMRG handoff.

## Start here on the other device

Before taking any substantive action, read these files completely in order:

1. `AGENTS.md`
2. `docs/PHASE1_CROSS_DEVICE_HANDOFF.md` (this file)
3. `docs/PHASE1_IDMRG_BENCHMARK.md`
4. `docs/PHASES_0_TO_4.md`
5. `docs/PHASE1_IDMRG_LIBRARY_DECISION.md`
6. `docs/PHASE1_IDMRG_STORAGE.md`

The ready-to-paste bootstrap message is in
`docs/PHASE1_CROSS_DEVICE_NEW_CHAT_PROMPT.md`. The new chat must not ask the
project owner to reconstruct the old conversation.

## Authority and last confirmed operational state

Perlmutter is authoritative for job state, logs, output artifacts, hashes, and
accounting. GitHub is the code-and-documentation transport. The ignored local
`output/` tree is only a mirror and can be stale.

The last event confirmed in this chat was a successful **live Perlmutter
`plan`**, not a benchmark completion. It printed:

```text
control SHA-256: 8fb5a1c0b99e5fa3c955f9e0e914913735e08fe64e90681a648d9ca339a05110
worker preflight: passed with explicit root, Julia timing, and HDF5 result I/O
accounting authority: live Perlmutter checks passed
```

The project owner was then given the literal `submit` command, but no later
submission, job ID, status, reconciliation, or result has been reported in this
chat. Therefore the benchmark's current scheduler state is **unknown**. Do not
infer that it was or was not submitted from this checkout. Determine the state
on Perlmutter before proposing any new job.

Use this non-exiting remote check; do not add `set -e`:

```bash
cd /global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction
module load julia

PACKAGE=output/phase1_idmrg/benchmarks/theta_p0p20000000_chi512_threads_retry_after_57574096_c7ef67c0e22b
if [[ -f "$PACKAGE/job_id.txt" ]]; then
  bash slurm/run_idmrg_benchmark_cpu.sh status
else
  bash slurm/run_idmrg_benchmark_cpu.sh plan
fi
```

If a recorded job is terminal but not reconciled, run the bare `reconcile`
action only after inspecting `status`. Do not submit, cancel, delete, prune, or
prepare a successor merely to resolve ambiguity.

## Fixed scientific lineage

The project studies the `J1=1`, `J2=0.12` triangular-lattice model on the YC8-1
cylinder with period 2, U(1) symmetry, complex tensors, and the uniform twist
gauge. The primary-forward metastable branch is the scientific object; a lower
energy from another basin does not replace it automatically.

The immutable accepted lineage parent and overlap reference is the
parallel-VUMPS state at `theta/pi=0.15`:

```text
SHA-256 38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803
```

Promoted parallel-VUMPS job `57392725` failed the fixed `1e-5` VUMPS residual
gate at `theta/pi=0.2` after exhausting the approved `0.05*pi` recovery floor.
Its restored best state is a rejected diagnostic only:

```text
SHA-256 f59dd18f29004d259a3d94e7bedadd99a7fcb88b1ba960fb7e357dd8e645e7c0
```

All 276 inner Krylov solves converged and retrospective overlap/U(1)/observable
diagnostics stayed smooth, so the stop is classified as outer-VUMPS numerical
divergence, not a physical endpoint or demonstrated branch jump. Do not submit
another VUMPS retry from that rejected tensor.

## iDMRG implementation and scientific result

The source-backed decision in `docs/PHASE1_IDMRG_LIBRARY_DECISION.md` selected
MPSKit 0.13.13 one-site iDMRG over TeNPy and the current ITensor Julia stack.
MPSKit supplies genuine iDMRG while allowing an exact, round-trip-checked
Julia-native U(1) bridge. The current ITensor stack supplies Project B state
I/O and observables but not true iDMRG. The isolated production environment is:

```text
Julia      1.12.x
MPSKit     0.13.13
HDF5       0.17.3
TensorKit  0.17.1
```

It lives in `idmrg/Project.toml` and `idmrg/Manifest.toml`; do not merge it into
the root ITensor environment. Important implementation entry points are:

- `idmrg/src/ProjectBIDMRG.jl`: MPSKit state/model construction, iDMRG,
  checkpoints, benchmark timing, and HDF5 result I/O;
- `src/IDMRGBridge.jl`: ITensor-side bridge construction and promotion-only
  conversion support;
- `scripts/prepare_phase1_idmrg_control.jl` and
  `scripts/prepare_phase1_idmrg_resume.jl`: immutable scientific controls;
- `slurm/run_idmrg_cpu.sh`: concise scientific operator workflow;
- `scripts/analyze_phase1_idmrg_result.jl`: native-first result analysis;
- `scripts/prepare_phase1_idmrg_benchmark.jl` and
  `slurm/run_idmrg_benchmark_cpu.sh`: guarded resource benchmark.

Perlmutter job `57452187` completed 80 iDMRG updates. Its branch diagnostics
passed, but it failed the predeclared native convergence gates. Its rejected
result became an explicitly labeled numerical seed for job `57500598`, while
the accepted `theta/pi=0.15` VUMPS state remained the lineage parent.

Job `57500598` completed 400 further one-site updates. The immutable native
analysis remains rejected under its original control:

```text
final bond-matrix update norm      2.3113487840e-6  (required <= 1e-8)
final-four intensive-energy span  1.2221335055e-12 (required <= 1e-9)
bond dimension                    512
one-site discarded weight         0 by construction
result bridge SHA-256              c7ef67c0e22b32d581fec9ed3d4f86b14182db15a1f80688c88fc311eb326116
```

The bond-matrix update norm is MPSKit's `norm(C_new-C_old)` after a complete
unit-cell sweep. It is not an environment residual, discarded weight, or VUMPS
projected residual. It decreased through the final 100 updates and reached its
run minimum at iteration 400, so the trajectory was slowly contracting rather
than plateaued.

The project owner subsequently selected a post-hoc working exploratory profile
that future controls may predeclare:

```text
bond-matrix update norm <= 1e-5
final-four intensive-energy span <= 1e-8
profile = phase1_exploratory_working_20260824
```

Job `57500598` passes that working native profile, but its original rejection
is immutable and the state is not promoted. Parent overlap, common observables,
U(1) sectors, and primary-forward continuity remain promotion gates. Native
failure correctly short-circuited the unnecessary ITensor conversion in the
current analysis.

## Current resource benchmark

Job `57500598` used a full regular-QOS CPU node but its solver step averaged
only about 4.76 CPUs and peaked at about 9.63 GiB RSS. It cost approximately
8.809722222 node-hours. No further full-node continuation is allowed until the
thread benchmark is reconciled and analyzed.

The active benchmark reference is
`configs/phase1_idmrg_benchmark_active_control.ref`. It pins:

```text
output/phase1_idmrg/benchmarks/theta_p0p20000000_chi512_threads_retry_after_57574096_c7ef67c0e22b/phase1_idmrg_benchmark_control.toml
SHA-256 8fb5a1c0b99e5fa3c955f9e0e914913735e08fe64e90681a648d9ca339a05110
```

The benchmark performs independent restarts from the rejected job-57500598
result at 2, 4, 8, and 16 Julia threads. Each receives two Slurm logical CPUs
per Julia thread, one warm-up plus four measured updates, and
`--cpu-bind=cores`. It requests one Shared-QOS allocation with 32 logical CPUs,
16 GiB, a 90-minute limit, and a maximum charge of 0.1875 node-hours. It writes
small timing records only: no checkpoint, full state, science promotion, or
automatic successor.

Three prior benchmark attempts are immutable invalid evidence:

| Job | Failure | Solver work | Valid timing? | Derived charge |
|---|---|---:|---|---:|
| `57548405` | Slurm-spooled worker inferred `/var/spool/slurmd` as project root | 0 updates | no | 0.000381944 node-h |
| `57550459` | Julia 1.12 lacks `Base.cputime()` | 0 updates | no | 0.007013889 node-h |
| `57574096` | HDF5 rejected a packed `BitVector` after writing began | five 2-thread updates | no histories | 0.030868056 node-h |

Schema 4 fixes all three paths: explicit worker root, libuv `uv_getrusage`, a
dense `UInt8` measured mask, exception cleanup, stale-temporary refusal, exact
package pins, and production HDF5 writer/readback preflight on both the login
node and compute worker.

The live plan reported the time-specific carried-forward budgets:

```text
Phase 1: 12.14364366381111 / 20.0 node-hours
Project B: 13.23807666381111 / 150.0 node-hours
```

Recompute from reconciled Perlmutter evidence after any later job.

## Verified code state

The following checks passed on the source device before this handoff:

- executable benchmark preflight under Julia 1.12.7, including the exact HDF5
  production writer/readback;
- the isolated iDMRG suite: 48 assertions across timing, HDF5 I/O, U(1) basis,
  a real MPSKit iterator/checkpoint, native convergence, rejected-seed import,
  and benchmark analysis;
- the copied Slurm-worker and owner-launcher guard suite, including automatic
  classification of all three invalid benchmark attempts;
- the bare local structural `plan` for the schema-4 control;
- the later live Perlmutter `plan`, including active hashes, executable
  preflight, live queue checks, and live accounting checks.

These checks do not establish that the schema-4 benchmark was subsequently
submitted or completed. That remains a Perlmutter status question.

## GitHub transfer boundary

At the start of this handoff work, the Git repository root was
`/Users/kevin/Code/QSL`, branch `main`, with `HEAD` and `origin/main` both at:

```text
e0b5526 Document final chi-512 VUMPS control
```

All iDMRG implementation, controls, tests, and current documentation were still
uncommitted: 11 tracked files under this project were modified and 36
non-ignored files were untracked. The unrelated tracked
`/Users/kevin/Code/QSL/.DS_Store` was also modified outside this project. Do
not stage or commit that root `.DS_Store` as part of the transfer.
The two cross-device files added by this handoff and the README index update
bring the expected pre-staging project status to 12 modified tracked files and
38 non-ignored untracked files.

The transfer commit must include the entire
`project_b_flux_dimensional_reduction/` subtree, especially:

- modified `AGENTS.md`, `configs/README.md`, `docs/PHASES_0_TO_4.md`, VUMPS
  automation/launcher source, and their tests;
- `configs/phase1_idmrg_*` active references and working convergence policy;
- all `docs/PHASE1_IDMRG_*` and cross-device handoff files;
- the complete `idmrg/` environment, source, scripts, manifest, and tests;
- iDMRG bridge, preparation, analysis, archive/lightweight, and launcher files
  under `src/`, `scripts/`, and `slurm/`;
- all new iDMRG fixtures and launcher/analysis tests.

GitHub deliberately does **not** carry:

- `output/` (139 MiB in the source-device snapshot);
- `.julia/` or `tmp/`;
- `*.h5` and `*.jld2` artifacts anywhere;
- Perlmutter `$PSCRATCH` checkpoints.

Consequently, a successful Git pull can still leave the active control paths
unresolvable. This is expected until `output/` is transferred separately.

## Exact cross-device transfer procedure

### 1. Commit and push code plus documentation from this device

Run from the QSL repository root. Review before committing; these commands do
not include the unrelated root `.DS_Store`:

```bash
cd /Users/kevin/Code/QSL
git status --short -- project_b_flux_dimensional_reduction
git add -A -- project_b_flux_dimensional_reduction
git diff --cached --check
git diff --cached --name-status
git diff --cached --stat
git commit -m "Add Project B MPSKit iDMRG handoff"
git push origin main
git rev-parse HEAD
```

Record the final commit SHA. No commit or push was performed automatically
while writing this handoff.

### 2. Pull that exact commit on the other device

First ensure the other checkout has no uncommitted work that a pull could
overwrite:

```bash
cd /PATH/TO/QSL
git status --short
git fetch origin
git switch main
git pull --ff-only origin main
git rev-parse HEAD
```

The printed SHA must equal the transfer commit recorded on this device.

### 3. Transfer the ignored run evidence

After the Git pull, use Globus with the `NERSC DTN` collection to copy exactly
this directory from Perlmutter into the matching desktop project directory:

```text
source:      /global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction/output/
destination: /PATH/TO/QSL/project_b_flux_dimensional_reduction/output/
direction:   Perlmutter -> other device
```

Use checksum comparison and keep destination mirroring/deletion disabled. Wait
for completion. Do not transfer `.git/`, `.julia/`, `tmp/`, or anything below
`$PSCRATCH` for this handoff.

Copying only `output/` here is intentional: GitHub has already supplied the
newer code and handoff documents, so a whole-tree Perlmutter-to-desktop transfer
could overwrite them with an older cluster snapshot.

### 4. Recreate dependencies rather than copying caches

For current iDMRG work, instantiate the isolated environment on the other
device:

```bash
cd /PATH/TO/QSL/project_b_flux_dimensional_reduction
julia --startup-file=no --project=idmrg -e 'using Pkg; Pkg.instantiate()'
```

Instantiate the root environment separately only when root ITensor/VUMPS
analysis is needed:

```bash
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate()'
```

Do not copy `.julia/`; the committed manifests are the dependency authority.

## First checks for the new chat

The new chat should report, without changing anything:

1. repository root, branch, `git rev-parse HEAD`, and `git status --short`;
2. both active-control reference paths and hashes;
3. whether every referenced ignored artifact exists locally after Globus;
4. the current remote benchmark status from Perlmutter;
5. whether reconciliation and sync-back are required;
6. only then, the smallest justified next action.

It must preserve the accepted `theta/pi=0.15` lineage, all rejected labels,
U(1), period 2, uniform gauge, immutable hashes, working versus original
convergence profiles, storage boundaries, one-job/budget guards, and explicit
submission authorization.
