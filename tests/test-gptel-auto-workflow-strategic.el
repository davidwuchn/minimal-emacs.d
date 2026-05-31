;;; test-gptel-auto-workflow-strategic.el --- Tests for strategic target selection -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-auto-workflow-strategic.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-auto-workflow-strategic.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-strategic)

;;; Customization tests

(ert-deftest test-strategic/selection-default ()
  "Strategic selection should default to t."
  (should gptel-auto-workflow-strategic-selection))

(ert-deftest test-strategic/max-targets-default ()
  "Max targets per run should default to 5."
  (should (= gptel-auto-workflow-max-targets-per-run 5)))

(ert-deftest test-strategic/denylist-defined ()
  "Headless target denylist should be defined."
  (should (listp gptel-auto-workflow-headless-target-denylist)))

(ert-deftest test-strategic/research-interval-default ()
  "Research interval should be 4 hours."
  (should (= gptel-auto-workflow-research-interval (* 4 3600))))

(ert-deftest test-strategic/max-research-turns-default ()
  "Max research turns should default to 3."
  (should (= gptel-auto-workflow-max-research-turns 3)))

(ert-deftest test-strategic/analyzer-time-budget-default ()
  "Analyzer time budget should default to 180.
Reduced from 240 — let it fail fast and fall back to faster backends."
  (should (= gptel-auto-workflow-analyzer-time-budget 180)))

;;; Research trace tests

(ert-deftest test-strategic/research-trace-for-hash-exists ()
  "Research trace for hash function should exist."
  (should (fboundp 'gptel-auto-workflow--research-trace-for-hash)))

;;; Clear analyzer state tests

(ert-deftest test-strategic/clear-analyzer-error-state-exists ()
  "Clear analyzer error state function should exist."
  (should (fboundp 'gptel-auto-workflow--clear-analyzer-error-state)))

;;; Skip headless target tests

(ert-deftest test-strategic/skip-headless-target-nil ()
  "Skip headless target should return nil for non-denylisted."
  (should-not (gptel-auto-workflow--skip-headless-target-p "lisp/modules/other.el")))

(ert-deftest test-strategic/skip-headless-target-when-headless ()
  "Skip headless target should return t when headless and denylisted."
  (let ((gptel-auto-workflow--headless t))
    (should (gptel-auto-workflow--skip-headless-target-p "lisp/modules/gptel-tools-bash.el"))))

(provide 'test-gptel-auto-workflow-strategic)
;;; test-gptel-auto-workflow-strategic.el ends here