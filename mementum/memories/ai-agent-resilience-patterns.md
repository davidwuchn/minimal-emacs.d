# AI Agent Resilience Patterns

## Core Insight
Agents achieve 60% single-run success → 25% across 8 consecutive runs **without resilience engineering**.

## Four Failure Domains with Recovery Contracts

| Domain | Cause | Recovery |
|--------|-------|----------|
| **Transient** | Network/timeout | Retry with `expt 2 n` backoff + random jitter |
| **Validation** | checkdoc/byte-compile fail | Re-prompt with *specific* lint errors |
| **State Loss** | Context overflow | Checkpoint/resume |
| **Structural** | API contract change | Mark stale, escalate to human |

**Critical:** "If you can't tell which domain a failure belongs to from the log line, your recovery code can't either."

## Self-Correction ≠ Blind Retry
Output validator raises typed error with specific failure reason → model re-runs with exact error context. Without the "why", it's a retry counter, not self-correction.

## Pipeline Enforcement
Stage order: `research → assess → spec → code`. No stage can skip its predecessor. Each mode gates valid strategies.

## Two-Tier Memory
- **First-order** λ[n]: observations about the work
- **Meta-order** λ(λ[n]): observations about the process

Auto-synthesize when ≥3 experiments share a failure mode → promote to knowledge page.

## Backend-Distributed Error Handling
Per-backend `cl-defmethod` for error extraction. Don't assume uniform error shape across LLM providers. Store `:detail` in experiment failure records.
