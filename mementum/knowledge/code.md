---
title: Code Quality and Efficiency Patterns
status: active
category: knowledge
tags: [code-quality, efficiency, workflow, tdd, refactoring, eight-keys]
---

# Code Quality and Efficiency Patterns

## Overview

Effective code manipulation requires balancing multiple concerns: efficiency, correctness, and maintainability. This page synthesizes proven patterns for improving code agent performance, making surgical edits to nested structures, conducting systematic code reviews, and applying test-driven development to code quality metrics.

---

## Code Agent Efficiency Patterns

### Efficiency Benchmarks by Task Type

Code agent efficiency varies significantly based on task complexity. Understanding these patterns allows for better task design and expectation setting.

| Task Type | Efficiency Range | Typical Steps | Recommended Pattern |
|-----------|-----------------|---------------|---------------------|
| Simple Edit | 0.82 - 0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8+ | glob → read×N → edit |
| Complex Refactor | 0.60 - 0.75 | 10-15 | analyze → plan → execute |

### The Eight Keys Alignment Framework

The Eight Keys framework provides a scoring system for evaluating code agent performance across multiple dimensions:

| Key | Excellent | Good | Needs Work | Formula |
|-----|-----------|------|------------|---------|
| Vitality | ≥0.85 | 0.75-0.84 | <0.75 | efficiency × completion |
| Clarity | ≥0.85 | 0.70-0.84 | <0.70 | tool-score × focus |
| Synthesis | ≥0.80 | 0.70-0.79 | <0.70 | context-utilization |

```python
# Example: Calculate vitality score
def calculate_vitality(efficiency, steps, max_steps=20):
    """Vitality measures how efficiently完成任务."""
    step_ratio = 1 - (steps / max_steps)
    return efficiency * step_ratio * 100

# Example scores
test_cases = [
    {"name": "code-001", "efficiency": 0.85, "steps": 5},
    {"name": "code-002", "efficiency": 0.88, "steps": 6},
    {"name": "code-003", "efficiency": 0.78, "steps": 8},
]

for tc in test_cases:
    score = calculate_vitality(tc["efficiency"], tc["steps"])
    print(f"{tc['name']}: vitality = {score:.2f}")
```

### Anti-Pattern Detection (Wu Xing Constraints)

Monitor these constraints to prevent workflow degradation:

| Anti-Pattern | Trigger Condition | Prevention |
|--------------|-------------------|------------|
| wood-overgrowth | steps > 20 | Set step budgets per phase |
| fire-excess | efficiency < 0.5 | Add scope hints to tasks |
| metal-rigidity | tool-score < 0.60 | Use appropriate tools |
| tool-misuse | continuations > 3 | Pre-define exploration scope |

```bash
# Check anti-pattern triggers
./check-constraints.sh --workflow-id code-003
# Output: PASS - all Wu Xing constraints satisfied
# - wood-overgrowth: ✓ (steps=8 <= 20)
# - fire-excess: ✓ (efficiency=0.72 >= 0.5)
# - metal-rigidity: ✓ (tool-score=0.78 >= 0.6)
# - tool-misuse: ✓ (continuations=2 <= 3)
```

### Task Scoping Best Practices

**For Exploration Tasks:**
- Add exploration scope hints to task descriptions
- Use `--max-count` or `--max-depth` in glob/grep operations
- Budget: 3-5 files for exploration, 1-2 for targeted edits

**For Simple Edits:**
- Skip P2 (planning) phase for direct-path efficiency
- Pattern: read → edit (valid for 5-6 step tasks)

**Context Management:**
```python
CONTEXT_BUDGETS = {
    "exploration": {"max_files": 5, "synthesis_required": True},
    "targeted_edit": {"max_files": 2, "synthesis_required": False},
    "refactor": {"max_files": 10, "synthesis_required": True},
}

def allocate_context(task_type, available_tokens):
    """Allocate context budget based on task type."""
    budget = CONTEXT_BUDGETS.get(task_type, CONTEXT_BUDGETS["targeted_edit"])
    return {
        "files": budget["max_files"],
        "tokens": available_tokens // budget["max_files"],
        "synthesis": budget["synthesis_required"]
    }
```

---

## Surgical Edits for Nested Code

### The Proble
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-gKTTF8.txt. Use Read tool if you need more]...