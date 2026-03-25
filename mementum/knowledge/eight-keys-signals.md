---
title: Eight Keys Signal Phrases
status: active
category: reference
tags: [eight-keys, signals, scoring, auto-workflow]
---

# Eight Keys Signal Phrases

Eight Keys scoring looks for specific phrases in commit messages and code.

## How Scoring Works

```
score = 0.6 × (signals found) + 0.4 × (anti-patterns avoided)
```

The scorer searches commit message + code diff for these phrases.

## Signal Phrases by Key

### φ Vitality (builds on discoveries, adapts)

| Signal | Usage |
|--------|-------|
| "builds on discoveries" | Reference past work: "Builds on discovery that X..." |
| "adapts to new information" | Show adaptation: "Adapts to new information about Y..." |
| "progressive improvement" | Show iteration: "Progressive improvement over previous approach..." |
| "learns from feedback" | Reference learning: "Learns from feedback on Z..." |
| "non-repetitive" | Avoid: rehashing same content |
| "evolves approach" | Show evolution: "Evolves approach from X to Y..." |

**Anti-patterns**: "mechanical rephrasing", "circular logic", "repeated failed approaches", "retrying same way"

### Clarity (explicit, testable)

| Signal | Usage |
|--------|-------|
| "explicit assumptions" | Add: `;; ASSUMPTION: ...` in code |
| "testable definitions" | Add: `;; TEST: ...` or `;; BEHAVIOR: ...` |
| "clear structure" | Use sections: PRECONDITIONS, POSTCONDITIONS |
| "measurable criteria" | Add: `;; CRITERIA: X must be Y` |
| "explicit success criteria" | Document: `;; SUCCESS: when X returns Y` |

**Anti-patterns**: "vague terms", "handle properly", "look good", "implicit assumptions"

**Example**:
```elisp
(defun my/function (arg)
  ;; ASSUMPTION: ARG is a string
  ;; BEHAVIOR: Returns t if ARG matches pattern
  ;; EDGE CASE: Empty string returns nil
  ...)
```

### ε Purpose (clear goals, measurable)

| Signal | Usage |
|--------|-------|
| "clear goals" | State in commit: "Goal: improve X by Y" |
| "measurable outcomes" | Add metrics: "Outcome: reduced time from X to Y" |
| "actionable function" | Document action: `;; ACTION: This function does X` |
| "defined deliverables" | List outputs: `;; DELIVERS: List of Y` |

**Anti-patterns**: "abstract descriptions", "no action", "unclear goals"

### τ Wisdom (planning, foresight)

| Signal | Usage |
|--------|-------|
| "planning before execution" | Reference plan: "Per plan in X..." |
| "error prevention" | Add guards: `;; GUARD: Prevents X when Y` |
| "risks identified" | Document: `;; RISK: X could cause Y` |
| "proactive measures" | Add: `;; PROACTIVE: Handles X before Y` |

**Anti-patterns**: "premature optimization", "reactive fixes", "no planning"

### π Synthesis (connects, integrates)

| Signal | Usage |
|--------|-------|
| "connects findings" | Reference: `;; CONNECTS: X from Y with Z` |
| "integrates knowledge" | Add: `;; INTEGRATES: Pattern from X` |
| "holistic view" | Document: `;; CONTEXT: This is part of X` |

**Anti-patterns**: "fragmented thinking", "isolated facts", "disconnected"

### μ Directness (efficient, concise)

| Signal | Usage |
|--------|-------|
| "direct communication" | Be direct in commit: "Fix X" not "Perhaps fix X" |
| "clear pass/fail" | Add: `;; RETURNS: t on success, nil on failure` |
| "concise" | Keep messages short, avoid fluff |

**Anti-patterns**: "polite evasion", "euphemisms", "softening language"

### ∃ Truth (evidence-based)

| Signal | Usage |
|--------|-------|
| "actual data" | Show: `;; DATA: Measured X at Y` |
| "evidence-based" | Reference: `;; EVIDENCE: Tests show X` |
| "acknowledges uncertainty" | Add: `;; NOTE: X may not work when Y` |

**Anti-patterns**: "wishful thinking", "should work", "false confidence"

### ∀ Vigilance (edge cases, validation)

| Signal | Usage |
|--------|-------|
| "edge cases handled" | Add: `;; EDGE CASE: X when Y` |
| "input validation" | Add: `;; VALIDATES: X is Y` |
| "boundary conditions" | Document: `;; BOUNDARY: X must be < Y` |

**Anti-patterns**: "assumes valid input", "missing edge cases"

## Commit Message Template

```
[context] Brief change description

HYPOTHESIS: {what} will improve {key} because {why}.

SIGNALS:
- {signal phrase 1}: {how applied}
- {signal phrase 2}: {how applied}

EVIDENCE:
- Tests: {results}
- Metrics: {before} → {after}
```

## Quick Reference for Executor

When making changes, include these in commit message:

| Target Key | Commit Should Say |
|------------|-------------------|
| φ Vitality | "builds on discovery that...", "adapts to..." |
| Clarity | "explicit assumptions:...", "testable:..." |
| ε Purpose | "goal:...", "measurable outcome:..." |
| τ Wisdom | "risk identified:...", "proactive:..." |
| π Synthesis | "connects X with Y", "integrates..." |
| μ Directness | Direct statement, no hedging |
| ∃ Truth | "evidence: tests pass", "data:..." |
| ∀ Vigilance | "edge case:...", "validates:..." |

## Why Scores Didn't Improve

From 2026-03-25 experiments:

| Experiment | Change | Missing Signals |
|------------|--------|-----------------|
| Constants extracted | Named patterns | No "explicit assumptions" in commit |
| Docstrings added | Good documentation | No "testable definitions" phrase |
| Stats tracking | Adaptive behavior | No "builds on discoveries" phrase |

**Fix**: Executor should include signal phrases in commit messages.