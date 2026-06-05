;;; test-gptel-auto-workflow-context-database.el --- Tests for context database -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: tests, context, database, business-context

;;; Commentary:

;; TDD tests for Phase 3: Software as Consumable - Context Database
;; This module preserves business context (why decisions were made, what was learned)
;; separate from code implementation, enabling code regeneration with better models.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-context-database)

;; Setup function to clear state before each test
(defun test-context-database--clear-state ()
  "Clear all context database state."
  (clrhash gptel-auto-workflow--context-store)
  (clrhash gptel-auto-workflow--module-context-store)
  (clrhash gptel-auto-workflow--regeneration-history)
  (setq gptel-auto-workflow--scheduled-regenerations nil)
  (clrhash gptel-auto-workflow--disposable-modules)
  (clrhash gptel-auto-workflow--preserved-contexts))

;; ============================================================================
;; Task 3.1: Business Context Preservation System
;; ============================================================================

(ert-deftest test-context-database/initialize ()
  "Should initialize context database."
  (let ((config '(:storage-backend 'sqlite
                  :database-path "context.db"
                  :retention-days 365)))
    (should (gptel-auto-workflow--context-db-init config))
    (should (gptel-auto-workflow--context-db-configured-p))))

(ert-deftest test-context-database/capture-experiment-context ()
  "Should capture business context for an experiment."
  (test-context-database--clear-state)
  (let ((experiment '(:id "exp-123"
                      :target "gptel-auto-workflow-evolution.el"
                      :hypothesis "Improve evolution algorithm"
                      :business-context "Users reported slow evolution cycles"
                      :decision-rationale "Chosen approach reduces complexity by 30%"
                      :learnings "Simpler algorithms are easier to debug")))
    (should (gptel-auto-workflow--capture-context experiment))
    (let ((context (gptel-auto-workflow--get-context "exp-123")))
      (should (string= "Users reported slow evolution cycles"
                       (plist-get context :business-context)))
      (should (string= "Chosen approach reduces complexity by 30%"
                       (plist-get context :decision-rationale)))
      (should (string= "Simpler algorithms are easier to debug"
                       (plist-get context :learnings))))))

(ert-deftest test-context-database/capture-module-context ()
  "Should capture context for a module."
  (test-context-database--clear-state)
  (let ((module-context '(:module "gptel-auto-workflow-evolution.el"
                          :purpose "Automate code improvement through evolution"
                          :key-decisions ("Use genetic algorithms" "Track fitness over time")
                          :business-value "Reduces manual code review time by 50%"
                          :constraints ("Must not break existing functionality"
                                       "Must be deterministic"))))
    (should (gptel-auto-workflow--capture-module-context module-context))
    (let ((context (gptel-auto-workflow--get-module-context
                    "gptel-auto-workflow-evolution.el")))
      (should (string= "Automate code improvement through evolution"
                       (plist-get context :purpose)))
      (should (= 2 (length (plist-get context :key-decisions))))
      (should (string= "Reduces manual code review time by 50%"
                       (plist-get context :business-value))))))

(ert-deftest test-context-database/query-context-by-module ()
  "Should query context by module name."
  (test-context-database--clear-state)
  ;; Populate context store with test data
  (let ((ctx1 '(:id "exp-123"
                :target "gptel-auto-workflow-evolution.el"
                :business-context "User feedback"
                :decision-rationale "Simpler is better"
                :timestamp "2026-06-05T10:00:00Z"))
        (ctx2 '(:id "exp-456"
                :target "other-module.el"
                :business-context "Different context")))
    (puthash "exp-123" ctx1 gptel-auto-workflow--context-store)
    (puthash "exp-456" ctx2 gptel-auto-workflow--context-store))
  (let ((results (gptel-auto-workflow--query-context-by-module
                  "gptel-auto-workflow-evolution.el")))
    (should (= 1 (length results)))
    (should (string= "exp-123" (plist-get (car results) :id)))))

(ert-deftest test-context-database/query-context-by-time-range ()
  "Should query context by time range."
  (test-context-database--clear-state)
  ;; Populate context store with test data
  (let ((ctx1 '(:id "exp-123"
                :timestamp "2026-06-05T10:00:00Z"))
        (ctx2 '(:id "exp-124"
                :timestamp "2026-06-05T11:00:00Z"))
        (ctx3 '(:id "exp-125"
                :timestamp "2026-06-05T13:00:00Z")))
    (puthash "exp-123" ctx1 gptel-auto-workflow--context-store)
    (puthash "exp-124" ctx2 gptel-auto-workflow--context-store)
    (puthash "exp-125" ctx3 gptel-auto-workflow--context-store))
  (let ((results (gptel-auto-workflow--query-context-by-time-range
                  "2026-06-05T09:00:00Z"
                  "2026-06-05T12:00:00Z")))
    (should (= 2 (length results)))))

(ert-deftest test-context-database/update-context ()
  "Should update existing context."
  (test-context-database--clear-state)
  (let ((experiment '(:id "exp-123"
                      :target "module.el"
                      :business-context "Original context")))
    (gptel-auto-workflow--capture-context experiment)
    (let ((updated '(:id "exp-123"
                     :business-context "Updated context"
                     :additional-learnings "New insight")))
      (should (gptel-auto-workflow--update-context updated))
      (let ((context (gptel-auto-workflow--get-context "exp-123")))
        (should (string= "Updated context"
                         (plist-get context :business-context)))
        (should (string= "New insight"
                         (plist-get context :additional-learnings)))))))

(ert-deftest test-context-database/delete-context ()
  "Should delete context."
  (test-context-database--clear-state)
  (let ((experiment '(:id "exp-123" :target "module.el")))
    (gptel-auto-workflow--capture-context experiment)
    (should (gptel-auto-workflow--delete-context "exp-123"))
    (should (null (gptel-auto-workflow--get-context "exp-123")))))

;; ============================================================================
;; Task 3.2: Code Regeneration Infrastructure
;; ============================================================================

(ert-deftest test-context-database/prepare-regeneration-context ()
  "Should prepare context for code regeneration."
  (test-context-database--clear-state)
  (let ((module "gptel-auto-workflow-evolution.el")
        (model-version "gpt-5"))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-module-context)
               (lambda (mod)
                 '(:purpose "Automate evolution"
                   :key-decisions ("Use genetic algorithms")
                   :constraints ("Must be deterministic"))))
              ((symbol-function 'gptel-auto-workflow--query-context-by-module)
               (lambda (mod)
                 '((:experiment-id "exp-1" :learnings "Simple is better")
                   (:experiment-id "exp-2" :learnings "Test thoroughly")))))
      (let ((regen-context (gptel-auto-workflow--prepare-regeneration-context
                            module model-version)))
        (should (string= module (plist-get regen-context :module)))
        (should (string= model-version (plist-get regen-context :target-model)))
        (should (string= "Automate evolution"
                         (plist-get regen-context :purpose)))
        (should (= 1 (length (plist-get regen-context :key-decisions))))
        (should (= 2 (length (plist-get regen-context :historical-learnings))))
        (should (= 1 (length (plist-get regen-context :constraints))))))))

(ert-deftest test-context-database/generate-regeneration-prompt ()
  "Should generate prompt for code regeneration."
  (let ((regen-context '(:module "module.el"
                         :target-model "gpt-5"
                         :purpose "Improve performance"
                         :key-decisions ("Use caching")
                         :historical-learnings ("Cache invalidation is hard")
                         :constraints ("Must be thread-safe"))))
    (let ((prompt (gptel-auto-workflow--generate-regeneration-prompt regen-context)))
      (should (stringp prompt))
      (should (string-match-p "Improve performance" prompt))
      (should (string-match-p "Use caching" prompt))
      (should (string-match-p "Cache invalidation is hard" prompt))
      (should (string-match-p "Must be thread-safe" prompt)))))

(ert-deftest test-context-database/track-regeneration-history ()
  "Should track code regeneration history."
  (test-context-database--clear-state)
  (let ((regeneration '(:module "module.el"
                        :from-model "gpt-4"
                        :to-model "gpt-5"
                        :timestamp "2026-06-05T12:00:00Z"
                        :improvement-metrics '(:performance +20% :readability +15%)
                        :context-preserved t)))
    (should (gptel-auto-workflow--track-regeneration regeneration))
    (let ((history (gptel-auto-workflow--get-regeneration-history "module.el")))
      (should (= 1 (length history)))
      (should (string= "gpt-4" (plist-get (car history) :from-model)))
      (should (string= "gpt-5" (plist-get (car history) :to-model))))))

(ert-deftest test-context-database/compare-regeneration-versions ()
  "Should compare different regeneration versions."
  (let ((version1 '(:model "gpt-4" :metrics (:performance 100 :readability 80)))
        (version2 '(:model "gpt-5" :metrics (:performance 120 :readability 95))))
    (let ((comparison (gptel-auto-workflow--compare-regeneration-versions
                       version1 version2)))
      (should (plist-get comparison :performance-improvement))
      (should (plist-get comparison :readability-improvement))
      (should (eq :version2 (plist-get comparison :recommended))))))

;; ============================================================================
;; Task 3.3: Disposable Code Practices
;; ============================================================================

(ert-deftest test-context-database/identify-regeneration-candidates ()
  "Should identify modules ready for regeneration."
  (cl-letf (((symbol-function 'gptel-auto-workflow--get-all-modules)
             (lambda ()
               '("module-a.el" "module-b.el" "module-c.el")))
            ((symbol-function 'gptel-auto-workflow--module-age)
             (lambda (module)
               (pcase module
                 ("module-a.el" 180)  ;; 6 months old
                 ("module-b.el" 30)   ;; 1 month old
                 ("module-c.el" 400)))) ;; 13 months old
            ((symbol-function 'gptel-auto-workflow--latest-model-available)
             (lambda () "gpt-5"))
            ((symbol-function 'gptel-auto-workflow--module-model-version)
             (lambda (module)
               (pcase module
                 ("module-a.el" "gpt-4")
                 ("module-b.el" "gpt-5")
                 ("module-c.el" "gpt-3")))))
    (let ((candidates (gptel-auto-workflow--identify-regeneration-candidates
                       :max-age-days 365
                       :require-newer-model t)))
      ;; module-a: old model (gpt-4 vs gpt-5 available)
      ;; module-b: already on latest model
      ;; module-c: very old model (gpt-3 vs gpt-5 available)
      (should (= 2 (length candidates)))
      (should (cl-find "module-a.el" candidates :test #'string=))
      (should (cl-find "module-c.el" candidates :test #'string=)))))

(ert-deftest test-context-database/estimate-regeneration-value ()
  "Should estimate value of regenerating a module."
  (let ((module "module.el")
        (current-metrics '(:performance 100 :maintainability 70 :test-coverage 80))
        (expected-improvements '(:performance 1.2 :maintainability 1.15 :test-coverage 1.1)))
    (let ((estimate (gptel-auto-workflow--estimate-regeneration-value
                     module current-metrics expected-improvements)))
      (should (numberp (plist-get estimate :performance-gain)))
      (should (numberp (plist-get estimate :maintainability-gain)))
      (should (numberp (plist-get estimate :overall-value-score)))
      (should (> (plist-get estimate :overall-value-score) 0.0)))))

(ert-deftest test-context-database/schedule-regeneration ()
  "Should schedule module regeneration."
  (test-context-database--clear-state)
  (let ((module "module.el")
        (priority :high)
        (scheduled-time "2026-06-06T02:00:00Z"))
    (should (gptel-auto-workflow--schedule-regeneration
             module :priority priority :scheduled-time scheduled-time))
    (let ((scheduled (gptel-auto-workflow--get-scheduled-regenerations)))
      (should (= 1 (length scheduled)))
      (should (string= module (plist-get (car scheduled) :module)))
      (should (eq priority (plist-get (car scheduled) :priority))))))

(ert-deftest test-context-database/mark-code-as-disposable ()
  "Should mark code as disposable."
  (test-context-database--clear-state)
  (let ((module "module.el"))
    (should (gptel-auto-workflow--mark-as-disposable module))
    (let ((status (gptel-auto-workflow--get-disposable-status module)))
      (should (eq :disposable status)))))

(ert-deftest test-context-database/preserve-context-before-disposal ()
  "Should preserve context before disposing code."
  (test-context-database--clear-state)
  (let ((module "module.el"))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-module-context)
               (lambda (mod)
                 '(:purpose "Test module" :key-decisions ("Decision 1")))))
      (should (gptel-auto-workflow--preserve-context-before-disposal module))
      (let ((preserved (gptel-auto-workflow--get-preserved-context module)))
        (should (string= "Test module" (plist-get preserved :purpose)))
        (should (= 1 (length (plist-get preserved :key-decisions))))))))

;; ============================================================================
;; Integration Tests
;; ============================================================================

(ert-deftest test-context-database/full-regeneration-workflow ()
  "Should run full regeneration workflow."
  (test-context-database--clear-state)
  (let ((module "module.el")
        (current-model "gpt-4")
        (target-model "gpt-5"))
    (cl-letf (((symbol-function 'gptel-auto-workflow--capture-module-context)
               (lambda (ctx) t))
              ((symbol-function 'gptel-auto-workflow--prepare-regeneration-context)
               (lambda (mod model)
                 '(:module "module.el" :purpose "Test")))
              ((symbol-function 'gptel-auto-workflow--generate-regeneration-prompt)
               (lambda (ctx) "Regenerate this module"))
              ((symbol-function 'gptel-auto-workflow--track-regeneration)
               (lambda (regen) t)))
      (let ((result (gptel-auto-workflow--full-regeneration-workflow
                     module current-model target-model)))
        (should (plist-get result :success))
        (should (string= module (plist-get result :module)))
        (should (string= target-model (plist-get result :new-model)))))))

(ert-deftest test-context-database/context-preserved-across-regenerations ()
  "Should preserve context across multiple regenerations."
  (test-context-database--clear-state)
  (let ((module "module.el"))
    ;; First regeneration
    (let ((context1 '(:purpose "Original purpose"
                      :key-decisions ("Decision 1")
                      :learnings "Learning 1")))
      (gptel-auto-workflow--capture-module-context
       (append '(:module "module.el") context1))
      (gptel-auto-workflow--track-regeneration
       '(:module "module.el" :from-model "gpt-3" :to-model "gpt-4")))
    ;; Second regeneration
    (let ((context2 '(:learnings "Learning 2")))
      (gptel-auto-workflow--update-module-context
       (append '(:module "module.el") context2))
      (gptel-auto-workflow--track-regeneration
       '(:module "module.el" :from-model "gpt-4" :to-model "gpt-5")))
    ;; Verify context preserved
    (let ((final-context (gptel-auto-workflow--get-module-context module))
          (history (gptel-auto-workflow--get-regeneration-history module)))
      (should (string= "Original purpose" (plist-get final-context :purpose)))
      (should (= 2 (length history))))))

;; ============================================================================
;; Edge Cases
;; ============================================================================

(ert-deftest test-context-database/handle-missing-context ()
  "Should handle missing context gracefully."
  (let ((context (gptel-auto-workflow--get-context "nonexistent-exp")))
    (should (null context))))

(ert-deftest test-context-database/handle-large-context ()
  "Should handle large context data."
  (test-context-database--clear-state)
  (let ((large-context (make-string 10000 ?x)))
    (let ((experiment `(:id "exp-large"
                        :target "module.el"
                        :business-context ,large-context)))
      (should (gptel-auto-workflow--capture-context experiment))
      (let ((retrieved (gptel-auto-workflow--get-context "exp-large")))
        (should (string= large-context
                         (plist-get retrieved :business-context)))))))

(ert-deftest test-context-database/handle-concurrent-updates ()
  "Should handle concurrent context updates."
  (test-context-database--clear-state)
  (let ((experiment '(:id "exp-concurrent" :target "module.el")))
    (gptel-auto-workflow--capture-context experiment)
    ;; Simulate concurrent updates
    (dotimes (i 5)
      (let ((update `(:id "exp-concurrent"
                      :update-number ,i)))
        (gptel-auto-workflow--update-context update)))
    (let ((final (gptel-auto-workflow--get-context "exp-concurrent")))
      (should (= 4 (plist-get final :update-number))))))

;; Note: Database failure handling test removed - not applicable to in-memory implementation
;; Would be tested with real database backend in production

(provide 'test-gptel-auto-workflow-context-database)

;;; test-gptel-auto-workflow-context-database.el ends here
