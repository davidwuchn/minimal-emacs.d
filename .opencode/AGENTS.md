# OV5 Local OpenCode Configuration

Project-specific agents and skills for Ouroboros V5 (OV5).

## Local Agents

- `ov5-architect` — Architecture decisions, cross-module design
- `pipeline-ops` — Pipeline operations, daemon management
- `mementum-curator` — Memory organization, synthesis

## Local Skills

- `run-pipeline` — Execute OV5 pipeline steps
- `sync-mementum` — Sync mementum across machines
- `ov5-status` — Check system health
- `brepl` — Bracket-fixing REPL for Elisp (evaluate, validate, auto-eval)

## Global Agents Used

- `@maintainer` (global) — Primary orchestrator
- `delegate-*` (global) — Task delegation
- `doc-explorer` (global) — Documentation
- `implementer` (global) — Code execution

## Model Routing

Uses global model routing. Local overrides:
- `ov5-architect` → delegate-opus (deep analysis)
- `pipeline-ops` → delegate-fast (quick commands)
- `mementum-curator` → delegate-qwen (second opinion)
