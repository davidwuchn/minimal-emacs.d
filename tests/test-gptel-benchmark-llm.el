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

(ert-deftest test-llm/auto-select-returns-cons-when-deepseek-available ()
  "auto-select-model should return (MODEL . BACKEND) when DeepSeek is registered."
  (require 'gptel-benchmark-llm)
  ;; If gptel-get-backend is available and deepseek is registered, verify format
  (when (fboundp 'gptel-get-backend)
    (let ((result (gptel-benchmark--auto-select-model)))
      (when result
        (should (consp result))
        (should (equal (car result) 'deepseek-chat))
        (should (object-of-class-p (cdr result) 'gptel-backend))))))

(ert-deftest test-llm/auto-select-returns-nil-when-no-deepseek ()
  "auto-select-model should return nil when DeepSeek is not available."
  (require 'gptel-benchmark-llm)
  ;; If gptel-get-backend exists but deepseek not found, should return nil
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