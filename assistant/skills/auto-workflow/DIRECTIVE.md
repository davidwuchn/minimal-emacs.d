---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.08
updated: 2026-05-08 18:16
total-experiments: 512
total-kept: 105
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-tools-agent-runtime.el` | 50% | 4 | 2 | ✅ High yield |
| `lisp/modules/gptel-workflow-benchmark.el` | 36% | 22 | 8 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-git.el` | 33% | 12 | 4 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-staging-merge.el` | 33% | 12 | 4 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-benchmark.el` | 33% | 3 | 1 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-staging-baseline.el` | 33% | 3 | 1 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-worktree.el` | 31% | 16 | 5 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-experiment-core.el` | 30% | 10 | 3 | ✅ High yield |
| `lisp/modules/gptel-agent-loop.el` | 25% | 12 | 3 | 🟡 Active |
| `lisp/modules/gptel-auto-workflow-behavioral-tests.el` | 24% | 29 | 7 | 🟡 Active |

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
- **lisp/modules/gptel-auto-workflow-projects.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-ext-retry.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-ext-tool-confirm.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-ext-tool-sanitize.el**: Try validation guards or error handling improvements (previous experiments discarded)
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

*This directive was auto-generated from 512 experiments (105 kept). It evolves every self-evolution cycle.*