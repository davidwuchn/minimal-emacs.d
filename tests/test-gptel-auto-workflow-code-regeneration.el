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
  (should-not (fboundp 'gptel-auto-workflow--evolution-model-stats)))

(provide 'test-gptel-auto-workflow-code-regeneration)

;;; test-gptel-auto-workflow-code-regeneration.el ends here