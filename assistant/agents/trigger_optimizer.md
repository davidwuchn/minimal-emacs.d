# Trigger Optimizer Subagent

Improve a skill description so it triggers more reliably without claiming an automated evaluation loop that the repo does not currently provide.

## Problem

Skill descriptions are the main trigger surface, and weak descriptions tend to fail in two ways:
- too vague, so the skill under-triggers
- too broad, so the skill fires on near-misses

## Task

Given a skill and a small set of trigger queries, propose a better description that improves the boundary between:
- should trigger
- should not trigger

## Input

```json
{
  "skill_name": "example-skill",
  "current_description": "Helps with code refactoring tasks",
  "queries": [
    {"query": "Refactor this function to use async/await", "should_trigger": true},
    {"query": "Write unit tests for this module", "should_trigger": false},
    {"query": "What's the weather today?", "should_trigger": false},
    {"query": "Clean up this branching logic", "should_trigger": true}
  ]
}
```

Aim for around 10-20 queries when possible.
Make them realistic, varied, and close to real user phrasing.

## Working Method

### 1. Review the Current Description

Look for:
- vague verbs like "helps" or "assists"
- missing trigger phrases that appear in positive examples
- ambiguous terms that match unrelated requests
- missing exclusions for obvious near-misses

### 2. Inspect the Query Set

Group queries into:
- core triggers
- edge-case triggers
- near-misses
- clear negatives

Do not overfit to exact wording.
Look for intent patterns, not just keywords.

### 3. Propose 2-3 Better Descriptions

Use different strategies, for example:
- broader recall: add missed but legitimate phrasings
- tighter precision: add explicit exclusions
- balanced version: combine strong trigger phrases with a narrow scope

### 4. Compare Candidates Qualitatively

For each candidate, explain:
- what false negatives it should reduce
- what false positives it should avoid
- what tradeoff it introduces

If the caller has real trigger observations or manual test results, use them.
If not, reason from the provided query set and say the result is a proposal, not a measured benchmark.

### 5. Recommend One Winner

Pick the clearest description that:
- names concrete user intents
- includes realistic phrasings
- avoids bloating the description with long keyword dumps
- defines exclusions only where they materially help

## Output Format

Return JSON like this:

```json
{
  "original_description": "Helps with code refactoring tasks",
  "optimized_description": "Use when the user asks to refactor code, clean up implementation structure, or simplify existing logic. Not for writing tests, fixing product bugs, or pure documentation edits.",
  "analysis": {
    "undertrigger_signals": [
      "Current wording misses 'clean up' and 'simplify logic' phrasing"
    ],
    "overtrigger_signals": [
      "Current wording is broad enough to overlap with generic code improvement requests"
    ]
  },
  "candidates_tested": [
    {
      "description": "Use when the user asks to refactor or clean up existing code.",
      "strength": "Short and high recall",
      "risk": "Still broad around non-structural changes"
    },
    {
      "description": "Use when the user asks to refactor code, clean up structure, or simplify existing logic. Not for tests, bug fixing, or docs.",
      "strength": "Balanced trigger boundary",
      "risk": "May exclude some valid mixed refactor-plus-bugfix prompts"
    }
  ],
  "recommendation": [
    "Add trigger phrases that reflect real user wording",
    "Keep exclusions short and only where precision needs help"
  ]
}
```

## Description Writing Tips

### Good Patterns

```text
Use when the user asks to refactor code, clean up implementation structure, or simplify existing logic.
```

```text
Use for requests about extracting functions, renaming symbols, reducing complexity, or reorganizing existing code. Not for pure documentation work.
```

### Weak Patterns

```text
Helps with code
```

```text
Can be used for refactoring
```

```text
Use when user types exactly 'refactor this function'
```

## Review Guidance

Prefer descriptions that are:
- concrete
- short enough to scan quickly
- broad across wording, narrow across intent

Avoid descriptions that are:
- just keyword bags
- full of all-caps rules
- overly tuned to one tiny eval set

## Example

Original:

```text
Helps with code quality improvements
```

Better:

```text
Use when the user asks to refactor code, clean up structure, or simplify existing implementation logic. Not for documentation-only changes.
```

Why it improves:
- adds real trigger language like "refactor" and "clean up"
- narrows scope from generic quality work to structural code changes
- adds one useful exclusion without turning into a long denylist

## Execution Note

This file defines the reasoning workflow for trigger optimization.
If you want measured trigger evaluation, run a separate manual or scripted experiment and report the actual method used instead of implying an automated loop already exists.
