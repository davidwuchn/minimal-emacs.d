;;; test-gptel-tools-agent-error.el --- Tests for error analysis -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-error.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-error.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-error)
(require 'gptel-tools-agent-prompt-analyze)
(require 'gptel-tools-agent-experiment-loop)

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

;;; Grade-failure-error-output tests

(ert-deftest test-error/grade-failure-error-output-normal ()
  "Normal grade details (matching rubric pattern) should return nil."
  (let ((result (gptel-auto-experiment--grade-failure-error-output
                 "Grader result for task: Grade output\nSUMMARY: SCORE: 4/4"
                 "Some agent output")))
    (should (null result))))

(ert-deftest test-error/grade-failure-error-output-retryable-string ()
  "Retryable string grade details should return the string."
  (let ((result (gptel-auto-experiment--grade-failure-error-output
                 "operation timed out" "Some output")))
    (should (stringp result))
    (should (string-match-p "timed out" result))))

(ert-deftest test-error/grade-failure-error-output-both-nil ()
  "Both nil should return nil."
  (let ((result (gptel-auto-experiment--grade-failure-error-output nil nil)))
    (should (null result))))

(ert-deftest test-error/grade-failure-error-output-non-retryable-string ()
  "Non-retryable string grade-details should fall through to agent output."
  (let ((result (gptel-auto-experiment--grade-failure-error-output
                 "success" "Error: timeout")))
    (should (stringp result))
    (should (string-match-p "Error" result))))

(ert-deftest test-error/grade-failure-error-output-agent-output-format ()
  "Agent output starting with Error: should be used when grade-details is nil."
  (let ((result (gptel-auto-experiment--grade-failure-error-output
                 nil "Error: curl failed")))
    (should (stringp result))
    (should (string-match-p "curl" result))))

(ert-deftest test-error/grade-failure-error-output-agent-output-non-error ()
  "Agent output without Error: prefix should return nil with nil grade-details."
  (let ((result (gptel-auto-experiment--grade-failure-error-output
                 nil "Task completed")))
    (should (null result))))

(ert-deftest test-error/first-available-skips-malformed-candidates ()
  "Malformed provider candidates should not crash fallback selection."
  (cl-letf (((symbol-function 'gptel-auto-workflow--backend-available-p)
             (lambda (backend) (string= backend "DeepSeek"))))
    (should (equal (gptel-auto-workflow--first-available-provider-candidate
                    '("MiniMax" ("DeepSeek" . "deepseek-v4-flash")))
                   '("DeepSeek" . "deepseek-v4-flash")))))

(provide 'test-gptel-tools-agent-error)
;;; test-gptel-tools-agent-error.el ends here
