---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.20
total-experiments: 950
total-kept: 204
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
| `lisp/modules/gptel-benchmark-evolution.el` | 35% | 17 | 6 | ✅ High yield |
| `lisp/modules/gptel-agent-loop.el` | 33% | 87 | 29 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-worktree.el` | 33% | 9 | 3 | ✅ High yield |
| `lisp/modules/gptel-auto-workflow-bootstrap.el` | 33% | 3 | 1 | ✅ High yield |
| `lisp/modules/gptel-benchmark-core.el` | 30% | 46 | 14 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-git.el` | 30% | 10 | 3 | ✅ High yield |
| `lisp/modules/gptel-sandbox.el` | 28% | 121 | 34 | 🟡 Active |
| `lisp/modules/gptel-ext-context-cache.el` | 28% | 101 | 28 | 🟡 Active |
| `lisp/modules/gptel-ext-fsm-utils.el` | 27% | 11 | 3 | 🟡 Active |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **Key insight** (2× from mementum)
- **unless-guard** (2× from git)
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

- **other** (761×): Investigate root cause
- **timeout** (94×): Add smaller batch sizes or chunked processing
- **test-failure** (41×): Run tests before committing experiments
- **validation-failed** (29×): Improve pre-grade validation prompts
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
- **lisp/modules/gptel-tools-agent-experiment-loop.el**: Apply Offline simulation functions diverge from live controller logic. (keep rate: 40%)
- **lisp/modules/gptel-benchmark-evolution.el**: Apply Offline simulation functions diverge from live controller logic. (keep rate: 35%)
- **lisp/modules/gptel-agent-loop.el**: Apply Offline simulation functions diverge from live controller logic. (keep rate: 33%)
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

*This directive was auto-generated from 950 experiments (204 kept locally across 950 local records). It evolves every self-evolution cycle.*