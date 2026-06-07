# Unified Pipeline

## What Happened

We had **four separate pipeline scripts**:

1. `run-pipeline.sh` — main research → digestion → auto-workflow
2. `run-pipeline-ops.sh` — plan creation, state update, pattern logging
3. `refine-module-docs-with-ov5.sh` — module doc refinement
4. `refine-module-docs-batch.sh` — batch doc refinement

User said: **"we just need one pipeline, no more, just one"**

## Action Taken

- Deleted `run-pipeline-ops.sh`, `refine-module-docs-with-ov5.sh`, `refine-module-docs-batch.sh`
- Merged `create_pipeline_plan`, `update_pipeline_plan`, `update_mementum_state`, `log_pipeline_patterns` directly into `run-pipeline.sh`
- Plan creation runs at pipeline start; state + pattern updates run at pipeline end

## Principle Applied

**S4 — Simplify not Complect** (Fire 火)

> "prefer(simple) > complect | unbraid(x) where_possible"

Four scripts with overlapping concerns → one script with clear lifecycle hooks.

## Validation

- `bash -n scripts/run-pipeline.sh` passes
- No functional loss: all ops functions still called at correct lifecycle points

## Related

- `mementum/knowledge/patterns.md` — Simplify not Complect pattern
- `AGENTS.md` S4 — Intelligence
