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
- `phase1_yc8_1_forward_chi512_legacy_0p1.toml`: fresh high-bond-dimension
  primary-forward restart on the requested `0.0,0.1,...,1.0` grid. It retains
  the strict `1e-5` residual and `0.99` overlap gates, records Krylov solves,
  and uses a distinct lineage and output directory.
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
chi 192, with SHA-256
`312f08abf8c78f15382fac8165ebf138866be06bf0456fddd0d46995f272fc86`.
A strict restart must set both `initial_state_file` and the known
`initial_state_sha256`; the launcher and Julia scan independently verify that
digest before optimization.

Fixed-chi job `56994767` did not pass the `1e-5` gate at theta/pi=0.24609375:
chi 192 reached a minimum residual `2.254667e-5` after the corresponding chi-128
minimum was `3.424244e-5`. The low-chi corrector sequence is now closed. Submit
the checked-in fresh chi-512 config above. If an allocation ends because of
wall time after saving accepted points, use
`scripts/prepare_phase1_chi512_legacy_resume.jl` with the highest-index accepted
state and the SHA-256 verified on Perlmutter. The generator validates the exact
0.1-grid history and writes a distinct continuation config and output directory.

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

The `hu_yc8_*_forward.toml` files remain later-phase templates with different
tolerance, spectrum, and threading settings; do not substitute them for the
dedicated chi-512 Phase 1 campaign.

The built-in product seeds are `alternating`, `alternating_shifted`, `block`,
and `random_balanced`. The latter is reproducible through `random_seed`.

`twist_gauge = "uniform"` is the production convention because it preserves
the finite-flux translations used in Hu et al.'s momentum analysis. The MPS
period is inferred automatically. An explicit `mps_period` is accepted only for
diagnostic commensurate supercells; such states are not unfolded during
momentum postprocessing.
