---
title: Pipeline Debugging Session Learnings (June 2026)
φ: 0.78
e: pipeline-debugging-june-2026
λ: when.pipeline.has.errors
Δ: 0.35
evidence: 4
sources:
  - Daemon Messages buffer (live inspection)
  - git history (255-defvar-fix, defcustom-override bug)
  - TDD tests (sanitize + void-defvar, 28 new)
---

💡 3 hours of live pipeline debugging. Key learnings:

**Bug 1: `*ERROR*: Unknown message:` in daemon logs (root cause: `my/gptel--sanitize-for-logging`)**
LLM output contains `%` and `&amp;` characters. Under concurrent writes to `*Messages*`, C-level `message_dolog` format-parser corrupts on `%` followed by non-format chars. `&` gets fragmented into `&_`, `&-`, `&(` artifacts. Fixed by escaping bare `%`→`%%` (preserving already-escaped `%%`) and `&`→`&&`. 4 TDD tests. Commit `5ec6da436`.

**Bug 2: Void defvars cause silent batch-mode crashes (98 found)**
`(defvar NAME)` without initial value = void, not nil. `boundp` returns nil. In batch mode where production.el isn't loaded, reading the variable crashes. A prior mass fix (255 defvar→nil, `9f91f7d9f`) was done but 98 new ones accumulated. New self-heal audit (check 11) detects them. Fixer is conservative: only adds nil when NO matching `defcustom` exists in same file (prevents the `c76c85212` bug where defvar(nil) overrides defcustom('draft)). 10 TDD tests.

**Bug 3: Void defvars fixed (agent-main.el, 5 defvars)** — `gptel-auto-workflow--running` and siblings had no initial value, crashing `--batch` pipeline starts.

**Lessons:**
- Stale `.elc` files: always `rm -f *.elc` when source-editing from outside Emacs
- `message_dolog` is non-atomic: format-sensitive chars (% &) must be escaped before logging
- defvar vs defcustom: defvar(nil) overrides defcustom defaults — the fixer must check
- Pi5 sync races: remote advances ~every 5-10 min; always fetch+rebase before push
