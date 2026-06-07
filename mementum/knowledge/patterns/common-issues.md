# Common Issues and Patterns

> **Synthesized from**: mementum analysis (>=3 sessions)
> **Auto-generated**: 2026-06-06
> **Updated**: 2026-06-06

---

## Pattern 1: Pi5 Auto-Evolves Files

**Frequency**: Every session
**Severity**: Low
**Description**: Pi5 automatically generates `research-insights-template-default.md` and `strategy-guidance.json` on every pipeline run.

**Resolution**:
```bash
# Use merge=theirs in .gitattributes
research-insights-template-default.md merge=theirs
strategy-guidance.json merge=theirs
```

**Prevention**:
- Never manually edit auto-evolved files
- On pull: `git checkout HEAD -- path` to discard local changes
- On conflict: Pi5 version wins

---

## Pattern 2: Python3 Regression

**Frequency**: 2 sessions
**Severity**: Medium
**Description**: Scripts revert to python3 after Pi5 commits, causing macOS compatibility issues.

**Resolution**:
```bash
# Replace python3 with jq for JSON parsing
jq -r '.key' file.json
# Instead of
python3 -c "import json; ..."
```

**Prevention**:
- Use `test-script-hygiene.el` to catch regressions
- Add jq dependency to README

---

## Pattern 3: Hardcoded Paths

**Frequency**: 1 session
**Severity**: Low
**Description**: Scripts contain machine-specific paths (e.g., `main-baseline-5036`).

**Resolution**:
```bash
# Use find glob instead of hardcoded paths
find var/tmp/experiments -path "*/mementum/knowledge/*.md" 2>/dev/null | head -1
```

**Prevention**:
- Use `test-script-hygiene.el` to catch hardcoded paths
- Prefer environment variables or config files

---

## Pattern 4: defvar at Top-Level

**Frequency**: 1 session
**Severity**: Low
**Description**: `defvar` at top-level calls functions that may not be defined at load time.

**Resolution**:
```elisp
;; Bad: defvar calls function at load time
(defvar var (undefined-function))

;; Good: lazy initialization
(defvar var nil)
(defun get-var ()
  (or var (setq var (undefined-function))))
```

**Prevention**:
- Use `fboundp` guards before calling functions in defvar
- Lazy initialization pattern

---

## Pattern 5: Nil Guard

**Frequency**: High (>=3 sessions)
**Severity**: Medium-High
**Description**: Elisp functions throw `wrong-type-argument` when passed nil.

**See Also**: [Nil Guard Pattern](nil-guard-pattern.md)

---

## Pattern 6: String Guard

**Frequency**: High (>=3 sessions)
**Severity**: Medium
**Description**: `string-suffix-p`, `string-match-p` throw `wrong-type-argument stringp nil`.

**See Also**: [String Guard Pattern](string-guard-pattern.md)

---

## Pattern 7: Worktree Safety

**Frequency**: High (>=3 sessions)
**Severity**: High
**Description**: Edit tools can leak into mayor checkout, contaminating the main branch.

**See Also**: [Worktree Safety Pattern](worktree-safety-pattern.md)

---

## Pattern 8: Workspace Boundary Violation

**Frequency**: High (>=3 sessions)
**Severity**: High
**Description**: Self-heal accessed `/Users/davidwu/lisp/modules` instead of `~/.emacs.d/lisp/modules`.

**See Also**: [Workspace Boundary Pattern](../workspace-boundary-violation.md)

---

## Auto-Detection

These patterns are auto-detected by `mementum-analyze` skill:
```bash
skill: mementum-analyze
# Scans sessions, counts occurrences, flags candidates
```

## Next Update

When >=3 new patterns detected -> create new knowledge page.
