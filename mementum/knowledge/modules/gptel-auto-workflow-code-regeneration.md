---
title: Code Regeneration
status: active
category: auto-workflow
tags: [yc, auto-workflow, regeneration, model-upgrade, disposable-code, context-database]
related: [gptel-auto-workflow-context-database, gptel-auto-workflow-evolution, gptel-auto-workflow-disposable-tracker, gptel-tools-agent-experiment-core, gptel-auto-workflow-mementum]
---

# Code Regeneration

> Software as Consumable — regenerate modules from business context when better models become available. Uses context-database sidecar data to build richer prompts for model-upgrade regeneration.

## Purpose

Code regeneration enables the "Software as Consumable" principle: when better AI models become available, modules can be regenerated from their business context rather than manually refactored. It prepares context by querying the context database for historical experiment data (key decisions, learnings, constraints, common patterns), generates a prompt that preserves institutional knowledge, and either overrides the experiment prompt or executes a full regeneration experiment. The `identify-candidates` function scans the context database for modules with sufficient history but below-threshold improvement, flagging them as candidates for regeneration.

## Public Functions

| Function | Purpose |
|----------|---------|
| `gptel-auto-workflow-code-regeneration--prepare-context` | Query context database for module's historical data; return context plist with `:purpose`, `:key-decisions`, `:historical-learnings`, `:constraints`, `:model-stats` |
| `gptel-auto-workflow-code-regeneration--generate-prompt` | Build a regeneration prompt from context plist preserving institutional knowledge |
| `gptel-auto-workflow-code-regeneration--identify-candidates` | Scan context database for modules with sufficient history and below-threshold score improvement; return candidate list |
| `gptel-auto-workflow-code-regeneration--full-workflow` | Full workflow: prepare context, generate prompt, set `--experiment-prompt-override`; when `execute` is non-nil, delegates to `--execute` |
| `gptel-auto-workflow-code-regeneration--execute` | Run the regeneration experiment via `gptel-auto-experiment-run` with callback; write mementum memory on result |

## Key Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `gptel-auto-workflow-regeneration-min-score-delta` | `0.05` | Minimum score improvement delta to consider a regeneration candidate |
| `gptel-auto-workflow-regeneration-min-history-count` | `3` | Minimum historical experiments to identify a regeneration candidate |
| `gptel-auto-workflow--experiment-prompt-override` | `nil` | When non-nil, overrides the experiment prompt entirely; set by regeneration workflow, cleared after each experiment run |

## Integration Points

- **Context Database**: Primary data source — uses `context-db-summary-for-target`, `context-db-query` for historical experiment data.
- **Evolution Module**: Uses `gptel-auto-workflow--evolution-model-stats` (optional) for model performance context in prompts.
- **Experiment Core**: Calls `gptel-auto-experiment-run` with a callback to capture regeneration results. Sets `--experiment-prompt-override` as a hook point.
- **Monitoring Agent (deploy-regen)**: When `monitoring-attempt-regen-on-deploy` is enabled, the monitoring agent's auto-deploy path calls `--execute` to regenerate modules instead of just symbolic deployment.
- **Mementum**: Writes `✅` or `❌` memories for regeneration success/failure.
- **Disposable Tracker**: Related concept — tracks modules that are candidates for regeneration due to stagnant improvement.

## Test Coverage

No dedicated test file found. Tested implicitly through the monitoring agent's deploy-regen integration and `gptel-auto-experiment-run` callback.