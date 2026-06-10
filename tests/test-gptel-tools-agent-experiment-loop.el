;;; test-gptel-tools-agent-experiment-loop.el --- Tests for experiment loop -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-experiment-loop.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-experiment-loop.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-experiment-loop)
(require 'gptel-tools-agent-error)

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

;;; Self-heal tool-call failure tests

(ert-deftest test-loop/make-retry-prompt-prepends-for-no-code-changes ()
  "make-retry-prompt should prepend self-heal λ notation for 'no code changes'."
  (let* ((original "Original prompt with task instructions")
         (result (gptel-auto-experiment--make-retry-prompt
                  "test.el"
                  "Agent made no code changes. Use Edit or Write tools to modify files."
                  original))
         (pos-self-heal (string-match "SELF-HEAL" result))
         (pos-original (string-match (regexp-quote original) result)))
    (should (stringp result))
    (should (> (length result) (length original)))
    ;; Self-heal λ notation should appear BEFORE original prompt (prepended, not appended)
    (should pos-self-heal)
    (should (string-match-p "λ self-heal" result))
    (should (string-match-p "¬tool_call" result))
    (should (string-match-p "∀change: ∃tool_call" result))
    (should (string-match-p "text_only.*≡ reject" result))
    ;; Original prompt should appear in the result
    (should pos-original)
    ;; Self-heal must appear before original prompt
    (should (< pos-self-heal pos-original))
    ;; Self-heal should be near the beginning (within first 100 chars)
    (should (< pos-self-heal 100))))

(ert-deftest test-loop/make-retry-prompt-wont-prepend-for-syntax-error ()
  "make-retry-prompt should NOT prepend self-heal for syntax errors."
  (let* ((original "Original prompt with task instructions")
         (result (gptel-auto-experiment--make-retry-prompt
                  "test.el"
                  "Syntax error: unmatched paren"
                  original)))
    (should (stringp result))
    ;; Original prompt should still appear
    (should (string-match-p (regexp-quote original) result))
    ;; No self-heal box
    (should-not (string-match-p "SELF-HEAL" result))
    (should-not (string-match-p "YOU WILL FAIL" result))))

(ert-deftest test-loop/make-retry-prompt-wont-prepend-for-unknown ()
  "make-retry-prompt should NOT prepend self-heal for unknown validation-error."
  (let* ((original "Original prompt with task instructions")
         (result (gptel-auto-experiment--make-retry-prompt
                  "test.el"
                  "Unknown validation error"
                  original)))
    (should (stringp result))
    (should (string-match-p (regexp-quote original) result))
    (should-not (string-match-p "SELF-HEAL" result))))

(ert-deftest test-loop/make-retry-prompt-handles-empty-original ()
  "make-retry-prompt should handle nil original-prompt."
  (let ((result (gptel-auto-experiment--make-retry-prompt
                 "test.el"
                 "Agent made no code changes"
                 nil)))
    (should (stringp result))
    (should (string-match-p "SELF-HEAL" result))))

;;; Plan Diversity Metric (inspired by PlanSearch arXiv:2409.03733)

(ert-deftest test-loop/diversity-metric-exists ()
  "Plan diversity metric should exist.
Inspired by PlanSearch: plan diversity predicts performance gains."
  (should (fboundp 'gptel-auto-experiment--hypothesis-diversity)))

(ert-deftest test-loop/diversity-maximal-when-no-previous ()
  "Diversity should be 1.0 (maximal) when no previous hypotheses exist."
  (let ((diversity (gptel-auto-experiment--hypothesis-diversity
                    "Add nil guard before calling car"
                    nil)))
    (should (= diversity 1.0))))

(ert-deftest test-loop/diversity-minimal-for-identical ()
  "Diversity should be 0.0 (minimal) when hypothesis is identical to previous."
  (let* ((hypothesis "Add nil guard before calling car")
         (previous-results
          (list (list :hypothesis "Add nil guard before calling car"
                      :target "lisp/modules/test.el"
                      :kept nil)))
         (diversity (gptel-auto-experiment--hypothesis-diversity
                     hypothesis previous-results)))
    ;; Identical hypothesis = 0 diversity
    (should (= diversity 0.0))))

(ert-deftest test-loop/diversity-high-for-different ()
  "Diversity should be high when hypothesis is very different from previous."
  (let* ((hypothesis "Add nil guard before calling car")
         (previous-results
          (list (list :hypothesis "Refactor data structure for performance"
                      :target "lisp/modules/test.el"
                      :kept nil)
                (list :hypothesis "Improve error handling in validation"
                      :target "lisp/modules/test.el"
                      :kept nil)))
         (diversity (gptel-auto-experiment--hypothesis-diversity
                     hypothesis previous-results)))
    ;; Very different hypotheses = high diversity (> 0.7)
    (should (> diversity 0.7))))

(ert-deftest test-loop/diversity-medium-for-partial-overlap ()
  "Diversity should be medium when hypothesis partially overlaps with previous."
  (let* ((hypothesis "Add nil guard before calling car")
         (previous-results
          (list (list :hypothesis "Add nil check before calling cdr"
                      :target "lisp/modules/test.el"
                      :kept nil)))
         (diversity (gptel-auto-experiment--hypothesis-diversity
                     hypothesis previous-results)))
    ;; Partial overlap = medium diversity (0.3-0.7)
    (should (and (> diversity 0.3) (< diversity 0.7)))))

;;; Plan-Level Search (PlanSearch arXiv:2409.03733)

(ert-deftest test-loop/plan-search-generate-candidates-exists ()
  "Plan-level search candidate generation should exist."
  (should (fboundp 'gptel-auto-experiment--generate-candidate-hypotheses)))

(ert-deftest test-loop/plan-search-select-diverse-exists ()
  "Plan-level search selection should exist."
  (should (fboundp 'gptel-auto-experiment--select-diverse-hypothesis)))

(ert-deftest test-loop/plan-search-generates-multiple-candidates ()
  "Should generate multiple candidate hypotheses."
  (let ((candidates (gptel-auto-experiment--generate-candidate-hypotheses
                     "lisp/modules/test.el" nil 5)))
    ;; Should return a list of candidates
    (should (listp candidates))
    ;; Should have at least 1 candidate (may have up to 5)
    (should (>= (length candidates) 1))
    ;; Each candidate should have :hypothesis :source :diversity
    (dolist (c candidates)
      (should (plist-get c :hypothesis))
      (should (plist-get c :source))
      (should (numberp (plist-get c :diversity))))))

(ert-deftest test-loop/plan-search-selects-diverse-hypothesis ()
  "Should select a diverse hypothesis when available."
  (let* ((previous-results
          (list (list :hypothesis "Add nil guard before calling car"
                      :target "lisp/modules/test.el"
                      :kept nil)))
         (selected (gptel-auto-experiment--select-diverse-hypothesis
                    "lisp/modules/test.el" previous-results 0.3)))
    ;; Should return a string (or nil if no diverse candidates)
    (should (or (null selected) (stringp selected)))
    ;; If selected, should be different from previous
    (when selected
      (should-not (string= selected "Add nil guard before calling car")))))

(ert-deftest test-loop/plan-search-avoids-duplicates ()
  "Should not select hypotheses already tested."
  (let* ((previous-results
          (list (list :hypothesis "Add nil guards before dangerous operations"
                      :target "lisp/modules/test.el"
                      :kept nil)
                (list :hypothesis "Simplify complex conditional logic"
                      :target "lisp/modules/test.el"
                      :kept nil)))
         (selected (gptel-auto-experiment--select-diverse-hypothesis
                    "lisp/modules/test.el" previous-results 0.3)))
    ;; Should not select exact duplicates
    (when selected
      (should-not (member selected
                          '("Add nil guards before dangerous operations"
                            "Simplify complex conditional logic"))))))

(provide 'test-gptel-tools-agent-experiment-loop)
;;; test-gptel-tools-agent-experiment-loop.el ends here