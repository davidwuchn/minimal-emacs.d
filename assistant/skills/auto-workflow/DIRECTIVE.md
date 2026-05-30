---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.30
total-experiments: 870
total-kept: 5
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-ext-context.el` | 50% | 2 | 1 | ✅ High yield |
| `lisp/modules/gptel-benchmark-comparator.el` | 50% | 4 | 2 | ✅ High yield |
| `lisp/modules/gptel-tools-agent.el` | 14% | 7 | 1 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-error.el` | 11% | 9 | 1 | 🟡 Active |
| `lisp/modules/gptel-ext-fsm-utils.el` | 0% | 7 | 0 | ❌ Plateaued |
| `lisp/modules/gptel-ext-retry.el` | 0% | 3 | 0 | ⏳ Insufficient data |
| `staging-review` | 0% | 9 | 0 | ❌ Plateaued |
| `lisp/modules/gptel-auto-workflow-projects.el` | 0% | 17 | 0 | ❌ Plateaued |
| `lisp/modules/gptel-auto-workflow-strategic.el` | 0% | 8 | 0 | ❌ Plateaued |
| `lisp/modules/gptel-tools-agent-prompt-build.el` | 0% | 4 | 0 | ⏳ Insufficient data |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **manual-fix** (68× from git)
- **Application for us** (24× from mementum)
- **Source type** (24× from mementum)
- **Description** (24× from mementum)
- **Application** (21× from mementum)
- **Implementation sketch** (20× from mementum)
- **How it works** (18× from mementum)
- **nil-guard-pattern** (18× from git)

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

- **other** (74×): Investigate root cause
- **validation-failed** (5×): Improve pre-grade validation prompts
- **api-limit** (5×): Implement provider fallback or rate limit handling
- **timeout** (3×): Add smaller batch sizes or chunked processing

## Success Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- Extract helper functions for repeated logic
- Improve error handling and recovery mechanisms

## Failed Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- TODO-only targets (no actionable bugs)
- Pure refactoring without bug fix
- Common Lisp symbols not in Emacs Lisp

## Next Hypotheses

<!-- AUTO-UPDATED: From experiment insights -->
- **lisp/modules/gptel-benchmark-comparator.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 50%)
- **lisp/modules/gptel-tools-agent.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-tools-agent-error.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-ext-fsm-utils.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-ext-retry.el**: Try validation guards or error handling improvements (previous experiments discarded)

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

*This directive was auto-generated from 870 experiments (5 kept locally across 87 local records). It evolves every self-evolution cycle.*