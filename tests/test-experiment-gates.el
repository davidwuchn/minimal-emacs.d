;;; test-experiment-gates.el --- Regression tests for OV5 experiment gates -*- lexical-binding: t; -*-

;; Tests that verify the Phase 1 hardening of OV5 experiment gates:
;; A. Staging default — gptel-auto-workflow-use-staging must be t.
;; B. Critical-file mutation block — protected gate-engine files cannot
;;    be mutated by experiments.
;; C. Grader-bypass genuine-result predicate — only genuine, strong
;;    passing grades can bypass benchmark failures.
;; D. Push quarantine — TODO (requires full pipeline mock, behavior
;;    verified by code review of staging-disabled-push-blocked branches).

;;; Code:

(require 'ert)
(require 'cl-lib)

;; ── Test A: Staging default ──

(ert-deftest test-experiment-gates/staging-default-t ()
  "After loading key modules, gptel-auto-workflow-use-staging must be t.
Phase 1 removed (defvar gptel-auto-workflow-use-staging nil) overrides in
benchmark.el and main.el. The defcustom in subagent.el sets the default to t."
  ;; Load the modules that previously had nil overrides
  (require 'gptel-tools-agent-subagent)
  (require 'gptel-tools-agent-benchmark)
  (require 'gptel-tools-agent-main)
  ;; Verify the variable defaults to t, not nil
  (should (boundp 'gptel-auto-workflow-use-staging))
  (should (eq gptel-auto-workflow-use-staging t)))

;; ── Test B: Critical-file mutation block ──

(require 'gptel-tools-agent-validation)

(ert-deftest test-experiment-gates/critical-file-mutation-blocked ()
  "A diff modifying a protected gate-engine file is blocked.
The critical-files list includes benchmark, validation, subagent, etc.
A diff adding a line to gptel-tools-agent-benchmark.el should return
an error string mentioning CRITICAL."
  (let ((diff-text
         "diff --git a/lisp/modules/gptel-tools-agent-benchmark.el b/lisp/modules/gptel-tools-agent-benchmark.el
--- a/lisp/modules/gptel-tools-agent-benchmark.el
+++ b/lisp/modules/gptel-tools-agent-benchmark.el
@@ -197,6 +197,7 @@
        gptel-auto-workflow-use-staging
+  (message \"hello from benchmark\")
        (bound-and-true-p gptel-auto-workflow--headless)))"))
    (let ((result (gptel-auto-experiment--validate-diff-text diff-text)))
      (should (stringp result))
      (should (string-match-p "CRITICAL" result))
      (should (string-match-p "protected file" result))
      (should (string-match-p "gptel-tools-agent-benchmark" result)))))

(ert-deftest test-experiment-gates/non-critical-file-passes ()
  "A diff modifying a non-protected file should return nil.
Must have >= 2 non-trivial added lines to pass the trivial-change check."
  (let ((diff-text
         "diff --git a/lisp/modules/gptel-ext-context.el b/lisp/modules/gptel-ext-context.el
--- a/lisp/modules/gptel-ext-context.el
+++ b/lisp/modules/gptel-ext-context.el
@@ -10,6 +10,8 @@
 (require 'cl-lib)
+(defvar gptel-ext-context--cache (make-hash-table :test 'equal))
+(defun gptel-ext-context--lookup (k) (gethash k gptel-ext-context--cache))"))
    (let ((result (gptel-auto-experiment--validate-diff-text diff-text)))
      (should-not result))))

(ert-deftest test-experiment-gates/empty-diff-blocked ()
  "An empty diff string is blocked (no changes produced)."
  (let ((result (gptel-auto-experiment--validate-diff-text "")))
    (should (stringp result))
    (should (string-match-p "no file changes" result))))

;; ── Test C: Grader-bypass genuine-result predicate ──

(require 'gptel-tools-agent-experiment-core)

(ert-deftest test-experiment-gates/grader-bypass-genuine-pass ()
  "Genuine passing grade + tests-passed + nucleus-passed → t."
  (let ((grade '(:passed t :score 8 :total 10))
        (bench '(:tests-passed t :nucleus-passed t :score 8)))
    (should (gptel-auto-experiment--grader-bypass-p
             t 8 10 grade bench nil t))))

(ert-deftest test-experiment-gates/grader-bypass-rejects-grader-only-failure ()
  "A grade with :grader-only-failure t is rejected."
  (let ((grade '(:passed t :score 8 :total 10 :grader-only-failure t))
        (bench '(:tests-passed t :nucleus-passed t :score 8)))
    (should-not (gptel-auto-experiment--grader-bypass-p
                 t 8 10 grade bench nil t))))

(ert-deftest test-experiment-gates/grader-bypass-rejects-quota-exhausted ()
  "A grade with :quota-exhausted t is rejected."
  (let ((grade '(:passed t :score 8 :total 10 :quota-exhausted t))
        (bench '(:tests-passed t :nucleus-passed t :score 8)))
    (should-not (gptel-auto-experiment--grader-bypass-p
                 t 8 10 grade bench nil t))))

(ert-deftest test-experiment-gates/grader-bypass-rejects-blind-mode ()
  "A grade with :blind-mode t is rejected."
  (let ((grade '(:passed t :score 8 :total 10 :blind-mode t))
        (bench '(:tests-passed t :nucleus-passed t :score 8)))
    (should-not (gptel-auto-experiment--grader-bypass-p
                 t 8 10 grade bench nil t))))

(ert-deftest test-experiment-gates/grader-bypass-rejects-auto-pass-details ()
  "A grade with :details containing 'auto-pass' is rejected.
Covers 'blind-mode-auto-pass' and similar bypass attempts."
  (let ((grade '(:passed t :score 8 :total 10 :details "blind-mode-auto-pass"))
        (bench '(:tests-passed t :nucleus-passed t :score 8)))
    (should-not (gptel-auto-experiment--grader-bypass-p
                 t 8 10 grade bench nil t))))

(ert-deftest test-experiment-gates/grader-bypass-rejects-low-score ()
  "A score below 0.75 threshold is rejected (5/10 = 0.50 < 0.75)."
  (let ((grade '(:passed t :score 5 :total 10))
        (bench '(:tests-passed t :nucleus-passed t :score 8)))
    (should-not (gptel-auto-experiment--grader-bypass-p
                 t 5 10 grade bench nil t))))

(ert-deftest test-experiment-gates/grader-bypass-exact-threshold-passes ()
  "A score exactly at 0.75 threshold passes (7.5/10 rounds to 0.75)."
  (let ((grade '(:passed t :score 8 :total 10))  ; 0.80 > 0.75, already covered
        (bench '(:tests-passed t :nucleus-passed t :score 8)))
    ;; 7.5/10 = 0.75 exactly
    (should (gptel-auto-experiment--grader-bypass-p
             t 15 20 grade bench nil t))))

(ert-deftest test-experiment-gates/grader-bypass-rejects-tests-failed ()
  "When :tests-passed is nil, bypass is rejected."
  (let ((grade '(:passed t :score 8 :total 10))
        (bench '(:tests-passed nil :nucleus-passed t :score 8)))
    (should-not (gptel-auto-experiment--grader-bypass-p
                 t 8 10 grade bench nil nil))))

(ert-deftest test-experiment-gates/grader-bypass-rejects-nucleus-failed ()
  "When :nucleus-passed is nil, bypass is rejected."
  (let ((grade '(:passed t :score 8 :total 10))
        (bench '(:tests-passed t :nucleus-passed nil :score 8)))
    (should-not (gptel-auto-experiment--grader-bypass-p
                 t 8 10 grade bench nil t))))

(ert-deftest test-experiment-gates/grader-bypass-rejects-validation-error ()
  "When validation-error is non-nil, bypass is rejected."
  (let ((grade '(:passed t :score 8 :total 10))
        (bench '(:tests-passed t :nucleus-passed t :score 8))
        (validation-error "syntax error in foo.el"))
    (should-not (gptel-auto-experiment--grader-bypass-p
                 t 8 10 grade bench validation-error t))))

(ert-deftest test-experiment-gates/grader-bypass-rejects-not-passed ()
  "When grade-passed is nil, bypass is rejected regardless of score."
  (let ((grade '(:passed nil :score 9 :total 10))
        (bench '(:tests-passed t :nucleus-passed t :score 8)))
    (should-not (gptel-auto-experiment--grader-bypass-p
                 nil 9 10 grade bench nil t))))

(ert-deftest test-experiment-gates/grader-bypass-rejects-zero-total ()
  "When grade-total is 0, bypass is rejected (division-by-zero guard)."
  (let ((grade '(:passed t :score 0 :total 0))
        (bench '(:tests-passed t :nucleus-passed t :score 8)))
    (should-not (gptel-auto-experiment--grader-bypass-p
                 t 0 0 grade bench nil t))))

;; ── Test D: Push quarantine state ──
;;
;; TODO: The push quarantine behavior (staging-disabled-push-blocked,
;; staging-disabled-grader-bypass-push-blocked) cannot be unit-tested
;; without mocking the full commit/push pipeline, worktree creation,
;; and branch management.  The behavior is verified through code review:
;;
;; - main keep path: lines ~1272-1303 of experiment-core.el
;;   When gptel-auto-workflow-use-staging is nil, the kept result is
;;   set to :comparator-reason "staging-disabled-push-blocked" and
;;   :kept nil, preventing unreviewed optimize branches from leaking.
;;
;; - grader-bypass path: lines ~1685-1705 of experiment-core.el
;;   Same guard: when staging is disabled, bypass push is blocked with
;;   :comparator-reason "staging-disabled-grader-bypass-push-blocked".
;;
;; - bypass-commit-and-push path: lines ~2043-2059 of experiment-core.el
;;   Same guard with :comparator-reason "staging-disabled-bypass-push-blocked".
;;
;; An integration/E2E test for push quarantine would require:
;;   1. A temporary git repo with remote configured
;;   2. Mocked worktree creation and branch management
;;   3. Mocked grader result callbacks
;; This is better suited for the E2E test suite (test-wrapped-fsm.el or
;; a new test-auto-workflow-gates.el) rather than a pure unit test.

;; ── Provide ──

(provide 'test-experiment-gates)
;;; test-experiment-gates.el ends here
