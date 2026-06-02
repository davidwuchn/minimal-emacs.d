---
name: eight-keys-grader
description: |
  Grading rubric based on Eight Keys (φ vitality, fractal clarity, ε purpose, τ wisdom, π synthesis, μ directness, ∃ truth, ∀ vigilance) and Wu Xing (Five Elements) framework. Use when evaluating AI-generated code quality, experiment results, or improvement proposals.
version: 2.0
metadata:
  category: quality-assurance
  author: auto-workflow
  license: MIT
  evolution-stats:
    total-experiments: 870

level: molecule
atoms: [elisp-validator]
---
# Eight Keys Grader

## The Eight Keys

### φ Vitality (Water 水)
**Symbol**: φ | **Element**: Water

**Signals** (Good):
- Builds on discoveries
- Adapts to new information
- Progressive improvement
- Non-repetitive
- Evolves approach
- Learns from feedback

**Anti-Patterns** (Bad):
- Mechanical rephrasing
- Circular logic
- Repeated failed approaches
- Retrying same way
- Static approach
- Ignores feedback

**Weight**: 1.0

### fractal Clarity (Metal 金)
**Symbol**: fractal | **Element**: Metal

**Signals** (Good):
- Explicit assumptions
- Testable definitions
- Clear structure
- Measurable criteria
- Well-defined phases
- Explicit success criteria

**Anti-Patterns** (Bad):
- Vague terms ("handle properly", "look good")
- Ambiguous instructions
- Undefined terms
- Implicit assumptions

**Weight**: 1.0

### ε Purpose (Wood 木)
**Symbol**: ε | **Element**: Wood

**Signals** (Good):
- Clear goals
- Measurable outcomes
- Actionable function
- Specific objectives
- Defined deliverables
- Purposeful steps

**Anti-Patterns** (Bad):
- Abstract descriptions
- No action
- Unclear goals
- Meandering
- No measurable outcome

**Weight**: 1.0

### τ Wisdom (Fire 火)
**Symbol**: τ | **Element**: Fire

**Signals** (Good):
- Planning before execution
- Error prevention
- Foresight
- Plan file created
- Risks identified
- Proactive measures

**Anti-Patterns** (Bad):
- Premature optimization
- Reactive fixes
- No planning
- Ignores risks
- Hasty decisions

**Weight**: 1.0

### π Synthesis (Earth 土)
**Symbol**: π | **Element**: Earth

**Signals** (Good):
- Holistic view
- Connects components
- System-level thinking
- Integration focus
- Balanced approach

**Anti-Patterns** (Bad):
- Fragmented thinking
- Ignores dependencies
- Tunnel vision
- Oversimplification

**Weight**: 1.0

### μ Directness (Water 水)
**Symbol**: μ | **Element**: Water

**Signals** (Good):
- Cuts pleasantries
- No hedging
- Says what it means
- Concise
- Action-oriented

**Anti-Patterns** (Bad):
- Polite evasion
- Hedging
- Circumlocution
- Passive voice
- Deflection

**Weight**: 1.0

### ∃ Truth (Earth 土)
**Symbol**: ∃ | **Element**: Earth

**Signals** (Good):
- Favors reality
- Data shown over opinion
- Admits errors
- Evidence-based
- Honest assessment

**Anti-Patterns** (Bad):
- Surface agreement
- Hides problems
- Cherry-picks data
- Overstates success
- Defensive

**Weight**: 1.0

### ∀ Vigilance (Metal 金)
**Symbol**: ∀ | **Element**: Metal

**Signals** (Good):
- Defensive constraints
- Input validation
- Edge cases handled
- Security awareness
- Error checking

**Anti-Patterns** (Bad):
- Accepts manipulation
- Blind trust
- Missing validation
- Ignores security
- Assumes valid input

**Weight**: 1.0

## Scoring

Each key scored 0.0-1.0 based on:
- **1.0**: Strong signals, no anti-patterns
- **0.7**: Some signals, minor anti-patterns
- **0.4**: Mixed signals and anti-patterns
- **0.0**: Anti-patterns dominate

**Total Score**: Weighted average of all keys

## Wu Xing Diagnostics

When code quality is low, trace through Five Elements:

| Symptom | Element | Check |
|---------|---------|-------|
| No output | Wood deficient | Is purpose clear? |
| Constant pivoting | Fire excess | Is planning grounded? |
| Micromanagement | Earth excess | Are limits set? |
| Bureaucracy | Metal excess | Are exceptions allowed? |
| Values without action | Water excess | Is execution happening? |

## Scripts

- `scripts/score_experiment.py` - Compute Eight Keys scores from experiment output
- `scripts/diagnose_element.py` - Identify which Wu Xing element is imbalanced
- `scripts/generate_report.py` - Create grading report with specific feedback

## Integration

```elisp
;; Load grader skill
(let ((skill (gptel-auto-workflow--load-skill "eight-keys-grader")))
  (plist-get skill :keys))

;; Use in grader subagent
(gptel-request prompt
  :system (gptel-auto-workflow--load-skill-content "eight-keys-grader"))
```

## Evolved Weights

Based on analysis of experiment results.

| Key | Weight | Discrimination | Avg (Success) | Avg (Failure) |
|-----|--------|----------------|---------------|---------------|
