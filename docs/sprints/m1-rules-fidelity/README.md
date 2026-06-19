# Sprint M1 — Rules Fidelity

Living backlog for the M1 milestone (Rules Fidelity) of the AoECard roadmap.

## What lives here

- `tasklist.md` — the ordered, technical task list for all M1 items. **This is the source of truth for sprint status.** Each item carries verified code references (files, line numbers, exact bugs) so any future SDD run can start from it.
- This folder does **not** hold SDD artifacts. When we work a part, its SDD change lives in `openspec/changes/<change-name>/` (OpenSpec convention, per user decision 2026-06-17).

## Workflow

1. Pick the next ready phase from `tasklist.md` (respect dependency order).
2. Run one **SDD change** for that phase:
   `explore → proposal → spec → design → tasks → apply → verify → sync → archive`
3. After each SDD phase completes, **update `tasklist.md`** (flip the checkbox, set the SDD status, log the commit/artifact link).
4. The M1 gate runs at the end of Phase 6.

## Scope decision

`CLAUDE.md` says SDD artifacts live in engram. For this sprint, the artifact store is **OpenSpec** (`openspec/changes/`), per explicit user override. This README records that override; update `CLAUDE.md` separately if the project wants the OpenSpec default to stick.

## Why M1 is split into 6 SDD changes (not one)

M1 touches 6 loosely-coupled areas (data cleanup, play-loop, destinos/provincias, tácticas/stronghold, efectos/métricas, gate). One SDD change for all of M1 would violate the design size budget and the cohesion contract (single rollback plan). Splitting by phase keeps each change reviewable and respects the real code dependencies. See `tasklist.md` for the dependency graph.
