;;; test-gptel-auto-workflow-research-benchmark.el --- Tests for research benchmarking -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-auto-workflow-research-benchmark.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-auto-workflow-research-benchmark.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-research-benchmark)

;;; Plist dedup tests

(ert-deftest test-research/plist-dedup-put-exists ()
  "Plist dedup put function should exist."
  (should (fboundp 'gptel-auto-workflow--plist-dedup-put)))

;;; Normalize controller rules tests

(ert-deftest test-research/normalize-controller-rules-exists ()
  "Normalize controller rules function should exist."
  (should (fboundp 'gptel-auto-workflow--normalize-controller-rules)))

;;; Score research output tests

(ert-deftest test-research/score-output-empty-string ()
  "Score research output should handle empty string."
  (let ((score (gptel-auto-workflow--score-research-output "")))
    (should (numberp score))))

(ert-deftest test-research/score-output-with-urls ()
  "Score research output should detect URLs."
  (let ((score (gptel-auto-workflow--score-research-output "See https://example.com")))
    (should (> score 0))))

;;; Format prompt tests

(ert-deftest test-research/format-strategy-prompt-exists ()
  "Format strategy prompt function should exist."
  (should (fboundp 'gptel-auto-workflow--format-research-strategy-prompt)))

;;; Load strategy tests

(ert-deftest test-research/load-strategy-as-text-exists ()
  "Load strategy as text function should exist."
  (should (fboundp 'gptel-auto-workflow--load-strategy-as-text)))

;;; Trace helpers tests

(ert-deftest test-research/trace-string-field-exists ()
  "Trace string field function should exist."
  (should (fboundp 'gptel-auto-workflow--trace-string-field)))

(ert-deftest test-research/trace-source-exists ()
  "Trace source function should exist."
  (should (fboundp 'gptel-auto-workflow--trace-source)))

(ert-deftest test-research/trace-strategy-exists ()
  "Trace strategy function should exist."
  (should (fboundp 'gptel-auto-workflow--trace-strategy)))

(provide 'test-gptel-auto-workflow-research-benchmark)
;;; test-gptel-auto-workflow-research-benchmark.el ends here