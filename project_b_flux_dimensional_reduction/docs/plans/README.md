# Project B plan index

This page routes a fresh task to the smallest relevant execution plan. Detailed
plans remain at their established paths to preserve links from controls and
historical handoffs.

## Active

| Workstream | State | Plan |
|---|---|---|
| Review follow-up: accounting, evidence audit, matched solver pilot | clean remote worktree confirmed; pull tracked v2 control, then live preflight | [REVIEW_FOLLOWUP_IMPLEMENTATION.md](REVIEW_FOLLOWUP_IMPLEMENTATION.md) |
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
