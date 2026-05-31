# GPTel Auto Workflow Research Strategy

## Strategy: template-default

## Experiments: 84 across targets
- test
- gptel-benchmark-subagent.el
- gptel-tools-agent-error.el
- gptel-benchmark-comparator.el
- gptel-tools-agent-prompt-build.el
- gptel-auto-workflow-strategic.el
- gptel-auto-workflow-projects.el

## Kept Hypothesis
- **Improving `gptel-auto-workflow-list-project-buffers`** - This function lists all project buffers tracked in `gptel-auto-workflow--project-buffers` hashmap, showing root path -> buffer name and live/dead status.

## Discarded Hypotheses
- None documented

## Context
The function `gptel-auto-workflow-list-project-buffers` is defined in `gptel-auto-workflow-projects.el` around line 800. It iterates over a hashmap and formats buffer information for display. This is part of a multi-project researcher support system for gptel-agent.
