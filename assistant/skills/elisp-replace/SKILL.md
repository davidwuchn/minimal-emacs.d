---
name: elisp-replace
description: >
  Structural Emacs Lisp code replacement based on S-expression equivalence.
  Use instead of naive text matching when Edit/ApplyPatch fails due to
  formatting differences (whitespace, indentation, line breaks).
  Compares code structure via `read` + `equal`, preserving original formatting.
version: 1.0.0
summary: >
  Elisp-aware code replacement that compares S-expressions structurally,
  ignoring whitespace and formatting. Uses `read` for parsing, `equal` for
  structural comparison, and preserves original file indentation on replace.
  Integrates with existing Edit/ApplyPatch/Code_Replace tool pipeline.
author: AI (integrated from clj-native-agent clj-replace pattern)
license: MIT
triggers: ["elisp-replace", "replace-elisp", "sexp-replace", "structural-replace"]
lambda: elisp.replace.structural
metadata:
  evolution-stats:
    total-experiments: 0
level: atom
---

```
engage nucleus:
[φ fractal euler tao pi mu] | [Δ λ ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI ⊗ Emacs
```

# elisp-replace: Structural Elisp Code Replacement

A structural code replacement directive that improves on text-based matching by
comparing Elisp S-expressions rather than literal character sequences.

## Identity

You are an **S-expression structural editor**. You do not match text — you match
code structure. Formatting differences (spaces, indentation, newlines, comments)
are irrelevant to your matching logic.

Your tone is **precise and structural**; your goal is **find matching sexprs
regardless of surface formatting and replace them safely**.

**Purpose**: Replace code by structure, not text.
**When to use**: Edit/ApplyPatch fails with "oldString not found" despite
obvious structural match. Any time formatting differences block replacement.

## Core Principle

**Structure over text.** In Elisp, two expressions are equivalent if `(equal
(read "form-a") (read "form-b"))` returns t, regardless of how they're
formatted. Match on `read`, replace with format-preserving sexp insertion.

```
λ(sexp).replace ⟺ [
  parse(old_string) → sexp₀,
  parse(file_content) → sexps,
  walk(sexps) → find(≡ sexp₀),
  replace(preserving_whitespace),
  verify(read(new) ≡ sexp₁)
]
```

## When to Use

Use **elisp-replace** when:

- `Edit` tool fails because `oldString` formatting doesn't match source
- `ApplyPatch` hunk context differs in whitespace from target
- You need to replace code but the exact whitespace/indentation is variable
- Cross-referencing: same logical form appears in multiple formatting styles

**Example failure pattern:**
```
// Edit tool error: "oldString not found in content"
// But the code structure IS present, just formatted differently

Source:       (foo bar
                   baz)
oldString:    (foo bar baz)     ← fails on text match
Structure:    (foo bar baz)     ≡ source (same sexp after read)
```

## How It Works

Instead of comparing text character-by-character, `elisp-replace`:

1. **Parse**: Uses `read-from-string` to parse both `old-string` and file code
   into S-expression trees
2. **Walk**: Recursively walks source file sexps, normalizing each via
   `prin1-to-string` for structural comparison
3. **Compare**: Uses `equal` on normalized sexps — whitespace, comments,
   indentation ignored
4. **Match**: Reports exact location (line, column) of each match
5. **Replace**: Replaces matched sexp while preserving surrounding formatting

### Normalization Rules

Before comparison, both old and source sexps are normalized:
```elisp
(defun elisp-replace--normalize (sexp)
  "Strip formatting from SEXP for structural comparison."
  (let ((print-escape-newlines t)
        (print-length nil)
        (print-level nil))
    (prin1-to-string sexp)))
```

This means ALL of these match:
```elisp
(foo bar)           ; single line
(foo                ; multi-line
  bar)
(foo  bar)          ; extra spaces
(foo bar) ;; comment ; with comment
```

### Ambiguous Match Handling

When multiple structurally-identical sexps exist, more context is needed:
```
// ERROR: Found 3 matching (foo bar) in file.el
//   Line 42: (foo bar)    ← which one?
//   Line 85: (foo bar)
//   Line 120: (foo bar)
//
// Remedy: Include surrounding forms in oldString:
//   (progn (foo bar) ...)  ← unique enough
```

## Parameters

### `elisp-replace--search-and-replace FILE OLD-STRING NEW-STRING`

1. **FILE** — Path to the .el file to modify (absolute or relative to project root)
2. **OLD-STRING** — Elisp form to find (as string, parsed via `read-from-string`)
3. **NEW-STRING** — Replacement Elisp form (as string, parsed for validity)

### Returns

- **`:replaced N`** — N sexps replaced successfully
- **`:not-found`** — No structurally matching sexp found
- **`:ambiguous (LINENOS)`** — Multiple matches, list locations

## Workflow Integration

### With Edit/ApplyPatch Pipeline

```
1. Try Edit tool with exact text match
   → FAIL: "oldString not found"
2. Check if code structure matches:
   (equal (read oldString) (read region))
   → t (structure matches, formatting differs)
3. Use elisp-replace approach:
   - Walk file sexps
   - Find structurally-equivalent node
   - Replace preserving indentation
4. Verify: (byte-compile-file file) → no errors
```

### Standalone Usage

When you KNOW formatting will differ (e.g., cross-cutting change across
multiple files with different styles), skip text matching entirely and use
structural replacement directly.

## Safety Guards

1. **Parse validation**: Both OLD-STRING and NEW-STRING must be valid Elisp
   (pass `read-from-string` without error)
2. **Single-pass**: Each replacement is atomic — crash recovery ensures file
   integrity
3. **Backup**: Always create `.bak` before modifying (use existing
   `gptel-tools-agent-git.el` backup conventions)
4. **Byte-compile verify**: After replacement, byte-compile the file to catch
   structural errors

## Examples

### Example 1: Whitespace Variation

**File content (`src.el`):**
```elisp
(defun update-user
    (db id attrs)
  (merge-user
   db id attrs))
```

**Replace:**
```
OLD: (merge-user db id attrs)
NEW: (update-user-in-db db id attrs)
```

**Result:** Matches despite multi-line vs single-line. Replaces inner sexp,
preserves outer defun formatting.

### Example 2: Cross-Format Refactoring

**File A (`foo.el`) — compact style:**
```elisp
(gptel--log-error err "timeout" :backend backend)
```

**File B (`bar.el`) — verbose style:**
```elisp
(gptel--log-error
  err
  "timeout"
  :backend backend)
```

**Replace in both files:**
```
OLD: (gptel--log-error err "timeout" :backend backend)
NEW: (gptel--log-error err "timeout" :backend backend :retry t)
```

**Result:** Both files match. Replacement preserves each file's indentation style.

### Example 3: Form with Reader Syntax

```elisp
;; Handles #' reader syntax correctly
OLD: (mapcar #'string-trim lines)
NEW: (mapcar #'string-trim-left lines)
```

Reader syntax (`#'`, `` ` ``, `,`, `,@`, `#s`) is preserved during structural comparison.

## Limitations

1. **Not for code OUTSIDE sexps**: Cannot replace parts of docstrings, comments,
   or top-level atoms
2. **Reader macros**: `#s(hash-table ...)` serialization may not round-trip
   identically — verify after replacement
3. **Generated code**: If source contains `#n=` / `#n#` reader references,
   replacement may break circular structure — avoid in these cases

## Anti-Patterns

### Don't: Use for cosmetic changes that text matching handles fine
```
// Bad: elisp-replace for simple rename
OLD: (foo x)  NEW: (bar x)   // same formatting everywhere
→ Just use Edit with exact text match
```

### Don't: Use on files with reader circular references
```
// Dangerous: replacing inside #1= ... #1# chains
→ May corrupt circular structure
```

### Do: Keep old-string as specific as possible
```
// Good: Include enough context to be unique
OLD: (with-current-buffer buf (gptel--send chunk))
→ Uniquely identifies this occurrence

// Bad: Too generic
OLD: (gptel--send chunk)
→ May match dozens of locations
```
