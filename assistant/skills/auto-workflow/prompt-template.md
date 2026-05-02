---
name: auto-workflow-prompt-template
description: Main experiment prompt template for auto-workflow agent
version: 1.0
---

You are running experiment {{experiment-id}} of {{max-experiments}} to optimize {{target}}.

## Working Directory
{{worktree-path}}

## Target File (full path)
{{target-full-path}}

{{large-target-guidance}}

{{controller-focus}}

{{inspection-thrash-contract}}

## Previous Experiment Analysis
{{previous-experiment-analysis}}

## Suggestions
{{suggestions}}

## Skills (Context from Learned Patterns)
{{self-evolution}}

## Previous Experiments
{{topic-knowledge}}

## Current Baseline
Overall Eight Keys score: {{baseline}}

{{weakest-keys}}

{{suggested-hypothesis}}

{{mutation-templates}}

{{axis-guidance}}

{{frontier-guidance}}

{{agent-behavior}}

## Objective
Improve the CODE QUALITY for {{target}}.
Focus on one improvement at a time.
Make minimal, targeted changes to CODE, not documentation.

## Constraints
- Time budget: {{time-budget}} minutes
- Immutable files: early-init.el, pre-early-init.el, lisp/eca-security.el
- Must pass tests: ./scripts/verify-nucleus.sh
- FORBIDDEN: Adding comments, docstrings, or documentation-only changes
- REQUIRED: Actual code changes (bug fixes, performance, refactoring, error handling)

## Code Improvement Types (PICK ONE)
1. **Bug Fix**: Fix an actual bug or error handling gap
2. **Performance**: Reduce complexity, add caching, optimize hot path
3. **Refactoring**: Extract functions, remove duplication, improve naming
4. **Safety**: Add validation, prevent edge cases, improve error messages
5. **Test Coverage**: Add missing tests for existing functionality

## Exploration Axis (PICK ONE)
A. **Error Handling** — Add validation, prevent edge cases, improve error messages
B. **Performance** — Reduce complexity, add caching, optimize hot path
C. **Refactoring** — Extract functions, remove duplication, improve naming
D. **Safety** — Add guards, type checking, boundary validation
E. **Test Coverage** — Add missing tests for existing functionality
F. **Memory Management** — Fix leaks, optimize allocation, cleanup patterns

{{validation-pipeline}}

## Instructions
1. FIRST LINE must be: HYPOTHESIS: [What CODE change and why]
2. Generate **3 candidate hypotheses** for this target. For each, write a one-line description.
3. Pick the **strongest candidate** based on: likelihood of improvement, minimal change, alignment with weakest keys and underexplored axes.
4. If a Controller-Selected Starting Symbol is present, line 2 must be exactly `{{focus-line}}`
5. If a Mandatory Focus Contract is present, obey it exactly; otherwise start from one concrete function or variable and prefer focused Grep or narrow Read before broader Code_Map surveys
6. Read only focused line ranges from the target file using its full path; avoid reading the entire file unless absolutely necessary
7. IDENTIFY a real code issue (bug, performance, duplication, missing validation)
8. Implement the CODE change minimally using Edit tool
9. Run validation pipeline (CHEAP - do these first):
   a. Syntax check: {{sexp-check-command}}
   b. Byte-compile: emacs -Q --batch -f batch-byte-compile {{target-full-path}}
   c. Load test: emacs -Q --batch -l {{target-full-path}}
   - If ANY validation step fails, FIX IT before proceeding
   - Do not run expensive tests on broken code
10. Run tests to verify: ./scripts/verify-nucleus.sh && ./scripts/run-tests.sh
9. DO NOT run git add, git commit, git push, or stage changes yourself.
   Leave edits uncommitted in the worktree; the auto-workflow controller
   handles grading, commit creation, review, and staging.
10. FINAL RESPONSE must include:
    - CHANGED: exact file path(s) and function/variable names touched
    - EVIDENCE: 1-2 concrete code snippets or diff hunks showing the real edit
    - VERIFY: exact command(s) run and whether they passed or failed
    - AXIS: which exploration axis this targets (A-F)
    - COMMIT: always "not committed" (workflow controller handles commits)
11. End the final response with: Task completed
12. NEVER reply with only "Done", only a commit message, or a vague success claim

CRITICAL: Your response MUST start with HYPOTHESIS: on the first line.
DO NOT add comments, docstrings, or documentation.
DO make actual code changes that improve functionality.
DO include concrete evidence of what changed so the grader can inspect it.

Example HYPOTHESES:
- HYPOTHESIS: Adding validation for nil input in process-item will prevent runtime errors
- HYPOTHESIS: Extracting duplicate retry logic into a helper will reduce code duplication
- HYPOTHESIS: Adding a cache for expensive computation will improve performance
- HYPOTHESIS: Fixing the off-by-one error in the loop will correct the boundary case
