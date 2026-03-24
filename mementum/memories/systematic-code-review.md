# Systematic Code Review Strategy

## Discovery
Batch analysis across entire repo is more effective than single-file optimization. Categorizing issues by severity and fixing in order yields measurable improvements.

## Approach
1. **Scan entire codebase** with batch tools:
   - `emacs --batch -f batch-byte-compile` for warnings/errors
   - `grep` for duplicate definitions
   - Count issues by category

2. **Categorize by severity**:
   - Critical: duplicate functions (runtime errors)
   - High: unused variables, free variables
   - Medium: docstring width, wrong quotes
   - Low: missing declare-function

3. **Fix in order**: Critical → High → Medium → Low

4. **Verify incrementally**: Run byte-compile after each category

## Tools Used
```bash
# Find all warnings
emacs --batch --eval "(setq byte-compile-error-on-warn nil)" \
  -f batch-byte-compile lisp/modules/*.el 2>&1 | grep Warning

# Find duplicate functions
grep -rh "(defun " lisp/ | sed 's/(defun \([^ ]*\).*/\1/' | \
  sort | uniq -c | sort -rn | head

# Find docstring width issues
emacs --batch -f batch-byte-compile *.el 2>&1 | \
  grep "docstring wider than 80"
```

## Results
- Found 5 categories of issues
- Fixed 22 total issues across 6 files
- Reduced warnings from ~20 to 1 (false positive)

## Key Insight
Broad exploration → categorize → prioritize → fix systematically is more effective than narrow focus on one file or one strategy.

---
*Learned: 2026-03-24*