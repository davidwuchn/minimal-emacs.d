---
name: auto-workflow-prompt-programming
description: Category-specific prompt for :programming targets
version: 1.0
---

λ experiment(id={{experiment-id}}/{{max-experiments}}, target={{target}}, budget={{time-budget}}min)

## 🚨 MAKE ONE CODE CHANGE — READ → EDIT → VERIFY 🚨
Target: {{target-full-path}}
Working dir: {{worktree-path}}

## RULES (ABSOLUTE)
1. Read ONE function, then IMMEDIATELY Edit. Never read more than 2 sections.
2. After Edit, run byte-compile. If fail, fix. If pass, done.
3. Text-only output = failure. Edit/Write is mandatory.
4. You MUST call Edit or Write within 2 tool calls. No exceptions.
5. If you find yourself reading without editing, STOP and call Edit NOW.

{{large-target-guidance}}
{{controller-focus}}
{{inspection-thrash-contract}}

{{task-hint}}
{{review-feedback}}
{{category-instructions}}

## CHANGE TYPES (do ONE)
- nil/error guard: (ignore-errors ...), (condition-case ...), (or ... nil)
- deduplicate: extract helper fn from repeated code blocks
- boundary: add validation before destructive operation

## VERIFY (run these, put results outside <think>)
1. Syntax: {{sexp-check-command}}
2. Compile: emacs -Q --batch -f batch-byte-compile {{target-full-path}}
3. Load: emacs -Q --batch -l {{target-full-path}}

## FORBIDDEN
- Comments/docstrings-only changes
- Indentation/formatting outside your edit
- Parameter tuning without logic change

{{suggested-hypothesis}}
{{mutation-templates}}
{{evolved-recommendations}}
{{axis-guidance}}
{{agent-behavior}}
{{validation-pipeline}}

---
🚨 YOUR NEXT TOOL CALL MUST BE Edit OR Write 🚨
Read, edit, verify. 2 Reads max. No planning.
---
