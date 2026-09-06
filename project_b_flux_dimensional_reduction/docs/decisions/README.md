# Project B decision index

Decision records preserve why a non-obvious choice exists. The established
documents below already serve that role and remain at their original paths so
existing links and immutable controls do not break.

| Decision | Status | Source |
|---|---|---|
| Make repository state authoritative over conversation history | accepted | [`001-repository-state-over-conversation-history.md`](001-repository-state-over-conversation-history.md) |
| Preserve labeled branches instead of building a minimum-energy envelope | accepted | [`../REPRODUCTION_PROTOCOL.md`](../REPRODUCTION_PROTOCOL.md) |
| Promote the SHA-pinned parallel-VUMPS chi-512 `theta/pi=0.15` state | accepted | [`../PHASE1_PARALLEL_VUMPS_PROMOTION.md`](../PHASE1_PARALLEL_VUMPS_PROMOTION.md) |
| Use MPSKit one-site iDMRG in an isolated Julia environment | accepted | [`../PHASE1_IDMRG_LIBRARY_DECISION.md`](../PHASE1_IDMRG_LIBRARY_DECISION.md) |
| Keep heavy optimizer checkpoints in Perlmutter scratch | accepted | [`../PHASE1_IDMRG_STORAGE.md`](../PHASE1_IDMRG_STORAGE.md), [`../YC8_1_CHI1024_BRIDGE.md`](../YC8_1_CHI1024_BRIDGE.md) |
| Treat the YC6-1 period-6 recovery as an independent diagnostic | accepted | [`../YC6_1_CHI512_RECOVERY.md`](../YC6_1_CHI512_RECOVERY.md) |
| Replace an overlap-only gate for the chi-1024 bridge with a multimetric trust region | active experiment | [`../YC8_1_CHI1024_BRIDGE.md`](../YC8_1_CHI1024_BRIDGE.md), `../../configs/phase1_yc8_1_multimetric_continuity.toml` |

Add a focused record here when a durable choice is not already explained by a
campaign document. Use this minimal form:

```text
# NNN - Decision title

Status: proposed | accepted | superseded
Date: YYYY-MM-DD

## Context
What forced a choice?

## Decision
What is now required?

## Consequences
What becomes easier, harder, or intentionally unsupported?

## Evidence
Which controls, artifacts, hashes, tests, or papers support it?
```

Do not create a record for transient debugging or copy a Git diff into one.
When a choice is superseded, retain the old record and link to the replacement.
