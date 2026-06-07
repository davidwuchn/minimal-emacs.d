;;; test-gptel-auto-workflow-context-database.el --- Tests for causal/business context database -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: tests, context, database, business-context, causal-chain

;;; Commentary:

;; ERT tests for the sidecar-based context database.
;; Covers all 8 public functions + backward-compat aliases.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-context-database)

;; ============================================================================
;; Test Fixtures
;; ============================================================================

(defvar test-context-db--tmp-dir nil
  "Temporary directory for test sidecar files.")

(defun test-context-database--setup ()
  "Set up temp directory and stub project-root for testing."
  (setq test-context-db--tmp-dir
        (make-temp-file "context-db-test" t))
  (let ((context-dir (expand-file-name gptel-auto-workflow-context-db-dir
                                        test-context-db--tmp-dir)))
    (unless (file-directory-p context-dir)
      (make-directory context-dir t)))
  ;; Stub gptel-auto-workflow--project-root to return tmp dir
  (cl-letf (((symbol-function 'gptel-auto-workflow--project-root)
             (lambda () test-context-db--tmp-dir))
            ((symbol-function 'gptel-auto-workflow--plist-get)
             (lambda (plist key &optional default)
               (let ((val (plist-get plist key)))
                 (if val val default))))
            ((symbol-function 'gptel-auto-workflow-context-db--derive-dependencies)
             (lambda (_target) nil)))
    t))

(defun test-context-database--teardown ()
  "Clean up temp directory."
  (when (and test-context-db--tmp-dir (file-directory-p test-context-db--tmp-dir))
    (delete-directory test-context-db--tmp-dir t))
  (setq test-context-db--tmp-dir nil))

(defmacro test-context-db--with-env (&rest body)
  "Execute BODY with test environment (stubs + cleanup)."
  `(unwind-protect
       (progn
         (test-context-database--setup)
         (cl-letf (((symbol-function 'gptel-auto-workflow--project-root)
                    (lambda () test-context-db--tmp-dir))
                   ((symbol-function 'gptel-auto-workflow--plist-get)
                    (lambda (plist key &optional default)
                      (let ((val (plist-get plist key)))
                        (if val val default))))
                   ((symbol-function 'gptel-auto-workflow-context-db--derive-dependencies)
                    (lambda (_target) nil)))
           ,@body))
     (test-context-database--teardown)))

;; ============================================================================
;; Test: capture and read
;; ============================================================================

(ert-deftest test-context-database/capture-and-read ()
  "Should capture context and read it back from sidecar."
  (test-context-db--with-env
   (let ((experiment '(:id 17
                       :target "lisp/modules/foo.el"
                       :hypothesis "Add nil guard around X to prevent wrong-type-argument in Y."
                       :decision "kept"
                       :score-before 0.51
                       :score-after 0.67
                       :grader-reason "Good nil handling improvement"
                       :comparator-reason "Expected reliability gain confirmed"
                       :business-value-score 0.4
                       :risk-score 0.2
                       :strategy "template-default"
                       :model "gpt-5.4"
                       :duration 84)))
     (let ((ctx (gptel-auto-workflow-context-db-capture experiment)))
       (should ctx)
       (should (= 17 (plist-get ctx :id)))
       (should (string= "lisp/modules/foo.el" (plist-get ctx :target)))
       (should (string= "Add nil guard around X to prevent wrong-type-argument in Y."
                        (plist-get ctx :hypothesis)))
       (should (string= "kept" (plist-get ctx :decision)))
       (should (= 0.51 (plist-get ctx :score-before)))
       (should (= 0.67 (plist-get ctx :score-after)))
       (should (= 0.4 (plist-get ctx :business-value-score)))
       (should (= 0.2 (plist-get ctx :risk-score)))
       ;; Read back from file
       (let ((read-ctx (gptel-auto-workflow-context-db-read 17)))
         (should read-ctx)
         (should (= 17 (plist-get read-ctx :id)))
         (should (string= "lisp/modules/foo.el" (plist-get read-ctx :target))))))))

;; ============================================================================
;; Test: business rationale derivation — nil guard
;; ============================================================================

(ert-deftest test-context-database/capture-nil-guard-rationale ()
  "Should derive 'reduce runtime failures' for nil guard hypothesis."
  (test-context-db--with-env
   (let ((experiment '(:id 1 :target "bar.el"
                       :hypothesis "Add nil guard to prevent crash"
                       :decision "kept" :score-before 0.3 :score-after 0.5)))
     (let ((ctx (gptel-auto-workflow-context-db-capture experiment)))
       (should ctx)
       (should (string-match-p "runtime failures" (plist-get ctx :business-rationale)))))))

;; ============================================================================
;; Test: business rationale derivation — refactor
;; ============================================================================

(ert-deftest test-context-database/capture-refactor-rationale ()
  "Should derive 'lower maintenance cost' for refactor hypothesis."
  (test-context-db--with-env
   (let ((experiment '(:id 2 :target "baz.el"
                       :hypothesis "Refactor to simplify complex logic"
                       :decision "kept" :score-before 0.4 :score-after 0.6)))
     (let ((ctx (gptel-auto-workflow-context-db-capture experiment)))
       (should ctx)
       (should (string-match-p "maintenance cost" (plist-get ctx :business-rationale)))))))

;; ============================================================================
;; Test: query by target
;; ============================================================================

(ert-deftest test-context-database/query-by-target ()
  "Should query contexts by target and return matching results."
  (test-context-db--with-env
   (gptel-auto-workflow-context-db-capture
    '(:id 10 :target "module-a.el" :hypothesis "Test A"
      :decision "kept" :score-before 0.3 :score-after 0.5))
   (gptel-auto-workflow-context-db-capture
    '(:id 11 :target "module-a.el" :hypothesis "Test B"
      :decision "kept" :score-before 0.4 :score-after 0.6))
   (gptel-auto-workflow-context-db-capture
    '(:id 12 :target "module-b.el" :hypothesis "Test C"
      :decision "kept" :score-before 0.3 :score-after 0.5))
   (let ((results (gptel-auto-workflow-context-db-query :target "module-a.el")))
     (should (= 2 (length results)))
     (should (cl-every (lambda (ctx) (string= "module-a.el" (plist-get ctx :target)))
                       results)))))

;; ============================================================================
;; Test: query by decision
;; ============================================================================

(ert-deftest test-context-database/query-by-decision ()
  "Should query contexts by decision and return matching results."
  (test-context-db--with-env
   (gptel-auto-workflow-context-db-capture
    '(:id 20 :target "x.el" :hypothesis "H"
      :decision "kept" :score-before 0.3 :score-after 0.5))
   (gptel-auto-workflow-context-db-capture
    '(:id 21 :target "y.el" :hypothesis "H2"
      :decision "rejected" :score-before 0.3 :score-after 0.3))
   (let ((kept (gptel-auto-workflow-context-db-query :decision "kept")))
     (should (= 1 (length kept)))
      (should (string= "kept" (plist-get (car kept) :decision))))
   (let ((rejected (gptel-auto-workflow-context-db-query :decision "rejected")))
     (should (= 1 (length rejected))))))

;; ============================================================================
;; Test: update observed impact
;; ============================================================================

(ert-deftest test-context-database/update-observed-impact ()
  "Should update observed-impact field in sidecar."
  (test-context-db--with-env
   (gptel-auto-workflow-context-db-capture
    '(:id 30 :target "mod.el" :hypothesis "H"
      :decision "kept" :score-before 0.4 :score-after 0.6))
   (let ((updated (gptel-auto-workflow-context-db-update-observed-impact
                   30 "Error rate dropped from 12% to 3%.")))
     (should updated)
     (should (string= "Error rate dropped from 12% to 3%."
                      (plist-get updated :observed-impact))))
   ;; Re-read to verify persistence
   (let ((ctx (gptel-auto-workflow-context-db-read 30)))
     (should (string= "Error rate dropped from 12% to 3%."
                      (plist-get ctx :observed-impact))))))

;; ============================================================================
;; Test: dependencies
;; ============================================================================

(ert-deftest test-context-database/dependencies ()
  "Should return experiment IDs that reference a target in their dependencies."
  (test-context-db--with-env
   ;; Stub derive-dependencies to return a known list for one target
   (cl-letf (((symbol-function 'gptel-auto-workflow-context-db--derive-dependencies)
              (lambda (target)
                (cond
                 ((string= target "lisp/modules/core.el")
                  (list "lisp/modules/utils.el"))
                 (t nil)))))
     (gptel-auto-workflow-context-db-capture
      '(:id 40 :target "lisp/modules/core.el" :hypothesis "H"
        :decision "kept" :score-before 0.4 :score-after 0.6))
     (gptel-auto-workflow-context-db-capture
      '(:id 41 :target "lisp/modules/other.el" :hypothesis "H2"
        :decision "kept" :score-before 0.3 :score-after 0.5))
     ;; Now query: which experiments depend on "lisp/modules/utils.el"?
     ;; Only experiment 40 has utils.el in its :dependencies
     (let ((dep-ids (gptel-auto-workflow-context-db-dependencies "lisp/modules/utils.el")))
       (should (member 40 dep-ids))))))

;; ============================================================================
;; Test: summary for target
;; ============================================================================

(ert-deftest test-context-database/summary-for-target ()
  "Should return aggregated summary for all contexts targeting a module."
  (test-context-db--with-env
   (gptel-auto-workflow-context-db-capture
    '(:id 50 :target "summod.el" :hypothesis "Test A"
      :decision "kept" :score-before 0.3 :score-after 0.5
      :business-value-score 0.4))
   (gptel-auto-workflow-context-db-capture
    '(:id 51 :target "summod.el" :hypothesis "Test B"
      :decision "kept" :score-before 0.4 :score-after 0.7
      :business-value-score 0.5))
   (gptel-auto-workflow-context-db-capture
    '(:id 52 :target "summod.el" :hypothesis "Test C"
      :decision "rejected" :score-before 0.3 :score-after 0.3
      :business-value-score 0.1))
   (let ((summary (gptel-auto-workflow-context-db-summary-for-target "summod.el")))
     (should (= 3 (plist-get summary :total-experiments)))
     (should (= 2 (plist-get summary :kept-count)))
     (should (= 1 (plist-get summary :rejected-count)))
     (should (<= (plist-get summary :avg-score-before) 0.35))
     (should (>= (plist-get summary :avg-score-after) 0.45))
     (should (>= (plist-get summary :avg-business-value-score) 0.3)))))

;; ============================================================================
;; Test: search
;; ============================================================================

(ert-deftest test-context-database/search ()
  "Should full-text search over narrative fields."
  (test-context-db--with-env
   (gptel-auto-workflow-context-db-capture
    '(:id 60 :target "mod1.el" :hypothesis "Add nil guard for safety"
      :decision "kept" :score-before 0.3 :score-after 0.5))
   (gptel-auto-workflow-context-db-capture
    '(:id 61 :target "mod2.el" :hypothesis "Refactor complex code"
      :decision "rejected" :score-before 0.4 :score-after 0.4))
   ;; Search for "nil guard" — should match experiment 60
   (let ((results (gptel-auto-workflow-context-db-search "nil guard")))
     (should (= 1 (length results)))
     (should (= 60 (plist-get (car results) :id))))
   ;; Search for "runtime failures" — should match via business-rationale
   (let ((results (gptel-auto-workflow-context-db-search "runtime")))
     (should (>= (length results) 1)))))

;; ============================================================================
;; Test: all-ids
;; ============================================================================

(ert-deftest test-context-database/all-ids ()
  "Should return sorted list of all experiment IDs with context sidecars."
  (test-context-db--with-env
   (gptel-auto-workflow-context-db-capture
    '(:id 100 :target "a.el" :hypothesis "H" :decision "kept" :score-before 0.3 :score-after 0.5))
   (gptel-auto-workflow-context-db-capture
    '(:id 50 :target "b.el" :hypothesis "H" :decision "kept" :score-before 0.3 :score-after 0.5))
   (gptel-auto-workflow-context-db-capture
    '(:id 75 :target "c.el" :hypothesis "H" :decision "kept" :score-before 0.3 :score-after 0.5))
   (let ((ids (gptel-auto-workflow-context-db-all-ids)))
     (should (= 3 (length ids)))
     (should (equal ids '(50 75 100))))))

;; ============================================================================
;; Test: read nonexistent
;; ============================================================================

(ert-deftest test-context-database/read-nonexistent ()
  "Should return nil when reading nonexistent experiment ID."
  (test-context-db--with-env
   (let ((ctx (gptel-auto-workflow-context-db-read 999)))
     (should (null ctx)))))

;; ============================================================================
;; Test: backward-compat aliases
;; ============================================================================

(ert-deftest test-context-database/backward-compat-aliases ()
  "Should have backward-compatible function aliases."
  (should (fboundp 'gptel-auto-workflow--capture-experiment-context))
  (should (fboundp 'gptel-auto-workflow--capture-context))
  (should (fboundp 'gptel-auto-workflow--get-context))
  (should (fboundp 'gptel-auto-workflow--context-db-load))
  (should (fboundp 'gptel-auto-workflow--context-db-persist))
  (should (fboundp 'gptel-auto-workflow--context-db-init))
  (should (fboundp 'gptel-auto-workflow--context-db-configured-p))
  (should (fboundp 'gptel-auto-workflow--get-context-summary))
  ;; Verify they work
  (should (gptel-auto-workflow--context-db-init '(:anything t)))
  (should (gptel-auto-workflow--context-db-configured-p))
  (should (gptel-auto-workflow--context-db-load))
  (should (gptel-auto-workflow--context-db-persist)))

;; ============================================================================
;; Test: module loads without errors
;; ============================================================================

(ert-deftest test-context-database/module-loads ()
  "Context database module should load without errors."
  :expected-result :passed
  (should (fboundp 'gptel-auto-workflow-context-db-capture))
  (should (fboundp 'gptel-auto-workflow-context-db-read))
  (should (fboundp 'gptel-auto-workflow-context-db-query))
  (should (fboundp 'gptel-auto-workflow-context-db-update-observed-impact))
  (should (fboundp 'gptel-auto-workflow-context-db-dependencies))
  (should (fboundp 'gptel-auto-workflow-context-db-summary-for-target))
  (should (fboundp 'gptel-auto-workflow-context-db-search))
  (should (fboundp 'gptel-auto-workflow-context-db-all-ids)))

;; ============================================================================
;; Test: causal chain derivation
;; ============================================================================

(ert-deftest test-context-database/causal-chain ()
  "Should derive causal chain from hypothesis and decision."
  (test-context-db--with-env
   (let ((experiment '(:id 70 :target "x.el"
                       :hypothesis "Add nil guard for crash prevention"
                       :decision "kept" :score-before 0.3 :score-after 0.5)))
     (let ((ctx (gptel-auto-workflow-context-db-capture experiment)))
       (should ctx)
       (let ((chain (plist-get ctx :causal-chain)))
         (should chain)
         (should (consp (car chain)))
         (should (string= "missing nil guard" (car (car chain)))))))))

;; ============================================================================
;; Test: decision rationale derivation
;; ============================================================================

(ert-deftest test-context-database/decision-rationale ()
  "Should derive decision rationale from decision and comparator-reason."
  (test-context-db--with-env
   (let ((experiment '(:id 80 :target "x.el"
                       :hypothesis "H"
                       :decision "kept"
                       :comparator-reason "Expected user-facing reliability gain confirmed"
                       :score-before 0.3 :score-after 0.5)))
     (let ((ctx (gptel-auto-workflow-context-db-capture experiment)))
       (should ctx)
       (should (string-match-p "Approved because" (plist-get ctx :decision-rationale)))))))

;; ============================================================================
;; Test: backward-compat capture via alias
;; ============================================================================

(ert-deftest test-context-database/backward-compat-capture ()
  "Should capture context via backward-compat alias."
  (test-context-db--with-env
   (let ((experiment '(:id 90 :target "alias.el" :hypothesis "H"
                       :decision "kept" :score-before 0.3 :score-after 0.5)))
     (let ((ctx (gptel-auto-workflow--capture-experiment-context experiment)))
       (should ctx)
       (should (= 90 (plist-get ctx :id))))
     ;; Also test --capture-context alias
     (let ((ctx2 (gptel-auto-workflow--capture-context
                  '(:id 91 :target "alias2.el" :hypothesis "H2"
                    :decision "kept" :score-before 0.4 :score-after 0.6))))
       (should ctx2)
       (should (= 91 (plist-get ctx2 :id)))))))

;; ============================================================================
;; Test: backward-compat get-context via alias
;; ============================================================================

(ert-deftest test-context-database/backward-compat-get-context ()
  "Should read context via backward-compat alias --get-context."
  (test-context-db--with-env
   (gptel-auto-workflow-context-db-capture
    '(:id 95 :target "compat.el" :hypothesis "H"
      :decision "kept" :score-before 0.3 :score-after 0.5))
    (let ((ctx (gptel-auto-workflow--get-context 95)))
      (should ctx)
      (should (= 95 (plist-get ctx :id))))))

(provide 'test-gptel-auto-workflow-context-database)

;;; test-gptel-auto-workflow-context-database.el ends here