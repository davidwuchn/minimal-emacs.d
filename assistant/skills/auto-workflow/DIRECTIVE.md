---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.25
total-experiments: 1113
total-kept: 234
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-benchmark-comparator.el` | 100% | 1 | 1 | ✅ High yield |
| `lisp/modules/strategic-daemon-functions.el` | 75% | 4 | 3 | ✅ High yield |
| `lisp/modules/gptel-auto-workflow-mementum.el` | 50% | 2 | 1 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-experiment-loop.el` | 45% | 11 | 5 | ✅ High yield |
| `lisp/modules/gptel-agent-loop.el` | 34% | 89 | 30 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-worktree.el` | 33% | 9 | 3 | ✅ High yield |
| `lisp/modules/gptel-benchmark-evolution.el` | 33% | 18 | 6 | ✅ High yield |
| `lisp/modules/gptel-auto-workflow-research-benchmark.el` | 33% | 6 | 2 | ✅ High yield |
| `lisp/modules/gptel-benchmark-core.el` | 29% | 52 | 15 | 🟡 Active |
| `lisp/modules/gptel-sandbox.el` | 28% | 121 | 34 | 🟡 Active |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **Application for us** (24× from mementum)
- **Source type** (24× from mementum)
- **Description** (24× from mementum)
- **Application** (20× from mementum)
- **Implementation sketch** (20× from mementum)
- **How it works** (18× from mementum)
- **Apply to us** (16× from mementum)
- **Emacs application** (14× from mementum)

## 🛠️ Effective Techniques

<!-- AUTO-UPDATED: From mementum insights -->

- Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (seen 2×)
- Use mathematical constants (φ, ψ, Δ, λ) as "attention magnets" to prime LLMs toward formal reasoning patterns (seen 2×)
- Zero client-side intelligence; AI decides, client executes. (seen 2×)
- 35+ structured tools with circuit breakers, automatic retry, and security controls (seen 2×)
- Programmatic verification before trust; self-modification loop. (seen 2×)
- [PLAN] + [EXPECT] with P(success) confidence scoring based on prior outcomes (seen 2×)

## 🛡️ Error Mitigation

<!-- AUTO-UPDATED: From experiment error analysis -->

- **other** (903×): Investigate root cause
- **timeout** (99×): Add smaller batch sizes or chunked processing
- **test-failure** (45×): Run tests before committing experiments
- **validation-failed** (36×): Improve pre-grade validation prompts
- **api-limit** (24×): Implement provider fallback or rate limit handling

## Success Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- Extract helper functions for repeated logic

## Failed Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- TODO-only targets (no actionable bugs)
- Pure refactoring without bug fix
- Common Lisp symbols not in Emacs Lisp

## Next Hypotheses

<!-- AUTO-UPDATED: From experiment insights -->
- **lisp/modules/strategic-daemon-functions.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 75%)
- **lisp/modules/gptel-tools-agent-experiment-loop.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 45%)
- **lisp/modules/gptel-agent-loop.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 34%)
- **lisp/modules/gptel-ext-retry.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-tools-agent-staging-baseline.el**: Try validation guards or error handling improvements (previous experiments discarded)

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

*This directive was auto-generated from 1113 experiments (234 kept locally across 1113 local records). It evolves every self-evolution cycle.*