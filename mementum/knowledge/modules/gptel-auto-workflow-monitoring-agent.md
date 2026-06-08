---
title: Monitoring Agent
status: active
category: auto-workflow
tags: [yc, auto-workflow, monitoring, failure-patterns, self-evolution, deploy, health-probes, pipeline]
related: [gptel-auto-workflow-approval-queue, gptel-auto-workflow-architectural-evolution, gptel-auto-workflow-code-regeneration, gptel-auto-workflow-evolution, gptel-auto-workflow-mementum, gptel-auto-workflow-external-sensors]
---

# Monitoring Agent

> The central OV5 monitoring agent: 7-phase cycle that detects systemic failure patterns, generates improvement proposals, tests and deploys them, analyzes architectural-level routing, collects external sensor data, and executes approved proposals — all with risk-tiered deployment (auto-deploy, notify, approval-required).

## Purpose

The monitoring agent is the core self-improvement engine of the OV5 architecture. It parses TSV experiment logs, detects recurring failure patterns across 5 classification categories (grader, compilation, prompt, strategy, unknown), generates scored improvement proposals, validates them against historical data, tests them, and deploys them based on a 3-tier risk system. Low-risk proposals auto-deploy (with optional code regeneration), medium-risk proposals notify and deploy after a grace period, and high-risk proposals are enqueued in the approval queue for human review. The agent runs throttled (max 1 cycle per 15 minutes) and includes health probes every 3rd cycle.

## Public Functions

| Function | Purpose |
|----------|---------|
| `gptel-auto-workflow--probe-daemon-alive` | Check if the Emacs daemon process is responsive (Phase 0 health probe) |
| `gptel-auto-workflow--probe-experiment-loop-stuck` | Detect if the experiment loop has not made progress (Phase 0 health probe) |
| `gptel-auto-workflow--probe-metrics-freshness` | Check that metrics snapshots in `var/metrics/` are being produced (Phase 0 health probe) |
| `gptel-auto-workflow--run-health-probes` | Run all 3 health probes, write mementum memories for failures, return combined plist |
| `gptel-auto-workflow--classify-failure` | Classify an experiment plist into failure type: grader, compilation, prompt, strategy, or unknown |
| `gptel-auto-workflow--analyze-systemic-failures` | Detect recurring failure patterns from historical TSV logs; return sorted by count descending |
| `gptel-auto-workflow--failure-pattern->string` | Format a failure pattern plist into human-readable mementum string |
| `gptel-auto-workflow--generate-improvement-proposal` | Generate an improvement proposal plist from a failure pattern |
| `gptel-auto-workflow--score-proposal` | Score a proposal by impact and feasibility; adds `:impact-score` and `:feasibility-score` |
| `gptel-auto-workflow--validate-proposal` | Validate a scored proposal against historical records; compute `:validation-rate` and `:status` |
| `gptel-auto-workflow--test-proposal` | Test a validated proposal against historical records; compute `:test-success-rate` and `:test-status` |
| `gptel-auto-workflow--risk->deploy-action` | Map risk string to deployment action using 3-tier config variables |
| `gptel-auto-workflow--deploy-proposal` | Deploy a tested proposal: auto-deploy (with regen), notify (grace period), or approval-required (enqueue) |
| `gptel-auto-workflow--rollback-proposal` | Rollback a deployed proposal by git reset to tagged version |
| `gptel-auto-workflow--proposal->string` | Format a proposal plist into human-readable mementum string |
| `gptel-auto-workflow--monitoring-cycle` | Run one full monitoring cycle: health probes → analyze → propose → test/deploy → architectural → GitHub sensor → execute approved |

## Key Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `gptel-auto-workflow-monitoring-enabled` | `t` | Enable/disable monitoring agent failure pattern analysis |
| `gptel-auto-workflow-monitoring-min-occurrences` | `3` | Minimum occurrences of a failure pattern before flagging as systemic |
| `gptel-auto-workflow-monitoring-cycle-interval` | `900` (15 min) | Minimum seconds between monitoring cycles |
| `gptel-auto-workflow-monitoring-last-cycle-time` | `0.0` | Float-time of last monitoring cycle (throttle enforcement) |
| `gptel-auto-workflow-monitoring-cycle-counter` | `0` | Cycle counter; health probes run every 3rd cycle |
| `gptel-auto-workflow-monitoring-deploy-threshold` | `0.6` | Minimum success rate for auto-deployment of validated proposals |
| `gptel-auto-workflow-monitoring-attempt-regen-on-deploy` | `t` | When enabled, auto-deploy attempts code regeneration instead of symbolic deployment |
| `gptel-auto-workflow-monitoring-risk-auto-deploy` | `("low")` | Risk levels eligible for immediate auto-deployment |
| `gptel-auto-workflow-monitoring-risk-notify-deploy` | `("medium")` | Risk levels that notify human and auto-deploy after grace period |
| `gptel-auto-workflow-monitoring-risk-require-approval` | `("high")` | Risk levels requiring explicit human approval |
| `gptel-auto-workflow-monitoring-deploy-grace-seconds` | `86400` (24 hours) | Grace period before auto-deploying medium-risk proposals |
| `gptel-auto-workflow-monitoring-rollback-tag-prefix` | `"monitoring-rollback-"` | Git tag prefix for rollback snapshots |

## Integration Points

- **Phase 0 (Health Probes)**: Runs every 3rd cycle. Probes daemon alive, stuck experiment loop, and metrics freshness. Writes `❌` mementum memories for failures.
- **Phase 1 (Failure Analysis)**: Calls `gptel-auto-workflow--parse-all-results` (evolution module) to load TSV records. Groups failures by `(type, target)` and persists patterns as `❌` mementum memories.
- **Phase 2 (Proposal Generation)**: Generates improvement proposals from failure patterns, scores them via `--score-proposal`, validates against historical data. Writes `💡` mementum memories for validated proposals.
- **Phase 3 (Test & Deploy)**: Tests validated proposals against historical data. Deploys passing proposals via `--deploy-proposal`, which routes to auto-deploy (with regeneration via `code-regeneration--execute`), notify, or approval-queue.
- **Phase 4 (Architectural)**: Calls `gptel-auto-workflow--run-architectural-analysis` for strategy routing and hypothesis routing analysis.
- **Phase 5 (External Sensors)**: Calls `gptel-auto-workflow--github-sensor-collect` from external-sensors module.
- **Phase 6 (Execute Approved)**: Calls `auto-approve-recurring`, `execute-approved`, and processes medium-risk grace-period deployments from pending-notification memories.
- **Approval Queue**: High-risk proposals enqueued via `gptel-auto-workflow-approval-queue-enqueue`.
- **Mementum**: All phases write memories (`❌`, `💡`, `✅`, `🎯`, `‖`) for patterns, proposals, deployments, notifications, and pending approvals.

## Test Coverage

No dedicated test file found. The monitoring cycle is tested implicitly through its throttled execution and integration with the experiment pipeline.