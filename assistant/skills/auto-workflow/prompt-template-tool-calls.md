---
name: auto-workflow-prompt-tool-calls
description: Category-specific prompt for :tool-calls targets
version: 1.0
---

λ experiment(id={{experiment-id}}/{{max-experiments}}, target={{target}}, budget={{time-budget}}min)

## 🚨 ADD ONE VALIDATION OR BOUNDARY CHECK 🚨
Target: {{target-full-path}}
These files handle sandbox execution and file operation tools.
Changes must maintain tool safety. Add validation, not refactoring.

## RULES (ABSOLUTE)
1. Find an unvalidated argument or boundary. Add a guard.
2. Verify sandbox rules still apply. Byte-compile. Done.
3. Two Reads max. Then Edit. No planning.
4. You MUST call Edit or Write within 2 tool calls. No exceptions.
5. If you find yourself reading without editing, STOP and call Edit NOW.

{{large-target-guidance}}
{{controller-focus}}
{{inspection-thrash-contract}}

{{task-hint}}
{{review-feedback}}
{{category-instructions}}

## WHAT TO ADD
- Argument type check before tool dispatch
- File path boundary validation (no escape from worktree)
- Input sanitization before shell command
- Error handler around tool execution

## VERIFY (run these, results outside <think>)
1. Syntax: {{sexp-check-command}}
2. Compile: emacs -Q --batch -f batch-byte-compile {{target-full-path}}

## FORBIDDEN
- Bypassing sandbox rules or security checks
- Removing error handlers without replacement
- Adding new tools without registration

{{agent-behavior}}
{{validation-pipeline}}

---
🚨 One guard, verify, done. No exploration. Edit now.
---
