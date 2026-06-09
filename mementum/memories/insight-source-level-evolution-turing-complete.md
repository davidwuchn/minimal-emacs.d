---
title: Research insight — source-level evolution is Turing-complete
category: research
tags: self-evolution, MOSS, source-code, architecture
related: self-evolving-agent-research, OV5 architecture
created: 2026-06-09
---

# Research Insight: Source-Level Evolution is Turing-Complete

## Key Finding

MOSS paper (2605.22794, May 2026) argues that **source-level adaptation** is fundamentally more general than text-level evolution:

- **Turing-complete** — strict superset of every text-mutable scope
- **Deterministic** — takes effect via code execution, not base-model compliance
- **No drift** — does not erode under long-context drift

Most self-evolving agents only evolve text artifacts (prompts, skills, memory schemas) and leave the agent harness untouched. Since routing, hook ordering, state invariants, and dispatch live in code, an entire class of structural failure is physically unreachable from the text layer.

## OV5 Alignment

OV5 already does source-level evolution:
- Self-heal-semantic module detects and fixes code bugs
- Evolution runs experiments in git worktrees with actual code changes
- Ontology graph captures structural relationships

## Action Item

Formalize OV5's evolution pipeline as a **deterministic multi-stage pipeline** with explicit stage ordering (inspired by MOSS). Current evolution is more ad-hoc.

## Related Papers

- Sibyl (2605.22343): Trial-to-behavior conversion formalization
- APEX (2605.21240): Exploration collapse prevention via strategy DAG

---

*From: arXiv:2605.22794 — MOSS: Self-Evolution through Source-Level Rewriting*
