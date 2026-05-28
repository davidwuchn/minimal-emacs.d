---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.28
total-experiments: 870
total-kept: 41
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-benchmark-principles.el` | 50% | 4 | 2 | ✅ High yield |
| `lisp/modules/gptel-benchmark-evolution.el` | 33% | 3 | 1 | ✅ High yield |
| `lisp/modules/gptel-ext-context.el` | 33% | 9 | 3 | ✅ High yield |
| `lisp/modules/gptel-benchmark-comparator.el` | 29% | 7 | 2 | 🟡 Active |
| `lisp/modules/gptel-benchmark-core.el` | 26% | 19 | 5 | 🟡 Active |
| `lisp/modules/gptel-ext-abort.el` | 25% | 4 | 1 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-staging-baseline.el` | 25% | 4 | 1 | 🟡 Active |
| `lisp/modules/gptel-ext-tool-permits.el` | 25% | 12 | 3 | 🟡 Active |
| `lisp/modules/gptel-tools-memory.el` | 22% | 54 | 12 | 🟡 Active |
| `lisp/modules/nucleus-tools.el` | 21% | 19 | 4 | 🟡 Active |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **Application for us** (24× from mementum)
- **Source type** (24× from mementum)
- **Description** (24× from mementum)
- **Application** (21× from mementum)
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

- **other** (229×): Investigate root cause
- **api-limit** (14×): Implement provider fallback or rate limit handling
- **timeout** (13×): Add smaller batch sizes or chunked processing
- **validation-failed** (12×): Improve pre-grade validation prompts
- **test-failure** (4×): Run tests before committing experiments

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
- **lisp/modules/gptel-benchmark-principles.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 50%)
- **lisp/modules/gptel-benchmark-evolution.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 33%)
- **lisp/modules/gptel-ext-context.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 33%)
- **lisp/modules/gptel-workflow-benchmark.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-ext-fsm-utils.el**: Try validation guards or error handling improvements (previous experiments discarded)

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

*This directive was auto-generated from 870 experiments (41 kept locally across 272 local records). It evolves every self-evolution cycle.*