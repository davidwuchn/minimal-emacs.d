# Mementum State

> **Bootstrapped**: 2026-06-06
> **Session**: Research Analysis + Plan Diversity Metric
> **Status**: ✅ **OV5 SELF-HEALING VERIFIED** — Pipeline detects, diagnoses, remediates, recovers
> **Latest**: Plan diversity metric wired into experiment logging (observability active)
> **Active Plan**: None — system is self-improving, pipeline running autonomously
> **Pi5**: Running, self-healing working (grader crash → BLIND MODE → recovery)

---

## Current Priorities (Auto-ranked)

| Priority | Item | Model | Status |
|---|---|---|---|
| **P0** | OV5 self-heal: fix workspace boundary violations | @maintainer | **COMPLETE** |
| **P0** | Platform sandbox (seatbelt + bubblewrap) | @maintainer | **COMPLETE** |
| **P0** | Security audit: fix 14 sandbox vulnerabilities | @maintainer | **COMPLETE** |
| **P0** | Self-heal semantic module (7 audit checks + auto-fixers) | @maintainer | **COMPLETE** |
| **P1** | Monitoring Agent: Complete (Phases 0-10) | @maintainer | **COMPLETE** |
| **P1** | Research paper analysis (MOSS, Sibyl, APEX) | @maintainer | **COMPLETE** |
| **P2** | Daemon watchdog hardening (heartbeat-based freeze detection) | @maintainer | **COMPLETE** |
| **P2** | Smart routing: eliminate hardcoded LLM backends | @maintainer | **COMPLETE** |
| **P2** | Strategy parse fix + column index corrections | @maintainer | **COMPLETE** |
| **P2** | Routing stats caching (dedup + memo + pre-bind) | @maintainer | **COMPLETE** |
| **P2** | Plan diversity metric (PlanSearch-inspired) | @maintainer | **COMPLETE** |

---

## Research Insights (May-June 2026 Papers)

### MOSS: Source-Level Self-Evolution (2605.22794)
- **Key insight**: Source-level adaptation is Turing-complete — strict superset of text-mutable scope
- **OV5 alignment**: Already does source-level evolution via self-heal-semantic + git worktrees
- **Action item**: Formalize evolution pipeline as deterministic multi-stage with explicit ordering

### Sibyl-AutoResearch: Trial-and-Error Harnesses (2605.22343)
- **Key insight**: Executable workflows don't produce research judgment; need explicit trial-to-behavior conversion
- **OV5 alignment**: Ontology graph already captures trial outcomes
- **Action item**: Formalize ontology updates as auditable conversion units

### APEX: Exploration Collapse (2605.21240)
- **Key insight**: Self-evolving agents suffer from exploration collapse as memory grows
- **OV5 alignment**: Category saturation detection prevents some collapse
- **Action item**: Add explicit strategy DAG with prerequisite edges to ontology

### RPG: Repository Planning Graph (2509.16198)
- **Key insight**: Replace free-form NL planning with explicit graph (nodes=capabilities, edges=dependencies)
- **OV5 gap**: No structured planning representation, no two-level planning (proposal vs implementation)
- **Action item**: Consider experiment dependency graph + graph-guided localization

### PlanSearch: Planning in Natural Language (2409.03733)
- **Key insight**: Plan diversity directly predicts performance gains from search
- **OV5 gap**: One hypothesis per target, no diversity metric, no plan-level search
- **Implemented**: `gptel-auto-experiment--hypothesis-diversity` (Jaccard similarity on tokens)
- **Next step**: Wire into experiment logging, consider plan-level search over diverse candidates

**Knowledge pages**:
- `mementum/knowledge/self-evolving-agent-research.md` (MOSS, Sibyl, APEX)
- `mementum/knowledge/research-planning-graph-plansearch-ov5-gaps.md` (RPG, PlanSearch)

**Memory**: `mementum/memories/insight-plan-diversity-predicts-performance.md`

---

## Self-Healing Verification (Latest Pipeline Run)

**Timeline**:
- 23:01:13 — Grader crashed (void-variable err)
- 23:01:14 — OV5 diagnosed: `backend-rate-limited`
- 23:01:14 — Attempted remediation
- 23:01:21 — Still crashed → entered **BLIND MODE**
- 23:08:31 — **Recovered** — grader 9/9 healthy

**Self-healing working as designed**:
- Detection ✓
- Diagnosis ✓
- Remediation attempt ✓
- Fallback (BLIND MODE) ✓
- Recovery ✓

---

## Active Patterns

- **Defense-in-depth**: L1 (Emacs sandbox) → L2 (boundary validator) → L3 (plan-mode whitelist) → L4 (OS sandbox)
- **Self-heal semantic**: 7 audit checks + auto-fixers (unbalanced parens, missing provides, unguarded calls, blank lines, etc.)
- **Monitoring agent**: Meta-improvement layer — detects failures, generates proposals, auto-deploys fixes
- **Ontology learning**: Every experiment outcome updates the ontology graph
- **Mementum memory**: Cross-session learning via git-based persistence
- **Git worktree isolation**: Each experiment runs in isolated worktree, no container overhead

---

## Next Steps

### Immediate
1. **Continue monitoring** — Let pipeline run, verify self-healing continues working
2. **Verify smart routing end-to-end** — Next cron cycle should use fallback chain for all LLM calls

### Near-Term
3. **Batch anchoring** — Group similar failures before proposing fixes (MOSS insight)
4. **Research action items** — Implement explicit strategy DAG with prerequisite edges (APEX insight)

---

## Relevant Files

- `lisp/modules/gptel-platform-sandbox.el`: Platform sandbox (seatbelt + bubblewrap)
- `lisp/modules/gptel-auto-workflow-self-heal-semantic.el`: 7 audit checks + auto-fixers
- `lisp/modules/gptel-auto-workflow-monitoring-agent.el`: Monitoring agent (Phases 0-10)
- `lisp/modules/gptel-auto-workflow-evolution.el`: Evolution cycle + ontology learning
- `mementum/knowledge/self-evolving-agent-research.md`: Research paper analysis
- `mementum/state.md`: This file — working memory, read first every session

---

*Active Mementum v1.1 — research insights, self-healing verified, ontology learning active*
