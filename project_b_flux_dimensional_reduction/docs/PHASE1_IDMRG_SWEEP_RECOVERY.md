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

The active scientific control is:

```text
output/phase1_idmrg/yc8_1/theta_p0p17500000_from_38312fc996fe_working_shared16g_charge_corrected/phase1_idmrg_sweep_step_control.toml
SHA-256 622b299613eaf10a859cc1bd9d7d773890359fac4389b610d40dcf8d518e52e4
```

Its immutable ITensor-to-MPSKit bridge SHA-256 is
`42d8410dfacbc00ebf51bf9e613e4bcbf7ba3fa795be12c273902b781dfc7d5c`.
A local MPSKit reconstruction gave an independent target-Hamiltonian energy
difference of `7.956895820004917e-8`, below the unchanged `1e-6` equivalence
guard.

An earlier unsubmitted local preparation used control SHA-256
`94b5bcf4404eabcdd5eaa9fcb7bade7e5de60a26fc281e633ec870da2ec5f160`.
It is preserved but superseded because its maximum-charge field omitted the
Shared-QOS memory-rounding step. It was never active on Perlmutter and must not
be submitted.

## Resource selection and budget

Perlmutter benchmark job `57576411` completed successfully. The independent
resource conclusion selects two Julia threads, four Slurm logical CPUs,
`--cpu-bind=cores`, 16 GiB, and Shared QOS. The control permits at most 400
one-site updates in 12 hours. Sixteen GiB rounds to five charged physical
cores under the recorded NERSC formula, giving a maximum forecast charge of `0.46875`
node-hours.

Before this control, reconciled usage is
`12.25235894158889 / 20` Phase 1 node-hours and
`13.34679194158889 / 150` Project B node-hours. The control permits one job,
has no automatic advance, and does not pre-authorize submission.

## Operator boundary

After Git and ignored output artifacts have been synchronized to Perlmutter,
the read-only authoritative check is:

```bash
cd /global/u2/k/kwang98/QSL/project_b_flux_dimensional_reduction
module load julia
bash slurm/run_idmrg_cpu.sh plan
```

Only a later literal `submit` command authorizes Slurm mutation. After a
successful run, reconcile and sync the package, then use the bare local
`analyze` action. Promotion still requires native passage, the unchanged
parent-overlap gate, common observables, sector diagnostics, and a finite
discarded one-update VUMPS stationarity probe. No successor point is prepared
or submitted automatically.
