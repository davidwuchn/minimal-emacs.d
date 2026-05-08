---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.08
updated: 2026-05-08 17:46
total-experiments: 870
total-kept: 117
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
| `lisp/modules/gptel-benchmark-evolution.el` | 33% | 3 | 1 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-git.el` | 29% | 17 | 5 | 🟡 Active |
| `lisp/modules/gptel-ext-tool-sanitize.el` | 25% | 16 | 4 | 🟡 Active |
| `lisp/modules/gptel-agent-loop.el` | 22% | 85 | 19 | 🟡 Active |
| `lisp/modules/gptel-auto-workflow-projects.el` | 19% | 16 | 3 | 🟡 Active |
| `lisp/modules/gptel-ext-retry.el` | 19% | 43 | 8 | 🟡 Active |
| `lisp/modules/gptel-sandbox.el` | 18% | 106 | 19 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-benchmark.el` | 17% | 6 | 1 | 🟡 Active |
| `lisp/modules/gptel-benchmark-core.el` | 16% | 37 | 6 | 🟡 Active |

## Success Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- Add input validation and sanitization guards
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
- **lisp/modules/gptel-sandbox.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-tools-agent-benchmark.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-benchmark-core.el**: Try validation guards or error handling improvements (previous experiments discarded)

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

*This directive was auto-generated from 870 experiments (117 kept). It evolves every self-evolution cycle.*