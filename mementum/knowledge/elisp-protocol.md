---
title: Elisp Protocol
status: active
category: protocol
tags: [elisp, emacs, dangerous-patterns, idioms]
related: []
instincts:
  cl-block-wrapper:
    φ: 0.85
    eight-keys:
      vitality: 0.80
      clarity: 0.90
      purpose: 0.85
      wisdom: 0.88
      synthesis: 0.75
      directness: 0.82
      truth: 0.95
      vigilance: 0.90
    evidence: 3
    last-tested: 2026-03-29
    last-updated: 2026-03-29
---

# Elisp Protocol

Dangerous patterns and idiomatic Elisp for safe code generation.

## Core Principle

**Validation-first development**. Elisp has subtle pitfalls that don't exist in other Lisps. Always byte-compile before committing.

```
λ(edit).write ⟺ [
  read_source(),
  edit(),
  byte_compile(),
  check_warnings(),
  commit()
]
```

## Dangerous Patterns

### cl-return-from Requires cl-block

**THE RULE**: `(cl-return-from name value)` requires `(cl-block name ...)` wrapper in the same function.

```
λ cl-return-from(x). cl-block(x) ∧ same_name(x) | runtime_error(x) ≢ compile_error(x)
```

WRONG:
```elisp
(defun my-func (x)
  (unless x
    (cl-return-from my-func nil))  ; ERROR at runtime!
  ...)
```

CORRECT:
```elisp
(defun my-func (x)
  (cl-block my-func
    (unless x
      (cl-return-from my-func nil))
    ...))
```

ALTERNATIVE:
```elisp
(defun my-func (x)
  (if x
      ...
    nil))  ; simpler, no cl-block needed
```

### Why This Matters

- **Runtime error, not compile-time** - Code passes byte-compile but fails at runtime
- **Validation catches it** - But only if validation runs the code
- **Common in early-exit patterns** - tempting to use for guard clauses

## Other Dangerous Patterns

| Pattern | Risk | Solution |
|---------|------|----------|
| `set-buffer` | Changes current buffer globally | Use `with-current-buffer` |
| `setq` on buffer-local | Affects all buffers with local value | Use `buffer-local-setq` or `setq-local` |
| `goto-char` without save | Cursor moves unexpectedly | Use `save-excursion` |
| `insert` without narrowing | Inserts in wrong place | Use `save-restriction` + `narrow-to-region` |
| `kill-buffer` without check | Kills wrong buffer | Check buffer name first |

## Idiomatic Patterns

### Buffer Safety

```elisp
(with-current-buffer buf
  (save-excursion
    (save-restriction
      (narrow-to-region start end)
      ...)))
```

### Conditional Return

```elisp
;; Prefer this over cl-return-from
(defun my-func (x)
  (cond
   ((null x) nil)
   ((< x 0) 'negative)
   (t (process x))))
```

### Property Lists

```elisp
;; Prefer plist-get over assoc for structured data
(plist-get props :key)  ; cleaner than (cdr (assoc 'key props))
```

## Verification Gates

- [ ] Byte-compile: `emacs --batch -f batch-byte-compile file.el`
- [ ] No warnings (or documented exceptions)
- [ ] If using cl-return-from: cl-block wrapper present
- [ ] Buffer operations: save-excursion/save-restriction used
- [ ] Tests pass (if available)

## Validation Command

```bash
emacs --batch -f batch-byte-compile file.el 2>&1 | grep -E "(Error|Warning)"
```

Clean output = no errors/warnings.