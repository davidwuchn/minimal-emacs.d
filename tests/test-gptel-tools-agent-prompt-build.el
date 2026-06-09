;;; test-gptel-tools-agent-prompt-build.el --- TDD tests for prompt-build -*- lexical-binding: t -*-

;;; Commentary:
;; Tests for the id extraction logic in gptel-tools-agent-prompt-build.el
;; Specifically the fix for (round :id) crash when :id is a string like 'exp-001'

;;; Code:

(require 'ert)

;; Helper function that mirrors the production logic
(defun tdd/extract-exp-id (raw-id)
  "Extract experiment ID from RAW-ID.
Mirrors the production logic in gptel-tools-agent-prompt-build.el:2395.
Returns an integer: numberp→round, stringp→extract digits, else 0."
  (cond ((numberp raw-id) (round raw-id))
        ((stringp raw-id)
         (if (string-match "[0-9]+" raw-id)
             (string-to-number (match-string 0 raw-id))
           0))
        (t 0)))

(ert-deftest tdd/prompt-build/exp-id-extraction/number-input ()
  "Number input: round it."
  (should (= 42 (tdd/extract-exp-id 42)))
  (should (= 43 (tdd/extract-exp-id 42.7)))
  (should (= 0 (tdd/extract-exp-id 0)))
  (should (= -5 (tdd/extract-exp-id -5.3))))

(ert-deftest tdd/prompt-build/exp-id-extraction/string-with-digits ()
  "String input with digits: extract first digit sequence."
  (should (= 1 (tdd/extract-exp-id "exp-001")))
  (should (= 42 (tdd/extract-exp-id "experiment-42")))
  (should (= 123 (tdd/extract-exp-id "run-123-abc")))
  (should (= 0 (tdd/extract-exp-id "exp-000"))))

(ert-deftest tdd/prompt-build/exp-id-extraction/string-without-digits ()
  "String input without digits: return 0."
  (should (= 0 (tdd/extract-exp-id "exp-abc")))
  (should (= 0 (tdd/extract-exp-id "no-digits-here")))
  (should (= 0 (tdd/extract-exp-id ""))))

(ert-deftest tdd/prompt-build/exp-id-extraction/other-types ()
  "Other types: return 0."
  (should (= 0 (tdd/extract-exp-id nil)))
  (should (= 0 (tdd/extract-exp-id 'symbol)))
  (should (= 0 (tdd/extract-exp-id '(list))))
  (should (= 0 (tdd/extract-exp-id :keyword))))

(ert-deftest tdd/prompt-build/exp-id-extraction/never-crashes-on-round ()
  "Regression: (round 'exp-001) crashes with wrong-type-argument.
The fix must handle string input without calling round on it."
  ;; This is what the bug was: (round "exp-001") → wrong-type-argument
  (should-error (round "exp-001") :type 'wrong-type-argument)
  ;; Our extraction handles it gracefully
  (should (= 1 (tdd/extract-exp-id "exp-001"))))

(provide 'test-gptel-tools-agent-prompt-build)
;;; test-gptel-tools-agent-prompt-build.el ends here
