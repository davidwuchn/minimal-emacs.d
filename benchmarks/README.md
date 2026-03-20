# Skill Evaluation Test Cases

This directory contains evaluation test cases for benchmarking skills.

## Directory Structure

```
evals/
├── README.md           # This file
├── eval-<name>.json    # Individual test case
└── suites/             # Grouped test suites
    └── suite-<name>.json
```

## Eval Format

Each eval is a JSON file with:

```json
{
  "id": "eval-001",
  "name": "descriptive-name",
  "prompt": "The task prompt for the skill",
  "assertions": [
    {
      "name": "assertion_name",
      "type": "check|script|llm",
      "expected": ["list", "of", "expected"],
      "command": "optional script command",
      "criteria": "optional LLM criteria"
    }
  ],
  "metadata": {
    "category": "code|research|analysis",
    "difficulty": "easy|medium|hard",
    "tags": ["optional", "tags"]
  }
}
```

## Assertion Types

| Type | Description | Fields |
|------|-------------|--------|
| `check` | Verify output contains expected elements | `expected` |
| `script` | Run shell command, exit 0 = pass | `command` |
| `llm` | LLM judgment based on criteria | `criteria` |

## Usage

Run benchmark via Bash:

```bash
# Run single eval
python scripts/run_eval.py --skill my-skill --eval evals/eval-001.json

# Run all evals in suite
python scripts/run_eval.py --skill my-skill --suite evals/suites/suite-code.json

# Run with baseline comparison
python scripts/run_eval.py --skill my-skill --baseline baseline-skill --eval evals/eval-001.json
```

Invoke from gptel:

```
RunAgent("grader", "grade eval-001", "Evaluate outputs from evals/eval-001.json")
RunAgent("analyzer", "analyze results", "Analyze benchmark.json for patterns")
RunAgent("comparator", "compare v1 vs v2", "Compare output_a/ vs output_b/")
```

## Example Eval

See `eval-example.json` for a complete example.