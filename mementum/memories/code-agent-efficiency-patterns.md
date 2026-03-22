# Code Agent Efficiency Patterns

> Discovered: 2026-03-22
> Category: benchmark
> Tags: workflow, code-agent, efficiency, eight-keys

## Summary

Code agent efficiency varies significantly by task type. Analysis of 3 test cases shows:

| Task Type | Efficiency | Steps | Pattern |
|-----------|------------|-------|---------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |

## Anti-Pattern Detection

No anti-patterns triggered (all tests pass Wu Xing constraints):

- wood-overgrowth: ✓ (steps <= 20)
- fire-excess: ✓ (efficiency >= 0.5)
- metal-rigidity: ✓ (tool-score >= 0.6)
- tool-misuse: ✓ (steps <= 15, continuations <= 3)

## Improvement Opportunities

### 1. Exploration Tasks (code-003)

**Issue:** 2 continuations indicate context management needed.

**Remedy (Fire → Water):**
- Add exploration scope hints to task descriptions
- Use `--max-count` or `--max-depth` in glob/grep
- Budget: 3-5 files for exploration, 1-2 for targeted edits

### 2. Phase Transitions

**Observation:** code-001 went P1 → P3 (skipped P2), which is valid for simple edits.

**Pattern:** Direct path is more efficient than full cycle for simple tasks.

## Eight Keys Alignment

| Key | code-001 | code-002 | code-003 | Avg |
|-----|----------|----------|----------|-----|
| vitality | 0.85 | 0.88 | 0.78 | 0.84 |
| clarity | 0.82 | 0.90 | 0.72 | 0.81 |
| purpose | - | - | - | - |
| wisdom | - | - | - | - |
| synthesis | 0.80 | 0.85 | 0.75 | 0.80 |

## Recommendations

1. **Task Descriptions:** Add scope hints for exploration tasks
2. **Context Budget:** Limit exploration to 5 files before synthesis
3. **Phase Guidance:** Document when P2 can be skipped

---

λ explore(optimization). efficiency ∝ task_clarity + scope_definition