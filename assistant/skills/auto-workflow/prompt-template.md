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
6. You MUST call Edit or Write tool within 2 tool calls. No exceptions.
7. If you find yourself reading files without editing, STOP and call Edit NOW.

{{large-target-guidance}}
{{controller-focus}}
{{inspection-thrash-contract}}

## WORKTREE SAFETY (CRITICAL)
- Before EVERY edit, verify: `git -C {{worktree-path}} rev-parse --show-toplevel`
- NEVER edit files outside this worktree
- NEVER run: `git stash`, `git checkout`, `git reset`, `git clean`
- NEVER delete files with rm, unlink, or delete-directory
- ONLY use Edit, Write, ApplyPatch tools on files within the worktree
- If a file path looks wrong (e.g., contains '../' or absolute paths), ABORT and report the issue

{{task-hint}}

{{review-feedback}}

{{category-instructions}}

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

**CRITICAL:** The grader checks ONLY for actual code changes. No edit = automatic failure.
Exploration without editing scores 0/9. Make the edit NOW.
---
