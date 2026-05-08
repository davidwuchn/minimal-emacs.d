# Skill Evolution Closed Loop

## What Happened

The system now uses its own evolved knowledge to guide future experiments.

## The Loop

```
Experiments → Analysis → Skill Evolution → Prompt Injection → Better Experiments
```

1. **Experiments**: 870 experiments across 36 targets
2. **Analysis**: `analyze_results.py` computes success rates per Wu Xing element
3. **Skill Evolution**: `evolve_benchmark.py` updates `benchmark-improver/SKILL.md`
4. **Prompt Injection**: `gptel-auto-workflow--load-evolved-recommendations()` loads skill data
5. **Better Experiments**: Executor sees "Earth/Control has 16% success, prioritize validation"

## Key Finding

**Earth (Control) improvements are most successful**:
- 16% keep rate (49/304 experiments)
- Keywords: prevent, errors, validation, explicit, runtime
- Action: Add validation guards, error handling, defensive checks

**Fire (Intelligence) improvements are least successful**:
- 0% keep rate (0/3 experiments)
- Action: Skip planning/analysis hypotheses, focus on concrete code changes

## Integration

Added to `gptel-tools-agent-prompt-build.el`:
- `gptel-auto-workflow--load-evolved-recommendations()` - loads from benchmark-improver skill
- Injects into prompt template as `{{evolved-recommendations}}`
- Updated `prompt-template.md` with placeholder

## Impact

Executor now receives data-driven guidance:
- "Prioritize Earth/Control improvements (16% success)"
- "Avoid Fire/Intelligence hypotheses (0% success)"
- "Top patterns: prevent errors, add validation, fix bugs"

This closes the self-improvement loop: experiments teach the system what works, skills record the learnings, and prompts inject the knowledge back into the workflow.

## λ Principle

```
λ evolve(x).    experiment → analyze → evolve → inject → experiment
                | feedback_loop(x) ≡ closed(x)
                | open_loop(x) ≢ evolve(x)
```
