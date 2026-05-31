---
name: auto-workflow-prompt-template
description: Main experiment prompt template for auto-workflow agent
version: 2.0
---

λ experiment(id={{experiment-id}}/{{max-experiments}}, target={{target}}, budget={{time-budget}}min)

## 🚨 YOUR TASK: MAKE ONE CODE CHANGE THEN STOP 🚨
Target: {{target-full-path}}
Working dir: {{worktree-path}}

## RULES (ABSOLUTE)
1. Read 1-2 focused functions, then IMMEDIATELY use Edit.
2. NEVER read more than 3 sections. After 3 Reads, you MUST Edit or Write.
3. NEVER describe changes — MAKE them. Text-only outputs = instant failure.
4. NEVER reformat, reindent, or add comments.
5. Make ONE change. Don't refactor the whole file.

{{large-target-guidance}}
{{controller-focus}}
{{inspection-thrash-contract}}

{{task-hint}}

{{review-feedback}}

## VERIFY (MANDATORY)
After every Edit:
1. `{{sexp-check-command}}` → must PASS
2. `emacs -Q --batch -f batch-byte-compile {{target-full-path}}` → must PASS
3. `emacs -Q --batch -l {{target-full-path}}` → must PASS

Put results outside <think> in VERIFY section.

## FORBIDDEN
- Comments/docstrings-only changes
- Indentation/whitespace changes outside your edit
- Parameter tuning (buffer sizes, timeouts, limits) without logic change
- Renaming without architectural benefit
- Reading more than 3 code sections before editing

{{suggested-hypothesis}}
{{mutation-templates}}
{{evolved-recommendations}}
{{axis-guidance}}
{{axis-performance}}
{{frontier-guidance}}
{{saturation-status}}
{{cross-target-patterns}}
{{strategy-frontier}}
{{failure-patterns}}
{{task-type-diversity}}
{{agent-behavior}}
{{validation-pipeline}}

---
**🚨 YOUR NEXT TOOL CALL MUST BE Edit OR Write 🚨**
DO NOT read more files. DO NOT explore further. DO NOT plan.
You have ONE target file and ONE change to make. Read it, edit it, verify it.
If you don't call Edit or Write within 2 tool calls, the experiment fails.
---
