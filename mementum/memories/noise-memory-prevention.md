---
title: Prevent Noise Memory Creation
φ: 0.85
e: noise-memory-prevention
λ: when.creating.memory
Δ: 0.05
evidence: 1
---

💡 Memory files should only be created when there's actual insight, not for null results.

## Problem

Auto-benchmark system created 45 memory files with null results:
- improvement-cycle files: "Observed ZERO issues, applied ZERO improvements"
- evolve-skill files: "ZERO anti-patterns → ZERO improvements"

These violate `λ store(x). gate-2: effort > 1_attempt ∨ likely_recur`.

## Fix

Guard memory creation with actual insight check:

```elisp
;; Before (creates noise)
(gptel-benchmark-memory-create ...)

;; After (only when insight)
(when (or (> (length anti-patterns) 0) (> applied 0))
  (gptel-benchmark-memory-create ...))
```

## Files Changed

- `gptel-benchmark-auto-improve.el:277` — improvement-cycle
- `gptel-benchmark-integrate.el:160` — feed-forward-improvement
- `gptel-benchmark-memory.el` — added `gptel-benchmark-memory--noise-p` and `gptel-benchmark-memory-audit`
- `scripts/audit-mementum.sh` — CI audit script
- `.github/workflows/ci.yml` — added mementum audit step

## Defense Layers

1. **Creation Gate** — `gptel-benchmark-memory-create` rejects noise content
2. **CI Check** — `audit-mementum.sh` fails CI on noise/stale references
3. **Manual Audit** — `M-x gptel-benchmark-memory-audit`

## Pattern

Memory = insight, not log. Null results don't need memory.