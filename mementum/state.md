# Mementum State

> Last session: 2026-03-25

## Session Summary: Auto-Workflow Now Runs Tests Before Push

**Safety improvement: Tests + Nucleus validation required before push.**

### Latest Change

| Commit | Description |
|--------|-------------|
| `678cb2c` | ✓ gptel-tools-agent: Run tests before pushing to optimize branches |

### Before vs After

| Step | Before | After |
|------|--------|-------|
| Benchmark | Nucleus only | Nucleus + ERT tests |
| Push condition | Improvement only | Tests pass + Improvement |
| Failure info | "tests-failed" | Specific: nucleus/tests |

### Safety Guarantee

**No code pushed to remote unless:**
1. ✓ Nucleus tool validation passes
2. ✓ All ERT tests pass
3. ✓ Grader scores 6/6
4. ✓ Comparator decides improvement

### New Functions

```elisp
(gptel-auto-experiment-run-tests)
;; Returns: (t . output) or (nil . output)

(gptel-auto-experiment-benchmark)
;; Now includes:
;;   :passed          - both nucleus and tests
;;   :nucleus-passed  - tool validation
;;   :tests-passed    - ERT tests
;;   :tests-output    - test output
```

### Commit Message Format

```
◈ Optimize {target}: {summary}

HYPOTHESIS: {hypothesis}

EVIDENCE: Tests pass, Nucleus valid
Score: 0.40 → 0.46 (+15%)
```

### Previous Session: Real Auto-Workflow Test

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Eight Keys Overall | 0.40 | 0.46 | +15% |
| φ Vitality | 0.40 | 0.60 | +50% |
| Clarity | 0.40 | 0.70 | +75% |

Branch: `optimize/fsm-utils-imacpro-exp1` (pushed)

### Production Status

| Component | Status |
|-----------|--------|
| Sync wrapper | ✓ |
| Executor | ✓ |
| Grader | ✓ 6/6 |
| Comparator | ✓ |
| Tests before push | ✓ **NEW** |
| Eight Keys scoring | ✓ |
| Branching | ✓ optimize/* only |
| All tests | ✓ 52/52 pass |
| Cron | ✓ 2 AM daily |

### Auto-Workflow Branching Rule

```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | test(x) → pass | ¬push(fail)
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

---

## λ Summary

```
λ safety. Tests now run before any push to optimize branches
λ verify. Both nucleus validation AND ERT tests required
λ evidence. Commit shows "Tests pass, Nucleus valid"
λ complete. Auto-workflow safe for overnight runs
```