# ✅ SKILL.md Template Variable Resilience

tags: researcher, SKILL.md, template, evolve_researcher.py, rebase

## Context
The researcher SKILL.md uses template variables ({{research-effectiveness}}, {{topic-performance}}, etc.) that get replaced with live data by `substitute-researcher-variables`. The daemon's `evolve_researcher.py` regenerates SKILL.md with hardcoded placeholder text each cycle, overwriting the template variables. Every rebase also reverted them.

## Solution (Two-Layer)
1. **Python source**: `evolve_researcher.py` now writes `{{template}}` variables instead of inline values. No more hardcoded `0.0% (0/0...)` or `*No topic data*`.
2. **Elisp defense**: `substitute-researcher-variables` auto-restores template variables from hardcoded patterns before substituting live data. Even if the Python script generates hardcoded text, the Elisp fixes it.

## When Re-adding Variables
The SKILL.md needs these template variables:
- `{{research-effectiveness}}` `{{kept-research}}` `{{total-research}}`
- `{{topic-performance}}`
- `{{research-champion}}` `{{ontology-gaps}}`
- `{{current-bottlenecks}}` `{{strategy-guidance}}`

If they're lost, the Elisp substitution function in `gptel-auto-workflow-strategic.el` will auto-restore them from hardcoded patterns.
