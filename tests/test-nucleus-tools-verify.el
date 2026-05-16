;;; test-nucleus-tools-verify.el --- Tests for tool verification -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for nucleus-tools-verify.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-nucleus-tools-verify.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nucleus-tools-verify)

;;; Verification tests

(ert-deftest test-verify/verify-tools-returns-alist ()
  "Verify tools should return an alist."
  (let ((result (nucleus--verify-tools)))
    (should (listp result))
    (dolist (item result)
      (should (consp item))
      (should (symbolp (cdr item))))))

(ert-deftest test-verify/verify-tools-has-status ()
  "Verify tools should have status symbols."
  (let ((result (nucleus--verify-tools)))
    (dolist (item result)
      (should (memq (cdr item) '(registered missing duplicate))))))

;;; Report tests

(ert-deftest test-verify/report-runs ()
  "Report verification should execute without error."
  (should (nucleus--report-tool-verification)))

(provide 'test-nucleus-tools-verify)
;;; test-nucleus-tools-verify.el ends here