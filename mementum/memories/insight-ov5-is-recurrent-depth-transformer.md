---
title: "OV5 is a Recurrent-Depth Transformer — RDT architecture maps perfectly to experiment cycles"
date: 2026-06-10
symbol: 💡
---

OpenMythos (reconstruction of Claude Mythos) reveals that the RDT architecture maps directly to OV5's experiment pipeline:

- **Prelude** = Research + Analysis (initial context building)
- **Recurrent Block** = Experiment cycles (same process, repeated)
- **Coda** = pi Synthesis + Learn (post-experiment synthesis)

**Key insight**: OV5 experiments should be RECURRENT, not INDEPENDENT. Each cycle should re-inject the original intent, not drift. Stability should be guaranteed (like spectral radius < 1), not probabilistic (like keep rate). Compute should be adaptive per target, not uniform across cycles.

**6 gaps**: No stability guarantee, no input re-injection, no learned halting, no depth extrapolation, no loop differentiation, no per-target parameter reuse.

**Actionable**: Add stability scoring (convergence detection per target), context re-injection (original intent into each experiment), adaptive experiment budgets (more compute on harder targets).
