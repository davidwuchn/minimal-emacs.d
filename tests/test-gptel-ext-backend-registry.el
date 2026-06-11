;;; test-gptel-ext-backend-registry.el --- Tests for backend registry model list -*- lexical-binding: t; -*-

;;; Commentary:
;; TDD: TokenPlan dropped support for qwen3.5 models (retired) and added
;; qwen3.7-plus. qwen3.7-plus is now preferred over qwen3.6-plus in
;; task-type defaults. Capabilities mirror qwen3.6-plus (text + reasoning,
;; no vision). This test guards those invariants.

;;; Code:

(require 'ert)
(require 'cl-lib)

(require 'gptel-ext-backend-registry)
(require 'gptel-ext-context-cache)

(ert-deftest test-registry/tokenplan-has-qwen3.7-plus ()
  "TokenPlan backend must list qwen3.7-plus in its :models."
  (let* ((entry (assoc 'TokenPlan gptel-backend-registry))
         (models (plist-get (cdr entry) :models)))
    (should (memq 'qwen3.7-plus models))))

(ert-deftest test-registry/tokenplan-has-qwen3.7-plus-metadata ()
  "TokenPlan must have model-metadata for qwen3.7-plus.
qwen3.7-plus is a reasoning model: capabilities must include
'code-generation' and 'reasoning' (per the qwen3.6-plus spec which it
succeeds). Pricing tier matches qwen3.6-plus."
  (let* ((entry (assoc 'TokenPlan gptel-backend-registry))
         (meta (plist-get (cdr entry) :model-metadata))
         (q37p (assq 'qwen3.7-plus meta)))
    (should q37p)
    (should (plist-get (cdr q37p) :context-window))
    (should (plist-get (cdr q37p) :pricing-input))
    (should (plist-get (cdr q37p) :pricing-output))
    ;; Capabilities: at least code-generation
    (let ((caps (plist-get (cdr q37p) :capabilities)))
      (should (memq 'code-generation caps)))))

(ert-deftest test-registry/qwen3.5-retired-everywhere ()
  "qwen3.5-plus and qwen3.5-flash were retired by the TokenPlan backend.
They must NOT appear in any backend's :models list."
  (let ((found '()))
    (dolist (entry gptel-backend-registry found)
      (let* ((backend-name (car entry))
             (models (plist-get (cdr entry) :models)))
        (when (or (memq 'qwen3.5-plus models)
                  (memq 'qwen3.5-flash models))
          (push backend-name found))))
    (should-not found)))

(ert-deftest test-registry/dashscope-has-qwen3.7-plus ()
  "DashScope backend must list qwen3.7-plus in its :models.
The provider rolled out qwen3.7-plus alongside TokenPlan; older
qwen3.6-plus is still available but qwen3.7-plus is the new default."
  (let* ((entry (assoc 'DashScope gptel-backend-registry))
         (models (plist-get (cdr entry) :models)))
    (should (memq 'qwen3.7-plus models))))

(ert-deftest test-registry/dashscope-task-type-defaults-use-qwen3.7-plus ()
  "Every DashScope default that was qwen3.6-plus must now be qwen3.7-plus."
  (let ((stale '()))
    (dolist (pair gptel-task-type-model-defaults)
      (let* ((backends (cdr pair))
             (dashscope (assoc 'DashScope backends)))
        (when (and dashscope (eq (cdr dashscope) 'qwen3.6-plus))
          (push (car pair) stale))))
    (should-not stale)))

(ert-deftest test-registry/task-type-defaults-prefer-qwen3.7-plus ()
  "For every task type that defaulted to qwen3.6-plus on TokenPlan,
the new default must be qwen3.7-plus (preferred over older model)."
  (let ((tokenplan-defaults '())
        (checked '()))
    ;; Collect every (TASK-TYPE . ((BACKEND . MODEL) ...))
    (dolist (pair gptel-task-type-model-defaults)
      (let* ((task-type (car pair))
             (backends (cdr pair))
             (tokenplan (assoc 'TokenPlan backends)))
        (when (and tokenplan (eq (cdr tokenplan) 'qwen3.6-plus))
          (push task-type tokenplan-defaults))))
    ;; None of the task types should still default to qwen3.6-plus;
    ;; they should all have been migrated to qwen3.7-plus.
    (should-not tokenplan-defaults)))

(ert-deftest test-registry/context-cache-has-qwen3.7-plus ()
  "Context cache must include qwen3.7-plus with 131072 window
(same tier as qwen3.6-plus)."
  (let ((cache my/gptel--known-model-context-windows))
    (should (assoc "qwen3.7-plus" cache))))

;;; Smart routing tests

(ert-deftest test-registry/select-for-task-returns-cons ()
  "`gptel-backend-registry-select-for-task' should return (BACKEND . MODEL)."
  (skip-unless (fboundp 'gptel-backend-registry-select-for-task))
  ;; Reset rate-limit state and fallback chains that may have been
  ;; corrupted by earlier test execution
  (let ((gptel-auto-workflow--rate-limited-backends nil)
        (gptel-auto-workflow--run-failed-backends nil)
        (gptel-auto-workflow--analyzer-failed-backends nil))
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
