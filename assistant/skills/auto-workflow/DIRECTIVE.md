---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.31
total-experiments: 870
total-kept: 11
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-benchmark-comparator.el` | 33% | 3 | 1 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-runtime.el` | 25% | 4 | 1 | 🟡 Active |
| `lisp/modules/gptel-ext-tool-permits.el` | 21% | 14 | 3 | 🟡 Active |
| `lisp/modules/gptel-benchmark-core.el` | 20% | 10 | 2 | 🟡 Active |
| `lisp/modules/gptel-tools-memory.el` | 10% | 10 | 1 | 🟡 Active |
| `lisp/modules/gptel-auto-workflow-projects.el` | 7% | 27 | 2 | ❌ Plateaued |
| `lisp/modules/gptel-tools-agent-prompt-build.el` | 5% | 20 | 1 | ❌ Plateaued |
| `lisp/modules/gptel-tools-agent.el` | 0% | 1 | 0 | ⏳ Insufficient data |
| `lisp/modules/gptel-agent-loop.el` | 0% | 8 | 0 | ❌ Plateaued |
| `lisp/modules/gptel-auto-workflow-mementum.el` | 0% | 1 | 0 | ⏳ Insufficient data |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **How it works** (38× from mementum)
- **Apply to us** (36× from mementum)
- **Application for us** (24× from mementum)
- **Source type** (24× from mementum)
- **Description** (24× from mementum)
- **Application** (21× from mementum)
- **Symbolic Attention Magnets** (20× from mementum)
- **Implementation sketch** (20× from mementum)

## 🛠️ Effective Techniques

<!-- AUTO-UPDATED: From mementum insights -->

- LLM analyzes *why* compressed context failed and updates compression guidelines iteratively (seen 4×)
- Manager agent builds a "task ledger" (plan with goals/subgoals) dynamically, then delegates to specialized agents (seen 4×)
- Two agents in a turn-based "maker creates, checker validates" loop with explicit acceptance criteria and iteration caps (seen 4×)
- Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (seen 2×)
- Use mathematical constants (φ, ψ, Δ, λ) as "attention magnets" to prime LLMs toward formal reasoning patterns (seen 2×)
- Zero client-side intelligence; AI decides, client executes. (seen 2×)

## 🛡️ Error Mitigation

<!-- AUTO-UPDATED: From experiment error analysis -->

- **other** (110×): Investigate root cause
- **validation-failed** (28×): Improve pre-grade validation prompts
- **timeout** (16×): Add smaller batch sizes or chunked processing
- **api-limit** (14×): Implement provider fallback or rate limit handling
- **test-failure** (4×): Run tests before committing experiments

## Success Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- Extract helper functions for repeated logic

## Failed Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- Source type
- Description
- Application
- Implementation sketch

## Next Hypotheses

<!-- AUTO-UPDATED: From experiment insights -->
- **lisp/modules/gptel-benchmark-comparator.el**: Apply LLM analyzes *why* compressed context failed and updates compression guidelines iteratively (keep rate: 33%)
- **lisp/modules/gptel-tools-agent-runtime.el**: Apply LLM analyzes *why* compressed context failed and updates compression guidelines iteratively (keep rate: 25%)
- **lisp/modules/gptel-ext-tool-permits.el**: Apply LLM analyzes *why* compressed context failed and updates compression guidelines iteratively (keep rate: 21%)
- **lisp/modules/gptel-tools-memory.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-auto-workflow-projects.el**: Try validation guards or error handling improvements (previous experiments discarded)

## Immutable Files

```
early-init.el
pre-early-init.el
lisp/eca-security.el
lisp/modules/gptel-ext-security.el
lisp/modules/gptel-ext-tool-confirm.el
lisp/modules/gptel-ext-tool-permits.el
eca/**
mementum/**
var/elpa/**
```

## Constraints

| Setting | Value |
|---------|-------|
| Per experiment | 15 minutes |
| Max per target | 10 experiments |
| Stop if no improvement | 3 consecutive |

---

*This directive was auto-generated from 870 experiments (11 kept locally across 173 local records). It evolves every self-evolution cycle.*