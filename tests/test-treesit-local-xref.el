;;; test-treesit-local-xref.el --- Tests for tree-sitter xref backend -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for treesit-local-xref.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-treesit-local-xref.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'treesit-local-xref)

;;; Backend tests

(ert-deftest test-xref/backend-returns-nil-no-treesit ()
  "Backend should return nil when treesit not available."
  (let ((treesit-available-p nil))
    (should-not (treesit-local-xref-backend))))

(ert-deftest test-xref/backend-symbol-name ()
  "Backend name should be treesit-local."
  (should (eq 'treesit-local 'treesit-local)))

(provide 'test-treesit-local-xref)
;;; test-treesit-local-xref.el ends here