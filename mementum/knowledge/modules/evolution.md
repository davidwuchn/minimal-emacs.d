# Evolution Module

## Purpose

Self-evolution engine using mementum as source of truth. Analyzes experiment history, detects patterns, and proposes improvements to the pipeline itself.

## Architecture

```
Git History ──┐
              ├──→ MEMENTUM ──→ Prompt Injection ──→ Experiments ──→ ...
Benchmark ────┘      ↑                                      │
                     └───────────────────────────────────────┘
```

## Key Functions

| Function | Purpose |
|---|---|
| `gptel-auto-workflow-evolution-run-cycle` | Run full evolution cycle |
| `gptel-auto-workflow--analyze-failure-patterns` | Detect systemic failures |
| `gptel-auto-workflow--propose-improvements` | Generate self-improvement proposals |
| `gptel-auto-workflow--evolution-scores` | Calculate evolution metrics |

## Configuration

```elisp
(defvar gptel-auto-workflow-evolution-interval 3600) ; 1 hour
```

## Integration Points

- **Mementum**: Reads experiment history from mementum/
- **Production**: Called periodically by production timer
- **Monitoring**: Failure patterns fed to monitoring agent
