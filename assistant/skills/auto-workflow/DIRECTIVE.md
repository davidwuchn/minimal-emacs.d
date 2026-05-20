---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.20
total-experiments: 1835
total-kept: 357
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-ext-core.el` | 40% | 20 | 8 | ✅ High yield |
| `lisp/modules/gptel-benchmark-integrate.el` | 40% | 15 | 6 | ✅ High yield |
| `lisp/modules/gptel-benchmark-memory.el` | 40% | 5 | 2 | ✅ High yield |
| `lisp/modules/gptel-tools.el` | 38% | 8 | 3 | ✅ High yield |
| `lisp/modules/gptel-benchmark-instincts.el` | 33% | 9 | 3 | ✅ High yield |
| `lisp/modules/gptel-auto-workflow-behavioral-tests.el` | 33% | 27 | 9 | ✅ High yield |
| `lisp/modules/gptel-ext-context.el` | 29% | 31 | 9 | 🟡 Active |
| `lisp/modules/gptel-tools-memory.el` | 29% | 7 | 2 | 🟡 Active |
| `lisp/modules/gptel-ext-fsm-utils.el` | 25% | 136 | 34 | 🟡 Active |
| `lisp/modules/gptel-benchmark-evolution.el` | 25% | 24 | 6 | 🟡 Active |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **Key insight** (2× from mementum)
- **manual-fix** (2× from git)

## 🛠️ Effective Techniques

<!-- AUTO-UPDATED: From mementum insights -->

- Offline simulation functions diverge from live controller logic. (seen 1×)
- Multiple cron jobs using the same Emacs daemon server name cause "already running" errors. (seen 1×)
- Merged experiment worktrees should be cleaned up to prevent accumulation. (seen 1×)
- Direct path is more efficient than full cycle for simple tasks. (seen 1×)
- Guard nil values before passing to functions expecting number-or-marker. (seen 1×)
- Use `(file-name-as-directory (expand-file-name dir))` to ensure trailing slash. (seen 1×)

## 🛡️ Error Mitigation

<!-- AUTO-UPDATED: From experiment error analysis -->

- **other** (1389×): Investigate root cause
- **timeout** (273×): Add smaller batch sizes or chunked processing
- **test-failure** (105×): Run tests before committing experiments
- **api-limit** (32×): Implement provider fallback or rate limit handling
- **validation-failed** (25×): Improve pre-grade validation prompts

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
- **lisp/modules/gptel-benchmark-integrate.el**: Apply Offline simulation functions diverge from live controller logic. (keep rate: 40%)
- **lisp/modules/gptel-ext-core.el**: Apply Offline simulation functions diverge from live controller logic. (keep rate: 40%)
- **lisp/modules/gptel-benchmark-memory.el**: Apply Offline simulation functions diverge from live controller logic. (keep rate: 40%)
- **lisp/modules/gptel-tools-agent-base.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-tools-agent-error.el**: Try validation guards or error handling improvements (previous experiments discarded)

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

*This directive was auto-generated from 1835 experiments (357 kept locally across 1835 local records). It evolves every self-evolution cycle.*