---
name: auto-workflow-validation-pipeline
description: Pre-evaluation validation pipeline for auto-workflow experiments. Defines cheap checks that run before expensive grading.
version: 1.0
---

# Validation Pipeline

## Philosophy

Validate cheaply before evaluating expensively. Like Meta-Harness's import-check before benchmark.

**Order:** Syntax → Compile → Load → Tests → Grade

**Abort early** if any step fails. Don't run expensive steps on broken code.

## Validation Steps (in order)

### Step 1: Syntax Check (CHEAP)
- Verify balanced parentheses
- Check for invalid `cl-return-from` without `cl-block`
- Ensure no conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
- **Cost:** ~1 second
- **Abort if:** Syntax error, unbalanced parens, conflict markers

### Step 2: Byte-Compile Check (CHEAP)
- Run `emacs -Q --batch -f batch-byte-compile FILE`
- Check for compiler warnings/errors
- **Cost:** ~5 seconds
- **Abort if:** Byte-compile fails or produces errors (warnings OK)

### Step 3: Load Test (CHEAP)
- Run `emacs -Q --batch -l FILE`
- Verify file loads without runtime errors
- Check for void variables, undefined functions
- **Cost:** ~3 seconds
- **Abort if:** Load fails, void variables, missing requires

### Step 4: Defensive Code Check (CHEAP)
- Check git diff for removed defensive patterns
- Look for removed `or` fallbacks, `assoc` without defaults
- **Cost:** ~1 second
- **Abort if:** Defensive code removed without proof

### Step 5: Pattern Check (CHEAP)
- Check for dangerous patterns (hardcoded paths, dataset-specific code)
- Verify no anti-patterns from agent-behavior skill
- **Cost:** ~1 second
- **Abort if:** Anti-pattern detected

## Evaluation Steps (EXPENSIVE - only if validation passes)

### Step 6: Test Suite
- Run `./scripts/verify-nucleus.sh`
- Check test results against baseline
- **Cost:** ~30-300 seconds
- **Abort if:** Tests fail (unless baseline match)

### Step 7: Eight Keys Grading
- Score code quality, correctness, generality
- Compare against baseline
- **Cost:** ~60-120 seconds

## Tracking

Record validation results per experiment:
- Which step failed (if any)
- Time spent in validation vs evaluation
- Pass rate by exploration axis

Use this data to:
1. Identify common validation failures
2. Guide agent behavior (e.g. "80% of Axis B failures are byte-compile errors")
3. Optimize validation order

## Example Flow

```
Experiment 1: Axis A (Error Handling)
  ✓ Syntax (0.8s)
  ✓ Byte-compile (4.2s)
  ✓ Load (2.1s)
  ✓ Defensive check (0.5s)
  ✓ Pattern check (0.3s)
  → Tests (45s)
  → Grade (89s)
  Result: KEPT (score 8/9)

Experiment 2: Axis B (Performance)
  ✓ Syntax (0.9s)
  ✗ Byte-compile (3.1s) → ERROR: void function `fast-cache-get`
  Result: VALIDATION-FAILED (saved 132s by not running tests/grade)
```

## Meta-Harness Insight

Meta-Harness validates ALL candidates before benchmarking ANY. This means:
- If 3 candidates are proposed and 2 fail validation, only 1 runs expensive benchmark
- Total time: validate×3 + benchmark×1 = cheap + expensive
- Without validation: benchmark×3 = 3× expensive

Our current system validates one candidate at a time. Future improvement: batch validation.
