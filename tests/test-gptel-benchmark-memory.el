;;; test-gptel-benchmark-memory.el --- Tests for mementum memory -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-benchmark-memory.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-benchmark-memory.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-benchmark-memory)

;;; Customization tests

(ert-deftest test-benchmark-memory/dir-default ()
  "Memory dir should default to ./mementum/."
  (should (equal gptel-benchmark-memory-dir "./mementum/")))

(ert-deftest test-benchmark-memory/auto-commit-default ()
  "Auto commit should default to t."
  (should gptel-benchmark-memory-auto-commit))

(ert-deftest test-benchmark-memory/phi-threshold-default ()
  "Phi threshold should default to 0.3."
  (should (= gptel-benchmark-memory-phi-threshold 0.3)))

(ert-deftest test-benchmark-memory/prune-age-default ()
  "Prune age should default to 30 days."
  (should (= gptel-benchmark-memory-prune-age-days 30)))

;;; Memory symbols tests

(ert-deftest test-benchmark-memory/symbols-defined ()
  "Memory symbols should be defined."
  (should (listp gptel-benchmark-memory-symbols)))

(ert-deftest test-benchmark-memory/symbol-insight ()
  "Insight symbol should be 💡."
  (should (equal (cdr (assq 'insight gptel-benchmark-memory-symbols)) "💡")))

(ert-deftest test-benchmark-memory/symbol-shift ()
  "Shift symbol should be 🔄."
  (should (equal (cdr (assq 'shift gptel-benchmark-memory-symbols)) "🔄")))

(provide 'test-gptel-benchmark-memory)
;;; test-gptel-benchmark-memory.el ends here