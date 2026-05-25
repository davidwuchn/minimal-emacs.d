---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.25
total-experiments: 2072
total-kept: 397
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-ext-tool-permits.el` | 57% | 7 | 4 | ✅ High yield |
| `lisp/modules/gptel-ext-core.el` | 35% | 34 | 12 | ✅ High yield |
| `lisp/modules/gptel-benchmark-instincts.el` | 33% | 9 | 3 | ✅ High yield |
| `lisp/modules/gptel-auto-workflow-behavioral-tests.el` | 33% | 27 | 9 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-strategy-harness.el` | 33% | 6 | 2 | ✅ High yield |
| `lisp/modules/gptel-tools.el` | 29% | 17 | 5 | 🟡 Active |
| `lisp/modules/gptel-ext-context.el` | 29% | 45 | 13 | 🟡 Active |
| `lisp/modules/gptel-benchmark-integrate.el` | 28% | 25 | 7 | 🟡 Active |
| `lisp/modules/gptel-ext-fsm-utils.el` | 25% | 147 | 37 | 🟡 Active |
| `lisp/modules/gptel-benchmark-memory.el` | 25% | 8 | 2 | 🟡 Active |

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

- **other** (1590×): Investigate root cause
- **timeout** (279×): Add smaller batch sizes or chunked processing
- **test-failure** (110×): Run tests before committing experiments
- **validation-failed** (45×): Improve pre-grade validation prompts
- **api-limit** (36×): Implement provider fallback or rate limit handling

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
- **lisp/modules/gptel-ext-tool-permits.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 57%)
- **lisp/modules/gptel-ext-core.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 35%)
- **lisp/modules/gptel-auto-workflow-behavioral-tests.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 33%)
- **lisp/modules/gptel-ext-reasoning.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-tools-agent-base.el**: Try validation guards or error handling improvements (previous experiments discarded)

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

*This directive was auto-generated from 2072 experiments (397 kept locally across 2072 local records). It evolves every self-evolution cycle.*