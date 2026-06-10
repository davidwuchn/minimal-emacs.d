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
  "make-retry-prompt should prepend self-heal lambda notation."
  (let* ((original "Original prompt with task instructions")
         (result (gptel-auto-experiment--make-retry-prompt
                  "test.el"
                  "Agent made no code changes. Use Edit or Write tools to modify files."
                  original))
         (pos-self-heal (string-match "SELF-HEAL" result))
         (pos-original (string-match (regexp-quote original) result)))
    (should (stringp result))
    (should (> (length result) (length original)))
    (should pos-self-heal)
    (should (string-match-p "self-heal" result))
    (should (string-match-p "tool_call" result))
    (should pos-original)
    (should (< pos-self-heal pos-original))
    (should (< pos-self-heal 100))))

(ert-deftest test-loop/make-retry-prompt-wont-prepend-for-syntax-error ()
  "make-retry-prompt should NOT prepend self-heal for syntax errors."
  (let* ((original "Original prompt with task instructions")
         (result (gptel-auto-experiment--make-retry-prompt
                  "test.el"
                  "Syntax error: unmatched paren"
                  original)))
    (should (stringp result))
    (should (string-match-p (regexp-quote original) result))
    (should-not (string-match-p "SELF-HEAL" result))))

(ert-deftest test-loop/make-retry-prompt-wont-prepend-for-unknown ()
  "make-retry-prompt should NOT prepend self-heal for unknown errors."
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

;;; Plan Diversity Metric (PlanSearch arXiv:2409.03733)

(ert-deftest test-loop/diversity-metric-exists ()
  "Plan diversity metric should exist."
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
    (should (listp candidates))
    (should (>= (length candidates) 1))
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
    (should (or (null selected) (stringp selected)))
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
    (when selected
      (should-not (member selected
                          '("Add nil guards before dangerous operations"
                            "Simplify complex conditional logic"))))))

;;; Experiment Relevance Scoring (AttnRes arXiv:2603.15031)

(ert-deftest test-loop/relevance-functions-exist ()
  "Relevance scoring functions should exist."
  (should (fboundp 'gptel-auto-experiment--compute-relevance))
  (should (fboundp 'gptel-auto-experiment--jaccard))
  (should (fboundp 'gptel-auto-experiment--tokenize))
  (should (fboundp 'gptel-auto-experiment--rank-relevant-experiments)))

(ert-deftest test-loop/jaccard-identical-is-one ()
  "Jaccard of identical token lists should be 1.0."
  (should (= 1.0 (gptel-auto-experiment--jaccard
                  '("hello" "world") '("hello" "world")))))

(ert-deftest test-loop/jaccard-disjoint-is-zero ()
  "Jaccard of disjoint token lists should be 0.0."
  (should (= 0.0 (gptel-auto-experiment--jaccard '("hello") '("world")))))

(ert-deftest test-loop/tokenize-filters-short-tokens ()
  "Tokenize should filter tokens shorter than 4 characters."
  (let ((tokens (gptel-auto-experiment--tokenize "add nil guard car")))
    (should (member "guard" tokens))
    (should-not (member "add" tokens))
    (should-not (member "nil" tokens))))

(ert-deftest test-loop/relevance-high-for-same-target ()
  "Relevance should be high for same target path."
  (let* ((target "lisp/modules/gptel-tools-agent-experiment-loop.el")
         (previous (list :target "lisp/modules/gptel-tools-agent-experiment-loop.el"
                         :hypothesis "Add nil guard before calling car"
                         :kept t))
         (relevance (gptel-auto-experiment--compute-relevance target previous)))
    (should (> relevance 0.3))))

(ert-deftest test-loop/relevance-low-for-unrelated ()
  "Relevance should be low for unrelated target and hypothesis."
  (let* ((target "lisp/modules/gptel-tools-agent-experiment-loop.el")
         (previous (list :target "lisp/modules/gptel-platform-sandbox.el"
                         :hypothesis "Improve documentation for public functions"
                         :kept t))
         (relevance (gptel-auto-experiment--compute-relevance target previous)))
    (should (< relevance 0.2))))

(ert-deftest test-loop/rank-returns-top-n ()
  "Rank should return at most N experiments sorted by relevance."
  (let* ((target "lisp/modules/gptel-tools-agent-main.el")
         (previous-results
          (list (list :target "lisp/modules/gptel-tools-agent-main.el"
                      :hypothesis "Simplify complex conditional logic")
                (list :target "lisp/modules/gptel-platform-sandbox.el"
                      :hypothesis "Refactor data structure")
                (list :target "lisp/modules/gptel-tools-agent-core.el"
                      :hypothesis "Improve main function error handling")))
         (ranked (gptel-auto-experiment--rank-relevant-experiments
                  target previous-results 3)))
    (should (<= (length ranked) 3))
    (should (string= (plist-get (cdar ranked) :target)
                     "lisp/modules/gptel-tools-agent-main.el"))))

(provide 'test-gptel-tools-agent-experiment-loop)
;;; test-gptel-tools-agent-experiment-loop.el ends here
