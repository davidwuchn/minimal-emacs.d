---
title: Dead Function Audit Methodology
date: 2026-05-16
symbol: 🔁
---

# Dead Function Audit Methodology

Systematic approach for finding and removing dead code in Emacs Lisp modules:

1. **Enumerate all defuns**: `rg '^\(defun ' lisp/ --glob '*.el' | awk -F: '{print $1, $2}'`
2. **Count references per function**: `rg -c 'function-name' lisp/ --glob '*.el'` — count of 1 means only the defun itself
3. **Cross-check tests**: `rg 'function-name' tests/` — any match means keep it
4. **Remove with precision**: Delete only the defun form (including docstring), not surrounding comments or section headers shared with other functions
5. **Verify**: `emacs --batch -L lisp/modules -l FILE` for each modified file, then run full test suite

Found 26 dead functions across two passes (8 + 18), removed 315+ lines total. Three functions initially flagged as dead had test references and were preserved: `gptel-auto-experiment-should-stop-p`, `gptel-auto-workflow-delete-worktree`, `gptel-auto-workflow--staging-branch-exists-p`.
