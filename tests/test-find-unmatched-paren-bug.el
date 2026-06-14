(ert-deftest test-daemon-repl/find-unmatched-paren-pos-mixed ()
  "find-unmatched-paren-pos should return the first unmatched open paren
when matched parens precede an unmatched one.  Example: '(a)(b)(c' has
matched (a) and (b), but the third ( at position 6 is unmatched.  The
function should return 6 — the position of the unbalanced (c — not 0."
  (should (= 6 (gptel-daemon-repl--find-unmatched-paren-pos "(a)(b)(c"))))
