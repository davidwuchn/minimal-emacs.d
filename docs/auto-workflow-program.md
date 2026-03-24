# Auto-Workflow Program

> Human-editable objectives for autonomous overnight optimization.
> Edit this file to change what the agent works on.

## Targets

Files to optimize (one per line, relative to project root):

```
lisp/modules/gptel-ext-retry.el
lisp/modules/gptel-ext-context.el
lisp/modules/gptel-tools-code.el
```

## Success Criteria

| Criterion | Threshold | Weight |
|-----------|-----------|--------|
| Eight Keys overall | >= 5% improvement | 50% |
| Tests pass | 100% | 30% |
| No immutable file changes | 100% | 20% |

## Constraints

### Immutable Files (never modify)

```
early-init.el
pre-early-init.el
lisp/eca-security.el
lisp/modules/gptel-ext-security.el
lisp/modules/gptel-ext-tool-confirm.el
lisp/modules/gptel-ext-tool-permits.el
lisp/modules/gptel-sandbox.el
eca/**
mementum/**
var/elpa/**
```

### Time Budget

| Setting | Value |
|---------|-------|
| Per experiment | 15 minutes |
| Max per target | 10 experiments |
| Stop if no improvement after | 3 consecutive |

### Optimization Focus

- [ ] Performance (startup time, memory)
- [x] Code clarity (readability, maintainability)
- [x] Both equally weighted

## Mutation Strategy

Agent-driven: Read git history + optimization skills to generate hypotheses.

Allowed mutation types:
- [x] caching
- [x] lazy-init
- [x] simplification
- [ ] parallel-processing (experimental)

## Priority Focus

Each experiment targets the weakest Eight Keys based on baseline scores:

| Key | Signals | Improvement Focus |
|-----|---------|-------------------|
| φ Vitality | builds on discoveries, adapts | Keep experiments alive |
| λ Efficiency | removes redundancy, optimizes | Simplify code paths |
| α Alignment | follows conventions, idioms | Match project patterns |
| ρ Robustness | handles errors, edge cases | Add guards, validations |
| σ Specificity | concrete over vague | Use precise language |
| θ Thoroughness | complete coverage | Add missing pieces |
| π Synthesis | connects findings | Integrate knowledge |
| κ Coherence | logical flow | Improve structure |

The prompt includes:
1. **Weakest Keys**: Top 2 lowest-scoring keys with focus signals
2. **Suggested Hypothesis**: From optimization skill (if available)
3. **Hypothesis Templates**: From linked mutation skills

## Target-Specific Patterns

Each target has an optimization skill in `mementum/knowledge/optimization-skills/{name}.md`:

```yaml
---
phi: 0.50
mutation-skills:
  - mementum/knowledge/mutations/caching.md
  - mementum/knowledge/mutations/lazy-init.md
---
```

Mutation skills provide hypothesis templates:
- `"Add caching to {component} to reduce redundant {operation}"`
- `"Memoize {function} for {scenario}"`

These are injected into experiment prompts for guided hypothesis generation.

## Morning Review

1. Review `var/tmp/experiments/{date}/results.tsv`
2. Check optimization skills for compounded learnings
3. Merge successful branches: `git merge optimize/{target}-exp{N}`
4. Edit this file to adjust objectives for next night