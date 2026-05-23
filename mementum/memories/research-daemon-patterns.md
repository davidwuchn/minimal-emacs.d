## Research Daemon Integration Patterns

### Critical Rules
1. **Every experiment row requires a non-none research hash** — linking outcomes to research trace is mandatory
2. **Missing research file = pipeline defect** — do not treat as empty success
3. **Prefer structured research outputs**: `{source, technique, apply-to-us, verification}` fields
4. **Fail fast on daemon disappearance** — don't wait for global timeout at orchestration boundaries

### Observable Self-Evolution
Prioritize changes that make the feedback loop visible through:
- `results.tsv` metadata columns
- Research trace linkage
- Controller decision logs

### Quality Signal
Structured, machine-parseable outputs > unstructured text. This enables automated verification downstream.
