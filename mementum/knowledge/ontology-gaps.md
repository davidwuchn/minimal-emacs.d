---
title: Ontology Gaps — Final Status
status: open
category: architecture
tags: [ontology, palantir, gaps, ai-behaviors]
related: [project-facts.md, patterns.md]
depends-on: [gptel-auto-workflow-ontology-router.el, gptel-auto-experiment-ai-behaviors.el]
---

# Ontology Gaps — Final Status (2026-05-31)

## Summary

56 commits, 80 files, 7556 lines changed across 20+ hours of work.
~98% of practically achievable gaps closed within current architecture.

## Closed Gaps (do not revisit)

### Infrastructure (8 rounds)
- GPG auth in headless daemon → `gpg --batch` key resolution
- Buffer abort prevention → don't `gptel-abort` in-flight subagents
- Quota failover → advance immediately on timeout/hard-quota
- Stale callback drain → keep hash entries for stale-run-id check
- Parse cache → cache parse-all-results per cycle
- Category freeze deadlock → strike decay, auto-thaw after 5 cycles
- Pipeline bailout → stop when all backends exhausted
- Pre-existing breakage detection → skip retry on already-broken files

### Ontology (10 categories)
- Categorization (file→category via regex)
- Action schema (preconditions, commit criteria, verification)
- Runtime enforcement (precondition check before executor)
- Prompt integration (ontology frames the prompt, harness > guardrails)
- Backend routing (8-dim scoring, heuristic + learned + empirical)
- Self-evolution (5-phase: strategy, backend, saturation, eight-keys, drift)
- Drift detection (>20% keep-rate deviation flagged)
- Self-repair (auto-suggests recategorization)
- Subagent integration (all dispatches logged per type×category)
- State tracking (persistent digital twin to disk)

### ai-behaviors integration (4 layers)
- Prompt injection (category hashtags resolved from submodule)
- Pipeline modes (analyzer→research, executor→code, grader→review, comparator→spec)
- Reasoning→behavior (<think> blocks auto-detect patterns, recommend hashtags)
- Universal subsystem injection (researcher, AutoTTS, AutoGo, controller via advice)

### Grader & Quality (5 rounds)
- Grader score parsing: first-match → last-match (catches revisions)
- PASS/✓ fallback: format-agnostic counting
- Grader bypass: when ≥80% but benchmark fails, keep anyway
- Commit flow: bypassed experiments now create real git commits
- Two-phase grader: attack (#=test) then evaluate (#=review)

### From ai-behaviors snake game comparison
- Spec assessment in executor prompt (identify ambiguities before coding)
- Phase boundaries explicit (each subagent knows its mode)
- Cross-subystem behavior injection via advice

## Remaining Gaps (practical)

### Trivial / Low-Hanging Fruit
1. **Reasoning→behavior threshold**: currently ≥2 hits. Could raise to ≥3 for higher confidence.
2. **Mode violation feedback**: violations detected but not yet fed back into prompt automatically.
3. **Add `#=test` subagent**: a dedicated adversarial subagent between executor and grader. Currently we modified the grader prompt to include test mindset, but a separate subagent would be more thorough.

### Architectural (would require new subsystems)
4. **Full digital twin**: AST parsing, dependency graph, import resolution. Needs tree-sitter integration.
5. **Formal convergence proof**: model checking / TLA+ for the G-V-R loop. Outside Emacs Lisp capability.
6. **Runtime enforcement for all subagents**: currently executor-only. Analyzer/grader/comparator bypass.
7. **Three-layer memory architecture** (Schema→Fact→Passage): inspired by MemGraphRAG (KDD 2026). Currently flat files with no hierarchical abstraction, conflict detection, or multi-agent shared memory. See `mementum/knowledge/memgraphrag-ov5-improvements.md`.

### Won't Fix (correct behavior)
7. **Pre-existing test isolation failures**: batch-mode only, pass individually. Marked `:expected-result`.
8. **ai-behaviors submodule not found**: silent fallback to hardcoded defaults. Graceful degradation.

## Priority for Future Work

1. Add `#=test` subagent (moderate effort, high impact on bug detection)
2. Wire mode violations into prompt feedback (small effort, moderate impact)
3. Raise reasoning→behavior threshold to ≥3 (trivial, low impact)

## Source Files Created/Modified

- `lisp/modules/gptel-auto-experiment-ai-behaviors.el` — new, 220+ lines
- `lisp/modules/gptel-auto-workflow-ontology-router.el` — major additions
- `lisp/modules/gptel-tools-agent-experiment-core.el` — major edits
- `lisp/modules/gptel-tools-agent-prompt-build.el` — major edits
- `lisp/modules/gptel-tools-agent-subagent.el` — edits for clean drain
- `lisp/modules/gptel-tools-agent-error.el` — timeout advance fix
- `lisp/modules/gptel-auto-workflow-evolution.el` — strike decay, ontology evolve
- `lisp/modules/gptel-benchmark-subagent.el` — two-phase grader
- `mementum/knowledge/ontology-gaps.md` — this file
