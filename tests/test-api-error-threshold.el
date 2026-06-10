;;; test-api-error-threshold.el --- TDD test for api-error-threshold initialization -*- lexical-binding: t; -*-

(require 'ert)
(require 'gptel-tools-agent-error)

(ert-deftest test-api-error-threshold-is-number ()
  "gptel-auto-experiment--api-error-threshold must be a number, not nil.
This prevents (>= gptel-auto-experiment--api-error-count nil)
which causes 'Wrong type argument: number-or-marker-p, nil'."
  (should (numberp gptel-auto-experiment--api-error-threshold))
  (should (> gptel-auto-experiment--api-error-threshold 0)))

(ert-deftest test-should-reduce-experiments-doesnt-error ()
  "gptel-auto-experiment--should-reduce-experiments-p must not signal
number-or-marker-p when api-error-threshold is properly set."
  (let ((gptel-auto-experiment--api-error-count 0))
    (should (booleanp (gptel-auto-experiment--should-reduce-experiments-p))))
  (let ((gptel-auto-experiment--api-error-count 10))
    (should (booleanp (gptel-auto-experiment--should-reduce-experiments-p)))))

(provide 'test-api-error-threshold)
;;; test-api-error-threshold.el ends here
