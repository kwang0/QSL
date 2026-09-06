# Phase 1 iDMRG sweep recovery

## Scientific decision

The completed `theta/pi=0.20` iDMRG continuation is not an accepted member of
the primary-forward lineage. Its immutable source control still rejects it
under the original `1e-8` bond-matrix-update and `1e-9` energy-span criteria.
A separate working-profile analysis preserves that classification, recomputes
the owner-selected `1e-5` and `1e-8` native gates as passed, and then rejects
promotion because the overlap with the accepted `theta/pi=0.15` parent is only
`0.9662307284691443`, below the fixed `0.99` branch gate.

The source result remains a rejected numerical seed. Its final MPSKit
bond-matrix update norm is `2.311348784022773e-6`; this is
`norm(C_new-C_old)` after a complete unit-cell sweep. It is not discarded
weight and is not the VUMPS projected residual. A discarded one-update VUMPS
stationarity probe from an earlier analysis attempt gave approximately
`1.633749e-5`; that probe does not change either native or branch acceptance.

The job history first satisfies the working native gate at iteration 303. By
then its intensive energy density has already moved to the lower-energy basin
seen in the branch-rejected final state. The saved iteration-300 and
iteration-320 checkpoints are therefore retained as immutable numerical
evidence, not selected as sweep parents.

## Next guarded point

The smallest forward recovery step is the midpoint of the failed interval:

```text
parent theta/pi                    0.15
target theta/pi                    0.175
lineage-root/parent SHA-256        38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803
numerical seed                     accepted parent itself
branch                             primary_forward_chi512_legacy_0p1
representation                     U(1), period-2 YC8-1, uniform twist gauge
native bond-matrix-update gate     1e-5
native final-four energy-span gate 1e-8
parent-overlap gate                0.99
```

No rejected VUMPS or iDMRG tensor participates in this startup state.

The first submitted control was:

```text
output/phase1_idmrg/yc8_1/theta_p0p17500000_from_38312fc996fe_working_shared16g_charge_corrected/phase1_idmrg_sweep_step_control.toml
SHA-256 622b299613eaf10a859cc1bd9d7d773890359fac4389b610d40dcf8d518e52e4
```

Its immutable ITensor-to-MPSKit bridge SHA-256 is
`42d8410dfacbc00ebf51bf9e613e4bcbf7ba3fa795be12c273902b781dfc7d5c`.
A local MPSKit reconstruction gave an independent target-Hamiltonian energy
difference of `7.956895820004917e-8`, below the unchanged `1e-6` equivalence
guard.

That control ran as Perlmutter job `57608599` and failed after eight seconds,
before Julia or any scientific update. Its exact log reports
`SLURM_CPUS_PER_TASK=9 != SLURM_TRES_PER_TASK=cpu=4`: 16 GiB expanded the
Shared-QOS allocation to 10 logical CPUs, while the batch task still declared
four. The reconciled sacct SHA-256 is
`fc4f6830d0a18fae918f50409cce725d6fc675388657ab64a8c806411754582e`;
the log SHA-256 is
`c91376b758a9fa143cf7e36fbb7a3d4d79688486d7e9d665c02126a17377f126`.
The package remains an immutable zero-update infrastructure failure.

The active retry control is:

```text
output/phase1_idmrg/yc8_1/theta_p0p17500000_from_38312fc996fe_working_shared16g_retry_after_57608599/phase1_idmrg_sweep_step_control.toml
SHA-256 a3b75247770cb86a3c155d48dfecf438b1e21b98119b3b8ed2db51a4868d02de
```

Its independently generated bridge SHA-256 is
`533f772c47d715535e6db1da274fb48bde5162dcb90e11d2665bdb9e89fe5b61`.
The control hash-pins both failure artifacts, retains the accepted parent as
its numerical seed, and uses a distinct home package and PSCRATCH namespace.

Perlmutter job `57611537` completed that retry with exit `0:0` after 33,423
seconds. It performed 371 one-site updates. The immutable result SHA-256 is
`03734ddbc4389a45428d69f961a0fdd0adda80567641c383d2f97998be734676`;
its final MPSKit bond-matrix update norm is `9.784243012995464e-6`, and its
final-four intensive-energy span is `1.6997034890664509e-9`. Both pass the
predeclared working native profile. The lightweight archive SHA-256 is
`e7a488e685e68026132a3d48cec09c1e019eb777df0d09e3b93669699fa70b78`,
the reconciled sacct SHA-256 is
`6888060a71a20ef0b2dbdceeb34eebc093b94dac9bf31cf79dc7dd1187172a0d`,
and the job-log SHA-256 is
`4af8d9ed4adcd9c6612344c937478eb8e25b45c8b177e989a7f1d9547340939d`.

The first postprocessing attempt was immutably rejected before branch gates
because a single transfer-fixed-point matrix pivot left a
`5.2672601943421586e-9` global phase error, above the unchanged `1e-9`
Hermitian-correction gate. Its analysis SHA-256 is
`37562ba47872de88494894e61fdcde9da6f67954ecdbbf83fe80dd99526c62bd`.
Independent diagnostics showed an isolated leading transfer eigenvalue
(magnitude gap `0.19903524674262085`) and eigen-residual
`4.7470841273425886e-15`. Aligning the arbitrary Arnoldi phase from the full
Hermitian-partner overlap reduced the correction to
`3.726441839017409e-15` without changing the gate. The phase-alignment fix is
covered by regression tests and preserves the first rejection artifact.

The resulting full immutable analysis SHA-256 is
`302b6db4a8e90d568dc61c82c2f8d2b37e588fa3125b69b5cced91752b99fe47`.
It confirms native convergence but rejects branch promotion: overlap per site
with the accepted theta/pi=0.15 parent is `0.9662443394038124`, below `0.99`.
The common one-update VUMPS stationarity probe was therefore not run. The
theta/pi=0.175 state remains a branch-rejected numerical seed only.

An earlier unsubmitted local preparation used control SHA-256
`94b5bcf4404eabcdd5eaa9fcb7bade7e5de60a26fc281e633ec870da2ec5f160`.
It is preserved but superseded because its maximum-charge field omitted the
Shared-QOS memory-rounding step. It was never active on Perlmutter and must not
be submitted.

## Second midpoint recovery

The failed primary-forward interval is now `0.15 -> 0.175`, so the next guarded
point is its midpoint:

```text
parent theta/pi                    0.15
target theta/pi                    0.1625
lineage-root/parent SHA-256        38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803
numerical seed                     accepted parent itself
rejected theta/pi=0.175 result     evidence only; not the startup tensor
branch                             primary_forward_chi512_legacy_0p1
representation                     U(1), period-2 YC8-1, uniform twist gauge
native bond-matrix-update gate     1e-5
native final-four energy-span gate 1e-8
parent-overlap gate                0.99
```

No rejected VUMPS or iDMRG tensor participates in the theta/pi=0.1625 startup
state. The package hash-pins job `57611537`, both immutable analyses, the full
and lightweight results, scheduler evidence, the benchmark selection, and the
earlier theta/pi=0.20 rejection chain.

The prepared active package is:

```text
output/phase1_idmrg/yc8_1/theta_p0p16250000_from_38312fc996fe_working_shared16g_after_57611537/phase1_idmrg_sweep_step_control.toml
control SHA-256 35fe2a21c4c68074bc43a2dc113e8e3256e8ad0ed6a59360f1c3f28c3f9e5ec6
bridge SHA-256  238eff157bb38f30b6453411e7ef5a45069e789cf445ff76f041b48858f42c42
```

## Resource selection and budget

Perlmutter benchmark job `57576411` completed successfully. The independent
resource conclusion selects two Julia threads and a four-logical-CPU solver
step with `--cpu-bind=cores`, 16 GiB, and Shared QOS. The retry requests 10
logical CPUs for the memory-sized outer allocation, then launches the solver
with `srun --exact --exclusive --nodes=1 --ntasks=1 --cpus-per-task=4`.
It permits at most 400 one-site updates in 12 hours. Sixteen GiB still rounds
to five charged physical cores, so the maximum forecast remains `0.46875`
node-hours.

Job `57608599` adds a derived `0.00008680555555555556` node-hours: eight
seconds times five charged physical cores divided by 128 cores per node. Before
the retry, usage is `12.252445747144446 / 20` Phase 1 node-hours and
`13.346878747144446 / 150` Project B node-hours.

Completed job `57611537` adds `0.3626627604166666` node-hours: 33,423 seconds
times five charged physical cores divided by 128 cores per node. Reconciled
usage is now `12.615108507561112 / 20` Phase 1 node-hours and
`13.709541507561113 / 150` Project B node-hours. The theta/pi=0.1625 control
retains the `0.46875`-node-hour ceiling and one-job/no-automatic-advance guard.

## Operator boundary

After Git and ignored output artifacts have been synchronized to Perlmutter,
the read-only authoritative check is:

```bash
cd /global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction
module load julia
bash slurm/run_idmrg_cpu.sh plan
```

The project owner's standing authorization permits the guarded `submit` action
after a successful live `plan`; no additional approval exchange is required.
After a successful run, reconcile and sync the package, then use the bare local
`analyze` action. Promotion still requires native passage, the unchanged
parent-overlap gate, common observables, sector diagnostics, and a finite
discarded one-update VUMPS stationarity probe. No successor point is prepared
or submitted automatically.
