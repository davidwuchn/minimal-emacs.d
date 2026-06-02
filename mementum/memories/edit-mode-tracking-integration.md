# Edit-Mode Tracking Integration

## What
Integrated `gptel-tools-edit--mode-used` into experiment logging so we can measure which edit mode (hashline/patch/string) succeeds per experiment.

## Why
The Harness Problem showed edit tool choice matters more than model. We need data to validate hashline improvements in production.

## Changes
1. `gptel-tools-agent-experiment-core.el` — Added `:edit-mode` to experiment result plist at both success and failure paths
2. `gptel-tools-agent-prompt-build.el` — Added TSV column for `:edit-mode` (last column)

## Data Flow
```
gptel-tools-edit.el sets gptel-tools-edit--mode-used
    │
    ▼
gptel-tools-agent-experiment-core.el captures it in result plist
    │
    ▼
gptel-auto-experiment-log-tsv writes it to results.tsv
```

## Values
- `hashline` — Content-addressed line editing succeeded
- `patch` — Unified diff patch succeeded
- `string` — Exact string replacement succeeded
- `none` — No edit performed (or variable not set)

## Verification
- Hashline tests: 15/15 pass (unchanged)
- TSV format: added 29th column

## Next Steps
1. Run experiments and collect edit-mode distribution data
2. Compare hashline vs string vs patch success rates per backend
3. Use data to tune edit mode preference per model

## Related
- `mementum/memories/hashline-edit-tool-implementation.md`
- `mementum/memories/harness-problem-edit-tool-critical.md`
