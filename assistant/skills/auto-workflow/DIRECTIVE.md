---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.17
total-experiments: 902
total-kept: 197
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-tools-agent-experiment-loop.el` | 40% | 5 | 2 | ✅ High yield |
| `lisp/modules/gptel-benchmark-evolution.el` | 40% | 10 | 4 | ✅ High yield |
| `lisp/modules/gptel-agent-loop.el` | 33% | 87 | 29 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-git.el` | 33% | 6 | 2 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-worktree.el` | 33% | 9 | 3 | ✅ High yield |
| `lisp/modules/gptel-auto-workflow-bootstrap.el` | 33% | 3 | 1 | ✅ High yield |
| `lisp/modules/gptel-benchmark-core.el` | 30% | 46 | 14 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-validation.el` | 30% | 10 | 3 | ✅ High yield |
| `lisp/modules/gptel-auto-workflow-behavioral-tests.el` | 29% | 21 | 6 | 🟡 Active |
| `lisp/modules/gptel-workflow-benchmark.el` | 29% | 7 | 2 | 🟡 Active |

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

- Multi-layer validation stack (seen 1×)
- ACP (Agent Client Protocol) - standardized agent communication (seen 1×)
- Offline simulation functions diverge from live controller logic. (seen 1×)
- Multiple cron jobs using the same Emacs daemon server name cause "already running" errors. (seen 1×)
- Merged experiment worktrees should be cleaned up to prevent accumulation. (seen 1×)
- Direct path is more efficient than full cycle for simple tasks. (seen 1×)

## 🛡️ Error Mitigation

<!-- AUTO-UPDATED: From experiment error analysis -->

- **other** (727×): Investigate root cause
- **timeout** (82×): Add smaller batch sizes or chunked processing
- **test-failure** (41×): Run tests before committing experiments
- **validation-failed** (27×): Improve pre-grade validation prompts
- **api-limit** (19×): Implement provider fallback or rate limit handling

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
- **lisp/modules/gptel-benchmark-evolution.el**: Apply Multi-layer validation stack (keep rate: 40%)
- **lisp/modules/gptel-tools-agent-experiment-loop.el**: Apply Multi-layer validation stack (keep rate: 40%)
- **lisp/modules/gptel-agent-loop.el**: Apply Multi-layer validation stack (keep rate: 33%)
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

*This directive was auto-generated from 902 experiments (197 kept locally across 902 local records). It evolves every self-evolution cycle.*