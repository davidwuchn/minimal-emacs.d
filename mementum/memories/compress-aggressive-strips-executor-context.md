## compress-aggressive Strips Executor Context (bug)

In `strategy-experiment-velocity-context.el`, `compress-aggressive` keeps only sections matching `("Task" "Code under analysis" "Failure patterns" "Guidance")`. This strips:
- Previous experiment results (so executor can't learn from failures)
- Analysis section (why the file needs improvement)
- Pattern history (what patterns have been tried)
- Evidence/grading data

**Result**: Executor receives a skeleton prompt with no directional guidance → produces generic/redundant changes → tool-error or discarded.

**Fix options**:
1. Add `"Previous results"` and `"Analysis"` to keep-sections
2. Change stage mapping: early-exploration → 'moderate' not 'aggressive' (the stage where we need *more* context, not less)
3. Add keep-rate awareness: if 0% kept after N experiments, upgrade to moderate compression

The hypothesis was that aggressive compression helps exploration. Evidence shows it starves the executor. This is testable: compare keep-rate with moderate vs aggressive in early stage.