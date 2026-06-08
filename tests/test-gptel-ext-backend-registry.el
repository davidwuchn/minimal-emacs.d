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

(provide 'test-gptel-ext-backend-registry)
;;; test-gptel-ext-backend-registry.el ends here
