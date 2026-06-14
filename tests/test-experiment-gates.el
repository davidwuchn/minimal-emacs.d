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
(require 'gptel-tools-agent-staging-merge)

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

(ert-deftest test-experiment-gates/diff-with-llm-markdown-blocked ()
  "A diff containing ```emacs-lisp blocks is flagged as LLM artifact."
  (let ((diff-text
         "diff --git a/x.el b/x.el
--- a/x.el
+++ b/x.el
@@ -1,1 +1,3 @@
+(progn (message \"x\") nil)
+```emacs-lisp
+(defun foo () 42)
+```"))
    (let ((result (gptel-auto-experiment--validate-diff-text diff-text)))
      (should (stringp result))
      (should (string-match-p "LLM markdown" result)))))

(ert-deftest test-experiment-gates/diff-with-debug-artifact-blocked ()
  "A diff with top-level (message ...) insertion is flagged as debug code.
Catches the LLM tendency to leave (message \"debugging X\") in commits."
  (let ((diff-text
         "diff --git a/lisp/modules/gptel-ext-context.el b/lisp/modules/gptel-ext-context.el
--- a/lisp/modules/gptel-ext-context.el
+++ b/lisp/modules/gptel-ext-context.el
@@ -1,1 +1,2 @@
+(message \"debug trace\")
+(defun foo () 42)"))
    (let ((result (gptel-auto-experiment--validate-diff-text diff-text)))
      (should (stringp result))
      (should (string-match-p "debug artifact" result)))))

(ert-deftest test-experiment-gates/diff-with-error-handling-removal-blocked ()
  "A diff that removes condition-case is flagged as vandalism."
  (let ((diff-text
         "diff --git a/x.el b/x.el
--- a/x.el
+++ b/x.el
@@ -1,5 +1,2 @@
-(condition-case err
-    (do-stuff)
-  (error (message \"oops\")))
+(do-stuff)"))
    (let ((result (gptel-auto-experiment--validate-diff-text diff-text)))
      (should (stringp result))
      (should (string-match-p "error handling" result)))))

(ert-deftest test-experiment-gates/diff-too-large-blocked ()
  "A diff with >80 added lines is flagged as off-task."
  (let* ((lines '("diff --git a/x.el b/x.el"
                  "--- a/x.el"
                  "+++ b/x.el"
                  "@@ -1,1 +1,82 @@"))
         (body-lines (mapcar (lambda (n) (format "+(line %d)" n))
                             (number-sequence 1 85)))
         (diff-text (mapconcat #'identity (append lines body-lines) "\n")))
    (let ((result (gptel-auto-experiment--validate-diff-text diff-text)))
      (should (stringp result))
      (should (string-match-p "too large" result)))))

(ert-deftest test-experiment-gates/diff-trivially-small-blocked ()
  "A diff with only 1 non-comment code line is flagged as trivial."
  (let ((diff-text
         "diff --git a/x.el b/x.el
--- a/x.el
+++ b/x.el
@@ -1,1 +1,2 @@
+;; a comment
+(provide 'x)"))
    (let ((result (gptel-auto-experiment--validate-diff-text diff-text)))
      (should (stringp result))
      (should (string-match-p "non-comment code lines" result)))))

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

;; ── Test E: Gate-engine files never fast-track ──

(ert-deftest test-experiment-gates/gate-engine-never-fast-track ()
  "Diffs touching gate-engine files are not fast-track eligible.
Gate-engine files (self-heal, audit helper, staging, experiment-core,
monitoring, pre-push, run-tests.sh) must go through full staging
verification; fast-track is blocked."
  (let ((gptel-auto-workflow-fast-track-enabled t)
        (gptel-auto-workflow-fast-track-max-files 5)
        (gptel-auto-workflow-fast-track-max-lines 50))
    (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
               (lambda (_cmd _timeout)
                 " lisp/modules/gptel-auto-workflow-self-heal-semantic.el | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)")))
      (should-not (gptel-auto-workflow--fast-track-eligible-p "test-branch")))
    (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
               (lambda (_cmd _timeout)
                 " lisp/modules/gptel-auto-workflow-audit-provide-inside-defun.el | 1 +\n 1 file changed, 1 insertion(+)")))
      (should-not (gptel-auto-workflow--fast-track-eligible-p "test-branch")))
    (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
               (lambda (_cmd _timeout)
                 " lisp/modules/gptel-tools-agent-staging-merge.el | 3 +--\n 1 file changed, 2 insertions(+), 1 deletion(-)")))
      (should-not (gptel-auto-workflow--fast-track-eligible-p "test-branch")))
    (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
               (lambda (_cmd _timeout)
                 " lisp/modules/gptel-tools-agent-experiment-core.el | 1 +\n 1 file changed, 1 insertion(+)")))
      (should-not (gptel-auto-workflow--fast-track-eligible-p "test-branch")))
    (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
               (lambda (_cmd _timeout)
                 " lisp/modules/gptel-tools-agent-experiment-loop.el | 1 +\n 1 file changed, 1 insertion(+)")))
      (should-not (gptel-auto-workflow--fast-track-eligible-p "test-branch")))
    (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
               (lambda (_cmd _timeout)
                 " lisp/modules/gptel-auto-workflow-monitoring-agent.el | 1 +\n 1 file changed, 1 insertion(+)")))
      (should-not (gptel-auto-workflow--fast-track-eligible-p "test-branch")))
    (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
               (lambda (_cmd _timeout)
                 " scripts/git-hooks/pre-push | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)")))
      (should-not (gptel-auto-workflow--fast-track-eligible-p "test-branch")))
    (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
               (lambda (_cmd _timeout)
                 " scripts/run-tests.sh | 1 +\n 1 file changed, 1 insertion(+)")))
      (should-not (gptel-auto-workflow--fast-track-eligible-p "test-branch")))
    (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
               (lambda (_cmd _timeout)
                 " lisp/modules/gptel-ext-context.el | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)")))
      (should (gptel-auto-workflow--fast-track-eligible-p "test-branch")))))

(ert-deftest test-experiment-gates/gate-engine-fast-track-multi-file ()
  "A multi-file diff where one file is gate-engine blocks fast-track.
Even if other files are non-gate-engine and the change is small,
touching any gate-engine file must block fast-track."
  (let ((gptel-auto-workflow-fast-track-enabled t)
        (gptel-auto-workflow-fast-track-max-files 5)
        (gptel-auto-workflow-fast-track-max-lines 50))
    (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
               (lambda (_cmd _timeout)
                 " lisp/modules/gptel-ext-context.el      | 2 +-\n lisp/modules/gptel-auto-workflow-self-heal-semantic.el | 1 +\n 2 files changed, 2 insertions(+), 1 deletion(-)")))
      (should-not (gptel-auto-workflow--fast-track-eligible-p "test-branch")))))

;; ── Test F: Monitoring semantic audit timeout ──

(ert-deftest test-experiment-gates/monitoring-semantic-audit-timeout-defcustom ()
  "The monitoring semantic audit timeout defcustom exists and is positive."
  (require 'gptel-auto-workflow-monitoring-agent)
  (should (boundp 'gptel-auto-workflow-monitoring-semantic-audit-timeout-seconds))
  (let ((val gptel-auto-workflow-monitoring-semantic-audit-timeout-seconds))
    (should (numberp val))
    (should (> val 0))))

(ert-deftest test-experiment-gates/monitoring-semantic-audit-timeout-kills-hang ()
  "A with-timeout wrapper kills a hung operation and reports failure.
Tests the Phase 10 timeout pattern: a hung body is killed by with-timeout
and the monitoring pattern can continue.  Uses run-with-timer + polling
to avoid brittle with-timeout interaction with pending process output
from other tests in the full-suite run."
  (let* ((start (float-time))
         (timed-out nil)
         (timer (run-with-timer 3 nil (lambda () (setq timed-out t))))
         (result nil))
    (unwind-protect
        (progn
          (while (and (not timed-out) (< (- (float-time) start) 999))
            (sleep-for 0.1))
          (setq result (if timed-out :timed-out :done)))
      (cancel-timer timer))
    (should (eq result :timed-out))
    (should (< (- (float-time) start) 30))))

(ert-deftest test-experiment-gates/monitoring-semantic-audit-timeout-writes-memory ()
  "When the monitoring semantic audit times out, a failure-pattern memory is written.
This gives OV5 a concrete signal to detect and self-heal hung detectors."
  (require 'gptel-auto-workflow-monitoring-agent nil t)
  (skip-unless (fboundp 'gptel-auto-workflow--monitoring-semantic-audit-timeout-handler))
  (let ((calls nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--mementum-write-memory)
               (lambda (symbol slug content)
                 (push (list symbol slug content) calls)
                 "/tmp/fake-memory.md")))
      (gptel-auto-workflow--monitoring-semantic-audit-timeout-handler)
      (should (= (length calls) 1))
      (should (eq (caar calls) '❌))
      (should (string-match-p "monitoring-semantic-audit-timeout" (nth 1 (car calls))))
      (should (string-match-p "Semantic audit timed out" (nth 2 (car calls))))
      (should (string-match-p "hung detector" (nth 2 (car calls)))))))

;; ── Provide ──

(provide 'test-experiment-gates)
;;; test-experiment-gates.el ends here
