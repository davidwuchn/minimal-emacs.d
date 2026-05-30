---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.30
total-experiments: 870
total-kept: 20
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-benchmark-principles.el` | 67% | 3 | 2 | ✅ High yield |
| `lisp/modules/gptel-benchmark-comparator.el` | 33% | 3 | 1 | ✅ High yield |
| `lisp/modules/gptel-benchmark-core.el` | 26% | 19 | 5 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-staging-baseline.el` | 25% | 4 | 1 | 🟡 Active |
| `lisp/modules/gptel-ext-tool-permits.el` | 25% | 12 | 3 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-runtime.el` | 25% | 4 | 1 | 🟡 Active |
| `lisp/modules/gptel-tools-memory.el` | 14% | 29 | 4 | 🟡 Active |
| `lisp/modules/gptel-workflow-benchmark.el` | 12% | 8 | 1 | 🟡 Active |
| `lisp/modules/gptel-auto-workflow-projects.el` | 8% | 12 | 1 | ❌ Plateaued |
| `lisp/modules/gptel-tools-agent-prompt-build.el` | 7% | 14 | 1 | ❌ Plateaued |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **manual-fix** (57× from git)
- **Application for us** (24× from mementum)
- **Source type** (24× from mementum)
- **Description** (24× from mementum)
- **Application** (21× from mementum)
- **Implementation sketch** (20× from mementum)
- **How it works** (18× from mementum)
- **Apply to us** (16× from mementum)

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

- **other** (159×): Investigate root cause
- **timeout** (14×): Add smaller batch sizes or chunked processing
- **api-limit** (14×): Implement provider fallback or rate limit handling
- **validation-failed** (12×): Improve pre-grade validation prompts
- **test-failure** (2×): Run tests before committing experiments

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
- **lisp/modules/gptel-benchmark-principles.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 67%)
- **lisp/modules/gptel-benchmark-comparator.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 33%)
- **lisp/modules/gptel-benchmark-core.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 26%)
- **lisp/modules/gptel-tools-memory.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-workflow-benchmark.el**: Try validation guards or error handling improvements (previous experiments discarded)

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

*This directive was auto-generated from 870 experiments (20 kept locally across 201 local records). It evolves every self-evolution cycle.*