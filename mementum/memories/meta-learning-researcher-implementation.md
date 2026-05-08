# Meta-Learning Researcher Implementation

## What Happened

Built a self-evolving researcher system that learns from experiment outcomes to prioritize research topics.

## Architecture

```
Experiments (870) → analyze_research_outcomes.py → topic-performance.json
                                                          ↓
                                               evolve_researcher.py
                                                          ↓
                                            Dynamic SKILL.md (v2.0)
                                                          ↓
                                    gptel-auto-workflow--substitute-researcher-variables
                                                          ↓
                                               Researcher Subagent
                                                          ↓
                                               Better Experiments
```

## Components Built

1. **analyze_research_outcomes.py** — Parses results.tsv, extracts topics from hypotheses, correlates with outcomes
2. **evolve_researcher.py** — Generates dynamic skill from analysis data
3. **Elisp integration** — Variable substitution, trigger system, cache loading
4. **Data files** — topic-performance.json, source-effectiveness.json, temporal-patterns.json

## Key Findings

| Topic | Success Rate | Status |
|-------|--------------|--------|
| nil-safety | 28.3% | 🎯 PRIORITIZE |
| validation-guard | 18.6% | 🎯 PRIORITIZE |
| helper-extraction | 9.3% | ⚠️ AVOID |
| async | 7.1% | ⚠️ AVOID |
| cleanup | 5.9% | ⚠️ AVOID |

## Impact

Researcher prompt now dynamically prioritizes topics with proven success.
Anti-patterns are data-driven, not static.
Skill auto-evolves every 50 experiments or when keep rate drops below 14%.

## λ Principle

```
λ meta-learn(x).  research → experiment → measure → evolve → research
                  | ¬static_prompt(x) | dynamic(x) ∝ outcome(y)
```

## Date: 2026-05-08
