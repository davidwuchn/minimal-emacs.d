---
name: auto-workflow-prompt-agentic
description: Category-specific prompt for :agentic targets
version: 2.0
---

λ experiment(id={{experiment-id}}/{{max-experiments}}, target={{target}}, budget={{time-budget}}min)

## 🚨 YOUR JOB: MAKE ONE HIGH-VALUE IMPROVEMENT 🚨
Target: {{target-full-path}}
These files handle agent dispatch, FSM state, and tool orchestration.
DO NOT restructure. DO NOT refactor widely. Make ONE focused change and stop.

## RULES (ABSOLUTE)
1. Read ONE function or section, then IMMEDIATELY Edit. Max 2 Reads.
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

## CHANGE TYPES (pick ONE — prioritize by business impact)
### HIGH VALUE (do these first)
- **Fix real bug**: Find a code path that can crash or produce wrong results. Fix it.
- **Improve error message**: Replace cryptic errors with actionable messages users can act on.
- **Add missing test**: Find an untested function and add an ERT test for it.
- **Fix documentation**: Find a misleading docstring and make it accurate.

### MEDIUM VALUE
- nil/error guard: (ignore-errors ...), (condition-case ...), (or ... nil) — ONLY if it prevents a real crash path
- deduplicate: extract helper fn from repeated code blocks (3+ repetitions)
- boundary: add validation before destructive operation

### LOW VALUE (avoid unless no other option)
- Style/formatting changes
- Adding redundant guards on already-safe code

## VERIFY (run these, results outside  ##)
1. Syntax: {{sexp-check-command}}
2. Compile: emacs -Q --batch -f batch-byte-compile {{target-full-path}}
3. Load: emacs -Q --batch -l {{target-full-path}}

## FORBIDDEN
- Removing error handlers, callback guards, or safety nets
- Restructuring dispatch logic or FSM state machines
- Adding new agent types or tool registrations
- Adding guards to code that is already safe

{{suggested-hypothesis}}
{{mutation-templates}}
{{memory-context}}
{{evolved-recommendations}}
{{agent-behavior}}
{{validation-pipeline}}

---
🚨 YOUR NEXT TOOL CALL MUST BE Edit OR Write 🚨
Read, edit, verify. 2 Reads max. No planning.
---
