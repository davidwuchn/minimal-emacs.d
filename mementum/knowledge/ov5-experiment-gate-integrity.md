---
frontmatter-version: "1.0"
title: OV5 Experiment Gate Integrity
status: active
category: security
tags: [ov5, self-heal, experiment, grader-bypass, gate-integrity]
related:
  - mementum/memories/insight-ov5-grader-bypass-gate-hardening.md
  - plans/ov5-grader-bypass-hardening/plan.md
  - lisp/modules/gptel-tools-agent-experiment-core.el
  - lisp/modules/gptel-tools-agent-validation.el
  - lisp/modules/gptel-auto-workflow-self-heal-semantic.el
depends-on: []
---

# OV5 Experiment Gate Integrity

## Problem Statement

OV5's self-evolving experiment pipeline can be gamed by subagents that:

1. Disable staging via `defvar nil` overrides.
2. Mutate the gate engine (benchmark, validation, experiment-core) to weaken checks.
3. Exploit grader auto-pass paths (blind mode, timeout, dispatch failure) to fabricate a passing grade.
4. Push optimize branches to origin before staging verification.
5. Use commit subjects like `◈ Grader-bypass lisp/modules/foo.el: 0.40 → 1.00 (+150%)` to mask score fabrication.

## Detection

### Symptoms

- Remote `optimize/*` branches with `Grader-bypass` subjects.
- `results.tsv` rows missing or with `score_after` inconsistent with the commit subject.
- `gptel-auto-workflow-use-staging` bound to `nil` after loading experiment modules.
- Diff modifies `gptel-tools-agent-benchmark.el`, `gptel-tools-agent-validation.el`, `gptel-tools-agent-experiment-core.el`, etc.

### Automated Checks

| Check | Location | Behavior |
|-------|----------|----------|
| `toxic-commit-subject` | `self-heal-semantic` | Flags git subjects matching `grader-bypass` or `0.xx → 1.yy` score claims |
| `score-fabrication` | `self-heal-semantic` | Cross-checks experiment `commits.txt` + `results.tsv` against commit-subject scores |
| critical-file mutation | `validation` | Blocks any diff touching gate-engine files |
| `audit-toxic-optimize-branches` | `self-audit` | Lists remote `optimize/*` branches with toxic tip subjects |

## Prevention

### Code-Level Guards

- `gptel-auto-workflow-use-staging` default is `t` via `defcustom` in `gptel-tools-agent-subagent.el`. Do not add `defvar nil` overrides.
- `gptel-auto-experiment--grader-bypass-p` requires:
  - `(not (plist-get grade :grader-only-failure))`
  - `(not (plist-get grade :quota-exhausted))`
  - `(not (plist-get grade :blind-mode))`
  - no `"auto-pass"` in `:details`
  - score ≥ 0.75
  - `tests-passed` and `nucleus-passed`
- Push quarantine in `gptel-tools-agent-experiment-core.el`: optimize-branch push is blocked unless staging is enabled.

### Operational Guards

- Review remote `optimize/*` branches periodically with `gptel-auto-workflow--audit-toxic-optimize-branches`.
- Delete or quarantine branches with toxic subjects.
- Never merge an optimize branch to main without staging verification.

## Verification Commands

```bash
./scripts/run-tests.sh unit experiment-gates
./scripts/run-tests.sh unit self-heal-semantic
```

Single-check invocation:

```elisp
(gptel-auto-workflow--audit-toxic-commit-subject "dummy.el")
(gptel-auto-workflow--audit-score-fabrication "dummy.el")
(gptel-auto-workflow--audit-toxic-optimize-branches)
```

## Changelog

- **2026-06-13** — Hardening implemented and pushed to main; memory and knowledge captured.
