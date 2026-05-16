;;; test-gptel-tools-agent-experiment-loop.el --- Tests for experiment loop -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-experiment-loop.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-experiment-loop.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-experiment-loop)

;;; Hypothesis extraction tests

(ert-deftest test-loop/extract-hypothesis-empty ()
  "Extract hypothesis should handle empty string."
  (let ((result (gptel-auto-experiment--extract-hypothesis "")))
    (should (or (null result) (stringp result)))))

(ert-deftest test-loop/extract-hypothesis-nil ()
  "Extract hypothesis should handle nil."
  (let ((result (gptel-auto-experiment--extract-hypothesis nil)))
    (should (or (null result) (stringp result)))))

;;; Agent error tests

(ert-deftest test-loop/agent-error-p-empty ()
  "Agent error check should return nil for empty."
  (should-not (gptel-auto-experiment--agent-error-p "")))

;;; Summarize tests

(ert-deftest test-loop/summarize-nil ()
  "Summarize should handle nil."
  (should-not (gptel-auto-experiment--summarize nil)))

(ert-deftest test-loop/summarize-string ()
  "Summarize should handle string."
  (let ((result (gptel-auto-experiment--summarize "a b c d e f g h")))
    (should (stringp result))))

;;; Teachable validation error tests

(ert-deftest test-loop/teachable-validation-error-p-empty ()
  "Teachable validation error check should handle empty."
  (should-not (gptel-auto-experiment--teachable-validation-error-p "test.el" nil)))

;;; Status file tests

(ert-deftest test-loop/status-file-exists ()
  "Status file function should exist."
  (should (fboundp 'gptel-auto-workflow--status-file)))

;;; Messages file tests

(ert-deftest test-loop/messages-file-exists ()
  "Messages file function should exist."
  (should (fboundp 'gptel-auto-workflow--messages-file)))

;;; Status active tests

(ert-deftest test-loop/status-active-p-nil ()
  "Status active check should handle nil."
  (should-not (gptel-auto-workflow--status-active-p nil)))

(provide 'test-gptel-tools-agent-experiment-loop)
;;; test-gptel-tools-agent-experiment-loop.el ends here