# Promoted chi-512 parallel-VUMPS continuation

## Decision

Final-control job `57337312` resolved the sequential-versus-parallel comparison
at `theta/pi=0.15`. With the exact accepted `0.1` parent and every other model,
optimizer, continuity, and resource setting unchanged, parallel VUMPS reduced
the residual monotonically from `4.224217e-4` to `9.183773e-6` in 10 outer
iterations. All 60 inner Krylov solves converged and parent overlap per site was
`0.9999782682`.

The accepted state is therefore promoted as the next primary-forward parent:

- state SHA-256:
  `38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803`;
- source control config SHA-256:
  `78a2a320b8fe641947336989188cd5c3e33b2607b1c29037ff88c3d664c43b93`;
- successful manual-review decision SHA-256:
  `19e2e1e6f58752d6540672c311d23767aed7a45270b3528be476567da77ff778`.

This promotion is specific to YC8-1, chi 512, the labeled
`primary_forward_chi512_legacy_0p1` lineage, and the pinned state above. It does
not authorize parallel VUMPS for another branch, chi, or geometry.

## Continuation contract

The next job starts from accepted `theta/pi=0.15` and schedules
`0.2,0.3,...,1.0`. Thus it rejoins the requested legacy `0.1*pi` grid at `0.2`;
the successful `0.15` bridge remains an extra accepted point and is not rerun.

The following settings remain unchanged:

- chi 512 and residual tolerance `1e-5`;
- strict parent lineage and overlap per site at least `0.99`;
- complete inner-Krylov diagnostics;
- two Julia threads, four scan CPUs, 8 GiB, and a 24-hour reservation;
- adaptive midpoint recovery no finer than `0.05*pi`;
- best-iterate preservation for rejected diagnostics only.

Later numerical recovery uses the existing guarded automatic policy. A clean
partial job resumes from its last immutable accepted state. A failure on a
`0.1*pi` interval may insert its `0.05*pi` midpoint. A demonstrably contracting
corrector at the step floor may receive a bounded iteration-cap retry. The
launcher stops for continuity loss, an inner-solver failure, exhausted
numerical recovery, changed evidence, or unsupported scheduler failure. iDMRG
is the next solver only after that promoted parallel recovery is exhausted; it
is not selected automatically.

## Safe Perlmutter generation and submission

First synchronize launcher 2.7.0, the source, scripts, tests, and documentation
to Perlmutter without replacing remote `output/`. Then run these commands on
Perlmutter:

```bash
cd /global/homes/k/kwang98/QSL/project_b_flux_dimensional_reduction

grep '^readonly LAUNCHER_VERSION=' slurm/run_scan_cpu.sh
# Expected: readonly LAUNCHER_VERSION="2.7.0"

control_run=output/phase1_jobs/20260821T014357Z-yc8-1-primary_forward_chi512_legacy_0p1-512
accepted_state=output/phase1_tests/yc8_1/parallel_update_p0p10000000_to_p0p15000000_chi512_f71fc084883e_b5ef48caaf7a/chi512/states/state_0001_yc8-1_primary_forward_chi512_legacy_0p1_independent_theta0_alternating_chi512_forward_seed101_chi512_theta_p0p15000000_accepted_aca60c183c9d.h5
accepted_sha256=38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803

sha256sum "$accepted_state" \
  "$control_run/config.snapshot.toml" \
  "$control_run/automatic_advance.toml"
# Expected, in order:
# 38312fc996f...  accepted state
# 78a2a320b8fe...  control config snapshot
# 19e2e1e6f587...  successful control decision

julia --project=. --startup-file=no \
  scripts/prepare_phase1_chi512_parallel_continuation.jl \
  "$accepted_state" \
  "$accepted_sha256" \
  "$control_run"

continuation_dir=output/phase1_generated_configs/chi512_parallel_promoted_from_p0p15000000_38312fc996fe
continuation_config="$continuation_dir/phase1_chi512_parallel_automatic.toml"

bash slurm/run_scan_cpu.sh plan "$continuation_config"
```

The plan must report:

- `parallel / restore-best=true`;
- flux schedule `0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0`;
- accepted initial-state SHA-256 beginning `38312fc996fe`;
- chi 512, residual tolerance `1e-5`, and outer cap 180;
- overlap floor `0.99` and recorded inner solves;
- zero existing immutable states in the new output directory; and
- worst-case reservation `0.562500000` node-hours.

Only after those fields match, submit exactly that generated configuration:

```bash
bash slurm/run_scan_cpu.sh submit "$continuation_config"
```

The generator and launcher are fail-closed. If the generator reports that its
configuration already exists, do not delete or regenerate it; inspect and plan
the existing immutable configuration at `continuation_config`.

## Monitoring and terminal workflow

Monitor through the launcher:

```bash
bash slurm/run_scan_cpu.sh status
```

After the allocation becomes terminal, reconcile and ask the non-submitting
automatic policy for the next decision:

```bash
bash slurm/run_scan_cpu.sh reconcile
bash slurm/run_scan_cpu.sh advance
```

If `advance` prepares another configuration, inspect its printed plan. Submit
it only with the explicit command printed by the launcher, equivalently:

```bash
bash slurm/run_scan_cpu.sh advance-submit RUN_ID
```

Every allocation remains a single job that may process multiple theta points.
It becomes terminal only when that allocation completes its remaining schedule,
records a guarded scientific stop, hits its time limit, or encounters an
infrastructure/process failure. An accepted theta point by itself does not end
the job.
