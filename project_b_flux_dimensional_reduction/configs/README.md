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
- `phase1_yc8_1_forward_recovery_from_0p23828125_chi128.toml`: current
  strict-lineage continuation from the accepted theta/pi=0.23828125 state. The
  synchronized theta/pi=0.2421875 residual was still contracting at iteration
  200, so this config preserves the inner solver, permits 360 outer iterations,
  records every inner Krylov solve, and enables plateau detection.
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
must resolve its exact accepted parent artifact; the current third recovery is
pinned to theta/pi=0.23828125 with SHA-256
`b6b54e47f894158f291e0f9851bce4fdc2322e31a49d3b79155acf21059ebeee`.
They fail closed if the immutable parent hash or strict lineage metadata does
not match the primary-forward branch. A strict restart must set both
`initial_state_file` and the known `initial_state_sha256`; the launcher and the
Julia scan independently verify that digest before optimization.

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
