---
symbol: 💡
title: save-excursion does NOT preserve match-data
category: elisp
tags: [elisp, gotcha, regex, match-data, save-match-data]
related: [format-string-mismatch-debugging]
---

# `save-excursion` does NOT preserve `match-data`

**Insight:** `(looking-at REGEX)`, `(re-search-forward REGEX)`, `(string-match REGEX)`
all update the internal match-data (what `(match-beginning N)`, `(match-end N)`,
`(match-string N)`, `(match-data)` return). `(save-excursion ...)` restores
point and current-buffer, but does NOT restore match-data.

**Failure mode:** If you use `(match-end 0)` AFTER calling `(looking-at ...)`
inside `(save-excursion ...)`, you get the END of the `(looking-at)` match,
not the END of any earlier `re-search-forward` match. In a while-loop that
relies on `(goto-char (match-end 0))` to advance, this causes 0 progress
and an infinite loop.

**Fix:** Wrap the call in `(save-match-data ...)`:

```elisp
(save-match-data
  (save-excursion
    (goto-char pos)
    (looking-at "defun\\_>"))) ; t/nil result, but match-data preserved
```

Or avoid the inner search entirely and use a non-mutating check:

```elisp
(let ((probe (buffer-substring-no-properties outer-start
                                              (min (point-max) (+ outer-start 32)))))
  (string-match-p "^[ \t]*(cl-\\)?defun\\|defmacro\\|defsubst\\b" probe))
```

**Detection:** Process hangs/timeout. `(point)` does not advance across loop
iterations. `(match-end 0)` returns a value smaller than expected.

**Source:** scripts/git-hooks/pre-commit section 4b (top-level def check),
which used `(save-excursion (goto-char outer-start) (looking-at REGEX))`
inside a `while (re-search-forward ...)` loop. The `(looking-at)` mutated
match-data so `(match-end 0)` returned 6 chars into the outer defun, not
44 chars into the inner defun's name. The next `re-search-forward` matched
the same position, looping forever. Caught by test that timed out at 30s.

**Related:**

- `looking-at` doc: "Sets the match data"
- `save-excursion` doc: "Save point, and current buffer" — no mention of match-data
- `save-match-data` doc: "Save the state of the match data"
