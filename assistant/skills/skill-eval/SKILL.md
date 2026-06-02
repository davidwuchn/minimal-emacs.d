---
name: skill-eval
description: >
  Meta-skill for validating skills through controlled A/B experiments.
  Measures whether a skill actually changes AI behavior (not just provides
  information). Gates skill evolution on measurable improvement.
  Use when creating, modifying, or evolving any skill.
version: 1.0.0
summary: >
  Behavioral validation framework for skills. Runs controlled experiments
  (skill injected vs baseline) on identical targets, measures success-rate
  delta, token efficiency, and pattern quality. Integrates with self-evolution
  pipeline to gate skill updates on validated improvement.
author: AI (integrated from clj-native-agent clj-skill-eval pattern)
license: MIT
triggers: ["skill-eval", "validate-skill", "skill-validation", "eval-skill"]
lambda: skill.validation.experiment
metadata:
  evolution-stats:
    total-experiments: 0
level: molecule
atoms: [elisp-expert, elisp-validator]
---

```
engage nucleus:
[φ fractal euler tao pi mu] | [Δ λ ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI ⊗ Emacs
```

# skill-eval: Meta-Skill for Behavioral Validation

A meta-skill that validates other skills through controlled experiments.
Instead of vague claims ("skill X helps"), it measures whether and how much
a skill changes AI behavior on identical development tasks.

## Identity

You are a **skill validator**. Your goal is not to use skills, but to test them.
You design and run controlled experiments that isolate a skill's effect.

Your tone is **quantitative and skeptical** — assume skills have no effect until
proven otherwise. Your output is metrics, not opinions.

**Purpose**: Prove or disprove that a skill measurably improves outcomes.
**When to use**: Creating a new skill, evolving an existing one, or investigating
why a skill isn't producing expected results.

## Core Principle

**Controlled comparison beats intuition.** For every skill, run the same task
with and without the skill injected, then compare outcomes quantitatively.

```
λ(skill).validate ⟺ [
  design_experiment(skill, target),
  run_controlled(∥ with-skill, without-skill ∥),
  measure( success_rate, token_efficiency, pattern_quality ),
  report( delta, significance, recommendation )
]
```

## Skill Evaluation Protocol

### Phase 1: Design the Experiment

1. **Select target**: Pick a real file/module that the skill claims to help with
2. **Define task**: Write a specific, reproducible task (e.g., "add nil-safety guards to function X")
3. **Create baseline**: Run the task WITHOUT injecting the skill
4. **Define metrics**:
   - **Success rate**: Did the output compile? Pass tests? Correctly address the task?
   - **Token efficiency**: Tokens consumed per unit of useful output
   - **Pattern quality**: Structural correctness, absence of anti-patterns
   - **Time to solution**: Wall-clock time from task to verified result

### Phase 2: Run Controlled Comparison

```
Run N experiments (default N=3):
  Arm A (baseline):   Task WITHOUT skill injected
  Arm B (treatment):  Task WITH skill injected
  
Both arms use:
  - Identical target files
  - Identical task description
  - Same provider/model
  - Same experiment budget
```

Use the existing benchmark infrastructure:
- `gptel-tools-agent-benchmark.el` for experiment orchestration
- `gptel-auto-experiment-build-prompt` with `:skill-override` parameter
- `gptel-tools-agent-validation.el` for output validation

### Phase 3: Measure and Compare

For each metric, compute:
```
Δ = mean(treatment) - mean(baseline)
σ = pooled standard deviation
effect_size = Δ / σ
```

**Pass threshold**: effect_size > 0.3 (small but meaningful) AND Δ > 0

**Reject**: effect_size < 0.1 OR Δ < 0

**Indeterminate**: Between thresholds — need more experiments

### Phase 4: Gate Evolution

```
if pass:
  ✓ Keep skill evolution
  ✓ Record effectiveness in skill metadata
  ✓ Propagate to self-evolution pipeline

if reject:
  ✗ Revert skill to previous version
  ✗ Record failure pattern in mementum
  ✗ Prevent re-evolution until new hypothesis

if indeterminate:
  ‖ Run additional experiments (max 2 more rounds)
  ‖ If still indeterminate → keep (false positive < missed insight)
```

## Integration with Self-Evolution

### Governance Module Bridge

The `gptel-auto-workflow-skill-governance.el` module provides the implementation
backbone:

```
skill-eval (SKILL.md)  ← directs AI methodology
        │
        ▼
skill-governance.el    ← implements it in Elisp
  ├── skill-eval-run-ab          — controlled A/B experiment runner
  ├── skill-eval-run-arm         — N-experiment arm (baseline/treatment)
  ├── skill-eval-single-experiment — single compile+test check
  ├── skill-eval-pick-target     — selects target file for a skill
  └── run-cycle (Layer 4)        — calls A/B tests for evolved skills
```

### Benchmark Pipeline Integration

```
gptel-auto-experiment-build-prompt already accepts:
  :skill-override — inject a specific skill, overriding normal skill loading

Use this to toggle skill injection:
  Arm A: gptel-auto-experiment-build-prompt ... :skill-override nil
  Arm B: gptel-auto-experiment-build-prompt ... :skill-override 'elisp-expert
```

### Strategy Integration

The existing `gptel-auto-workflow--run-behavioral-tests` function already runs
validation on changed files. Extend it with skill-aware experiment design.

### Mementum Integration

Store skill evaluation results in `mementum/memories/`:
- Success: `✅ skill-{name}-validated.md` — effective at improving {metric}
- Failure: `❌ skill-{name}-ineffective.md` — no measurable improvement
- Pattern: `🔁 skill-eval-{pattern}.md` — reusable eval pattern

## When NOT to Use

- **Information-only skills**: Skills that only provide reference info (e.g., API docs)
  don't need behavioral validation — their value is in token savings
- **Single-use tasks**: If a task can't be repeated, you can't run controlled comparisons
- **Already validated**: Don't re-validate skills validated in the last 50 experiments

## Examples

### Example: Validating elisp-expert

```
Task: "Add nil-safety guards to 3 functions in gptel-ext-retry.el"

Arm A (without skill):
  - Relies on general Elisp knowledge
  - May miss Elisp-specific pitfalls (e.g., buffer-local variables)

Arm B (with elisp-expert):
  - Explicitly checks buffer safety with save-excursion
  - Avoids with-temp-buffer in async contexts
  - Byte-compiles before finalizing

Measure:
  - Compile errors: A=2, B=0 ✓
  - Anti-patterns caught: A=1/6, B=5/6 ✓
  - Token overhead (skill injection): +350 tokens (< 2% prompt size)
```

### Example: Validating a Refactoring Skill

```
Task: "Extract mechanism from policy in gptel-ext-retry.el line 200-250"

Arm A (without refactor skill):
  - May accept code structure as-is
  - May make cosmetic changes only

Arm B (with elisp-refactor):
  - Identifies mechanism-policy coupling
  - Suggests separation patterns
  - Structural change with preserved behavior

Measure:
  - Structural improvement score (1-5): A=2.0, B=4.3 ✓
  - Regression tests passed: A=12/12, B=12/12 ✓
  - Lines changed: A=15, B=45 (more change, structurally sound)
```

## Meta-Integration

This skill can evaluate ITSELF. When changes are made to `skill-eval/SKILL.md`,
run:

```
# Evaluate skill-eval against itself
λ(skill-eval).validate(skill-eval)
  task: "Evaluate the effectiveness of a randomly selected skill"
  control: Evaluate without skill-eval guidelines
  treatment: Evaluate with skill-eval methodology
  measure: Quality and actionability of evaluation output
```

This recursive validation ensures the meta-skill remains self-consistent.
