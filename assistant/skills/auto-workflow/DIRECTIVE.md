---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.16
total-experiments: 1765
total-kept: 345
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-benchmark-memory.el` | 50% | 4 | 2 | ✅ High yield |
| `lisp/modules/gptel-benchmark-integrate.el` | 43% | 14 | 6 | ✅ High yield |
| `lisp/modules/gptel-ext-core.el` | 40% | 20 | 8 | ✅ High yield |
| `lisp/modules/gptel-tools.el` | 38% | 8 | 3 | ✅ High yield |
| `lisp/modules/gptel-auto-workflow-behavioral-tests.el` | 35% | 26 | 9 | ✅ High yield |
| `lisp/modules/gptel-ext-context.el` | 29% | 31 | 9 | 🟡 Active |
| `lisp/modules/gptel-auto-workflow-git-learning.el` | 29% | 7 | 2 | 🟡 Active |
| `lisp/modules/gptel-tools-memory.el` | 29% | 7 | 2 | 🟡 Active |
| `lisp/modules/gptel-benchmark-core.el` | 28% | 68 | 19 | 🟡 Active |
| `lisp/modules/gptel-ext-fsm-utils.el` | 26% | 132 | 34 | 🟡 Active |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **unless-guard** (8× from git)
- **extract-helper-function** (7× from git)
- **add-variable** (4× from git)
- **Applicability** (2× from mementum)
- **Key insight** (2× from mementum)

## 🛠️ Effective Techniques

<!-- AUTO-UPDATED: From mementum insights -->

- Removing Defensive JSON Key Lookups (seen 2×)
- Schema Validation + Type Checking Gap (seen 1×)
- Correct parentheses balance" (seen 1×)
- define marker traits on tools, derive all classification lists from markers at load time. (seen 1×)
- commit `0b3a4da` (seen 1×)
- commit `25c63eb` then `9056845` (seen 1×)

## 🛡️ Error Mitigation

<!-- AUTO-UPDATED: From experiment error analysis -->

- **other** (1332×): Investigate root cause
- **timeout** (270×): Add smaller batch sizes or chunked processing
- **test-failure** (103×): Run tests before committing experiments
- **api-limit** (32×): Implement provider fallback or rate limit handling
- **syntax-error** (20×): Add pre-flight syntax validation

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
- **lisp/modules/gptel-benchmark-memory.el**: Apply Removing Defensive JSON Key Lookups (keep rate: 50%)
- **lisp/modules/gptel-benchmark-integrate.el**: Apply Removing Defensive JSON Key Lookups (keep rate: 43%)
- **lisp/modules/gptel-ext-core.el**: Apply Removing Defensive JSON Key Lookups (keep rate: 40%)
- **lisp/modules/gptel-auto-workflow-strategic.el**: Try validation guards or error handling improvements (previous experiments discarded)
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

*This directive was auto-generated from 1765 experiments (345 kept locally across 1765 local records). It evolves every self-evolution cycle.*