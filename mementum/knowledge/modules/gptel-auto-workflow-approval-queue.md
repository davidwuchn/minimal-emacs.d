---
title: Approval Queue
status: active
category: auto-workflow
tags: [yc, auto-workflow, approval, human-in-the-loop, deploy, risk-management]
related: [gptel-auto-workflow-monitoring-agent, gptel-auto-workflow-mementum]
---

# Approval Queue

> Human approval gate for high-risk OV5 proposals. Persists proposals as .sexp files, supports interactive review/approve/reject, 7-day auto-expiry, and recurring-proposal deduplication.

## Purpose

The approval queue closes the last gap in the OV5 self-improving loop by providing a human-in-the-loop gate for high-risk proposals. When the monitoring agent's `--deploy-proposal` determines a proposal requires approval (risk level "high"), it is enqueued here instead of auto-deployed. The queue persists proposals as `.sexp` files under `var/approval-queue/pending/`, supports interactive review via `*Approval Queue*` buffer, and archives decisions to `var/approval-queue/decisions/`. Proposals expire after 7 days by default. A recurring-proposal auto-approval mechanism handles duplicate proposals when the same component+target pair exceeds a configurable threshold, closing the loop for patterns that keep re-emerging without human intervention.

## Public Functions

| Function | Purpose |
|----------|---------|
| `gptel-auto-workflow-approval-queue-enqueue` | Persist a tested proposal as a pending .sexp entry; deduplicates by component+target |
| `gptel-auto-workflow-approval-queue-list` | Return sorted list of pending entries (prunes expired first unless `include-expired` is set) |
| `gptel-auto-workflow-approval-queue-review` | Display pending proposals in `*Approval Queue*` buffer for interactive review |
| `gptel-auto-workflow-approval-queue-approve` | Approve a proposal by ID, moving it from pending to decisions with `:decision-by "human"` |
| `gptel-auto-workflow-approval-queue-reject` | Reject a proposal by ID, moving it to decisions with `:status "rejected"` |
| `gptel-auto-workflow-approval-queue-prune-expired` | Move expired proposals (past `:expires-at`) to decisions directory; returns count pruned |
| `gptel-auto-workflow-approval-queue-auto-approve-recurring` | Auto-approve oldest when duplicates exceed `auto-approve-threshold`; reject rest |
| `gptel-auto-workflow-approval-queue-dedup` | Collapse duplicate pending proposals, keeping only the newest per target |
| `gptel-auto-workflow-approval-queue-pending-p` | Return non-nil if there are pending (non-expired) proposals |
| `gptel-auto-workflow-approval-queue-summary` | Return summary plist with `:pending`, `:expired`, `:oldest-created-at` |
| `gptel-auto-workflow-approval-queue-execute-approved` | Process all approved-but-undeployed proposals: create rollback tag, write mementum, mark deployed |
| `gptel-auto-workflow-approval-queue-prioritize-targets` | Inject approved-proposal targets into priority list with 0.5 bonus |
| `gptel-auto-workflow-approval-queue-persist-priorities` | Write approved-proposal priorities to `var/tmp/approval-priorities.el` for next cycle |

## Key Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `gptel-auto-workflow-approval-queue-expiry-seconds` | `(* 7 24 60 60)` (7 days) | Seconds before a pending proposal is auto-expired |
| `gptel-auto-workflow-approval-queue-dir` | `"var/approval-queue"` | Base directory for queue (contains `pending/` and `decisions/` subdirs) |
| `gptel-auto-workflow-approval-queue-auto-approve-threshold` | `3` | Number of duplicate pending proposals before auto-approving the oldest |
| `gptel-auto-workflow-approval-queue-priority-file` | `"var/tmp/approval-priorities.el"` | File where approved-proposal priorities are written for next experiment cycle |

## Integration Points

- **Monitoring Agent (Phase 3 deploy)**: When `--deploy-proposal` determines `deploy-action` is `"approval-required"`, it calls `approval-queue-enqueue` to persist the high-risk proposal.
- **Monitoring Agent (Phase 6)**: Calls `auto-approve-recurring` to handle duplicate proposals, then `execute-approved` to deploy all approved-but-undeployed proposals.
- **Mementum**: `execute-approved` writes `✅` memories for deployed proposals and creates git rollback tags via `--git-cmd`.
- **Prioritization**: `prioritize-targets` feeds approved proposal targets into the next experiment cycle's priority file, biasing target selection toward human-approved changes.

## Test Coverage

No dedicated test file found. Tested implicitly through the monitoring agent's Phase 3/6 deployment pipeline.