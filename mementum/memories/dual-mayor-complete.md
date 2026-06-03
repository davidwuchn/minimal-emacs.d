---
id: dual-mayor-phases-5-7-complete
date: 2026-06-03
type: milestone
status: complete
---

# Dual Mayor Implementation: All 7 Phases Complete

## What Was Built

### Phase 5: Cross-Mayor Communication
- `lisp/modules/gptel-auto-workflow-beads.el` — Lightweight bead protocol for GTM↔PMF communication
- `mementum/decisions/` + `TEMPLATE.md` — Human decision gate between mayors
- `gptel-auto-workflow-human-decision-gate` custom variable — configurable blocking
- Auto-file beads from research findings, auto-update from experiment results

### Phase 6: Full Separation
- `mementum/gtm/strategy-roadmap.md` — GTM owns strategy, PMF reads it
- Strategy I/O functions: `--read-gtm-strategy`, `--write-gtm-strategy`, `--ensure-gtm-strategy-template`
- GTM auto-start runs strategy evolution periodically
- PMF reads strategy focus at start of each run
- `assistant/commands/pmf-mayor-run.md` + `gtm-mayor-research.md` — Discrete command references

### Phase 7: Innovation Metrics
- PMF metrics: experiments/day, keep-rate %, hours per validation
- GTM metrics: findings/day, strategy accuracy %, PMF signal strength
- Dashboard templates updated with metric placeholders
- Auto-update on experiment/research completion

## Key Decisions
- **No `.claude/commands/`** — we use opencode/nucleus/gptel, not Claude. Used `assistant/commands/` instead.
- **projects.el parse error** — commit 1407ecf20 introduced an "end of file during parsing" error. Reverted to parent commit version.
- **Bead protocol** — Simple markdown frontmatter for cross-mayor communication, parsed by dedicated module

## Test Results
2149 tests, 2097 expected, 0 unexpected, 52 skipped — all passing.
