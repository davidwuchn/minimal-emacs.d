## Error Module Pattern Consolidation (2026-06-03)

### Changes to gptel-tools-agent-error.el

**1. Fixed O(n²) performance in `gptel-auto-workflow--plist-delete-all`**
- Before: Used `append` in loop → O(n²) for each call
- After: Uses `push` + `nreverse` → O(n)
- Impact: Called in `rewrite-subagent-provider` for each backend rewrite

**2. Extracted shared error pattern constants**
- `gptel-auto-experiment--auth-error-pattern` - used by both `provider-auth-error-p` and `error-categories`
- `gptel-auto-experiment--rate-limit-overload-pattern` - used by `rate-limit-error-p` and `error-categories`
- `gptel-auto-experiment--timeout-pattern` - used by `shared-retryable-patterns` and `error-categories`

**3. Updated consumers to reference constants**
- `provider-auth-error-p` now delegates to `--auth-error-pattern`
- `rate-limit-error-p` concatenates `--rate-limit-overload-pattern`
- `error-categories` backquote list unquotes the constants

### Eight Keys Signals
- Clarity: explicit assumptions in docstrings, testable definitions
- π Synthesis: connects pattern detection with categorization via shared constants
- ∀ Vigilance: prevents pattern drift between detection and categorization

### Evidence
- Byte-compile clean (warnings only, no errors)
- 3 new defconst, 3 functions updated to reference them