---
title: Paren Depth Debugging Technique
date: 2026-06-04
symbol: 💡
---

When `check-parens` reports "Unmatched bracket" but you can't see it:

1. **Use parse-partial-sexp depth tracking** — write a tiny elisp script
   that prints depth per line. Find where depth goes wrong.

2. **Trace top-level boundaries** — find where depth 0->1 and 1->0
   transitions happen. If a form starts (0->1) but never ends (1->0),
   that's your unclosed form.

3. **Daemon vs batch discrepancy** — the daemon may have modified buffers
   not saved to disk. Always `(revert-buffer t t)` before trusting the
   daemon's view. The file ON DISK is the truth.

4. **Batch-mode paren check** — `emacs --batch -Q` with `parse-partial-sexp`
   is the definitive test. No packages loaded, no buffer tricks.

5. **Count parens from inside out** — at the suspect line, identify each
   close paren by which open paren it matches. Work from innermost to
   outermost. Missing close = unclosed form. Extra close = over-closed.
