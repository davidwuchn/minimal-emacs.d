---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.21
total-experiments: 1889
total-kept: 366
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-tools.el` | 38% | 13 | 5 | ✅ High yield |
| `lisp/modules/gptel-ext-core.el` | 34% | 29 | 10 | ✅ High yield |
| `lisp/modules/gptel-benchmark-instincts.el` | 33% | 9 | 3 | ✅ High yield |
| `lisp/modules/gptel-auto-workflow-behavioral-tests.el` | 33% | 27 | 9 | ✅ High yield |
| `lisp/modules/gptel-ext-context.el` | 29% | 31 | 9 | 🟡 Active |
| `lisp/modules/gptel-benchmark-integrate.el` | 26% | 23 | 6 | 🟡 Active |
| `lisp/modules/gptel-ext-fsm-utils.el` | 26% | 142 | 37 | 🟡 Active |
| `lisp/modules/gptel-benchmark-evolution.el` | 25% | 24 | 6 | 🟡 Active |
| `lisp/modules/gptel-benchmark-memory.el` | 25% | 8 | 2 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-strategy-evolver.el` | 25% | 8 | 2 | 🟡 Active |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **Application for us** (24× from mementum)
- **How it works** (18× from mementum)
- **manual-fix** (10× from git)
- **Key Pattern** (8× from mementum)
- **unless-guard** (6× from git)
- **error-handling** (4× from git)
- **Key insight** (2× from mementum)
- **Agent Design Pattern Catalogue (arXiv:2405.10467)** (2× from mementum)

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

- **other** (1440×): Investigate root cause
- **timeout** (274×): Add smaller batch sizes or chunked processing
- **test-failure** (105×): Run tests before committing experiments
- **api-limit** (32×): Implement provider fallback or rate limit handling
- **validation-failed** (27×): Improve pre-grade validation prompts

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
- **lisp/modules/gptel-tools.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 38%)
- **lisp/modules/gptel-ext-core.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 34%)
- **lisp/modules/gptel-auto-workflow-behavioral-tests.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 33%)
- **lisp/modules/gptel-tools-memory.el**: Try validation guards or error handling improvements (previous experiments discarded)
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

*This directive was auto-generated from 1889 experiments (366 kept locally across 1889 local records). It evolves every self-evolution cycle.*