---
name: auto-workflow-prompt-natural-language
description: Category-specific prompt for :natural-language targets
version: 2.0
---

λ experiment(id={{experiment-id}}/{{max-experiments}}, target={{target}}, budget={{time-budget}}min)

## 🚨 IMPROVE ONE PROMPT OR TEXT STRUCTURE 🚨
Target: {{target-full-path}}
These files are prompt templates and text processors.
Preserve format structure. Improve clarity or safety.

## RULES (ABSOLUTE)
1. Read ONE section, then IMMEDIATELY Edit. Never read more than 2 sections.
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
- **Fix misleading instruction**: Find text that could confuse the AI or user. Make it accurate.
- **Add missing fallback**: Find a template variable with no default. Add a sensible fallback.
- **Improve clarity**: Find ambiguous phrasing. Make it specific and testable.

### MEDIUM VALUE
- Add format validation before output
- Deduplicate repeated instructions
- Remove obsolete instructions

### LOW VALUE (avoid unless no other option)
- Cosmetic rewording without functional change

## VERIFY (run these, results outside  ##)
1. Syntax: {{sexp-check-command}}
2. Compile: emacs -Q --batch -f batch-byte-compile {{target-full-path}}

## FORBIDDEN
- Removing fallback handlers without replacement
- Changing template variable names
- Breaking prompt format structure

{{memory-context}}
{{agent-behavior}}
{{validation-pipeline}}

---
🚨 One improvement, verify, done. Edit now.
---
