# Case-Fold-Sensitive Placeholder Filters

**Context:** `lisp/modules/gptel-auto-workflow-self-audit.el` - `gptel-auto-workflow-self-audit--check-defvar-override-defcustom`

**Bug:** The uppercase-placeholder cleanup used `string-match-p` on a symbol name without forcing `case-fold-search` off, so the filter could treat lowercase symbols like `some-var` as matches and drop real violations.

**Fix:** Bind `case-fold-search` to `nil` inside the predicate before matching `\`[A-Z_-]+\'`.

**Lesson:** When a regex is meant to separate symbol case, make case sensitivity explicit in the predicate. Relying on ambient search settings can create silent false negatives.

**Symbol:** 💡
