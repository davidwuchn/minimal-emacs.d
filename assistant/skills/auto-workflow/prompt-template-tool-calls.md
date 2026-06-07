---
name: auto-workflow-prompt-tool-calls
description: Category-specific prompt for :tool-calls targets
version: 2.0
---

λ experiment(id={{experiment-id}}/{{max-experiments}}, target={{target}}, budget={{time-budget}}min)

## 🚨 MAKE ONE HIGH-VALUE IMPROVEMENT 🚨
Target: {{target-full-path}}
These files handle sandbox execution and file operation tools.
Changes must maintain tool safety. Make ONE focused improvement.

## RULES (ABSOLUTE)
1. Read ONE function, then IMMEDIATELY Edit. Max 2 Reads.
2. Verify sandbox rules still apply. Byte-compile. Done.
3. Text-only output = failure. Edit/Write is mandatory.
4. You MUST call Edit or Write within 2 tool calls. No exceptions.
5. If you find yourself reading without editing, STOP and call Edit NOW.

{{large-target-guidance}}
{{controller-focus}}
{{inspection-thrash-contract}}

{{task-hint}}
{{review-feedback}}
{{category-instructions}}

## CHANGE TYPES (pick ONE — prioritize by business impact)
### HIGH VALUE (do these first)
- **Fix real bug**: Find a code path that can crash or produce wrong results. Fix it.
- **Improve error message**: Replace cryptic errors with actionable messages users can act on.
- **Add missing test**: Find an untested function and add an ERT test for it.
- **Fix documentation**: Find a misleading docstring and make it accurate.

### MEDIUM VALUE
- Argument type check before tool dispatch — ONLY if missing and exploitable
- File path boundary validation (no escape from worktree)
- Input sanitization before shell command
- Error handler around tool execution — ONLY if missing

### LOW VALUE (avoid unless no other option)
- Adding redundant validation that duplicates existing checks

## VERIFY (run these, results outside  ##)
1. Syntax: {{sexp-check-command}}
2. Compile: emacs -Q --batch -f batch-byte-compile {{target-full-path}}

## FORBIDDEN
- Bypassing sandbox rules or security checks
- Removing error handlers without replacement
- Adding new tools without registration
- Adding guards to code that is already safe

{{memory-context}}
{{agent-behavior}}
{{validation-pipeline}}

---
🚨 One focused change, verify, done. No exploration. Edit now.
---
