# Configuration guide

`phase1_idmrg_active_control.ref` is the two-line operational pointer for the
current iDMRG package: relative control path followed by exact SHA-256. It lets
the project owner use bare `plan`, `submit`, `status`, `reconcile`, and
`analyze` launcher commands without weakening immutable-control validation.
Update it only after a new iDMRG control has been generated and locally
validated; never choose an active package by modification time.

The current pointer selects the guarded `theta/pi=0.15 -> 0.1625` midpoint
described in `docs/PHASE1_IDMRG_SWEEP_RECOVERY.md`. Job `57611537` completed
the preceding theta/pi=0.175 retry and passed its predeclared working native
gate, but its `0.9662443394038124` overlap with the accepted theta/pi=0.15
parent failed the unchanged `0.99` branch gate. The midpoint package hash-pins
that result and both immutable analyses, starts from the accepted lineage
parent rather than the rejected tensor, requests 10 allocation logical CPUs,
and launches the benchmarked two-Julia-thread solver in an exact
four-logical-CPU step. Standing owner authorization covers guarded submission
after a successful live plan; automatic advance remains disabled.

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

- `science_yc6_1_legacy_period6_chi512.toml`: independent scientific
  recreation of the legacy YC6-1 chi-512 six-site-supercell trajectory. It
  retains the `1e-5` VUMPS residual target, records inner-solver and continuity
  diagnostics, and adaptively brackets the old basin jump without touching the
  accepted YC8-1 lineage. Use only through
  `slurm/run_yc6_1_recovery_cpu.sh`; see
  `docs/YC6_1_CHI512_RECOVERY.md`.
- `science_yc6_1_legacy_period6_chi512_after_57629467.toml`: strict-lineage
  continuation after the 48-hour timeout. It hash-pins the accepted
  `theta/pi=0.3` state (`741261e9...`), restarts at `0.35`, preserves the
  rejected `0.4` state only as evidence, writes to a distinct output tree, and
  requests a full-state optimizer checkpoint every five completed iterations.
  Launcher 1.2.0 routes those heavy checkpoints to a job-specific `$PSCRATCH`
  directory and leaves only compact resume controls in the project output.
- `science_yc6_1_legacy_period6_chi512_tol1e4_after_p0p3375.toml`:
  explicitly authorized exploratory continuation with a `1e-4` VUMPS outer
  residual gate. It hash-pins the stricter-profile accepted `theta/pi=0.3375`
  state (`ac239341...`), repeats `0.35` without importing the old-tolerance
  checkpoint, preserves all other solver and branch gates, and writes to a
  distinct `tol1e4` output tree. This is launcher 1.3.0's default.
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

An optimizer checkpoint is intentionally separate from an accepted restart. It
requires strict lineage, exactly one target flux, immutable SHA-256 provenance,
matching model and branch metadata, and—when an accepted parent exists—the
same accepted-parent hash and parent flux history. A checkpoint MPS may be at
an intermediate growth dimension not exceeding the requested chi. Supported
numerical-seed reasons are `periodic_checkpoint`, `growth_stage_checkpoint`,
`pretimeout_checkpoint`, and the historical
`maximum_iterations_contracting`. Each new checkpoint receives a generated
hash-pinned one-point resume configuration. A checkpoint or rejected artifact
remains a numerical seed: it must never be placed in `initial_state_file`, have
its acceptance flag edited, or replace the accepted lineage parent.

All Phase 1 configs set `require_parent_overlap = true`, so the mixed-transfer
overlap and the associated observable diagnostics are always computed after a
parent exists. Historical controls use `continuity_policy = "overlap_floor"`
implicitly and retain their immutable cutoff semantics. The new
`science_yc8_1_primary_forward_chi1024_bridge.toml` instead uses
`continuity_policy = "multimetric_trust_region"`: its `0.90` overlap value is
an alarm floor, while entropy, local-energy, magnetization, Schmidt-spectrum,
resolved neutral/spin-1 correlation-length, and U(1)-sector diagnostics decide
branch acceptance. Its execution profile pins parallel VUMPS, four Julia
threads in an eight-logical-CPU solver step, single-threaded BLAS and Strided,
and threaded BlockSparse contractions. See
`docs/YC8_1_CHI1024_BRIDGE.md` for its calibration and reverse-consistency
requirement. The same document describes the hash-gated generator that can
emit the `0.475:0.025:1.0` successor only after all reverse comparisons pass.

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
