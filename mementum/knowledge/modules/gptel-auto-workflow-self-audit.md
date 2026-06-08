---
title: Self Audit
status: active
category: auto-workflow
tags: [yc, auto-workflow, self-audit, meta, health-check, knowledge-gap, pricing, pipeline, byte-compile]
related: [gptel-auto-workflow-bare-path-diagnostic, gptel-auto-workflow-mementum, gptel-auto-workflow-ontology-predict]
---

# Self Audit

> Meta-level self-audit: detect and auto-fix system gaps. Finds what human reviewers would notice — backend cold-start, strategy cold-start, staging-merge bottlenecks, byte-compile health, knowledge graph gaps, and pricing freshness. Synthesizes system-health knowledge pages from recurring audit findings.

## Purpose

The self-audit module embodies the YC principle that "self-evolve and self-heal" must include META — auditing the system itself, not just the code it produces. It runs 6 checks: (1) byte-compile health of all auto-workflow modules, (2) backend cold-start (backends with 0 experiments in the cold-start window), (3) strategy cold-start (strategies with 0 evaluations), (4) staging-merge bottleneck (>50% of failures are staging-merge), (5) knowledge graph gaps (isolated nodes, low-confidence communities), and (6) pricing freshness (bailian-pricing.md vs gptel-backend-registry). When issues are found, it writes `audit-fix-*.md` memory files and a structured result file for pipeline auto-remediation. When ≥3 audit-fix memories exist, it synthesizes `system-health-patterns.md` knowledge page for prompt injection.

## Public Functions

| Function | Purpose |
|----------|---------|
| `gptel-auto-workflow-self-audit-run` | Run all 6 self-audit checks; return comprehensive findings plist |
| `gptel-auto-workflow-self-audit-execute` | Run audit, write memory if issues found, write structured result, synthesize system-health; return formatted report |
| `gptel-auto-workflow-self-audit-verify-recovery` | Compare before/after audit results to verify remediation effectiveness |
| `gptel-auto-workflow-self-audit-apply-pipeline-signals` | Read signal files from pipeline Step 0.5 and apply them to the daemon (force-try-backends, exploration-rate, grader-timeout, force-grader-backends) |
| `gptel-auto-workflow-self-audit--run-backend-check` | Audit backend cold-start; return `:used`, `:all`, `:cold` |
| `gptel-auto-workflow-self-audit--run-strategy-check` | Audit strategy cold-start; return evaluation stats |
| `gptel-auto-workflow-self-audit--run-merge-check` | Audit staging-merge bottleneck; return merge stats |
| `gptel-auto-workflow-self-audit--run-knowledge-gap-check` | Check unified graph for isolated nodes and low-confidence communities |
| `gptel-auto-workflow-self-audit--byte-compile-check` | Check that all auto-workflow modules byte-compile cleanly |
| `gptel-auto-workflow-self-audit--check-pricing-freshness` | Compare bailian-pricing.md against gptel-backend-registry for discrepancies |
| `gptel-auto-workflow-self-audit--compute-token-economics` | Compute token economics from experiment TSV data using real registry pricing |
| `gptel-auto-workflow-self-audit--format-report` | Format audit result as markdown for the digest |
| `gptel-auto-workflow-self-audit--write-memory` | Write `audit-fix-*.md` memory file when issues are found |
| `gptel-auto-workflow-self-audit--write-structured-result` | Write `var/tmp/self-audit-result.el` for pipeline self-heal consumption |
| `gptel-auto-workflow-self-audit--synthesize-system-health` | Aggregate ≥3 audit-fix memories into `system-health-patterns.md` knowledge page |

## Key Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `gptel-auto-workflow-self-audit-enabled` | `t` | Enable/disable self-audit checks during pipeline |
| `gptel-auto-workflow-self-audit-cold-start-window` | `7` | Days of history to scan for cold-start detection |
| `gptel-auto-workflow-self-audit-bottleneck-threshold` | `0.5` | Fraction threshold for staging-merge bottleneck detection |
| `gptel-auto-workflow--grader-timeout-override` | `nil` | Override for grader timeout in seconds (set by pipeline auto-fix) |
| `gptel-auto-workflow--force-grader-backends` | `nil` | List of backend names to force for grading (set by pipeline auto-fix) |

## Integration Points

- **Pipeline (Step 0.5)**: `--execute` is the pipeline entry point. Writes `var/tmp/self-audit-result.el` for `run-pipeline.sh` Step 0.5 auto-remediation.
- **Signal Files**: `--apply-pipeline-signals` bridges bash pipeline signals into the Emacs daemon via `var/tmp/force-try-backends.txt`, `var/tmp/exploration-rateOverride.txt`, `var/tmp/grader-timeoutOverride.txt`, and `var/tmp/force-grader-backends.txt`.
- **Unified Graph**: `--run-knowledge-gap-check` uses `gptel-auto-workflow--unified-graph-ensure` and `--unified-graph-communities` to detect isolated nodes and low-confidence communities.
- **Backend Registry**: `--check-pricing-freshness` compares `mementum/knowledge/bailian-pricing.md` against `gptel-backend-registry` for pricing discrepancies (20% tolerance for exchange rate).
- **Mementum**: Writes `audit-fix-*.md` memories and synthesizes `system-health-patterns.md` knowledge page from ≥3 audit runs.
- **Token Economics**: `--compute-token-economics` computes per-model cost breakdown from 24h of experiment TSV data.
- **Bare Path Diagnostic**: Related self-heal diagnostic; both are pre-experiment quality checks.

## Test Coverage

No dedicated test file found. Tested implicitly through pipeline execution and the `verify-recovery` before/after comparison.