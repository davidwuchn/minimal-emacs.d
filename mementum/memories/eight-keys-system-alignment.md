# Eight Keys System Alignment (2026-05-22)

## Insight

The Eight Keys framework maps each subsystem to its own success metric, breaking the zero-score feedback loop where everything was judged on executor keep-rate.

## Subsystem → Key → Correct Target

| System | Key | Bug Fixed | New Target |
|--------|-----|-----------|------------|
| AutoGo | μ Directness | Zero-champion deadlock: `--crown-champion` silently rejected 0% strategies, but gate thought it succeeded | Champion must beat baseline (18%), not absolute zero |
| meta-harness | ∀ Vigilance | No axis diversity enforcement; all proposals hit same axis A | Block 3 consecutive same-axis proposals |
| meta-harness | fractal Clarity | Axis definitions not testable | Check against known axes A-F |
| Researcher | ε Purpose | Scored on executor keep-rate (wrong metric) | Score on pattern actionability: count concrete techniques in findings |
| self-evolve | ∃ Truth | `(and nil (daemonp))` hard-disabled production timer | Removed nil; module loads and starts hourly evolution |
| self-evolve | τ Wisdom | `require` commented out | Re-enabled; evolution module is stable |

## Root Cause

All systems fed into same broken cycle: researcher finds patterns → injected into executor prompt → experiment scores 0 → AutoTTS sees bad data → AutoGo has no champion → meta-harness generates 0-score strategies → self-evolve plateaus. Decoupling metrics breaks the loop.

## Files Changed

- `gptel-auto-workflow-evolution.el` — AutoGo gate + baseline computation
- `gptel-tools-agent-strategy-evolver.el` — axis diversity checks
- `gptel-auto-workflow-research-benchmark.el` — pattern actionability scoring
- `gptel-auto-workflow-production.el` — re-enabled production timer
