# Research Strategy: Template-Default

## Overview
65 experiments across 10 targets in `gptel-auto-workflow` and `gptel-benchmark` modules.

## Key Kept Hypotheses (by concern)

### Idempotency / Safety
- Add idempotency guard for re-adding advice + extract symmetric disable function
- Fix misleading message + directory existence validation (bug fix)

### Cache Performance
- Change `eq` → `equal` for project list cache validation in `gptel-auto-workflow--normalized-projects`
- Reorder: check cache BEFORE calling `ensure-buffer-tables`

### Robustness / Edge Cases
- Add `ignore-errors` around `file-attributes` for invalid project paths
- Add early guard for empty project lists
- Add nil-safety guard for buffer iteration
- Filter `not-applicable` entries before sorting in `gptel-benchmark-eight-keys-weakest`

### Code Clarity
- Replace `format-mode-line` with direct `mode-name` access + use `when` instead of `if`
- Extract buffer lookup into clear validation sequence with explicit nil guards

## Discarded Hypotheses
None explicitly listed (placeholder section).

## Quality Dimensions
- **φ Vitality**: Progressive improvement, adapts to discovery, handles edge cases
- **fractal Clarity**: Explicit assumptions, testable, removes unnecessary complexity