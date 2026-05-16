;;; test-gptel-tools-agent-subagent.el --- Tests for subagent delegation -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-subagent.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-subagent.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-subagent)

;;; Subagent origin tests

(ert-deftest test-subagent/origin-buffer-declared ()
  "Subagent origin buffer variable should be declared."
  (should (intern-soft "my/gptel--subagent-origin-buffer")))

;;; First existing directory tests

(ert-deftest test-subagent/first-existing-returns-nil-for-empty ()
  "First existing should return nil for no dirs."
  (should-not (my/gptel--first-existing-directory)))

(ert-deftest test-subagent/first-existing-returns-nil-for-nonexistent ()
  "First existing should return nil for nonexistent dirs."
  (should-not (my/gptel--first-existing-directory "/nonexistent1" "/nonexistent2")))

;;; Curl buffer priming tests

(ert-deftest test-subagent/prime-curl-buffer-no-error ()
  "Prime curl buffer should handle nil args."
  (ignore-errors (my/gptel--prime-curl-buffer-directory nil nil))
  (should t))

;;; Safe callback invocation tests

(ert-deftest test-subagent/invoke-callback-safely-handles-functionp ()
  "Invoke callback safely should check functionp."
  (should (functionp 'my/gptel--invoke-callback-safely)))

(ert-deftest test-subagent/invoke-callback-safely-with-result ()
  "Invoke callback safely should pass result."
  (let ((captured nil))
    (my/gptel--invoke-callback-safely (lambda (r) (setq captured r)) 'test-result)
    (should (eq captured 'test-result))))

(provide 'test-gptel-tools-agent-subagent)
;;; test-gptel-tools-agent-subagent.el ends here