;;; test-gptel-auto-workflow-code-regeneration.el --- Tests for code regeneration module -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-code-regeneration)
(require 'gptel-auto-workflow-context-database)

;; ============================================================================
;; Tests: prompt-override variable
;; ============================================================================

(ert-deftest test-regen/prompt-override-var-exists ()
  (should (boundp 'gptel-auto-workflow--experiment-prompt-override)))

(ert-deftest test-regen/prompt-override-default-nil ()
  (should (null gptel-auto-workflow--experiment-prompt-override)))

;; ============================================================================
;; Tests: backward-compat defaliases exist
;; ============================================================================

(ert-deftest test-regen/backward-compat-aliases-exist ()
  (should (fboundp 'gptel-auto-workflow--prepare-regeneration-context))
  (should (fboundp 'gptel-auto-workflow--generate-regeneration-prompt))
  (should (fboundp 'gptel-auto-workflow--identify-regeneration-candidates))
  (should (fboundp 'gptel-auto-workflow--full-regeneration-workflow)))

;; ============================================================================
;; Tests: backward-compat aliases callable
;; ============================================================================

(ert-deftest test-regen/backward-compat-generate-prompt-alias-callable ()
  (let* ((ctx (list :module "test.el" :target-model "v2"
                    :purpose "P" :model-stats nil))
         (via-alias (gptel-auto-workflow--generate-regeneration-prompt ctx))
         (via-new (gptel-auto-workflow-code-regeneration--generate-prompt ctx)))
    (should (equal via-alias via-new))))

;; ============================================================================
;; Tests: generate-prompt
;; ============================================================================

(ert-deftest test-regen/generate-prompt-returns-string ()
  (let* ((regen-context (list :module "foo.el" :target-model "gpt-4o"
                              :purpose "Improve quality"
                              :key-decisions (list "D1" "D2")
                              :historical-learnings (list "L1" "L2")
                              :constraints (list "C1")
                              :model-stats nil))
         (prompt (gptel-auto-workflow-code-regeneration--generate-prompt
                  regen-context)))
    (should (stringp prompt))
    (should (> (length prompt) 0))
    (should (string-match-p "Regenerate module: foo.el" prompt))
    (should (string-match-p "Target model: gpt-4o" prompt))))

(ert-deftest test-regen/generate-prompt-with-nil-fields ()
  (let* ((regen-context (list :module "bar.el" :target-model "gpt-4o"
                              :purpose nil :key-decisions nil
                              :historical-learnings nil
                              :constraints nil :model-stats nil))
         (prompt (gptel-auto-workflow-code-regeneration--generate-prompt
                  regen-context)))
    (should (stringp prompt))
    (should (string-match-p "No purpose specified" prompt))
    (should (string-match-p "Model stats unavailable" prompt))))

;; ============================================================================
;; Tests: fboundp guards
;; ============================================================================

(ert-deftest test-regen/fboundp-guard-evolution ()
  "Code-regen should use `fboundp' guard, not direct call, for evolution stats.
Test passes if `gptel-auto-workflow--evolution-model-stats' is referenced
in code-regen source via `fboundp' — meaning code-regen can load without
evolution being present.  We don't assert the function is undefined
(other tests may load it)."
  ;; Indirect verification: the function is referenced with fboundp
  (let ((code (with-temp-buffer
                (insert-file-contents
                 (expand-file-name
                  "lisp/modules/gptel-auto-workflow-code-regeneration.el"
                  user-emacs-directory))
                (buffer-string))))
    (should (string-match-p
             "(fboundp 'gptel-auto-workflow--evolution-model-stats)"
             code))))

;; ============================================================================
;; Tests: --execute function
;; ============================================================================

(ert-deftest test-regen/execute-exists ()
  "The --execute function should be defined."
  (should (fboundp 'gptel-auto-workflow-code-regeneration--execute)))

(ert-deftest test-regen/execute-returns-no-success-when-experiment-unavailable ()
  "--execute should return :success nil when gptel-auto-experiment-run is not available."
  (cl-letf (((symbol-function 'gptel-auto-experiment-run) nil))
    (let ((result (gptel-auto-workflow-code-regeneration--execute "test-module.el" "v2")))
      (should (eq (plist-get result :success) nil))
      (should (equal (plist-get result :module) "test-module.el"))
      (should (eq (plist-get result :kept) nil)))))

(ert-deftest test-regen/execute-success-path ()
  "--execute should return :success t when experiment is kept."
  (let ((mementum-calls nil))
    (cl-letf (((symbol-function 'gptel-auto-experiment-run)
               (lambda (target id max baseline quality prev callback &optional log-fn)
                 (funcall callback (list :target target :id id :kept t :score-after 0.85))))
              ((symbol-function 'gptel-auto-workflow--mementum-write-memory)
                (lambda (symbol slug content)
                  (push (list symbol slug content) mementum-calls)))
               ((symbol-function 'gptel-auto-workflow--mementum-slug)
                (lambda (text) (replace-regexp-in-string "[^a-zA-Z0-9]" "-" (downcase (or text "")))))
               ((symbol-function 'gptel-auto-workflow--evolution-model-stats) nil)
               ((symbol-function 'gptel-auto-workflow-context-db-query) nil)
               ((symbol-function 'gptel-auto-workflow-context-db-summary-for-target) nil))
       (let ((result (gptel-auto-workflow-code-regeneration--execute "test-module.el" "v2")))
        (should (eq (plist-get result :success) t))
        (should (eq (plist-get result :kept) t))
        (should (equal (plist-get result :module) "test-module.el"))
         ;; Should have written success mementum
         (should (cl-find-if
                  (lambda (c) (and (eq (nth 0 c) '✅)
                                   (string-match-p "regen-success" (nth 1 c))))
                  mementum-calls))))))

(ert-deftest test-regen/execute-failure-path ()
  "--execute should return :success nil when experiment is rejected."
  (let ((mementum-calls nil))
    (cl-letf (((symbol-function 'gptel-auto-experiment-run)
               (lambda (target id max baseline quality prev callback &optional log-fn)
                 (funcall callback (list :target target :id id :kept nil :score-after 0.2))))
               ((symbol-function 'gptel-auto-workflow--mementum-write-memory)
                (lambda (symbol slug content)
                  (push (list symbol slug content) mementum-calls)))
               ((symbol-function 'gptel-auto-workflow--mementum-slug)
                (lambda (text) (replace-regexp-in-string "[^a-zA-Z0-9]" "-" (downcase (or text "")))))
               ((symbol-function 'gptel-auto-workflow--evolution-model-stats) nil)
               ((symbol-function 'gptel-auto-workflow-context-db-query) nil)
               ((symbol-function 'gptel-auto-workflow-context-db-summary-for-target) nil))
       (let ((result (gptel-auto-workflow-code-regeneration--execute "test-module.el" "v2")))
         (should (eq (plist-get result :success) nil))
         (should (eq (plist-get result :kept) nil))
         ;; Should have written failure mementum
         (should (cl-find-if
                  (lambda (c) (and (eq (nth 0 c) '❌)
                                   (string-match-p "regen-failed" (nth 1 c))))
                  mementum-calls))
         ;; Should have cleared prompt override
         (should (null gptel-auto-workflow--experiment-prompt-override))))))

(ert-deftest test-regen/execute-error-path ()
  "--execute should return :success nil when experiment run throws an error."
  (let ((mementum-calls nil))
     (cl-letf (((symbol-function 'gptel-auto-experiment-run)
                (lambda (&rest args)
                  (signal 'error (list "API unavailable"))))
               ((symbol-function 'gptel-auto-workflow--mementum-write-memory)
                (lambda (symbol slug content)
                  (push (list symbol slug content) mementum-calls)))
               ((symbol-function 'gptel-auto-workflow--mementum-slug)
                (lambda (text) (replace-regexp-in-string "[^a-zA-Z0-9]" "-" (downcase (or text "")))))
               ((symbol-function 'gptel-auto-workflow--evolution-model-stats) nil)
               ((symbol-function 'gptel-auto-workflow-context-db-query) nil)
               ((symbol-function 'gptel-auto-workflow-context-db-summary-for-target) nil))
      (let ((result (gptel-auto-workflow-code-regeneration--execute "test-module.el" "v2")))
        (should (eq (plist-get result :success) nil))
        (should (eq (plist-get result :kept) nil))
        ;; Should have written failure mementum for error
        (should (cl-find-if
                  (lambda (c) (and (eq (nth 0 c) '❌)
                                   (string-match-p "regen-failed" (nth 1 c))))
                  mementum-calls))))))

;; ============================================================================
;; Tests: full-workflow :execute param
;; ============================================================================

(ert-deftest test-regen/full-workflow-without-execute ()
  "full-workflow without :execute should just set prompt override (original behavior)."
  (let ((mementum-calls nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--evolution-model-stats) nil)
              ((symbol-function 'gptel-auto-workflow-context-db-query) nil)
              ((symbol-function 'gptel-auto-workflow-context-db-summary-for-target) nil))
      (setq gptel-auto-workflow--experiment-prompt-override nil)
      (let ((result (gptel-auto-workflow-code-regeneration--full-workflow "test.el" "current" "v2")))
        (should (eq (plist-get result :success) t))
        (should (stringp gptel-auto-workflow--experiment-prompt-override))
         (should (plist-get result :prompt))))))

(ert-deftest test-regen/full-workflow-with-execute ()
  "full-workflow with execute flag should delegate to --execute."
  (let ((mementum-calls nil))
    (cl-letf (((symbol-function 'gptel-auto-experiment-run)
               (lambda (target id max baseline quality prev callback &optional log-fn)
                 (funcall callback (list :target target :id id :kept t :score-after 0.85))))
              ((symbol-function 'gptel-auto-workflow--mementum-write-memory)
                (lambda (symbol slug content)
                  (push (list symbol slug content) mementum-calls)))
               ((symbol-function 'gptel-auto-workflow--mementum-slug)
                (lambda (text) (replace-regexp-in-string "[^a-zA-Z0-9]" "-" (downcase (or text "")))))
               ((symbol-function 'gptel-auto-workflow--evolution-model-stats) nil)
               ((symbol-function 'gptel-auto-workflow-context-db-query) nil)
               ((symbol-function 'gptel-auto-workflow-context-db-summary-for-target) nil))
       (setq gptel-auto-workflow--experiment-prompt-override nil)
       (let ((result (gptel-auto-workflow-code-regeneration--full-workflow "test.el" "current" "v2" t)))
         (should (eq (plist-get result :kept) t))))))

(provide 'test-gptel-auto-workflow-code-regeneration)

;;; test-gptel-auto-workflow-code-regeneration.el ends here