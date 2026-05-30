## Digest: External Research Turn 1/4 - Task-Type Diversity

### Technique 1: Diversity-Driven Experiment Generation
- **Source type**: Auto-workflow analysis
- **Impact**: high
- **Difficulty**: easy
- **Description**: The experiment system shows 0 experiments across all 5 task types (refactoring, bug-fix, performance, feature, validation) for principles-neopi5 target. Early-exploration stage means breadth > depth.
- **Application**: Generate first experiment in an underexplored category rather than default/uncategorized
- **Implementation sketch**: Pick either "refactoring" (extract functions, remove duplication) or "bug-fix" (edge cases, error handling gaps) as first hypothesis category

### Technique 2: Targeted Fixes Over Full Re-reads
- **Source type**: λ notation constraint
- **Impact**: medium
- **Difficulty**: easy
- **Description**: λ ¬thrash rule: read ≤2 files before writing next experiment; prefer targeted fix(specific) over re-read(all)
- **Application**: Reduces token waste and speeds up experiment cycle time
- **Implementation sketch**: When proposing next experiment, read max 2 source files, then immediately write the experiment

### Technique 3: Hypothesis Keyword Classification
- **Source type**: Auto-workflow system
- **Impact**: medium
- **Difficulty**: easy
- **Description**: `gptel-benchmark--detect-task-type` classifies experiments by hypothesis keywords. Matching keywords ensures experiment is counted in diversity stats.
- **Application**: Ensure first experiment hypothesis includes explicit keyword from: refactoring (extract/simplify/DRY), bug-fix (fix/error/handle), performance (optimize/cache/speed), validation (guard/nil-check), feature (add/implement)
- **Implementation sketch**: Write hypothesis like "Refactoring: extract duplicated X into helper function" instead of generic

### Summary for Directive
- **Top hypothesis**: Generate first refactoring experiment on principles-neopi5 with explicit task-type keyword in hypothesis
- **Target modules**: gptel-benchmark-principles.el
- **Expected improvement**: Seed diversity tracking (0→1 experiments), establish baseline for subsequent experiments