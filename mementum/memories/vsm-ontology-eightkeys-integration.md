# VSM Ontology Eight-Key Integration (2026-05-22)

## Insight

Three isomorphic frameworks stack vertically: VSM (who) → Ontology (what) → Eight Keys (how well). All map to the same 5 Wu Xing elements.

## Architecture

```
S5 Water  → Researcher     → Agentic      → φ Vitality, ∃ Truth
S4 Fire   → AutoTTS        → Programming  → τ Wisdom
S3 Earth  → self-evolve    → Tool-calls   → π Synthesis, ∀ Vigilance
S2 Metal  → AutoGo         → NL           → fractal Clarity, μ Directness
S1 Wood   → auto-workflow  → All          → ε Purpose
```

## Key Finding

The frameworks had two parallel implementations that never connected:
- `benchmark-principles.el` (theoretical Eight Keys) — never called by workflow
- `evolution.el` (operational VSM) — reimplemented diagnostics independently

Wired them together via fboundp delegate: evolution's `--categorize-experiment-target` now delegates to ontology router's `--categorize-target`. Eight Keys scoring feeds into VSM health check.

## Root Zero-Score Loop

All subsystems judged by executor keep-rate → everything scored 0 → no champion crowned → no strategies promoted → no improvement. Fix: each subsystem optimized for its own Eight Key.
