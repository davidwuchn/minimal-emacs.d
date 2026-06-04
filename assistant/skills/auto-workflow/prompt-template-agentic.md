---
name: auto-workflow-prompt-agentic
description: Category-specific prompt for :agentic targets
version: 1.0
---

λ experiment(id={{experiment-id}}/{{max-experiments}}, target={{target}}, budget={{time-budget}}min)

## 🚨 YOUR JOB: ADD ONE SAFETY GUARD 🚨
Target: {{target-full-path}}
These files handle agent dispatch, FSM state, and tool orchestration.
DO NOT restructure. DO NOT refactor widely. Add ONE guard and stop.

## RULES (ABSOLUTE)
1. Find any gethash/assoc/plist-get that lacks a nil check.
2. Add (or ... nil), (ignore-errors ...), or (condition-case ...).
3. Verify the change doesn't break dispatch. Byte-compile. Done.
4. Two Reads max. Then Edit. No planning.
5. You MUST call Edit or Write within 2 tool calls. No exceptions.
6. If you find yourself reading without editing, STOP and call Edit NOW.

{{large-target-guidance}}
{{controller-focus}}
{{inspection-thrash-contract}}

{{task-hint}}
{{review-feedback}}
{{category-instructions}}

## WHAT TO GUARD (pick ONE)
- gethash/plist-get without nil check → add (or (gethash ...) default)
- file operations without error handler → add (ignore-errors ...)
- FSM callback without state check → add nil-guard before callback

## VERIFY (run these, results outside <think>)
1. Syntax: {{sexp-check-command}}
2. Compile: emacs -Q --batch -f batch-byte-compile {{target-full-path}}
3. Load: emacs -Q --batch -l {{target-full-path}}

## FORBIDDEN
- Removing error handlers, callback guards, or safety nets
- Restructuring dispatch logic or FSM state machines
- Adding new agent types or tool registrations

{{suggested-hypothesis}}
{{mutation-templates}}
{{memory-context}}
{{evolved-recommendations}}
{{agent-behavior}}
{{validation-pipeline}}

---
🚨 YOUR NEXT TOOL CALL MUST BE Edit OR Write 🚨
One guard, one file, byte-compile, done. No exploration.
---
