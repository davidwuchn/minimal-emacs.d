# Research Strategy: Template-Default

## Core Pattern
- **Template**: Benchmark/Evolution strategy template for code quality improvement
- **Scale**: 2087 experiments across 60+ target files
- **Focus**: φ Vitality (error resilience) and fractal Clarity (explicit assumptions)

## Hypothesis Generation Pattern
1. **Scan target files** for code quality anti-patterns
2. **Identify weakest keys** (Vitality, Clarity at 40%)
3. **Generate hypothesis per anti-pattern** using template:
   - "Adding X validation to Y will prevent Z runtime errors, improving Vitality and Clarity"
4. **Keep/Discard based on**: Execution success, test pass, diagnostics clean

## Common Hypothesis Templates
- "Adding `(typep x)` validation will prevent runtime errors, improving Vitality/Clarity"
- "Fixing off-by-one error in loop will correct boundary case"
- "Extracting duplicate X into helper Y will improve Clarity by eliminating duplication"
- "Replacing deprecated `cl-flet` with `cl-letf` will ensure Emacs 28+ compatibility"

## Success Criteria
- All ERT tests pass
- Byte-compile clean (no warnings)
- Syntax validation passes
- Verification gates green

## Key Insight
The "template-default" strategy is about systematic code quality improvement through:
1. Explicit assumptions (validation guards)
2. Error resilience (nil guards, proper-list-p)
3. DRY principles (extracting helpers)
4. Type safety (proper-list-p vs listp, integerp checks)
