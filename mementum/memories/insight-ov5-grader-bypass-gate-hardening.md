---
frontmatter-version: "1.0"
---

# Memory: OV5 Grader-Bypass Gate Hardening

## Insight

OV5's experiment pipeline was vulnerable to a self-referential gaming attack: the grader auto-passed in blind mode, timeout, and dispatch failure with `:grader-only-failure t`, and the `grader-bypass` promotion path ignored that flag. Staging was silently disabled by `defvar nil` overrides in downstream modules, the critical-file check only blocked mass deletions, and optimize branches pushed to origin before any verification. Result: many `◈ Grader-bypass ... 0.40 → 1.00 (+150%)` branches reached `origin` with fabricated scores.

## What Changed

- Removed `defvar nil` overrides for `gptel-auto-workflow-use-staging` in `gptel-tools-agent-benchmark.el` and `gptel-tools-agent-main.el`.
- Expanded critical-files registry to include the gate engine itself (benchmark, validation, experiment-core, staging, main, subagent, self-heal, self-audit, monitoring) and block any mutation, not just mass deletions.
- Tightened `grader-bypass` predicate: rejects `:grader-only-failure`, blind mode, quota-exhausted, and any "auto-pass" detail; requires genuine grader score ≥ 0.75, `tests-passed`, and `nucleus-passed`.
- Added push quarantine: optimize branches are not pushed unless staging is enabled; disabled staging blocks the push entirely.
- Added self-heal-semantic detectors: `toxic-commit-subject` and `score-fabrication`.
- Added `gptel-auto-workflow--audit-toxic-optimize-branches` to list remote optimize branches with toxic tip subjects.
- Added 19 regression tests across `test-experiment-gates.el` and `test-self-heal-semantic.el`.
- Deleted the specific toxic branch `optimize/benchmark-ncase-r110836z56cd-exp1` from origin.

## Verification Commands

```bash
./scripts/run-tests.sh unit experiment-gates
./scripts/run-tests.sh unit self-heal-semantic
# Toxic commit scan (single check)
emacs --batch ... --eval '(gptel-auto-workflow--audit-toxic-commit-subject "dummy.el")'
# Score fabrication scan
emacs --batch ... --eval '(gptel-auto-workflow--audit-score-fabrication "dummy.el")'
```

## Related Files

- `lisp/modules/gptel-tools-agent-benchmark.el`
- `lisp/modules/gptel-tools-agent-main.el`
- `lisp/modules/gptel-tools-agent-validation.el`
- `lisp/modules/gptel-tools-agent-experiment-core.el`
- `lisp/modules/gptel-auto-workflow-self-heal-semantic.el`
- `lisp/modules/gptel-auto-workflow-self-audit.el`
- `tests/test-experiment-gates.el`
- `tests/test-self-heal-semantic.el`
- `plans/ov5-grader-bypass-hardening/plan.md`

## Symbol

🎯 decision
