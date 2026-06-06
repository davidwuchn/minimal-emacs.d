;;; gptel-ext-backend-registry.el --- Single source of truth for LLM backends -*- lexical-binding: t -*-

;; This file is the SINGLE SOURCE OF TRUTH for all backend/model configuration.
;; When adding/updating models, ONLY edit this file.
;; Other modules reference this registry via accessor functions.

;;; Backend Definitions

(defconst gptel-backend-registry
  `((MiniMax
     :host "api.minimaxi.com"
     :models (MiniMax-M3)
     :default-model MiniMax-M3
     :model-metadata
       ((MiniMax-M3
        :context-window 1000000
        :pricing-input 0.30 :pricing-output 1.20 :pricing-cache-hit 0.06
        :capabilities (code-generation tool-calls)
        :speed fast
        :thinking-policy off)))

    (DeepSeek
     :host "api.deepseek.com"
     :models (deepseek-v4-pro deepseek-v4-flash)
     :default-model deepseek-v4-pro
     :model-metadata
      ((deepseek-v4-pro
        :context-window 1000000
        :pricing-input 0.43 :pricing-output 0.86 :pricing-cache-hit 0.004
        :capabilities (reasoning code-generation)
        :speed slow
        :reasoning-effort (high max)
        :thinking-policy auto)
        (deepseek-v4-flash
         :context-window 1000000
         :pricing-input 0.14 :pricing-output 0.28 :pricing-cache-hit 0.003
         :capabilities (code-generation reasoning)
         :speed fast
         :thinking-policy auto)))

    (moonshot
     :host "api.kimi.com"
     :models (kimi-k2.6 kimi-k2.5)
     :default-model kimi-k2.6
     :model-metadata
      ((kimi-k2.6
        :context-window 262144
        :pricing-input 0.95 :pricing-output 4.00 :pricing-cache-hit 0.16
        :capabilities (code-generation tool-calls long-context)
        :speed medium
        :thinking-policy auto)))

    (CF-Gateway
     :host "gateway.ai.cloudflare.com"
     :models (\@cf/moonshotai/kimi-k2.6)
     :default-model \@cf/moonshotai/kimi-k2.6
     :model-metadata
      ((\@cf/moonshotai/kimi-k2.6
        :context-window 262144
        :pricing-input 0.95 :pricing-output 4.00 :pricing-cache-hit 0.16
        :capabilities (code-generation tool-calls long-context reasoning)
        :speed medium
        :thinking-policy auto)))

    (DashScope
     :host "coding.dashscope.aliyuncs.com"
     :models (qwen3.6-plus qwen3.5-plus qwen3-coder-plus)
     :default-model qwen3.6-plus
     :model-metadata
      ((qwen3.6-plus
        :context-window 131072
        :pricing-input 0.29 :pricing-output 1.14 :pricing-cache-hit 0.06
        :capabilities (code-generation tool-calls)
        :speed medium
        :thinking-policy off)
       (qwen3.5-plus
        :context-window 131072
        :pricing-input 0.14 :pricing-output 0.57 :pricing-cache-hit 0.03
        :capabilities (code-generation)
        :speed fast
        :thinking-policy off)))

    (Z-AI
     :host "open.bigmodel.cn"
     :models (glm-5.1 glm-5 glm-4.7)
     :default-model glm-5.1
     :model-metadata
      ((glm-5.1
        :context-window 200000
        :pricing-input 0.50 :pricing-output 1.50
        :capabilities (code-generation tool-calls reasoning)
        :speed medium
        :max-output 128000
        :thinking-policy off)
       (glm-5
        :context-window 131072
        :pricing-input 0.50 :pricing-output 1.50
        :capabilities (code-generation)
        :speed medium
        :thinking-policy off)))

    (Copilot
     :host "api.github.com"
     :models (gpt-5.4-mini gpt-5.4)
     :default-model gpt-5.4-mini
     :model-metadata
      ((gpt-5.4-mini
        :context-window 128000
        :pricing-input 0.50 :pricing-output 1.50
        :capabilities (code-generation)
        :speed fast
        :thinking-policy off)))

     (TokenPlan
      :host "token-plan.cn-beijing.maas.aliyuncs.com"
      :models (qwen3.7-max qwen3.6-plus qwen3.6-flash deepseek-v4-pro deepseek-v4-flash kimi-k2.6 glm-5.1)
      :default-model qwen3.7-max
      :model-metadata
      ((qwen3.7-max
         :context-window 131072
         :pricing-input 0.29 :pricing-output 1.14 :pricing-cache-hit 0.06
         :capabilities (reasoning code-generation)
         :speed medium
         :thinking-policy off)
        (qwen3.6-plus
         :context-window 131072
         :pricing-input 0.29 :pricing-output 1.14 :pricing-cache-hit 0.06
         :capabilities (code-generation tool-calls)
         :speed medium
         :thinking-policy off)
        (qwen3.6-flash
         :context-window 131072
         :pricing-input 0.14 :pricing-output 0.57 :pricing-cache-hit 0.03
         :capabilities (code-generation)
         :speed fast
         :thinking-policy off)
        (deepseek-v4-pro
         :context-window 1000000
         :pricing-input 0.43 :pricing-output 0.86 :pricing-cache-hit 0.004
         :capabilities (reasoning code-generation)
         :speed slow
         :thinking-policy auto)
        (deepseek-v4-flash
         :context-window 1000000
         :pricing-input 0.14 :pricing-output 0.28 :pricing-cache-hit 0.003
         :capabilities (code-generation)
         :speed fast
         :thinking-policy auto)
        (kimi-k2.6
         :context-window 262144
         :pricing-input 0.95 :pricing-output 4.00 :pricing-cache-hit 0.16
         :capabilities (code-generation tool-calls long-context)
         :speed medium
         :thinking-policy auto)
        (glm-5.1
         :context-window 128000
         :pricing-input 0.50 :pricing-output 2.00
         :capabilities (code-generation)
         :speed medium
         :thinking-policy off))))
  "Unified backend registry.
Each entry: (BACKEND-NAME :host HOST :models (MODELS...) :default-model MODEL
             :model-metadata ((MODEL :context-window N :pricing-input X ...)))

THIS IS THE SINGLE SOURCE OF TRUTH.
When adding/updating models, ONLY edit this structure.")

;;; Task-Type Defaults

(defconst gptel-task-type-model-defaults
  '((analyzer   . ((MiniMax . MiniMax-M3)
                    (TokenPlan . qwen3.7-max)
                    (DashScope . qwen3.6-plus)
                    (moonshot . kimi-k2.6)
                    (DeepSeek . deepseek-v4-flash)))
     (grader     . ((Z-AI . glm-5.1)
                    (MiniMax . MiniMax-M3)
                    (TokenPlan . qwen3.7-max)
                    (DashScope . qwen3.6-plus)
                    (DeepSeek . deepseek-v4-pro)
                    (moonshot . kimi-k2.6)
                    (CF-Gateway . \@cf/moonshotai/kimi-k2.6)))
     (executor   . ((Z-AI . glm-5.1)
                    (MiniMax . MiniMax-M3)
                    (TokenPlan . qwen3.6-flash)
                    (DeepSeek . deepseek-v4-flash)
                    (CF-Gateway . \@cf/moonshotai/kimi-k2.6)
                    (DashScope . qwen3.6-plus)
                    (moonshot . kimi-k2.6)))
     (researcher . ((MiniMax . MiniMax-M3)
                    (TokenPlan . qwen3.7-max)
                    (DashScope . qwen3.6-plus)
                    (DeepSeek . deepseek-v4-pro)
                    (moonshot . kimi-k2.6)
                    (CF-Gateway . \@cf/moonshotai/kimi-k2.6)))
     (reviewer   . ((Z-AI . glm-5.1)
                    (MiniMax . MiniMax-M3)
                    (TokenPlan . qwen3.7-max)
                    (DashScope . qwen3.6-plus)
                    (DeepSeek . deepseek-v4-pro)
                    (moonshot . kimi-k2.6)
                    (CF-Gateway . \@cf/moonshotai/kimi-k2.6)))
     (comparator . ((Z-AI . glm-5.1)
                    (MiniMax . MiniMax-M3)
                    (TokenPlan . qwen3.7-max)
                    (DashScope . qwen3.6-plus)
                    (DeepSeek . deepseek-v4-pro)
                    (moonshot . kimi-k2.6)
                    (CF-Gateway . \@cf/moonshotai/kimi-k2.6))))
  "Per-task-type model defaults per backend.
Derived from `gptel-backend-registry` — update the registry, then regenerate
this.")

;;; Fallback Chains

(defconst gptel-fallback-chains
  '((executor  . (MiniMax moonshot TokenPlan Z-AI DeepSeek CF-Gateway DashScope Copilot))
    (analyzer  . (MiniMax moonshot TokenPlan Z-AI DeepSeek CF-Gateway DashScope Copilot))
    (grader    . (MiniMax moonshot TokenPlan Z-AI CF-Gateway DeepSeek DashScope Copilot))
    (default   . (MiniMax moonshot TokenPlan Z-AI CF-Gateway DeepSeek DashScope Copilot)))
  "Fallback chain ordering per task type.
Backends are tried in this order when rate-limited or failing.
DeepSeek first for executor (proven to make edits).
Copilot is LAST — reserved for when all other backends are
rate-limited/out of quota.  This preserves Copilot quota for
emergency use only.")

;;; Effort Level Configuration

(defconst gptel-backend-effort-levels
  '((deepseek-v4-pro . ((xhigh . "high") (high . "medium") (default . "low")))
    (deepseek-v4-flash . ((xhigh . "high") (high . "medium") (default . "low")))
    (qwen3.7-max . ((xhigh . "high") (high . "medium") (default . "low")))
    (kimi-k2.6 . ((xhigh . "high") (high . "medium") (default . "low")))
    (glm-5.1 . ((xhigh . "high") (high . "medium") (default . "low"))))
  "Effort level mapping per backend/model.
Maps logical effort levels (xhigh, high, default) to API-specific reasoning_effort values.
Based on DeepSWE benchmark data: effort level dramatically affects pass@1 scores.")

(defconst gptel-task-type-effort-defaults
  '((executor . high)
    (grader . high)
    (reviewer . high)
    (analyzer . default)
    (researcher . default)
    (comparator . default))
  "Default effort level per task type.
Executor/grader/reviewer use 'high for quality-critical tasks.
Analyzer/researcher/comparator use 'default for speed/cost optimization.")

(defun gptel-backend-registry-effort-level (backend model &optional task-type)
  "Return API-specific effort level for BACKEND/MODEL.
TASK-TYPE defaults to 'executor if not provided.
Returns the reasoning_effort value to send in API requests,
or nil if the backend doesn't support effort levels."
  (let* ((effort (or task-type 'executor))
         (logical-level (or (cdr (assoc effort gptel-task-type-effort-defaults))
                           'default))
         (model-efforts (cdr (assoc model gptel-backend-effort-levels))))
    (when model-efforts
      (cdr (assoc logical-level model-efforts)))))

(defun gptel-backend-registry-all-effort-levels ()
  "Return list of all (BACKEND MODEL EFFORT-LEVEL API-VALUE) tuples.
Useful for generating effort-level comparison tables."
  (let (result)
    (dolist (entry gptel-backend-effort-levels result)
      (let ((model (car entry))
            (efforts (cdr entry)))
        (dolist (level efforts)
          (push (list 'unknown model (car level) (cdr level)) result))))))

;;; Accessor Functions

(defun gptel-backend-registry-get (backend model property)
  "Get PROPERTY for MODEL on BACKEND from the unified registry.
Returns nil if not found."
  (when-let* ((backend-entry (assoc backend gptel-backend-registry))
              (metadata (plist-get (cdr backend-entry) :model-metadata))
              (model-entry (assoc model metadata)))
    (plist-get (cdr model-entry) property)))

(defun gptel-backend-registry-all-models ()
  "Return list of all (BACKEND . MODEL) pairs."
  (let (result)
    (dolist (entry gptel-backend-registry result)
      (let ((backend (car entry))
            (models (plist-get (cdr entry) :models)))
        (dolist (model models)
          (push (cons backend model) result))))))

(defun gptel-backend-registry-pricing (backend model)
  "Return pricing plist (:input :output :cache-hit) for BACKEND/MODEL."
  (list :input (or (gptel-backend-registry-get backend model :pricing-input) 0)
        :output (or (gptel-backend-registry-get backend model :pricing-output) 0)
        :cache-hit (or (gptel-backend-registry-get backend model :pricing-cache-hit) 0)))

(defun gptel-backend-registry-context-window (backend model)
  "Return context window size for BACKEND/MODEL."
  (or (gptel-backend-registry-get backend model :context-window) 128000))

(defun gptel-backend-registry-task-model (task-type backend)
  "Return default model for TASK-TYPE on BACKEND."
  (when-let* ((task-entry (assoc task-type gptel-task-type-model-defaults))
              (backend-entry (assoc backend (cdr task-entry))))
    (cdr backend-entry)))

(defun gptel-backend-registry-fallback-chain (task-type)
  "Return fallback chain for TASK-TYPE."
  (or (cdr (assoc task-type gptel-fallback-chains))
      (cdr (assoc 'default gptel-fallback-chains))))

(defun gptel-backend-registry-default-model (backend)
  "Return default model for BACKEND."
  (when-let* ((entry (assoc backend gptel-backend-registry)))
    (plist-get (cdr entry) :default-model)))

(defun gptel-backend-registry-host (backend)
  "Return API host for BACKEND."
  (when-let* ((entry (assoc backend gptel-backend-registry)))
    (plist-get (cdr entry) :host)))

;;; Thinking Policy — Self-Evolving

(defun gptel-backend-registry-thinking-policy (model)
  "Return thinking-policy for MODEL from the unified registry.
Values: off, on, auto."
  (let ((policy nil))
    (catch 'found
      (dolist (backend-entry gptel-backend-registry)
        (when-let* ((metadata (plist-get (cdr backend-entry) :model-metadata))
                    (model-entry (assoc model metadata)))
          (setq policy (plist-get (cdr model-entry) :thinking-policy))
          (throw 'found t))))
    (or policy 'off)))

(defun gptel-backend-registry--thinking-params (model)
  "Return request-params for MODEL's thinking mode based on self-evolving policy.
Looks up :thinking-policy from gptel-backend-registry.
- 'off → (:enable_thinking :json-false) or (:thinking (:type \"disabled\"))
- 'on  → (:enable_thinking :json-true) or (:thinking (:type \"enabled\"))
- 'auto → checks experiment history; defaults to off for executor."
  (let* ((policy (gptel-backend-registry-thinking-policy model))
         (effective (if (eq policy 'auto)
                        (gptel-backend-registry--auto-thinking model)
                      policy)))
    (cond
     ((memq model '(MiniMax-M3))
      (if (eq effective 'off)
          '(:thinking (:type "disabled") :max_completion_tokens 8192)
        '(:thinking (:type "enabled") :max_completion_tokens 8192)))
     ;; Z-AI (BigModel) uses :thinking object, not :enable_thinking
     ((memq model '(glm-5.1 glm-5 glm-4.7))
      (if (eq effective 'off)
          '(:thinking (:type "disabled") :max_tokens 65536)
        '(:thinking (:type "enabled") :max_tokens 65536)))
     ;; kimi on moonshot uses :thinking/:reasoning directly
     ((memq model '(kimi-k2.6 \@cf/moonshotai/kimi-k2.6))
      (if (eq effective 'off)
          '(:enable_thinking :json-false)
        '(:enable_thinking :json-true)))
     ;; Bailian/DashScope models use :enable_thinking
     (t
      (if (eq effective 'off)
          '(:enable_thinking :json-false)
        '(:enable_thinking :json-true))))))

(defvar gptel-backend-registry--thinking-history nil
  "Alist of (model . ((kept-on . N) (total-on . N) (kept-off . N) (total-off . N))).
Populated by gptel-auto-experiment-ai-behaviors when experiments complete.
Used by gptel-backend-registry--auto-thinking to decide thinking mode.")

(defun gptel-backend-registry--auto-thinking (model)
  "Decide thinking mode for MODEL based on experiment history.
Returns 'off if insufficient data or thinking-off wins; 'on otherwise.
Minimum 5 experiments with each mode before making a decision."
  (let* ((stats (cdr (assoc model gptel-backend-registry--thinking-history)))
         (on-kept (or (cdr (assoc 'kept-on stats)) 0))
         (on-total (or (cdr (assoc 'total-on stats)) 0))
         (off-kept (or (cdr (assoc 'kept-off stats)) 0))
         (off-total (or (cdr (assoc 'total-off stats)) 0)))
    (if (and (>= on-total 5) (>= off-total 5))
        ;; Enough data: compare keep-rates
        (let ((on-rate (if (> on-total 0) (/ (float on-kept) on-total) 0.0))
              (off-rate (if (> off-total 0) (/ (float off-kept) off-total) 0.0)))
          (if (> off-rate on-rate) 'off 'on))
      ;; Insufficient data: default to 'off (safer for executor)
      'off)))

(defun gptel-backend-registry--record-thinking-outcome (model thinking-enabled kept-p)
  "Record one thinking experiment outcome for MODEL.
THINKING-ENABLED is t or nil. KEPT-P is t if the experiment was kept."
  (let* ((entry (assoc model gptel-backend-registry--thinking-history))
         (stats (if entry
                    (cdr entry)
                  (let ((new (list (cons 'kept-on 0) (cons 'total-on 0)
                                   (cons 'kept-off 0) (cons 'total-off 0))))
                    (push (cons model new) gptel-backend-registry--thinking-history)
                    new))))
    (if thinking-enabled
        (progn
          (setf (cdr (assoc 'total-on stats)) (1+ (or (cdr (assoc 'total-on stats)) 0)))
          (when kept-p
            (setf (cdr (assoc 'kept-on stats)) (1+ (or (cdr (assoc 'kept-on stats)) 0)))))
      (setf (cdr (assoc 'total-off stats)) (1+ (or (cdr (assoc 'total-off stats)) 0)))
      (when kept-p
        (setf (cdr (assoc 'kept-off stats)) (1+ (or (cdr (assoc 'kept-off stats)) 0)))))))

(provide 'gptel-ext-backend-registry)
;;; gptel-ext-backend-registry.el ends here
