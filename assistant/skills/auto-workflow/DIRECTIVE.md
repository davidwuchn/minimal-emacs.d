---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
<<<<<<< ours — preamble `(preamble)` (F, confidence: medium)
// hint: Logic changed on both sides. Requires understanding intent of each change.
version: 2026.05.17
total-experiments: 901
total-kept: 197
=======
version: 2026.05.22
total-experiments: 1976
total-kept: 383
>>>>>>> theirs — preamble `(preamble)` (F, confidence: medium)
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
<<<<<<< ours — heading `Active Targets` (F, confidence: medium)
// hint: Logic changed on both sides. Requires understanding intent of each change.
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
=======
| `lisp/modules/gptel-tools-agent-strategy-harness.el` | 40% | 5 | 2 | ✅ High yield |
| `lisp/modules/gptel-tools.el` | 38% | 13 | 5 | ✅ High yield |
| `lisp/modules/gptel-ext-core.el` | 34% | 29 | 10 | ✅ High yield |
| `lisp/modules/gptel-benchmark-instincts.el` | 33% | 9 | 3 | ✅ High yield |
| `lisp/modules/gptel-auto-workflow-behavioral-tests.el` | 33% | 27 | 9 | ✅ High yield |
| `lisp/modules/gptel-ext-context.el` | 30% | 44 | 13 | 🟡 Active |
| `lisp/modules/gptel-benchmark-integrate.el` | 26% | 23 | 6 | 🟡 Active |
| `lisp/modules/gptel-ext-fsm-utils.el` | 25% | 147 | 37 | 🟡 Active |
| `lisp/modules/gptel-benchmark-evolution.el` | 25% | 28 | 7 | 🟡 Active |
| `lisp/modules/gptel-benchmark-memory.el` | 25% | 8 | 2 | 🟡 Active |
>>>>>>> theirs — heading `Active Targets` (F, confidence: medium)

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

<<<<<<< ours — heading `🧬 Meta-Learned Patterns` (F, confidence: medium)
// hint: Logic changed on both sides. Requires understanding intent of each change.
- **extract-helper-function** (9× from git)
- **error-handling** (7× from git)
- **unless-guard** (4× from git)
- **Applicability** (2× from mementum)
- **Key insight** (2× from mementum)
- **manual-fix** (2× from git)
- **add-variable** (2× from git)
=======
- **Application for us** (24× from mementum)
- **Source type** (24× from mementum)
- **Description** (24× from mementum)
- **Application** (20× from mementum)
- **Implementation sketch** (20× from mementum)
- **How it works** (18× from mementum)
- **Apply to us** (16× from mementum)
- **Emacs application** (14× from mementum)
>>>>>>> theirs — heading `🧬 Meta-Learned Patterns` (F, confidence: medium)

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

<<<<<<< ours — heading `🛡️ Error Mitigation` (F, confidence: medium)
// hint: Logic changed on both sides. Requires understanding intent of each change.
- **other** (727×): Investigate root cause
- **timeout** (81×): Add smaller batch sizes or chunked processing
- **test-failure** (41×): Run tests before committing experiments
- **validation-failed** (27×): Improve pre-grade validation prompts
- **api-limit** (19×): Implement provider fallback or rate limit handling
=======
- **other** (1513×): Investigate root cause
- **timeout** (274×): Add smaller batch sizes or chunked processing
- **test-failure** (106×): Run tests before committing experiments
- **validation-failed** (38×): Improve pre-grade validation prompts
- **api-limit** (33×): Implement provider fallback or rate limit handling
>>>>>>> theirs — heading `🛡️ Error Mitigation` (F, confidence: medium)

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
<<<<<<< ours — heading `Next Hypotheses` (F, confidence: medium)
// hint: Logic changed on both sides. Requires understanding intent of each change.
- **lisp/modules/gptel-benchmark-evolution.el**: Apply Multi-layer validation stack (keep rate: 40%)
- **lisp/modules/gptel-tools-agent-experiment-loop.el**: Apply Multi-layer validation stack (keep rate: 40%)
- **lisp/modules/gptel-agent-loop.el**: Apply Multi-layer validation stack (keep rate: 33%)
- **lisp/modules/nucleus-tools.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-ext-retry.el**: Try validation guards or error handling improvements (previous experiments discarded)
=======
- **lisp/modules/gptel-tools-agent-strategy-harness.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 40%)
- **lisp/modules/gptel-tools.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 38%)
- **lisp/modules/gptel-ext-core.el**: Apply Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (keep rate: 34%)
- **lisp/modules/gptel-ext-reasoning.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-tools-agent-base.el**: Try validation guards or error handling improvements (previous experiments discarded)
>>>>>>> theirs — heading `Next Hypotheses` (F, confidence: medium)

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

<<<<<<< ours — heading `Constraints` (T, confidence: high)
// hint: Cosmetic change on both sides. Pick either version or combine formatting.
*This directive was auto-generated from 901 experiments (197 kept locally across 901 local records). It evolves every self-evolution cycle.*
=======
*This directive was auto-generated from 1976 experiments (383 kept locally across 1976 local records). It evolves every self-evolution cycle.*
>>>>>>> theirs — heading `Constraints` (T, confidence: high)
