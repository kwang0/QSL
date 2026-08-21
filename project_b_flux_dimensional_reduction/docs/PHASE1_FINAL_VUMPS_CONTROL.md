# Final chi-512 VUMPS control before an iDMRG pivot

## Scientific question

The accepted YC8-1 primary-forward chi-512 lineage currently ends at
`theta/pi=0.1`. Sequential VUMPS failed both the direct `0.1 -> 0.2` update and
the halved `0.1 -> 0.15` update even though the parent/candidate overlap,
virtual U(1) support, and every recorded inner Krylov solve remained healthy.
The last unresolved VUMPS-specific variable is the library's multisite update
schedule.

This final control therefore retries only `theta/pi=0.15` from the exact
accepted `0.1` parent with `multisite_update_alg="parallel"`. Chi 512, the
`1e-5` residual gate, all inner-solver settings, the `0.99` parent-overlap gate,
the model, seed, minimal cell, and uniform twist gauge remain unchanged. The
one-point schedule isolates the comparison; it is not a new fine-step campaign.

## Pinned source evidence

- accepted `theta/pi=0.1` parent SHA-256:
  `f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc`;
- sequential `theta/pi=0.15` source job: `57245573`;
- submitted sequential config SHA-256:
  `1a272abe6879c69827d1f14547a0b6d4780083945e414ad3f1cb9ee1a050749f`;
- sequential outcome SHA-256:
  `001eadee6f43e73fa9228c4221c8ac81edc821db58a391625037806b16e0b2cf`;
- sequential rejected-candidate SHA-256:
  `b5ef48caaf7a10eb00e4fd003e8fd1b5a57add77a8111b270a358a7c8f049953`.

Job `57245573` reached its lowest residual, `4.279780651e-5`, at outer
iteration 13 and stopped for residual divergence at iteration 32 with residual
`1.027012e-3`. All 320 inner solves converged. A retrospective read-only check
gave parent overlap per site `0.9999724354`; both cuts retained identical U(1)
sector labels and multiplicities, with sector-weight total-variation distances
`0.00127015` and `0.00107379`. Halving the step improved the minimum residual
by about `2.37x` relative to the direct `0.2` attempt, but it still missed the
acceptance tolerance by `4.28x`.

## Failure artifact and acceptance rule

Only this pinned control enables `restore_best_on_failure=true`. The optimizer
keeps an in-memory copy of each newly lowest-residual iterate. If the outer
trajectory later diverges or plateaus, the saved rejected HDF5 artifact contains
that lowest-residual MPS rather than the degraded terminal iterate. Schema-v7
states and schema-v4 flux outcomes record both values through
`optimizer/residual`, `optimizer/terminal_residual`, `optimizer/best_iteration`,
`optimizer/returned_iteration`, and `optimizer/restored_best_on_failure`.
They also store the requested `optimizer/multisite_update_alg` and
`optimizer/restore_best_on_failure_enabled` settings explicitly.

This is diagnostic preservation only. It cannot make a point accepted: the
candidate must still reach residual at most `1e-5`, have every recorded inner
solve converge, and pass parent overlap per site at least `0.99`. A restored
candidate remains explicitly rejected.

The outcomes are:

- **VUMPS control passes:** an immutable accepted `theta/pi=0.15` state exists,
  there is no `scan_outcome.toml`, and all numerical and continuity gates pass.
  Stop for review before promoting parallel VUMPS to a longer campaign.
- **VUMPS control fails numerically:** a `scan_outcome.toml` records residual or
  continuity failure at `theta/pi=0.15`. End the VUMPS campaign and implement
  the iDMRG comparison next.
- **Allocation or implementation failure:** Slurm timeout/node failure, a
  nonzero scan-process exit, or absent scientific outcome is inconclusive.
  Diagnose or rerun the same control; do not count it as evidence for iDMRG.

## Perlmutter preparation and submission

Synchronize launcher 2.6.0 and the source/docs to Perlmutter without replacing
remote `output/`. Perlmutter remains authoritative. Then run:

The generator performs only SHA-256 and scalar HDF5-metadata validation on the
login node; it does not deserialize either chi-512 MPS or run optimization.

```bash
cd /global/homes/k/kwang98/QSL/project_b_flux_dimensional_reduction

grep '^readonly LAUNCHER_VERSION=' slurm/run_scan_cpu.sh
# Expected: readonly LAUNCHER_VERSION="2.6.0"

parent_state=output/phase1/yc8_1/primary_forward_chi512_legacy_0p1/seed_101/chi512/states/state_0002_yc8-1_primary_forward_chi512_legacy_0p1_independent_theta0_alternating_chi512_forward_seed101_chi512_theta_p0p10000000_accepted_12126bd1b66b.h5
parent_sha256=f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc
sequential_outcome=output/phase1/yc8_1/chi512_auto_refine_interval_from_p0p10000000_p0p15000000_to_p1p00000000_f71fc084883e/seed_101/chi512/scan_outcome.toml

sha256sum "$parent_state" "$sequential_outcome"
# Expected parent:  f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc
# Expected outcome: 001eadee6f43e73fa9228c4221c8ac81edc821db58a391625037806b16e0b2cf

julia --project=. --startup-file=no \
  scripts/prepare_phase1_chi512_parallel_control.jl \
  "$parent_state" \
  "$parent_sha256" \
  "$sequential_outcome"

test_dir=output/phase1_test_configs/parallel_update_p0p10000000_to_p0p15000000_chi512_f71fc084883e_b5ef48caaf7a
control_config="$test_dir/phase1_chi512_parallel_control.toml"

bash slurm/run_scan_cpu.sh plan "$control_config"
```

The plan must show `parallel / restore-best=true`, flux schedule `0.15`, chi
512, residual tolerance `1e-5`, the pinned parent hash, overlap floor `0.99`,
zero existing immutable states, and a `0.562500000` node-hour reservation.
Only then submit:

```bash
bash slurm/run_scan_cpu.sh submit "$control_config"
```

Monitor with the guarded launcher rather than running additional login-node
inspection loops:

```bash
bash slurm/run_scan_cpu.sh status
```

After the allocation becomes terminal:

```bash
bash slurm/run_scan_cpu.sh reconcile
bash slurm/run_scan_cpu.sh advance
```

`advance` never submits a successor for this final control. It writes the
immutable decision and reports either successful VUMPS review, the numerical
iDMRG pivot, or an inconclusive scheduler/implementation ending. Synchronize
the new run directory and its isolated `output/phase1_tests/` directory locally
before detailed scientific analysis.
