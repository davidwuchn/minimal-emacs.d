# Skill Benchmark Execution Guide

## Overview

The benchmark system uses Eight Keys (φ, fractal, ε, τ, π, μ, ∃, ∀) for evaluation.
See `mementum/knowledge/nucleus-patterns.md` for the Eight Keys rubric.

## Pipeline Architecture

```
┌─────────────┐     ┌──────────┐     ┌───────────┐     ┌──────────┐
│  Generate   │ ──▶ │  Execute │ ──▶ │   Grade   │ ──▶ │ Analyze  │
│  (tests)    │     │ (prompts)│     │ (outputs) │     │ (trends) │
└─────────────┘     └──────────┘     └───────────┘     └──────────┘
```

### Subagent Roles

| Agent | Role | Function |
|-------|------|----------|
| `explorer` | Test Generation | Scans skill definitions, generates test cases |
| `researcher` | Test Execution | Executes prompts against skill, collects outputs |
| `grader` | Output Scoring | Grades outputs against expected/forbidden behaviors |
| `analyzer` | Pattern Detection | Identifies systematic failures, Eight Keys violations |
| `reviewer` | Eight Keys Scoring | Evaluates outputs against Eight Keys rubric |

## Quick Start

### Step 1: Generate Prompts

```bash
cd /Users/davidwu/.emacs.d
python3 scripts/benchmark_skill.py --skill clojure-expert --tests assistant/evals/skill-tests/clojure-expert.json
```

This creates `outputs/prompt_*.txt` files.

### Step 2: Execute Prompts

**Option A: Manual (via gptel)**
```
M-x gptel-send with prompt file contents
Save response to outputs/output_<id>.txt
```

**Option B: Batch via subagent**
```elisp
;; Run all prompts through researcher subagent
(dolist (file (directory-files "outputs" t "prompt_.*\\.txt"))
  (let ((prompt (with-temp-buffer (insert-file-contents file) (buffer-string)))
        (output-file (replace-regexp-in-string "prompt" "output" file)))
    ;; Send to AI and save to output-file
    ))
```

**Option C: Quick test with one prompt**
```bash
# View a prompt
cat outputs/prompt_clj-001.txt
```

### Step 3: Grade Outputs

```bash
# Re-run with outputs in place
python3 scripts/benchmark_skill.py --skill clojure-expert --tests assistant/evals/skill-tests/clojure-expert.json
```

## Benchmark Results

Results are saved to `outputs/benchmark.json`:

```json
{
  "skill": "clojure-expert",
  "version": "1.0.0",
  "summary": {
    "overall_grade": "B",
    "average_score": 82.5
  },
  "test_results": [
    {
      "test_id": "clj-001",
      "grade": "A",
      "expected_passed": ["Mentions REPL", "Uses idiomatic Clojure"],
      "expected_failed": [],
      "forbidden_violated": []
    }
  ]
}
```

## Improvement Workflow

1. **Run benchmark** → Get grades
2. **Analyze failures** → Check `expected_failed` and `forbidden_violated`
3. **Update skill** → Fix issues in SKILL.md
4. **Re-run benchmark** → Verify improvement

## Available Test Suites

| Skill | Test File | Tests |
|-------|-----------|-------|
| clojure-expert | `skill-tests/clojure-expert.json` | 5 |
| reddit | `skill-tests/reddit.json` | 5 |
| requesthunt | `skill-tests/requesthunt.json` | 5 |
| seo-geo | `skill-tests/seo-geo.json` | 5 |

## Adding New Tests

```json
{
  "id": "unique-id",
  "name": "test_name",
  "prompt": "What user says",
  "expected_behaviors": ["What should happen"],
  "forbidden_behaviors": ["What should NOT happen"],
  "grading_criteria": {
    "vitality": "Optional Eight Keys criteria"
  }
}
```

## Integration with CI

```yaml
# .github/workflows/skill-benchmark.yml
- name: Run Skill Benchmarks
  run: |
    python3 scripts/benchmark_skill.py --all-skills
    # Check if any skill scored below B
    python3 -c "
import json
with open('outputs/benchmark.json') as f:
    data = json.load(f)
if data['summary']['overall_grade'] in ['D', 'F']:
    exit(1)
"
```