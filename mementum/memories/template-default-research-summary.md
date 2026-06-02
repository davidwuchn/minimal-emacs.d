# Template-Default Research Strategy

## Overview
65 experiments across 10 targets focusing on φ Vitality and fractal Clarity.

## Key Themes

### 1. Idempotency Guards
Add guards to prevent re-adding active advice + extract symmetric disable functions.

### 2. Cache Validation Fix (`gptel-auto-workflow--normalized-projects`)
- **Problem**: Uses `eq` (identity) instead of `equal` (content) for project list comparison
- **Fix**: Change to `equal`, check cache before `ensure-buffer-tables`
- **Rationale**: Prevents unnecessary invalidation on reassignment

### 3. Buffer Lookup Extraction
Extract into validation sequence with explicit nil guards. Improves robustness for missing FSM state.

### 4. Edge Case Handling
- `ignore-errors` around `file-attributes` for invalid paths
- Early guard for empty project lists

### 5. Mode-line Simplification
Replace `format-mode-line` with direct `mode-name` access + `when` vs `if`.

### 6. Runtime Crash Prevention (`gptel-benchmark-eight-keys-weakest`)
Filter `not-applicable` entries before sorting to prevent `(< 'not-applicable <number>)` errors.

## Priority Targets
1. `gptel-auto-workflow-projects.el` - cache validation, buffer lookup
2. `gptel-tools-agent-error.el` - idempotency guards
3. `gptel-benchmark-subagent.el` - runtime crash fix

## Quality Properties
- **φ Vitality**: Progressive improvement, adapts to discovery/edge cases
- **fractal Clarity**: Explicit assumptions, testable, removes unnecessary complexity
