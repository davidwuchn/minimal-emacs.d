---
title: "Auto-Research vs OV5: Research Capability Gaps"
status: active
category: architecture
tags: [auto-research, researcher, literature-survey, quality-gates, peer-review]
related: [helium-vs-ov5-gaps, deep-searcher-vs-ov5-gaps]
depends-on: []
---

# Auto-Research vs OV5: Research Capability Gaps

**Date**: 2026-06-16  
**Source**: https://victorchen96.github.io/auto_research/skill/paper-writing.html  
**Paper**: Deli AutoResearch — Scientific Paper Writing Skill Group v2.0

## Auto-Research's Core Innovation

Auto-Research models scientific paper writing as a **hierarchical skill group** with 5 sub-skills, 4 quality gates, and iterative review loops. The system autonomously produces 8.5/10 survey papers through structured division of labor, phase routing, and quality gates.

## Architecture Comparison

| Dimension | Auto-Research | OV5 |
|-----------|---------------|-----|
| **Literature Survey** | 4-stage pipeline: Recall → LQS Score → Classify → Upgrade | Ad-hoc research with strategy selection |
| **Quality Gates** | 5 gates: Literature, Experiment, Structure, Figures, Final Review | 7 gates for code experiments, none for research |
| **Peer Review** | Multi-persona scoring (5 reviewers) with weakness routing | Single-grader scoring, no peer review |
| **Experiment Design** | 4-stage loop: Design → Execute → Iterate → Report | Experiment loop exists but no hypothesis pre-registration |
| **Iterative Improvement** | Score progression 6.0 → 7.0 → 8.0 → 8.5+ | No score progression tracking for research |
| **Citation Management** | LQS scoring, A/B/C/D classification, venue upgrade | No citation management |
| **Weakness Routing** | Routes review weaknesses to responsible sub-skill | No weakness routing |

## Auto-Research's 5 Sub-Skills

### 1. Literature Survey (20% of time, foundation)
**4-stage pipeline:**
- **Stage 1: High-Recall Retrieval** — 20-30 keyword queries, 200-500 raw candidates
- **Stage 2: LQS Multi-Dimensional Scoring** — Recency (30%), Citation Impact (25%), Venue (20%), Institution (10%), Acceptance (15%)
- **Stage 3: Citation Depth Classification** — A-level (1-3 paragraphs), B-level (2-5 sentences), C-level (1 sentence), D-level (dropped)
- **Stage 4: Venue Upgrade** — Cross-check DBLP + OpenReview, arXiv → accepted

**Quality Gate:**
- Citations ≥ 80 (draft) / ≥ pages×3 (final)
- Within 1yr ≥ 40%
- Accepted ≥ 30%
- arXiv-only ≤ 60%
- Verification rate ≥ 80%

### 2. Paper Structure & Logic (35% of time, main driver)
- Chapter architecture (9 sections)
- Paragraph logic patterns (Claim-Evidence-Implication, Compare-Contrast, etc.)
- Taxonomy design (MECE, multi-axis matrix)
- Formal claims (Conjecture + Remark, hedge ladder)
- Related work differentiation

**Quality Gate:**
- Compiles with 0 errors & 0 undefined refs
- Every .tex file ≤ 300 lines
- Abstract-conclusion alignment
- ≥ 1 formal claim

### 3. Experiment Design (20% of time, +1.0~1.5 points)
**4-stage loop:**
- **Stage 1: Design** — Hypothesis, independent/dependent vars, control vars, expected results
- **Stage 2: Execute** — API path (hours) or GPU RL path (days)
- **Stage 3: Iterate** — Ceiling/floor effect handling, max 5 iterations
- **Stage 4: Report** — results.json + experiment_summary.md

**Quality Gate:**
- Clear hypothesis pre-registered
- Statistical test reported (p or CI)
- ≥ 3 trials with std
- No ceiling/floor effect

### 4. Academic Figures & Tables (10% of time, +0.5~1.0 points)
- Table types: Comparison Matrix, Benchmark Table, Ablation Table, Taxonomy Table, Meta-analysis
- Figure types: Data-driven (matplotlib), Architecture (TikZ), Simple schematics (PIL)
- Quality checklist: Vector format, font size ≥ 10pt, academic palette

**Quality Gate:**
- Tables ≥ 10, Figures ≥ 6 (full survey)
- booktabs format, no vertical lines
- Each carries a non-trivial insight

### 5. Peer Review Simulation (15% of time, drives iteration)
**5 Reviewer Personas:**
- R1 Experimentalist (statistical rigor)
- R2 Theorist (formal definitions, proofs)
- R3 Perfectionist (writing quality, figures)
- R4 Synthesizer (cross-cutting analysis)
- R5 Newcomer (accessibility, definitions)

**Scoring Protocol:**
- Each reviewer scores independently
- Final score = median of all reviewers
- Dimensions: Novelty, Comprehensiveness, Clarity, Technical Depth, Experimental Validation
- Anti-inflation: First round capped at 7.0, max +1.5 per round

**Weakness Routing Table:**
- "Citation coverage insufficient" → Literature Stage 1-2
- "Structure unclear" → Structure reorganize
- "No experiments" → Experiment design
- "Tables incomparable" → Figures regroup

## Highest-Leverage Gaps for OV5

### Gap 1: Structured Literature Survey Pipeline
**Problem**: OV5's researcher does ad-hoc research without systematic literature survey.  
**Auto-Research solution**: 4-stage pipeline with LQS scoring and citation classification.  
**OV5 implementation**: Create `gptel-auto-workflow-research-literature.el` with:
- `research-literature-recall` — high-recall retrieval (20-30 queries)
- `research-literature-score` — LQS multi-dimensional scoring
- `research-literature-classify` — A/B/C/D citation depth classification
- `research-literature-upgrade` — venue upgrade via DBLP/OpenReview

### Gap 2: Research Quality Gates
**Problem**: OV5 has 7 gates for code experiments but none for research quality.  
**Auto-Research solution**: 5 quality gates (Literature, Experiment, Structure, Figures, Final Review).  
**OV5 implementation**: Add research quality gates to `gptel-auto-workflow-research-integration.el`:
- Gate 1: Literature (citations ≥ 80, within 1yr ≥ 40%, accepted ≥ 30%)
- Gate 2: Experiment (hypothesis pre-registered, statistical test, ≥ 3 trials)
- Gate 3: Structure (compiles, abstract-conclusion alignment)
- Gate 4: Figures (tables ≥ 10, figures ≥ 6)
- Gate 5: Final Review (all gates passed, score ≥ target)

### Gap 3: Peer Review Simulation
**Problem**: OV5 has single-grader scoring, no multi-persona peer review.  
**Auto-Research solution**: 5 reviewer personas with independent scoring and weakness routing.  
**OV5 implementation**: Create `gptel-auto-workflow-research-review.el` with:
- `research-review-simulate` — multi-persona scoring (5 reviewers)
- `research-review-score` — median scoring across dimensions
- `research-review-route-weaknesses` — route weaknesses to responsible sub-skill
- `research-review-anti-inflation` — cap first round at 7.0, max +1.5 per round

### Gap 4: Iterative Improvement Loop
**Problem**: OV5 doesn't track research score progression or drive iterative improvement.  
**Auto-Research solution**: Score progression 6.0 → 7.0 → 8.0 → 8.5+ with phase routing.  
**OV5 implementation**: Add to `gptel-auto-workflow-research-integration.el`:
- `research-score-track` — track score progression across iterations
- `research-phase-route` — route to appropriate phase (Draft, Deep Improvement, Sprint)
- `research-iteration-loop` — loop: review → weakness routing → fix → compile → review
- Stop conditions: score ≥ 8.5 OR Δ ≤ 0.3 for 2 rounds OR iter > 12

### Gap 5: Hypothesis Pre-Registration
**Problem**: OV5's experiment loop doesn't pre-register hypotheses or statistical plans.  
**Auto-Research solution**: Experiment design stage requires hypothesis, vars, control vars, expected results, statistical plan decided BEFORE running.  
**OV5 implementation**: Modify `gptel-auto-experiment-loop` to:
- Require hypothesis pre-registration before experiment execution
- Require statistical plan (p or CI, ≥ 3 trials)
- Detect ceiling/floor effects and iterate
- Max 5 iterations, then accept best result

## Implementation Priority

1. **Structured literature survey** (Gap 1) — Foundation for all other improvements
2. **Research quality gates** (Gap 2) — Ensures research meets minimum standards
3. **Peer review simulation** (Gap 3) — Drives iterative improvement
4. **Iterative improvement loop** (Gap 4) — Systematic score progression
5. **Hypothesis pre-registration** (Gap 5) — Statistical rigor for experiments

## What OV5 Has That Auto-Research Lacks

- **Self-healing**: Auto-Research can't fix its own code when evaluators break
- **Monitoring agent**: Auto-Research has no meta-improvement layer
- **Ontology learning**: Auto-Research doesn't build knowledge graphs from experiments
- **7 gates for code**: Auto-Research has research gates but not code quality gates
- **Git worktree isolation**: Auto-Research doesn't isolate experiments
- **Datahike World Store**: Auto-Research has no structured memory layer
- **Approval queue**: Auto-Research has no human governance for high-risk proposals
- **VSM diagnostics**: Auto-Research doesn't have five-element health model

## Strategic Insight

Auto-Research optimizes **research quality and paper writing** through structured pipelines, quality gates, and peer review simulation. OV5 optimizes **code improvement and self-evolution** through experiment loops, ontology learning, and self-healing.

**Integration opportunity**: Add auto-research's research quality pipeline to OV5's existing code improvement loop. This gives OV5 both research rigor (literature survey, peer review) and code quality (7 gates, self-healing).

## Next Actions

1. Implement `gptel-auto-workflow-research-literature.el` — 4-stage literature survey pipeline
2. Add research quality gates to `gptel-auto-workflow-research-integration.el`
3. Implement `gptel-auto-workflow-research-review.el` — peer review simulation
4. Add score progression tracking and iterative improvement loop
5. Modify experiment loop to require hypothesis pre-registration

## References

- Auto-Research paper writing skill: https://victorchen96.github.io/auto_research/skill/paper-writing.html
- OV5 researcher: `lisp/modules/gptel-tools-agent-research.el`
- OV5 research integration: `lisp/modules/gptel-auto-workflow-research-integration.el`
- Related gap analysis: `mementum/knowledge/helium-vs-ov5-gaps.md`
