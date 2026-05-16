---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.16
total-experiments: 910
total-kept: 157
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-benchmark-comparator.el` | 50% | 12 | 6 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-runtime.el` | 38% | 8 | 3 | ✅ High yield |
| `lisp/modules/gptel-workflow-benchmark.el` | 35% | 23 | 8 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-staging-baseline.el` | 33% | 3 | 1 | ✅ High yield |
| `lisp/modules/gptel-ext-context-images.el` | 33% | 9 | 3 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-worktree.el` | 29% | 24 | 7 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-error.el` | 29% | 28 | 8 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-git.el` | 28% | 29 | 8 | 🟡 Active |
| `lisp/modules/gptel-agent-loop.el` | 25% | 32 | 8 | 🟡 Active |
| `lisp/modules/gptel-ext-abort.el` | 25% | 4 | 1 | 🟡 Active |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **extract-helper-function** (11× from git)
- **add-variable** (6× from git)
- **unless-guard** (5× from git)
- **error-handling** (3× from git)
- **Applicability** (2× from mementum)
- **Key insight** (2× from mementum)

## 🛠️ Effective Techniques

<!-- AUTO-UPDATED: From mementum insights -->

- Removing Defensive JSON Key Lookups (seen 2×)
- Schema Validation + Type Checking Gap (seen 1×)
- commit `0b3a4da` (seen 1×)
- Correct parentheses balance" (seen 1×)
- define marker traits on tools, derive all classification lists from markers at load time. (seen 1×)
- Repetition Guard (seen 1×)

## 🛡️ Error Mitigation

<!-- AUTO-UPDATED: From experiment error analysis -->

- **other** (741×): Investigate root cause
- **timeout** (105×): Add smaller batch sizes or chunked processing
- **validation-failed** (38×): Improve pre-grade validation prompts
- **api-limit** (18×): Implement provider fallback or rate limit handling
- **test-failure** (8×): Run tests before committing experiments

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
- **lisp/modules/gptel-benchmark-comparator.el**: Apply Removing Defensive JSON Key Lookups (keep rate: 50%)
- **lisp/modules/gptel-tools-agent-runtime.el**: Apply Removing Defensive JSON Key Lookups (keep rate: 38%)
- **lisp/modules/gptel-workflow-benchmark.el**: Apply Removing Defensive JSON Key Lookups (keep rate: 35%)
- **lisp/modules/gptel-sandbox.el**: Try validation guards or error handling improvements (previous experiments discarded)
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

*This directive was auto-generated from 910 experiments (157 kept locally across 910 local records). It evolves every self-evolution cycle.*