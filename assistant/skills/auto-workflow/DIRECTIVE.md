---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.22
total-experiments: 1034
total-kept: 221
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
| `lisp/modules/gptel-tools-agent-experiment-loop.el` | 40% | 5 | 2 | ✅ High yield |
| `lisp/modules/gptel-benchmark-evolution.el` | 35% | 17 | 6 | ✅ High yield |
| `lisp/modules/gptel-agent-loop.el` | 34% | 88 | 30 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-worktree.el` | 33% | 9 | 3 | ✅ High yield |
| `lisp/modules/gptel-benchmark-core.el` | 31% | 48 | 15 | ✅ High yield |
| `lisp/modules/gptel-sandbox.el` | 28% | 121 | 34 | 🟡 Active |
| `lisp/modules/gptel-ext-context-cache.el` | 28% | 101 | 28 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-validation.el` | 27% | 11 | 3 | 🟡 Active |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **Application for us** (24× from mementum)
- **How it works** (18× from mementum)
- **Key Pattern** (8× from mementum)
- **manual-fix** (8× from git)
- **unless-guard** (5× from git)
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

- **other** (835×): Investigate root cause
- **timeout** (98×): Add smaller batch sizes or chunked processing
- **test-failure** (43×): Run tests before committing experiments
- **validation-failed** (32×): Improve pre-grade validation prompts
- **api-limit** (20×): Implement provider fallback or rate limit handling

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
- **lisp/modules/gptel-tools-agent-experiment-loop.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 40%)
- **lisp/modules/gptel-benchmark-evolution.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 35%)
- **lisp/modules/nucleus-tools.el**: Try validation guards or error handling improvements (previous experiments discarded)
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

*This directive was auto-generated from 1034 experiments (221 kept locally across 1034 local records). It evolves every self-evolution cycle.*