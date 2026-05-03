---
name: meta-harness-proposer
description: Run one iteration of prompt-building strategy evolution. Proposes 3 new strategy candidates based on prior results.
version: 1.0
---

# Meta-Harness Prompt-Building Strategy Evolution

Run ONE iteration of strategy evolution. Do all analysis and prototyping in the main session.

**You do NOT run benchmarks.** You analyze results, prototype changes, and implement new strategies. The outer loop handles benchmarking separately.

## CRITICAL CONSTRAINTS

- You MUST propose exactly 3 new strategy candidates every iteration.
- Do NOT write "the frontier is optimal" or "stop iterating", or abort early.
- ALWAYS complete all steps including prototyping.
- Design exactly 3 candidates per iteration: mix of exploitation and exploration.

### Anti-parameter-tuning rules

The most common failure mode is creating strategies that are just parameter variants of existing ones. Check `evolution_summary.jsonl` for what's been tried.

**Good candidates change a fundamental mechanism:**

- A new prompt section ordering algorithm (e.g., dynamic ordering based on target file characteristics)
- A new context retrieval strategy (e.g., load related files based on git blame, not just the target)
- A new variable computation method (e.g., compute statistical summaries of prior experiments, not just raw data)
- A new skill loading pattern (e.g., conditional skill loading based on target analysis)
- A new adaptive compression strategy (e.g., compress sections that correlate with failure, not just size-based)

**Bad candidates just tune numbers.** If the logic is identical to the base except for constants, thresholds, or section ordering, it's a parameter variant. Rewrite with a genuinely novel mechanism.

**Combining strategies is valid.** Take the section ordering from strategy A and the context retrieval from strategy B.

### Anti-overfitting rules

- **No target-specific hints.** Do not hardcode knowledge about specific files or modules.
- **Never mention target file names** in strategy code, prompts, or comments.
- **General patterns are OK.** Rules like "prioritize failure patterns for large files" or "balance exploration axes" are fine — they apply broadly.
- **Strategies must work on any Emacs Lisp file.** Do not assume specific module structures or naming conventions.

### Exploitation Axes

A=Prompt template architecture, B=Context retrieval, C=Section ordering, D=Variable computation, E=Skill loading, F=Adaptive compression.

If last 3 iterations explored the same axis, pick different ones.

## WORKFLOW

### Step 0: Post-eval reports (write if missing)

Check `assistant/strategies/reports/`. For each past iteration that has results in `evolution_summary.jsonl` but NO report, write one. Each report should be **<=30 lines** covering: what changed, which targets improved/regressed and why, and a takeaway for future iterations.

### Step 1: Analyze

1. **Read all state files:**
   - `assistant/strategies/evolution_summary.jsonl` — what's been tried
   - `assistant/strategies/frontier.json` — current Pareto frontier
   - `assistant/strategies/evaluations.jsonl` — detailed evaluation results
   - Recent TSV results if available

2. Formulate 3 hypotheses — each must be falsifiable and target a different mechanism.

### Step 2: Prototype — MANDATORY

**You MUST prototype your mechanism before writing the final strategy.** Do NOT skip this step. Candidates that skip prototyping tend to have bugs or produce no improvement.

For each candidate:

1. Write a test script in `/tmp/` that exercises the core mechanism in isolation.
2. Try 2-3 variants and compare before picking the best one.
3. Delete scripts when done.

### Step 3: Implement

For each of the 3 candidates:

1. Copy a top-performing base strategy to `assistant/strategies/prompt-builders/strategy-<name>.el`, then make targeted modifications.
2. Implement the new mechanism according to your hypothesis.
3. **Self-critique (mandatory):** After implementing, re-read the file and check: does this strategy introduce a genuinely NEW mechanism, or is it just a parameter variant? If the logic is identical to the base except for numbers, REWRITE with a truly novel mechanism.
4. Validate: `emacs -Q --batch --eval '(load "assistant/strategies/prompt-builders/strategy-<name>.el" nil t)'`

### Step 4: Write pending_eval.json

Write to `assistant/strategies/pending_eval.json`:

```json
{
  "iteration": <N>,
  "candidates": [
    {
      "name": "<snake_case_name>",
      "file": "assistant/strategies/prompt-builders/strategy-<name>.el",
      "hypothesis": "<falsifiable claim>",
      "axis": "<A-F>",
      "base_strategy": "<what it builds on>",
      "components": ["tag1", "tag2", "..."]
    }
  ]
}
```

Output: `CANDIDATES: <name1>, <name2>, <name3>`

## Strategy Interface

Every strategy must provide:

```elisp
(defun strategy-<name>-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using strategy <name>.
Returns a prompt string.")

(defun strategy-<name>-get-metadata ()
  "Return metadata for this strategy."
  (list :name "<name>"
        :version "1.0"
        :hypothesis "<hypothesis>"
        :axis "<A-F>"
        :created "<date>"
        :parent-strategies '(<parents>)
        :components '("tag1" "tag2")
        :description "<description>"))
```

- Strategies are discovered automatically from `assistant/strategies/prompt-builders/`
- Must call functions from `gptel-tools-agent-prompt-build` module
- Must return a non-empty string (the prompt)
- Must register self via `gptel-auto-workflow--register-strategy`

## Directory Structure

- Strategies: `assistant/strategies/prompt-builders/strategy-*.el`
- Evaluations: `assistant/strategies/evaluations.jsonl`
- Frontier: `assistant/strategies/frontier.json`
- Evolution summary: `assistant/strategies/evolution_summary.jsonl`
- Pending eval: `assistant/strategies/pending_eval.json`
- Reports: `assistant/strategies/reports/`
- Metadata: `assistant/strategies/metadata/*.json`

## evolution_summary.jsonl Format

One JSON object per line, one line per evaluated candidate:

```json
{"iteration": 1, "system": "example_strategy", "avg_val": 0.75, "axis": "A", "hypothesis": "...", "delta": +0.05, "outcome": "75.0% (+5.0)", "components": ["section-reorder", "failure-first"]}
```
