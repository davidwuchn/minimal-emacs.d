;;; test-gptel-ext-transient.el --- Tests for transient menu fixes -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-ext-transient.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-ext-transient.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-ext-transient)

;;; Transient origin buffer tests

(ert-deftest test-transient/origin-buffer-nil-initially ()
  "Origin buffer should be nil initially."
  (should-not (bound-and-true-p my/gptel--transient-origin-buffer)))

(ert-deftest test-transient/origin-preset-nil-initially ()
  "Origin preset should be nil initially."
  (should-not (bound-and-true-p my/gptel--transient-origin-preset)))

(provide 'test-gptel-ext-transient)
;;; test-gptel-ext-transient.el ends here