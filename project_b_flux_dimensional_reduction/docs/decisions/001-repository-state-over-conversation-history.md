# 001 - Repository state over conversation history

Status: accepted

Date: 2026-09-06

## Context

Project B spans long Codex conversations, automatic context compactions,
multiple computers, Git transport, ignored run evidence, and live Perlmutter
state. Important constraints and numerical conclusions had accumulated in both
chat and an increasingly large `AGENTS.md`. A fresh task could therefore load
stale operational history, miss a recent result, or ask the owner to reconstruct
an earlier conversation.

## Decision

Project continuity is repository-first and split by semantic role:

- `AGENTS.md` contains durable rules and safety boundaries only.
- `PROJECT_STATE.md` is the rolling current objective, endpoint, evidence
  boundary, known issues, and priority list.
- `ARCHITECTURE.md` holds stable authority, environment, data-flow, and storage
  design.
- `docs/plans/` routes active execution work; campaign plans retain detailed
  discoveries and progress.
- `docs/decisions/` preserves non-obvious rationale.
- Git retains exact implementation history.
- `NEW_TASK_PROMPT.md` contains a status-free bootstrap.
- `scripts/audit_project_context.jl` performs the same read-only Git/control
  audit on Windows and Perlmutter.
- Conversation and Codex memory may help navigation but are never scientific,
  operational, or hash authority.

A small `AGENTS.md` at the parent Git root routes Project B work to the
subtree-specific instructions even when a task is opened from the QSL root.

## Consequences

- A new task can reconstruct the project without access to an old chat.
- Dated handoffs remain useful provenance but cannot silently override current
  state.
- `PROJECT_STATE.md` must be updated when a material endpoint, unknown, issue,
  or priority changes; otherwise the structure still permits staleness.
- Live Perlmutter facts remain deliberately outside version-controlled claims
  until captured in compact evidence and synchronized.
- The instruction chain is shorter and less polluted by historical jobs, but a
  task must explicitly read the routed state and plan files before acting.

## Evidence

- OpenAI's `AGENTS.md` guidance documents root-to-working-directory discovery,
  local precedence, and rebuilding the instruction chain for each new run:
  <https://learn.chatgpt.com/docs/agent-configuration/agents-md>.
- The project audit passes from both the Project B directory and the parent Git
  root on the Windows checkout and validates both active-control hashes.
