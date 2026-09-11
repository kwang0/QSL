# Project B plan index

This page routes a fresh task to the smallest relevant execution plan. Detailed
plans remain at their established paths to preserve links from controls and
historical handoffs.

## Active

| Workstream | State | Plan |
|---|---|---|
| Signed momentum calibration | proposed after full-flux review; preserve stored labels | [Decision 010](../decisions/010-fullflux-continuation-outcome.md) |
| YC8-1 Figures 2 and 3 reproduction | requirements and feasibility reviewed; growth/preparation and embedded-window gap solver proposed | [Decision 004](../decisions/004-yc8-1-figure-reproduction-feasibility.md) |
| Fixed-flux solver calibration | proposed; baseline upturn confirmed by bounded trial | [Decision 006](../decisions/006-relaxation-continuation-outcome.md) |
| YC8-1 primary-forward chi-1024 bridge and full theta sweep | blocked at fixed-flux chi growth; no theta advance | [`../YC8_1_CHI1024_BRIDGE.md`](../YC8_1_CHI1024_BRIDGE.md) |
| Phase 1 allocation and phase ordering | active | [`../PHASES_0_TO_4.md`](../PHASES_0_TO_4.md) |

The rolling endpoint, latest hashes, accounting correction, and ordered next
actions are in [`../PROJECT_STATE.md`](../PROJECT_STATE.md). That file wins over
older plan prose when a dated status differs.

## Paused or diagnostic

| Workstream | State | Plan |
|---|---|---|
| YC6-1 legacy-period-6 recovery | paused independent finite-size diagnostic | [`../YC6_1_CHI512_RECOVERY.md`](../YC6_1_CHI512_RECOVERY.md) |
| YC8-1 iDMRG midpoint recovery | prepared but not current main path | [`../PHASE1_IDMRG_SWEEP_RECOVERY.md`](../PHASE1_IDMRG_SWEEP_RECOVERY.md) |

## Completed decisions or historical plans

- [FULLFLUX_CONTINUATION.md](FULLFLUX_CONTINUATION.md): job 58179916,
  all 126 updates and 30 analyses through pi complete and reviewed. Magnetic
  drift and update dependence prevent stable Fig. 3 reproduction; absolute
  momentum labels require a signed convention calibration.

- [ROUNDTRIP_CONTINUATION.md](ROUNDTRIP_CONTINUATION.md): job 58131989,
  all 96 updates and 100 analyses complete, reconciled and reviewed. Local
  observables nearly return; spectra retain memory and magnetization grows.

- [RELAXATION_CONTINUATION.md](RELAXATION_CONTINUATION.md): job 58082150,
  all 464 updates and 50 analyses complete, reconciled and reviewed. Short
  spectra agree; prolonged relaxation changes states; no native pass or promotion.

- [REVIEW_FOLLOWUP_IMPLEMENTATION.md](REVIEW_FOLLOWUP_IMPLEMENTATION.md):
  accounting repairs, evidence audit, pilot 58005544, live reconciliation and
  synchronized review complete; all native gates failed, no promotion.
- [`../PHASE1_IDMRG_BENCHMARK.md`](../PHASE1_IDMRG_BENCHMARK.md): completed
  thread/resource benchmark and Shared-QOS selection.
- [`../PHASE1_FINAL_VUMPS_CONTROL.md`](../PHASE1_FINAL_VUMPS_CONTROL.md): final
  chi-512 parallel-control test that produced the accepted lineage root.
- [`../PHASE1_CROSS_DEVICE_HANDOFF.md`](../PHASE1_CROSS_DEVICE_HANDOFF.md):
  historical 2026-08-25 transfer snapshot, retained for provenance.

For a substantial new workstream, either create a focused plan in this
directory or designate an existing campaign document here. A plan should
contain its goal, invariants, completed and remaining steps, validation, and
dated durable discoveries. Keep raw logs and exploratory dialogue out of it.
