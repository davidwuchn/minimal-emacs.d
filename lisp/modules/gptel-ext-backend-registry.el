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
       :context-window 196608
       :pricing-input 0.30 :pricing-output 1.20 :pricing-cache-hit 0.06
       :capabilities (code-generation tool-calls)
       :speed fast)))

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
       :reasoning-effort (high max))
       (deepseek-v4-flash
        :context-window 1000000
        :pricing-input 0.14 :pricing-output 0.28 :pricing-cache-hit 0.003
        :capabilities (code-generation reasoning)
        :speed fast)))

    (moonshot
     :host "api.kimi.com"
     :models (kimi-k2.6 kimi-k2.5)
     :default-model kimi-k2.6
     :model-metadata
     ((kimi-k2.6
       :context-window 262144
       :pricing-input 0.95 :pricing-output 4.00 :pricing-cache-hit 0.16
       :capabilities (code-generation tool-calls long-context)
       :speed medium)))

    (CF-Gateway
     :host "gateway.ai.cloudflare.com"
     :models (\@cf/moonshotai/kimi-k2.6)
     :default-model \@cf/moonshotai/kimi-k2.6
     :model-metadata
     ((\@cf/moonshotai/kimi-k2.6
       :context-window 262144
       :pricing-input 0.95 :pricing-output 4.00 :pricing-cache-hit 0.16
       :capabilities (code-generation tool-calls long-context reasoning)
       :speed medium)))

    (DashScope
     :host "coding.dashscope.aliyuncs.com"
     :models (qwen3.6-plus qwen3.5-plus qwen3-coder-plus)
     :default-model qwen3.6-plus
     :model-metadata
     ((qwen3.6-plus
       :context-window 131072
       :pricing-input 0.29 :pricing-output 1.14 :pricing-cache-hit 0.06
       :capabilities (code-generation tool-calls)
       :speed medium)
      (qwen3.5-plus
       :context-window 131072
       :pricing-input 0.14 :pricing-output 0.57 :pricing-cache-hit 0.03
       :capabilities (code-generation)
       :speed fast)))

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
       :max-output 128000)
      (glm-5
       :context-window 131072
       :pricing-input 0.50 :pricing-output 1.50
       :capabilities (code-generation)
       :speed medium)))

    (Copilot
     :host "api.github.com"
     :models (gpt-5.4-mini gpt-5.4)
     :default-model gpt-5.4-mini
     :model-metadata
     ((gpt-5.4-mini
       :context-window 128000
       :pricing-input 0.50 :pricing-output 1.50
       :capabilities (code-generation)
       :speed fast)))

     (TokenPlan
      :host "token-plan.cn-beijing.maas.aliyuncs.com"
      :models (qwen3.7-max qwen3.6-plus qwen3.6-flash deepseek-v4-pro deepseek-v4-flash kimi-k2.6 glm-5.1)
      :default-model qwen3.7-max
      :model-metadata
      ((qwen3.7-max
        :context-window 131072
        :pricing-input 0.29 :pricing-output 1.14 :pricing-cache-hit 0.06
        :capabilities (reasoning code-generation)
        :speed medium)
       (qwen3.6-plus
        :context-window 131072
        :pricing-input 0.29 :pricing-output 1.14 :pricing-cache-hit 0.06
        :capabilities (code-generation tool-calls)
        :speed medium)
       (qwen3.6-flash
        :context-window 131072
        :pricing-input 0.14 :pricing-output 0.57 :pricing-cache-hit 0.03
        :capabilities (code-generation)
        :speed fast)
       (deepseek-v4-pro
        :context-window 1000000
        :pricing-input 0.43 :pricing-output 0.86 :pricing-cache-hit 0.004
        :capabilities (reasoning code-generation)
        :speed slow)
       (deepseek-v4-flash
        :context-window 1000000
        :pricing-input 0.14 :pricing-output 0.28 :pricing-cache-hit 0.003
        :capabilities (code-generation)
        :speed fast)
       (kimi-k2.6
        :context-window 262144
        :pricing-input 0.95 :pricing-output 4.00 :pricing-cache-hit 0.16
        :capabilities (code-generation tool-calls long-context)
        :speed medium)
       (glm-5.1
        :context-window 128000
        :pricing-input 0.50 :pricing-output 2.00
        :capabilities (code-generation)
        :speed medium))))
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

(provide 'gptel-ext-backend-registry)
;;; gptel-ext-backend-registry.el ends here
