# Configuration guide

`phase1_idmrg_active_control.ref` is the two-line operational pointer for the
current iDMRG package: relative control path followed by exact SHA-256. It lets
the project owner use bare `plan`, `submit`, `status`, `reconcile`, and
`analyze` launcher commands without weakening immutable-control validation.
Update it only after a new iDMRG control has been generated and locally
validated; never choose an active package by modification time.

The current pointer selects the guarded `theta/pi=0.15 -> 0.175` recovery step
described in `docs/PHASE1_IDMRG_SWEEP_RECOVERY.md`. It starts from the accepted
lineage parent itself, uses the predeclared working convergence profile and the
benchmarked 2-thread/4-CPU Shared allocation, and has no automatic submission
or advance.

`phase1_idmrg_benchmark_active_control.ref` is the separate two-line pointer
for the low-cost iDMRG resource benchmark. It supports the same bare
`plan`, `submit`, `status`, `reconcile`, and local `analyze` actions through
`slurm/run_idmrg_benchmark_cpu.sh`. The benchmark pointer never replaces the
scientific control pointer and cannot authorize a continuation or state
promotion. Jobs `57548405` and `57550459` both failed before a scientific
update—the first from Slurm-spool project-root resolution and the second from
an unsupported Julia 1.12 CPU-timing call. Job `57574096` completed five
2-thread updates but then failed because HDF5 0.17.3 cannot serialize a packed
`BitVector`; its partial temporary file contains no timing histories. The
pointer now names a distinct schema-4 package that hash-pins all three failures.
Its `plan` action executes the real worker preflight with an explicit project
root, corrected process CPU timing, exact package-version checks, and the actual
HDF5 result writer/readback before `submit` is available.

Benchmark job `57576411` subsequently completed all 2/4/8/16-thread steps with
exit `0:0`. Independent analysis selected two Julia threads and four Slurm
logical CPUs by projected Shared-QOS node-hours per 100 updates. The benchmark
pointer is retained as immutable evidence; it is not a scientific parent.

`phase1_idmrg_working_convergence.toml` records the project owner's exploratory
iDMRG thresholds for controls prepared after job `57500598`: bond-matrix update
norm at most `1e-5` and final-four intensive-energy span at most `1e-8`. The
policy does not rewrite the immutable criteria or rejection recorded by that
completed job. A future control using the working pair must carry the exact
`phase1_exploratory_working_20260824` profile label, and native passage still
does not replace the overlap, observable, U(1), and branch-continuity gates.
The iDMRG control preparers load the thresholds and policy SHA-256 from this
file, and the validator rejects a future working-profile control if either
value or the policy digest differs.

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
  primary-forward restart on the requested `0.0,0.1,...,1.0` grid. Job
  `57192723` accepted `0.0` and `0.1` before the direct `0.2` update diverged.
  It retains the strict `1e-5` residual and `0.99` overlap gates, records
  Krylov solves, and uses a distinct lineage and output directory.
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
minimum was `3.424244e-5`. The low-chi corrector sequence is closed. The fresh
chi-512 job `57192723` then accepted `theta/pi=0.0` and `0.1`, but the direct
`0.1 -> 0.2` step reached a minimum `1.013369e-4` before stopping as
`diverging_residual`. Job `57245573` then tested the exact-parent `0.15`
midpoint: its minimum improved to `4.279781e-5` but the sequential update still
diverged, with all inner solves and retrospective branch diagnostics healthy.
Launcher 2.6.0 admits one final generated control at the same parent/target with
`multisite_update_alg="parallel"`; it is not a reusable hand-written config.
Generate and submit it only through the procedure in
`docs/PHASE1_FINAL_VUMPS_CONTROL.md`. The standalone
`scripts/prepare_phase1_chi512_bridge_from_0p1.jl` produces the same complete
remaining schedule as a compatibility fallback. The legacy resume generator
remains only for manual recovery of older runs and must not replace the pinned
final control.

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
