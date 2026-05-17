---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.17
total-experiments: 945
total-kept: 161
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

- **extract-helper-function** (9× from git)
- **error-handling** (7× from git)
- **unless-guard** (4× from git)
- **Applicability** (2× from mementum)
- **Key insight** (2× from mementum)
- **manual-fix** (2× from git)
- **add-variable** (2× from git)

## 🛠️ Effective Techniques

<!-- AUTO-UPDATED: From mementum insights -->

- Direct path is more efficient than full cycle for simple tasks. (seen 1×)
- Multi-layer validation stack (seen 1×)
- ACP (Agent Client Protocol) - standardized agent communication (seen 1×)
- Offline simulation functions diverge from live controller logic. (seen 1×)
- Guard nil values before passing to functions expecting number-or-marker. (seen 1×)
- Use `(file-name-as-directory (expand-file-name dir))` to ensure trailing slash. (seen 1×)

## 🛡️ Error Mitigation

<!-- AUTO-UPDATED: From experiment error analysis -->

- **other** (771×): Investigate root cause
- **timeout** (105×): Add smaller batch sizes or chunked processing
- **validation-failed** (42×): Improve pre-grade validation prompts
- **api-limit** (19×): Implement provider fallback or rate limit handling
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
- **lisp/modules/gptel-benchmark-comparator.el**: Apply Direct path is more efficient than full cycle for simple tasks. (keep rate: 50%)
- **lisp/modules/gptel-tools-agent-runtime.el**: Apply Direct path is more efficient than full cycle for simple tasks. (keep rate: 38%)
- **lisp/modules/gptel-workflow-benchmark.el**: Apply Direct path is more efficient than full cycle for simple tasks. (keep rate: 35%)
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

*This directive was auto-generated from 945 experiments (161 kept locally across 945 local records). It evolves every self-evolution cycle.*