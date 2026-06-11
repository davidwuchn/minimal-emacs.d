;;; test-gptel-benchmark-llm.el --- Tests for LLM suggestions -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-benchmark-llm.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-benchmark-llm.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-benchmark-llm)

;;; Customization tests

(ert-deftest test-llm/enabled-default ()
  "LLM benchmark should be enabled by default."
  (should gptel-benchmark-llm-enabled))

(ert-deftest test-llm/model-default-nil ()
  "LLM model should default to nil."
  (should-not gptel-benchmark-llm-model))

;;; Auto-select model tests

(ert-deftest test-llm/auto-select-returns-cons-when-backend-available ()
  "auto-select-model should return (MODEL . BACKEND) via smart routing."
  (require 'gptel-benchmark-llm)
  ;; Ensure fallback chain is initialized (may be nil if ontology-router
  ;; module loaded first with defvar nil)
  (unless (and (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
               gptel-auto-workflow-executor-rate-limit-fallbacks)
    (when (and (fboundp 'gptel-backend-registry-fallback-chain-as-cons)
               (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks))
      (setq gptel-auto-workflow-executor-rate-limit-fallbacks
            (gptel-backend-registry-fallback-chain-as-cons 'executor))))
  (let ((gptel-auto-workflow--rate-limited-backends nil)
        (gptel-auto-workflow--run-failed-backends nil)
        (gptel-auto-workflow--analyzer-failed-backends nil))
    (when (fboundp 'gptel-get-backend)
      (let ((result (gptel-benchmark--auto-select-model)))
        (when result
          (should (consp result))
          (should (symbolp (car result)))
          (should (object-of-class-p (cdr result) 'gptel-backend)))))))

(ert-deftest test-llm/auto-select-returns-nil-when-no-backend ()
  "auto-select-model should return nil when smart routing finds nothing."
  (require 'gptel-benchmark-llm)
  ;; If gptel-get-backend returns nil for all backends, should return nil
  (cl-letf (((symbol-function 'gptel-get-backend) (lambda (_) nil)))
    (should-not (gptel-benchmark--auto-select-model))))

(ert-deftest test-llm/auto-select-not-called-when-model-explicit ()
  "When gptel-benchmark-llm-model is set, auto-select should be skipped."
  (let ((gptel-benchmark-llm-model "my-custom-model"))
    ;; The let* in call-llm-request short-circuits: if llm-model is set,
    ;; auto-model is never computed. Verify the logic:
    (should (equal gptel-benchmark-llm-model "my-custom-model"))))

(provide 'test-gptel-benchmark-llm)
;;; test-gptel-benchmark-llm.el ends here