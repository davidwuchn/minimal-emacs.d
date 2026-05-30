---
name: auto-workflow-agent-behavior
description: Behavioral rules and constraints for auto-workflow agent. Guides how the agent approaches code improvement experiments.
version: 1.0
---

# Auto-Workflow Agent Behavior

## CRITICAL CONSTRAINTS

- You MUST make actual CODE changes using the Edit or Write tools. Text-only responses will be rejected.
- You MUST verify your changes work before submitting.
- You MUST NOT write "the code is optimal" or abort early.
- You MUST complete all steps including prototyping.
- **TOOL USAGE IS MANDATORY:** Outputting markdown text without file modifications is a failure. Use Edit or Write to modify files.

### Anti-Parameter-Tuning Rules

The most common failure mode is creating changes that are just parameter variants.

**Good candidates change a fundamental mechanism:**
- A new error handling strategy (e.g. early validation vs defensive coding)
- A new data structure (e.g. hash table vs list, memoization)
- A new abstraction (e.g. extract function, create helper)
- A new validation pattern (e.g. schema checking, type guards)

**Bad candidates just tune numbers:**
- Changing loop bounds without changing logic
- Adjusting buffer sizes without architectural change
- Renaming variables without semantic improvement
- Adding comments or docstrings

**If your change can be described as "same logic, different constants", REWRITE with a truly novel mechanism.**

### Anti-Overfitting Rules

- **No target-specific hacks.** Changes must generalize to similar code patterns.
- **Never hardcode assumptions** about the specific file being edited.
- **General patterns are OK.** Rules like "validate nil inputs" or "cache repeated computation" apply broadly.
- **Do not add feature-specific code** unless the feature is already part of the system's design.

## EXPLORATION AXES

Track which axes have been explored recently. If last 3 experiments explored the same axis, pick a different one.

A. **Error Handling** — Add validation, prevent edge cases, improve error messages
B. **Performance** — Reduce complexity, add caching, optimize hot path
C. **Refactoring** — Extract functions, remove duplication, improve naming
D. **Safety** — Add guards, type checking, boundary validation
E. **Test Coverage** — Add missing tests for existing functionality
F. **Memory Management** — Fix leaks, optimize allocation, cleanup patterns

## WORKFLOW

**Do ALL steps yourself in the main session.**

### Step 0: Analyze

1. **Read state files:**
   - Check the target file structure and existing patterns
   - Review previous experiments on this target (if any)
   - Identify the weakest Eight Keys scores
2. **Formulate 1-3 hypotheses** — each must be falsifiable and target a different mechanism.
3. **Pick the strongest hypothesis** based on:
   - Likelihood of real improvement
   - Minimal change surface area
   - Alignment with weakest keys

### Step 1: Prototype — MANDATORY

**You MUST prototype your mechanism before editing the target file.** Do NOT skip this step.

For complex changes:
1. Write a scratch implementation in a comment or separate buffer
2. Verify the logic handles edge cases
3. Test the approach mentally against the target code
4. Only then apply to the actual file

### Step 2: Implement

1. **Use Edit or Write tools** to modify the target file. Do NOT just describe changes in text.
2. Make minimal, targeted changes to the target file
3. **NEVER reformat, reindent, or restyle code.** Do NOT run `indent-region`, `save-buffer` with auto-indent, or any tool that changes whitespace/line breaks outside your actual code change. The grader treats unrelated indentation changes as a FORBIDDEN behavior.
4. **Surgical edits only:** Change ONLY the specific lines needed for your improvement. If your diff shows changes to functions other than your target, or indentation changes in unrelated code, UNDO and redo more precisely.
5. Follow existing code style and conventions
6. **Self-critique (mandatory):** After implementing, re-read the change:
   - Is this genuinely NEW logic or just a parameter variant?
   - Would this change help similar code elsewhere?
   - Is the change minimal enough?
   - Does the diff contain any indentation/whitespace changes outside the target function?
7. If the answer to any is "no", REWRITE

### Step 3: Validate — MANDATORY

**Verification is not optional. Experiments WITHOUT verification commands are rejected automatically.**

After EVERY edit, you MUST run verification in this exact order:

1. **Check git diff:** Verify `git diff` shows actual file modifications. If empty, you failed — go back to Step 2.
2. **Syntax check:** Run `{{sexp-check-command}}`
3. **Byte-compile:** Run `emacs -Q --batch -f batch-byte-compile {{target-full-path}}`
4. **Load test:** Run `emacs -Q --batch -l {{target-full-path}}`
5. **Record results:** In your final response under VERIFY, list the exact commands run and their PASS/FAIL status.

**Failure to run verification = automatic experiment rejection. The grader checks for verification commands explicitly.**

### Step 4: Document

In your final response, include:
- **CHANGED:** Exact file paths and function/variable names
- **EVIDENCE:** Concrete code snippets or diff hunks
- **VERIFY:** Commands run and results
- **AXIS:** Which exploration axis this targets (A-F)

## FORBIDDEN PATTERNS

- **Text-only responses without file modifications.** If you do not use Edit or Write tools, the experiment will fail immediately.
- Adding comments, docstrings, or documentation-only changes
- Changing formatting without semantic improvement
- Renaming without architectural benefit
- Parameter sweeps (buffer sizes, timeouts, limits)
- Removing functionality without replacement
- Adding dependencies without justification

## EVALUATION CRITERIA

Your change will be evaluated on:
1. **Correctness** — Does it actually fix/improve something?
2. **Generality** — Would it help similar code patterns?
3. **Minimality** — Is the change as small as possible?
4. **Verification** — Did you prove it works?
5. **Novelty** — Is it a new mechanism, not just tuning?
