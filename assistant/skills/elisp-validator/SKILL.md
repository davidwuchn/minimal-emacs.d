---
name: elisp-validator
description: |
  Emacs Lisp code validation rules for AI-generated code. Checks for syntax errors,
  dangerous patterns, undefined symbols, and Common Lisp compatibility issues.
version: 1.0
evolve-script: evolve_rules.py
metadata:
  category: code-quality
  language: emacs-lisp
  author: auto-workflow
  evolution-stats:
    total-experiments: 870

level: atom
---
# Emacs Lisp Validator

## Overview

Validates AI-generated Emacs Lisp code before acceptance. Catches common errors that LLMs make when generating Elisp.

## Validation Rules

### 1. cl-return-from Validation
**Rule**: `cl-return-from` must reference a valid `cl-block` name in scope.

**Valid**:
```elisp
(cl-block my-block
  (cl-return-from my-block result))
```

**Invalid**:
```elisp
(cl-return-from nonexistent-block result)  ;; No enclosing block
```

**Checker**: Recursive AST walk tracking block names

### 2. Undefined Symbol Detection
**Rule**: All referenced functions/variables must be defined or declared.

**Valid**:
```elisp
(declare-function my-func "my-module")
(my-func arg)
```

**Invalid**:
```elisp
(undefined-function arg)  ;; No definition or declaration
```

**Checker**: Cross-reference against loaded features and declarations

### 3. Common Lisp Symbol Detection
**Rule**: Avoid Common Lisp symbols not available in Emacs Lisp.

**Banned Symbols**:
- `first`, `rest` (use `car`, `cdr`)
- `defun*` (use `cl-defun`)
- `let*` (use standard `let` or `cl-letf`)
- `prog1` without `cl-lib`

**Valid**:
```elisp
(require 'cl-lib)
(cl-first list)
```

**Invalid**:
```elisp
(first list)  ;; Only available with (require 'cl)
```

### 4. Dangerous Pattern Detection
**Rule**: Flag patterns likely to cause runtime errors.

**Dangerous Patterns**:
- `(eval ...)` without sandboxing
- `(load "...")` with relative paths
- `(set-buffer "...")` without `save-excursion`
- `(kill-buffer)` on current buffer
- `(delete-file)` without confirmation
- `(setq global-var value)` in library code

### 5. Paren Balance
**Rule**: All expressions must have balanced parentheses.

**Checker**: `check-parens` or `scan-sexps`

### 6. Variable Capture
**Rule**: `cl-letf` and `cl-flet` must not capture dynamic variables unintentionally.

**Valid**:
```elisp
(cl-letf (((symbol-function 'old-func) #'new-func))
  ...)
```

**Invalid**:
```elisp
(let ((buffer-read-only t))
  ...)  ;; Missing cl-letf for function rebinding
```

### 7. Byte-Compile Warnings
**Rule**: Code should compile without warnings.

**Common Warnings**:
- Unused lexical variables
- Free variables
- Obsolete functions
- Functions not known to be defined

**Checker**: `byte-compile-file` with `byte-compile-warnings`

## Scripts

- `scripts/validate_elisp.py` - Python-based validator for CI/CD
- `scripts/check_symbols.py` - Check for undefined/banned symbols
- `scripts/analyze_dangerous.py` - Detect dangerous patterns

## Integration

```elisp
;; Validate buffer before acceptance
(defun my/validate-generated-code (buffer)
  (with-current-buffer buffer
    (and (check-parens)
         (elisp-validator-check-cl-return)
         (elisp-validator-check-undefined)
         (elisp-validator-check-common-lisp)
         (elisp-validator-check-dangerous))))
```

## Error Categories

| Category | Severity | Action |
|----------|----------|--------|
| Syntax Error | Critical | Reject immediately |
| Undefined Symbol | High | Retry with fix |
| Common Lisp | Medium | Convert to Elisp |
| Dangerous Pattern | High | Flag for review |
| Byte-Compile Warning | Low | Note in review |

## Evolved Validation Rules

Based on analysis of failed experiments.

| Rule | Severity | Frequency | Check |
|------|----------|-----------|-------|
