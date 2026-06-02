---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.06.01
total-experiments: 870
total-kept: 14
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
| `lisp/modules/gptel-ext-context.el` | 50% | 2 | 1 | ✅ High yield |
| `lisp/modules/gptel-benchmark-comparator.el` | 50% | 4 | 2 | ✅ High yield |
| `lisp/modules/gptel-tools-agent-prompt-build.el` | 21% | 14 | 3 | 🟡 Active |
| `lisp/modules/gptel-tools-agent.el` | 14% | 7 | 1 | 🟡 Active |
| `lisp/modules/gptel-benchmark-subagent.el` | 13% | 15 | 2 | 🟡 Active |
| `lisp/modules/gptel-auto-workflow-projects.el` | 11% | 35 | 4 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-error.el` | 7% | 15 | 1 | ❌ Plateaued |
| `lisp/modules/gptel-ext-fsm-utils.el` | 0% | 7 | 0 | ❌ Plateaued |
| `lisp/modules/gptel-ext-retry.el` | 0% | 3 | 0 | ⏳ Insufficient data |
| `staging-review` | 0% | 11 | 0 | ❌ Plateaued |

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **manual-fix** (59× from git)
- **How it works** (38× from mementum)
- **Apply to us** (36× from mementum)
- **Application for us** (24× from mementum)
- **Source type** (24× from mementum)
- **Description** (24× from mementum)
- **Application** (21× from mementum)
- **Symbolic Attention Magnets** (20× from mementum)

## 🛠️ Effective Techniques

<!-- AUTO-UPDATED: From mementum insights -->

- LLM analyzes *why* compressed context failed and updates compression guidelines iteratively (seen 4×)
- Manager agent builds a "task ledger" (plan with goals/subgoals) dynamically, then delegates to specialized agents (seen 4×)
- Two agents in a turn-based "maker creates, checker validates" loop with explicit acceptance criteria and iteration caps (seen 4×)
- Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts. (seen 2×)
- Use mathematical constants (φ, ψ, Δ, λ) as "attention magnets" to prime LLMs toward formal reasoning patterns (seen 2×)
- Zero client-side intelligence; AI decides, client executes. (seen 2×)

## 🛡️ Error Mitigation

<!-- AUTO-UPDATED: From experiment error analysis -->

- **other** (106×): Investigate root cause
- **timeout** (17×): Add smaller batch sizes or chunked processing
- **validation-failed** (15×): Improve pre-grade validation prompts
- **api-limit** (5×): Implement provider fallback or rate limit handling

## Success Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- Extract helper functions for repeated logic

## Failed Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- Source type
- Description
- Application
- Implementation sketch

## Next Hypotheses

<!-- AUTO-UPDATED: From experiment insights -->
- **lisp/modules/gptel-benchmark-comparator.el**: Apply LLM analyzes *why* compressed context failed and updates compression guidelines iteratively (keep rate: 50%)
- **lisp/modules/gptel-tools-agent-prompt-build.el**: Apply LLM analyzes *why* compressed context failed and updates compression guidelines iteratively (keep rate: 21%)
- **lisp/modules/gptel-tools-agent.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-benchmark-subagent.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-auto-workflow-projects.el**: Try validation guards or error handling improvements (previous experiments discarded)

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

*This directive was auto-generated from 870 experiments (14 kept locally across 143 local records). It evolves every self-evolution cycle.*