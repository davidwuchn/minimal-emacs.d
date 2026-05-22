---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.22
total-experiments: 1227
total-kept: 236
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-tools-agent-staging-baseline.el` | 33% | 3 | 1 | ✅ High yield |
| `lisp/modules/gptel-agent-loop.el` | 31% | 64 | 20 | ✅ High yield |
| `lisp/modules/gptel-tools-memory.el` | 31% | 32 | 10 | ✅ High yield |
| `lisp/modules/gptel-benchmark-core.el` | 29% | 59 | 17 | 🟡 Active |
| `lisp/modules/nucleus-tools.el` | 29% | 21 | 6 | 🟡 Active |
| `lisp/modules/gptel-ext-context.el` | 27% | 26 | 7 | 🟡 Active |
| `lisp/modules/gptel-ext-abort.el` | 25% | 8 | 2 | 🟡 Active |
| `lisp/modules/gptel-benchmark-tests.el` | 25% | 8 | 2 | 🟡 Active |
| `lisp/modules/nucleus-tools-validate.el` | 24% | 21 | 5 | 🟡 Active |
| `lisp/modules/gptel-ext-retry.el` | 23% | 52 | 12 | 🟡 Active |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **Application for us** (24× from mementum)
- **Source type** (24× from mementum)
- **Description** (24× from mementum)
- **Application** (20× from mementum)
- **Implementation sketch** (20× from mementum)
- **How it works** (18× from mementum)
- **Key Pattern** (8× from mementum)
- **unless-guard** (7× from git)

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

- **other** (1065×): Investigate root cause
- **validation-failed** (90×): Improve pre-grade validation prompts
- **timeout** (36×): Add smaller batch sizes or chunked processing
- **api-limit** (20×): Implement provider fallback or rate limit handling
- **test-failure** (13×): Run tests before committing experiments

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
- **lisp/modules/gptel-tools-agent-staging-baseline.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 33%)
- **lisp/modules/gptel-tools-memory.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 31%)
- **lisp/modules/gptel-agent-loop.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 31%)
- **lisp/modules/gptel-ext-tool-sanitize.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-ext-fsm.el**: Try validation guards or error handling improvements (previous experiments discarded)

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

*This directive was auto-generated from 1227 experiments (236 kept locally across 1227 local records). It evolves every self-evolution cycle.*