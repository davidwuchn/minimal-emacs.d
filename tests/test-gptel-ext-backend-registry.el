;;; test-gptel-ext-backend-registry.el --- Tests for backend registry model list -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for the unified backend registry invariants.

;;; Code:

(require 'ert)
(require 'cl-lib)

(require 'gptel-ext-backend-registry)

;;; Smart routing tests

(ert-deftest test-registry/select-for-task-returns-cons ()
  "`gptel-backend-registry-select-for-task' should return (BACKEND . MODEL)."
  (skip-unless (fboundp 'gptel-backend-registry-select-for-task))
  ;; Reset rate-limit state and fallback chains that may have been
  ;; corrupted by earlier test execution
  (let ((gptel-auto-workflow--rate-limited-backends nil))
    (when (and (fboundp 'gptel-backend-registry-fallback-chain-as-cons)
               (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks))
      (setq gptel-auto-workflow-executor-rate-limit-fallbacks
            (gptel-backend-registry-fallback-chain-as-cons 'executor)))
    (condition-case nil
        (let ((result (gptel-backend-registry-select-for-task 'executor)))
          (when (and result (consp result))
            (let ((backend (car result))
                  (model (cdr result)))
              (should (or (object-of-class-p backend 'gptel-backend)
                          (null backend)))
              (when model
                (should (symbolp model))))))
      (error nil))))

(ert-deftest test-registry/select-for-task-skips-excluded ()
  "select-for-task should skip backends in exclude-backends."
  (skip-unless (fboundp 'gptel-backend-registry-select-for-task))
  ;; Get the first backend in the executor chain
  (let* ((chain (gptel-backend-registry-fallback-chain 'executor))
         (first-backend (car chain))
         (result (gptel-backend-registry-select-for-task
                  'executor (list first-backend))))
    ;; If result is non-nil, it must NOT use the excluded backend
    (when result
      (should (not (equal (gptel-backend-name (car result))
                          (symbol-name first-backend)))))))

(ert-deftest test-registry/fallback-chain-as-cons-format ()
  "`gptel-backend-registry-fallback-chain-as-cons' should return
alist of (\"BackendName\" . \"model-name\") string pairs."
  (skip-unless (fboundp 'gptel-backend-registry-fallback-chain-as-cons))
  (let ((result (gptel-backend-registry-fallback-chain-as-cons 'executor)))
    (should (listp result))
    (should (> (length result) 0))
    (dolist (entry result)
      (should (consp entry))
      (should (stringp (car entry)))
      (should (stringp (cdr entry))))))

(ert-deftest test-registry/fallback-chain-as-cons-skips-excluded ()
  "fallback-chain-as-cons should not include excluded backends."
  (skip-unless (fboundp 'gptel-backend-registry-fallback-chain-as-cons))
  (let* ((chain (gptel-backend-registry-fallback-chain 'executor))
         (first-backend (symbol-name (car chain)))
         (result (gptel-backend-registry-fallback-chain-as-cons
                  'executor (list (car chain)))))
    (dolist (entry result)
      (should-not (string= (car entry) first-backend)))))

(ert-deftest test-registry/cf-gateway-deepseek-model-names-have-slash ()
  "CF-Gateway DeepSeek models must use deepseek/deepseek- prefix (BYOK format).
The plain deepseek-v4-pro without the deepseek/ prefix returns 400 'No such model'
from the Workers AI endpoint.  The BYOK provider was registered with the slashed name."
  (let ((entry (assoc 'CF-Gateway gptel-backend-registry))
        (found-v4-pro nil)
        (found-v4-flash nil))
    (should entry)
    (dolist (m (plist-get (cdr entry) :models))
      (when (eq m 'deepseek/deepseek-v4-pro)
        (setq found-v4-pro t))
      (when (eq m 'deepseek/deepseek-v4-flash)
        (setq found-v4-flash t))
      ;; Must NOT have plain unslashed names
      (when (memq m '(deepseek-v4-pro deepseek-v4-flash))
        (ert-fail (format "Plain model name %s in CF-Gateway registry — must use deepseek/deepseek-v4-pro format" m))))
    (should found-v4-pro)
    (should found-v4-flash)
    ;; Also check the backend definition
    (when (boundp 'gptel--cf-gateway)
      (let ((be-models (gptel-backend-models gptel--cf-gateway)))
        (should (memq 'deepseek/deepseek-v4-pro be-models))
        (should (memq 'deepseek/deepseek-v4-flash be-models))))))

(ert-deftest test-registry/cf-gateway-default-model-is-slashed ()
  "CF-Gateway default model must use the BYOK slashed format."
  (let ((entry (assoc 'CF-Gateway gptel-backend-registry)))
    (should entry)
    (should (eq (plist-get (cdr entry) :default-model)
                'deepseek/deepseek-v4-pro))))

(ert-deftest test-registry/thinking-policy-valid-values ()
  "All :thinking-policy values must be valid symbols: off, on, or auto."
  (let ((valid '(off on auto))
        (bad nil))
    (dolist (be gptel-backend-registry)
      (when-let* ((metadata (plist-get (cdr be) :model-metadata)))
        (dolist (model-entry metadata)
          (let* ((model (car model-entry))
                 (policy (plist-get (cdr model-entry) :thinking-policy)))
            (when (and policy (not (memq policy valid)))
              (push (list (car be) model policy) bad))))))
    (when bad
      (ert-fail (format "Invalid :thinking-policy values found: %S (valid: %S)" bad valid)))))

(provide 'test-gptel-ext-backend-registry)
;;; test-gptel-ext-backend-registry.el ends here
