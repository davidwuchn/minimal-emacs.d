# Silent file truncation: missing `)` in defun swallows the rest of the file

## The pattern

When an Emacs Lisp source file has a missing close-paren `)` somewhere
in the middle, Emacs does NOT report an error.  Instead, the first
defun that contains the unbalanced paren EXTENDS to the end of the
file, swallowing every subsequent defun, defvar, and defcustom.

The file is "loaded" successfully.  `provide` runs.  But every
function defined AFTER the unbalanced paren is silently NOT defined.

## Example

In `gptel-auto-workflow-production.el` (commit `6ebccec0e`), the
`gptel-auto-workflow--pending-decisions-p` defun had a missing `)`
after the auto-expire block was added inside it.  The result:

- L515: `(defun gptel-auto-workflow--pending-decisions-p ()` — open
- L1286: stray `)` — the only close
- File provided and loaded
- 21+ functions (--update-dashboard, --innovation-queue-*, etc.) NOT bound

## How to detect

1. **Count top-level forms** with `(while (re-search-forward "^(" nil t)
   (read (current-buffer)))`.  A truncated file has fewer forms than
   expected.
2. **List all fboundp symbols** for the feature.  Truncated files are
   missing the functions defined after the paren.
3. **`scan-lists` from each defun** to confirm it has a matching close
   within the same defun body.

## How to prevent

- **Always run `find . -name "*.elc" -delete` before testing** — stale
  byte-code shadows the broken source.  A `require` against a stale
  .elc reports the old (working) version, masking the bug.
- **Add a test that asserts all key public functions are fboundp**
  after loading the module.  See
  `tests/test-gptel-auto-workflow-production.el`
  (`test-production/all-key-functions-fboundp`).
- **Don't trust "the file loaded".**  Check that the functions you
  expect to be defined actually are.

## Related: the broken regex

In the same file, the `gptel-auto-workflow--innovation-queue-add`
function had a regex pattern with 33 blank lines inside a string
literal:

```
"| ID | Source | ... | Actual\nImpact\n\n\n\n\n\n\n...\n|\n|----|...|\n"
```

This pattern would only match files with EXACTLY 33 blank lines
between the header and the separator — a pattern no real markdown
table has.  The function silently failed to insert entries.

**Fix**: replace with `regexp-quote` of the actual header line, plus
the separator as part of the match (so the original separator is
replaced, not duplicated).

## Files affected

- `lisp/modules/gptel-auto-workflow-production.el` — missing `)` and
  broken regex, both fixed in this session.
- Pattern may exist in other auto-evolved files; check any module
  whose functions are not bound even though it "loads".
