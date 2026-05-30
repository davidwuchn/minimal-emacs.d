# Task-Type Diversity Gap in Experiments

## Finding
Researcher analysis reveals zero experiments across all task types for current targets:
- Refactoring: 0
- Bug Fix: 0
- Performance: 0
- Feature Addition: 0
- Validation/Safety: 0

## Recommendation
The auto-workflow should diversify experiment generation across these types rather than focusing on a single category. The system is in early-exploration stage, so breadth is more valuable than depth.

## Actionable Types
1. **Refactoring**: Extract functions, remove duplication, improve naming
2. **Bug Fix**: Edge cases, error handling gaps, actual bugs
3. **Performance**: Hot path optimization, caching, complexity reduction
4. **Feature Addition**: New functionality or capabilities
5. **Validation/Safety**: Safety guards, type checking, boundary validation

## Constraint (from λ notation)
- Read ≤2 files before writing next experiment
- Prefer targeted fixes over full re-reads
- `cl-return-from` valid only inside matching `cl-block` with name match
