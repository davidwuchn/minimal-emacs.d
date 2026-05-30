---
name: auto-workflow-prompt-template
description: Main experiment prompt template for auto-workflow agent
version: 1.1
---

You are running experiment {{experiment-id}} of {{max-experiments}} to optimize {{target}}.

## CRITICAL: YOUR TASK IS CODE CHANGES ONLY
**DO NOT do research. DO NOT analyze the codebase broadly. DO NOT investigate failure patterns.**
**Your job: Make ONE focused code change to {{target}} and verify it works.**
**Start from a concrete function, make the edit, run validation. That's it.**

## Objective
Improve the CODE QUALITY for {{target}}.
Focus on one improvement at a time.
Make minimal, targeted changes to CODE, not documentation.

## Working Directory
{{worktree-path}}

## Target File (full path)
{{target-full-path}}

{{large-target-guidance}}

{{controller-focus}}

{{inspection-thrash-contract}}

## Constraints
- Time budget: {{time-budget}} minutes
- Immutable files: early-init.el, pre-early-init.el, lisp/eca-security.el
- Must pass tests: ./scripts/verify-nucleus.sh
- FORBIDDEN: Adding comments, docstrings, or documentation-only changes
- FORBIDDEN: Reformatting, reindenting, or changing whitespace in code outside your actual change. The grader penalizes unrelated indentation changes as "style-only without functional impact".
- REQUIRED: Actual code changes (bug fixes, performance, refactoring, error handling)
- REQUIRED: Surgical precision — change ONLY the specific lines needed. Do NOT trigger `indent-region`, `save-buffer` with auto-indent, or any tool that reformats code.

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

## Instructions
1. FIRST LINE must be: HYPOTHESIS: [What CODE change and why]
2. Generate **3 candidate hypotheses** for this target. Format them EXACTLY as:
   CANDIDATE_1: [one-line description]
   CANDIDATE_2: [one-line description]
   CANDIDATE_3: [one-line description]
3. Pick the **strongest candidate** based on: likelihood of improvement, minimal change, alignment with weakest keys and underexplored axes.
4. If a Controller-Selected Starting Symbol is present, line 2 must be exactly `{{focus-line}}`
5. If a Mandatory Focus Contract is present, obey it exactly; otherwise start from one concrete function or variable and prefer focused Grep or narrow Read before broader Code_Map surveys
6. Read only focused line ranges from the target file using its full path; avoid reading the entire file unless absolutely necessary
7. IDENTIFY a real code issue (bug, performance, duplication, missing validation)
8. **CRITICAL: YOU MUST USE Edit OR Write TOOLS.** Text-only descriptions of changes cause immediate failure. After reading code, your very next action MUST be an Edit or Write tool call that changes the file. Do not describe changes—make them.
9. **MANDATORY VERIFICATION — WITHOUT THIS, EXPERIMENT FAILS AUTOMATICALLY**
   After EVERY code change, you MUST run these THREE verification commands IN ORDER:
   a. Syntax check: {{sexp-check-command}}
   b. Byte-compile: emacs -Q --batch -f batch-byte-compile {{target-full-path}}
   c. Load test: emacs -Q --batch -l {{target-full-path}}
   
   **YOU MUST ACTUALLY RUN THESE COMMANDS. DO NOT SKIP THEM.**
   **The grader checks for evidence that you ran them. If missing, you get 0/4 and FAIL.**
   
    **WARNING: The VERIFY section MUST appear OUTSIDE <think> blocks.** The grader only counts verification evidence in visible output. Putting it inside <think> tags causes automatic FAIL on verification-attempted.
    
    Example VERIFY section (MUST include in final response, after closing </think>):
   VERIFY:
   - Syntax check: emacs -Q --batch --eval="(check-parens)" {{target-full-path}} → PASS
   - Byte-compile: emacs -Q --batch -f batch-byte-compile {{target-full-path}} → PASS  
   - Load test: emacs -Q --batch -l {{target-full-path}} → PASS
   
   - If ANY validation step fails, FIX IT before proceeding
   - Do not run expensive tests on broken code
 10. (Optional) Run full tests: ./scripts/verify-nucleus.sh && ./scripts/run-tests.sh
 11. DO NOT run git add, git commit, git push, or stage changes yourself.
     Leave edits uncommitted in the worktree; the auto-workflow controller
     handles grading, commit creation, review, and staging.
 12. DO NOT trigger auto-indentation. After using Edit tool, do NOT call `save-buffer` if it triggers `indent-region`. Use Write tool only for new files, not to rewrite existing files just to "fix formatting".
 14. FINAL RESPONSE must include:
     - CHANGED: exact file path(s) and function/variable names touched
     - EVIDENCE: 1-2 concrete code snippets or diff hunks showing the real edit
     - VERIFY: exact command(s) run and whether they passed or failed
     - AXIS: which exploration axis this targets (A-F)
     - COMMIT: always "not committed" (workflow controller handles commits)
 15. End the final response with: Task completed
 16. NEVER reply with only "Done", only a commit message, or a vague success claim

CRITICAL: Your response MUST start with HYPOTHESIS: on the first line.
DO NOT add comments, docstrings, or documentation.
DO make actual code changes that improve functionality.
DO include concrete evidence of what changed so the grader can inspect it.

Example HYPOTHESES:
- HYPOTHESIS: Adding validation for nil input in process-item will prevent runtime errors
- HYPOTHESIS: Extracting duplicate retry logic into a helper will reduce code duplication
- HYPOTHESIS: Adding a cache for expensive computation will improve performance
- HYPOTHESIS: Fixing the off-by-one error in the loop will correct the boundary case

---

## Context (Reference Only - Do Not Research From This)

## Previous Experiment Analysis
{{previous-experiment-analysis}}

## Suggestions
{{suggestions}}

## Skills (Context from Learned Patterns)
{{self-evolution}}

## Nucleus Guidance (Category-Aware Attention)
{{nucleus-persona}}

{{moderator-lens}}

## Research Quality (Allium Audit)
{{allium-issues}}

## Auto-Repair Guidance
{{allium-repair}}

## Previous Experiments
{{topic-knowledge}}

## External Research Findings
{{research-findings}}

## Current Baseline
Overall Eight Keys score: {{baseline}}

{{weakest-keys}}

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
