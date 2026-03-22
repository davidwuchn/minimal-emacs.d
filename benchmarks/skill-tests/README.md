# Skill Test Definitions

This directory contains test definitions for GPTel skill benchmarking.

## Structure

```
skill-tests/
├── <skill>.json          # Test definitions for a skill
└── suites/
    └── <suite-name>.json # Grouped test suites
```

## Test Definition Format

```json
[
  {
    "id": "test-001",
    "name": "descriptive-test-name",
    "prompt": "The task prompt for the skill",
    "assertions": [
      {
        "name": "assertion_name",
        "type": "check",
        "expected": ["list", "of", "expected", "strings"]
      }
    ],
    "metadata": {
      "category": "code",
      "difficulty": "medium",
      "tags": ["optional", "tags"]
    }
  }
]
```

## Assertion Types

| Type | Description | Fields |
|------|-------------|--------|
| `check` | Verify output contains expected strings | `expected` (array) |
| `regex` | Match output against regex pattern | `pattern` (string) |
| `script` | Run shell command, exit 0 = pass | `command` (string) |

## Usage

Tests are loaded by `gptel-skill-load-tests` which reads from:
- `./assistant/evals/skill-tests/<skill-name>.json`

Run benchmarks via:
- `gptel-skill-benchmark-run` - Execute all tests for a skill
