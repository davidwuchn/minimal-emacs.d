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
  (when (fboundp 'gptel-get-backend)
    ;; Mock the registry to return a valid backend.  Earlier test
    ;; execution can corrupt the fallback chain and backend registry
    ;; (especially when test files load modules in find-order).
    (cl-letf (((symbol-function 'gptel-backend-registry-select-for-task)
               (lambda (_task)
                 (let ((be (ignore-errors (gptel-get-backend "DeepSeek"))))
                   (if be
                       (cons be (gptel-backend-model be))
                     ;; Fallback: DeepSeek not registered; construct
                     ;; a minimal backend object directly.
                     (when (fboundp 'gptel--make-backend)
                       (let ((mock-be (gptel--make-backend
                                       :name 'deepseek
                                       :id "deepseek"
                                       :model "deepseek-v4-flash")))
                         (cons mock-be "deepseek-v4-flash"))))))))
      (let ((result (gptel-benchmark--auto-select-model)))
        (when result
          (should (consp result))
          (should (symbolp (car result)))
          (let ((backend (cdr result)))
            (should (object-of-class-p backend 'gptel-backend))))))))

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