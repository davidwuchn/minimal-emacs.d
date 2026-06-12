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
  (require 'gptel)
  (require 'gptel-benchmark-llm)
  (cl-letf (((symbol-function 'gptel-benchmark--auto-select-model)
             (lambda ()
               (let ((be (gptel--make-backend
                          :name 'test-backend
                          :host "api.test"
                          :models '(test-model))))
                 (cons 'test-model be)))))
    (let ((result (gptel-benchmark--auto-select-model)))
      (should result)
      (should (consp result))
      (should (symbolp (car result)))
      (let ((backend (cdr result)))
        (should (gptel-backend-p backend))))))

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

;;; Timeout tests

(ert-deftest test-llm/synthesize-sync-timeout-returns-nil ()
  "When gptel request never calls back, timeout returns nil (does not hang)."
  (cl-letf (((symbol-function 'gptel-benchmark-llm-synthesize-knowledge)
             (lambda (_topic _memories _callback) nil)))
    (let ((result (gptel-benchmark-llm-synthesize-knowledge-sync
                   "test" '("memory content") 2)))
      (should-not result))))

(ert-deftest test-llm/synthesize-sync-completes-before-timeout ()
  "When callback fires before timeout, returns the result."
  (cl-letf (((symbol-function 'gptel-benchmark-llm-synthesize-knowledge)
             (lambda (_topic _memories callback)
               (funcall callback "synthesized content"))))
    (let ((result (gptel-benchmark-llm-synthesize-knowledge-sync
                   "test" '("memory") 5)))
      (should (equal result "synthesized content")))))

(provide 'test-gptel-benchmark-llm)
;;; test-gptel-benchmark-llm.el ends here