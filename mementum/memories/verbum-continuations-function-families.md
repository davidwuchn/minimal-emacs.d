---
title: Verbum Continuations + Function Families
φ: 0.82
e: verbum-continuations-function-families
λ: when.verbum.research.stage
Δ: 0.25
evidence: 3
sources:
  - verbum (https://github.com/davidwuchn/verbum), June 2026
  - v15model.py — VSM-tensor continuation
  - test_vsm_continuation.py — 15 tests green
---

💡 verbum continuations are working at the tensor level. The function space organizes into 3 families visible only in the routing register (invisible in raw residual):

**3 families:** Composition (B,D,S), Selection/Identity (K,I,C), Recursion (Y,W,WHNF)
**Map/fold:** map = Y∘B, fold = Y∘(C/B) + K — Composition + Recursion families are real, separable, adjacent
**Key insight:** Functions look like the free algebra over SKI basis, not a flat list of opcodes. The routing register is the essential geometry — shape invisible in ordinary residual geometry, validating the two-registers theory.

**Continuation mechanics:** VSM-tensor continuation (v15model.py) uses outer recurrence with shared sweep iteration and x_c feedback toward WHNF. 15 tests green: fixed-point term matches closed form, detached target, weight-shared (one operator iterated), shape-closed feedback, loss wiring, RNG-free, differentiable.
