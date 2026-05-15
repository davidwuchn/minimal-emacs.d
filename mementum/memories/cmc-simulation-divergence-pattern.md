# CMC Simulation Divergence Pattern

**Pattern:** Offline simulation functions diverge from live controller logic.

**Symptom:** Offline evaluation of controller configs produces inaccurate objective scores because the simulation uses different thresholds, defaults, or decision gates than the actual controller.

**Root Cause:** Simulation functions were written as simplified approximations rather than faithful mirrors of the controller. Specific divergences found:
- Missing `warm-up` and `min-complete` gates (simulation allows premature STOP)
- Hardcoded defaults that differ from canonical (`delta-slack` 0.01 vs 0.04, `trend-threshold` 0.05 vs 0.04)
- Wrong config keys (`trend-threshold` pulling `:branch-threshold`)
- Missing dual-key fallback chains (`:stop-threshold`/`:min-confidence-stop`, `:token-budget`/`:max-tokens-budget`)

**Fix:** Simulation must mirror `controller-decide-research-flow` exactly, including all gates, thresholds, and fallback chains. Add regression tests that validate simulation matches controller for specific trace scenarios.

**Generalization:** Whenever there are two code paths for the same decision (live + offline), systematically verify they're equivalent. The canonical source is always the live path.

**Canonical config key resolution:** `gptel-auto-workflow--controller-config-rule-signals` in `strategic-daemon-functions.el` is the single source of truth for default values and key aliases.
