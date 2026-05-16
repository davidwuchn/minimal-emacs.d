;;; test-gptel-tools-agent-error.el --- Tests for error analysis -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-error.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-error.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-error)

;;; Pattern matching tests

(ert-deftest test-error/match-ignore-case-matches ()
  "Pattern should match case-insensitively."
  (should (gptel-error--match-ignore-case "timeout" "TIMEOUT"))
  (should (gptel-error--match-ignore-case "timeout" "operation timeout")))

(ert-deftest test-error/match-ignore-case-no-match ()
  "Pattern should not match unrelated strings."
  (should-not (gptel-error--match-ignore-case "timeout" "success")))

(ert-deftest test-error/match-ignore-case-nil-string ()
  "Pattern should not match nil string."
  (should-not (gptel-error--match-ignore-case "timeout" nil)))

;;; Retryable error detection tests

(ert-deftest test-error/is-retryable-timed-out ()
  "Timeout errors should be retryable."
  (should (gptel-auto-experiment--is-retryable-error-p "operation timed out")))

(ert-deftest test-error/is-retryable-server-error ()
  "Server errors should be retryable."
  (should (gptel-auto-experiment--is-retryable-error-p "server_error 500")))

(ert-deftest test-error/is-retryable-malformed-json ()
  "Malformed JSON should be retryable."
  (should (gptel-auto-experiment--is-retryable-error-p "Malformed JSON response")))

(ert-deftest test-error/is-retryable-curl-28 ()
  "Curl exit code 28 should be retryable."
  (should (gptel-auto-experiment--is-retryable-error-p "curl failed with exit code 28")))

(ert-deftest test-error/is-retryable-not-success ()
  "Success messages should not be retryable."
  (should-not (gptel-auto-experiment--is-retryable-error-p "success")))

;;; Hard quota error tests

(ert-deftest test-error/hard-quota-pattern-exists ()
  "Hard quota pattern constant should exist."
  (should (stringp gptel-auto-experiment--hard-quota-error-pattern)))

(ert-deftest test-error/hard-quota-matches-exceeded ()
  "Hard quota pattern should match quota exceeded."
  (let ((case-fold-search t))
    (should (string-match-p gptel-auto-experiment--hard-quota-error-pattern
                            "allocated quota exceeded"))))

;;; Rate limit error tests

(ert-deftest test-error/rate-limit-error-p-matches ()
  "Rate limit errors should be detected."
  (should (gptel-auto-experiment--rate-limit-error-p "rate limit exceeded")))

(ert-deftest test-error/rate-limit-error-p-overloaded ()
  "Overloaded errors should be detected as rate limit."
  (should (gptel-auto-experiment--rate-limit-error-p "overloaded_error")))

;;; Aborted output detection tests

(ert-deftest test-error/aborted-output-p-empty ()
  "Empty output should not be aborted."
  (should-not (gptel-auto-experiment--aborted-agent-output-p "")))

(ert-deftest test-error/aborted-output-p-normal ()
  "Normal output should not be aborted."
  (should-not (gptel-auto-experiment--aborted-agent-output-p "Task completed successfully")))

(provide 'test-gptel-tools-agent-error)
;;; test-gptel-tools-agent-error.el ends here