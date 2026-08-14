# Configuration guide

The supplied files cover the first Project B calculations:

- `pilot_yc6_1.toml`: a low-cost regression geometry matching the legacy scan.
- `phase1_yc8_1_forward_chi128.toml`: primary two-flavor threaded branch.
- `phase1_yc8_1_forward_recovery_from_0p21875_chi128.toml`: strict-lineage
  recovery from the accepted theta/pi=0.21875 primary state, using half-sized
  continuation steps and a distinct immutable output directory.
- `phase1_yc8_1_forward_recovery_from_0p2265625_chi128.toml`: second
  strict-lineage corrector from the accepted theta/pi=0.2265625 state. It keeps
  the 1e-5 residual gate, allows 200 iterations, requires parent overlap per
  site of at least 0.99, and refines down to 1/256 of pi.
- `phase1_yc8_1_forward_recovery_from_0p23828125_chi128.toml`: completed
  strict-lineage continuation from the accepted theta/pi=0.23828125 state. It
  accepted theta/pi=0.2421875 after 308 iterations, then bracketed a chi-128
  numerical plateau at theta/pi=0.24609375.
- `phase1_yc8_1_reverse_chi128.toml`: independently prepared two-flavor reverse basin diagnostic.
- `phase1_yc8_0_forward_chi128.toml`: primary four-flavor threaded branch.
- `phase1_yc8_0_reverse_chi128.toml`: independently prepared four-flavor reverse basin diagnostic.
- `hu_yc8_1_forward.toml`: the two-flavor Hu geometry, with the expected crossing at `theta/pi=1`.
- `hu_yc8_0_forward.toml`: the four-flavor Hu geometry, with the expected crossing at `theta/pi=2`.
- `yc6_1_chi_ladder_at_pi.toml`: a finite-entanglement ladder at the YC6-1 crossing.

For YC10, copy the corresponding YC8 file inside this project, change
`circumference`, give it a distinct `output_directory`, and use the Hu bond
dimensions only after the lower-cost workflow is clean.

For a reverse continuation, use a strictly decreasing `fluxes_over_pi` array.
The first Phase 1 reverse endpoint must be prepared independently, so the
supplied reverse configs intentionally omit `initial_state_file`. After that
endpoint exists, a restarted reverse job may use a converged artifact from the
same branch/preparation/direction/seed. `lineage_policy = "strict"` rejects a
checkpoint descended from the primary forward preparation.

The YC8-1 recovery configs are deliberately not independent preparations. Each
must resolve its exact accepted parent artifact and fails closed if the
immutable parent hash or strict-lineage metadata does not match the
primary-forward branch. The current accepted frontier is theta/pi=0.2421875,
chi 128, with SHA-256
`37fdbca9e3c5d1089085b709948cfbf854593301bb242c46c93c7895e76e7caf`.
A strict restart must set both `initial_state_file` and the known
`initial_state_sha256`; the launcher and Julia scan independently verify that
digest before optimization.

The fixed-flux chi-128 to chi-192 expansion completed without reaching the
residual gate, but its final 277 iterations contracted monotonically and project
the `1e-5` crossing near cumulative iteration 484. The next diagnostic is
generated rather than checked in because both absolute state paths must be
verified on Perlmutter. Use `scripts/prepare_phase1_fixed_flux_resume.jl` with
the accepted chi-128 parent and the SHA-pinned rejected chi-192 artifact. The
generated config permits 180 additional iterations at the same theta and keeps
generic plateau termination disabled. `initial_state_file` remains the accepted
branch parent; `optimizer_checkpoint_file` is a numerical seed only. Exact
commands and decision rules are in `docs/PHASE1_PLATEAU_DIAGNOSTICS.md`.

An optimizer checkpoint is intentionally more restrictive than an ordinary
restart. It requires strict lineage, exactly one fixed flux, both SHA-256
digests, the same model and branch metadata, the same accepted-parent hash, the
requested chi already present in the checkpoint MPS, and
`stop_reason=maximum_iterations_contracting`. A rejected artifact must never be
placed in `initial_state_file` or have its acceptance flag edited.

All Phase 1 configs set `require_parent_overlap = true`. Once a point has an
accepted parent, continuation acceptance requires both the optimizer residual
and a mixed-transfer overlap per site of at least
`minimum_parent_overlap_per_site`. `parent_overlap_tolerance` and
`parent_overlap_krylov_dimension` control only that one-eigenvalue diagnostic.
The first independently prepared endpoint is exempt because it has no parent.
The default `0.99` threshold is a configurable branch trust-region guard, not a
claim about a universal physical fidelity cutoff; inspect the stored overlaps
and audit metrics after the first real continuation job.

The `hu_yc8_*_forward.toml` files remain later-phase chi=512 templates; do not
substitute them for the sparse chi=128 Phase 1 configs.

The built-in product seeds are `alternating`, `alternating_shifted`, `block`,
and `random_balanced`. The latter is reproducible through `random_seed`.

`twist_gauge = "uniform"` is the production convention because it preserves
the finite-flux translations used in Hu et al.'s momentum analysis. The MPS
period is inferred automatically. An explicit `mps_period` is accepted only for
diagnostic commensurate supercells; such states are not unfolded during
momentum postprocessing.
