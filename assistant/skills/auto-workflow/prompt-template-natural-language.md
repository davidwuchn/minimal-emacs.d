---
name: auto-workflow-prompt-natural-language
description: Category-specific prompt for :natural-language targets
version: 1.0
---

λ experiment(id={{experiment-id}}/{{max-experiments}}, target={{target}}, budget={{time-budget}}min)

## 🚨 IMPROVE ONE PROMPT OR TEXT STRUCTURE 🚨
Target: {{target-full-path}}
These files are prompt templates and text processors.
Preserve format structure. Improve clarity or safety.

## RULES
1. Find one unclear or unsafe prompt section.
2. Improve wording or add a guard/fallback.
3. Verify template structure intact. Byte-compile. Done.
4. Two Reads max. Then Edit. No planning.

{{large-target-guidance}}
{{controller-focus}}
{{inspection-thrash-contract}}

{{task-hint}}
{{review-feedback}}
{{category-instructions}}

## WHAT TO IMPROVE
- Add fallback handler for missing template variable
- Clarify ambiguous instruction
- Add format validation before output

## VERIFY (run these, results outside <think>)
1. Syntax: {{sexp-check-command}}
2. Compile: emacs -Q --batch -f batch-byte-compile {{target-full-path}}

## FORBIDDEN
- Removing fallback handlers without replacement
- Changing template variable names
- Breaking prompt format structure

{{agent-behavior}}
{{validation-pipeline}}

---
🚨 One improvement, verify, done. Edit now.
---
