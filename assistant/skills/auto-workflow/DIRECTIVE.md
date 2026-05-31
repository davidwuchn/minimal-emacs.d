---
name: auto-workflow-directive
description: Evolving program definition for auto-workflow
version: 2026.05.31
total-experiments: 870
<<<<<<< Updated upstream
total-kept: 2
=======
total-kept: 7
>>>>>>> Stashed changes
---

# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> This directive is AUTO-EVOLVED from experiment results.
> Philosophy: Learn from every experiment. Adapt the program.

## Active Targets

<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->
| Target | Keep Rate | Total | Kept | Status |
|--------|-----------|-------|------|--------|
<<<<<<< Updated upstream
| `lisp/modules/gptel-auto-workflow-projects.el` | 12% | 16 | 2 | 🟡 Active |
| `lisp/modules/gptel-tools-agent-benchmark.el` | 0% | 1 | 0 | ⏳ Insufficient data |
| `lisp/modules/gptel-auto-workflow-strategic.el` | 0% | 3 | 0 | ⏳ Insufficient data |
| `lisp/modules/gptel-tools-agent-prompt-build.el` | 0% | 3 | 0 | ⏳ Insufficient data |
| `lisp/modules/gptel-tools-agent-error.el` | 0% | 3 | 0 | ⏳ Insufficient data |
| `lisp/modules/gptel-benchmark-subagent.el` | 0% | 3 | 0 | ⏳ Insufficient data |
| `lisp/modules/gptel-tools-agent-experiment-core.el` | 0% | 10 | 0 | ❌ Plateaued |
| `lisp/modules/gptel-auto-workflow-ontology-strategy.el` | 0% | 3 | 0 | ⏳ Insufficient data |
=======
| `lisp/modules/gptel-benchmark-principles.el` | 25% | 4 | 1 | 🟡 Active |
| `lisp/modules/gptel-auto-workflow-projects.el` | 23% | 26 | 6 | 🟡 Active |
| `lisp/modules/gptel-auto-workflow-research-integration.el` | 0% | 2 | 0 | ⏳ Insufficient data |
| `staging-verification` | 0% | 2 | 0 | ⏳ Insufficient data |
| `lisp/modules/gptel-auto-workflow-strategic.el` | 0% | 12 | 0 | ❌ Plateaued |
| `staging-merge` | 0% | 1 | 0 | ⏳ Insufficient data |
| `staging-review` | 0% | 1 | 0 | ⏳ Insufficient data |
| `lisp/modules/gptel-tools-agent-prompt-build.el` | 0% | 8 | 0 | ❌ Plateaued |
| `lisp/modules/gptel-tools-agent-error.el` | 0% | 6 | 0 | ❌ Plateaued |
| `lisp/modules/gptel-benchmark-subagent.el` | 0% | 3 | 0 | ⏳ Insufficient data |
>>>>>>> Stashed changes

## 🧬 Meta-Learned Patterns

<!-- AUTO-UPDATED: From git history + mementum analysis -->
*These patterns were automatically extracted from successful experiments.*

- **How it works** (38× from mementum)
- **Apply to us** (36× from mementum)
- **Source type** (24× from mementum)
- **Description** (24× from mementum)
- **Application for us** (24× from mementum)
- **Application** (21× from mementum)
- **Implementation sketch** (20× from mementum)
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

<<<<<<< Updated upstream
- **validation-failed** (25×): Improve pre-grade validation prompts
- **other** (16×): Investigate root cause
- **timeout** (1×): Add smaller batch sizes or chunked processing
=======
- **other** (50×): Investigate root cause
- **timeout** (7×): Add smaller batch sizes or chunked processing
- **validation-failed** (5×): Improve pre-grade validation prompts
- **test-failure** (2×): Run tests before committing experiments
- **api-limit** (1×): Implement provider fallback or rate limit handling
>>>>>>> Stashed changes

## Success Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- Extract helper functions for repeated logic
- Improve error handling and recovery mechanisms

## Failed Patterns

<!-- AUTO-UPDATED: From mementum knowledge -->
- Source type
- Description
- Application
- Implementation sketch

## Next Hypotheses

<!-- AUTO-UPDATED: From experiment insights -->
<<<<<<< Updated upstream
- **lisp/modules/gptel-auto-workflow-projects.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-auto-workflow-strategic.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-tools-agent-prompt-build.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-tools-agent-error.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-benchmark-subagent.el**: Try validation guards or error handling improvements (previous experiments discarded)
=======
- **lisp/modules/gptel-benchmark-principles.el**: Apply LLM analyzes *why* compressed context failed and updates compression guidelines iteratively (keep rate: 25%)
- **lisp/modules/gptel-auto-workflow-projects.el**: Apply LLM analyzes *why* compressed context failed and updates compression guidelines iteratively (keep rate: 23%)
- **lisp/modules/gptel-auto-workflow-strategic.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-tools-agent-prompt-build.el**: Try validation guards or error handling improvements (previous experiments discarded)
- **lisp/modules/gptel-tools-agent-error.el**: Try validation guards or error handling improvements (previous experiments discarded)
>>>>>>> Stashed changes

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

<<<<<<< Updated upstream
*This directive was auto-generated from 870 experiments (2 kept locally across 42 local records). It evolves every self-evolution cycle.*
=======
*This directive was auto-generated from 870 experiments (7 kept locally across 65 local records). It evolves every self-evolution cycle.*
>>>>>>> Stashed changes
