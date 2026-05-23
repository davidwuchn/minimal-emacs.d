;;; -*- no-byte-compile: t; lexical-binding: t; -*-

(require 'gptel)
(require 'gptel-openai)
(require 'gptel-gemini)
(require 'gptel-gh)

(defun my/gptel-api-key (host)
  "Get API key for HOST from auth-source, return nil if not found.
Unlike `gptel-api-key-from-auth-source', this won't prompt during process filters."
  (let ((auth-source-creation-prompts nil)
        (result (auth-source-user-and-password host "api")))
    (cadr result)))

;;; DashScope Backend - uses OpenAI-compatible API
;;; No custom parser needed - standard OpenAI SSE format

(defun gptel-make-dashscope (name &rest args)
  "Register a DashScope backend with NAME.
Uses standard OpenAI-compatible format - no custom parser needed.
ARGS are passed to `gptel-make-openai'."
  (declare (indent 1))
  (apply #'gptel-make-openai name args))

;; --- Provider Backends ---
(defvar gptel--copilot (gptel-make-gh-copilot "Copilot"))

(defvar gptel--gemini
  (gptel-make-gemini "Gemini"
    :key (lambda () (my/gptel-api-key "generativelanguage.googleapis.com"))
    :stream t
    :models '(gemini-3.5-flash gemini-3.1-pro-preview gemini-3-flash-preview)))

(defvar gptel--minimax
  (gptel-make-openai "MiniMax"
    :host "api.minimaxi.com"
    :endpoint "/v1/chat/completions"
    :key (lambda () (my/gptel-api-key "api.minimaxi.com"))
    :stream t
    :curl-args '("--http1.1" "--max-time" "180" "--connect-timeout" "30")
    :models '(minimax-m2.7-highspeed minimax-m2.7 minimax-m2.5 minimax-m2.1)))

(defvar gptel--dashscope
  (gptel-make-dashscope "DashScope"
    :host "coding.dashscope.aliyuncs.com"
    :key (lambda () (my/gptel-api-key "coding.dashscope.aliyuncs.com"))
    :stream t
    :curl-args '("--http1.1" "--max-time" "180" "--connect-timeout" "30")
    :models '(qwen3.6-plus qwen3.5-plus qwen3-max-2026-01-23 qwen3-coder-next qwen3-coder-plus kimi-k2.5 glm-5 glm-4.7 MiniMax-M2.5)))

;; Refresh the backend object on reload so long-lived workflow daemons pick up
;; contract changes like header callback arity.
(setq gptel--moonshot
      (gptel-make-openai "moonshot"
        :host "api.kimi.com"
        :endpoint "/coding/v1/chat/completions"
        :key (lambda () (my/gptel-api-key "api.kimi.com"))
        :header (lambda (_info)
                  `(("Authorization" . ,(concat "Bearer " (gptel--get-api-key)))
                    ("User-Agent"    . "KimiCLI/1.3")))
        :stream t
        :curl-args '("--http1.1" "--max-time" "180" "--connect-timeout" "30")
        :models '((kimi-k2.6
                   :request-params (:reasoning (:effort "high")
                                               :thinking  (:type "enabled")))
                  kimi-for-coding)))

(defvar gptel--deepseek
  (gptel-make-openai "DeepSeek"
    :host "api.deepseek.com"
    :endpoint "/chat/completions"
    :key (lambda () (my/gptel-api-key "api.deepseek.com"))
    :stream t
    :models '((deepseek-v4-flash
               :request-params (:thinking (:type "disabled")))
              (deepseek-v4-pro
               :request-params (:thinking (:type "enabled")
                                :reasoning_effort "high")))))

(defvar gptel--cf-gateway
  (gptel-make-openai "CF-Gateway"
    :host "gateway.ai.cloudflare.com"
    :endpoint "/v1/e68f70855c32831717611057ed23aa46/mindward/workers-ai/v1/chat/completions"
    :key (lambda () (my/gptel-api-key "gateway.ai.cloudflare.com"))
    :stream t
    :models '(\@cf/openai/gpt-oss-120b
              \@cf/moonshotai/kimi-k2.6
              \@cf/zai-org/glm-4.7-flash
              \@cf/openai/whisper
              \@cf/openai/whisper-large-v3-turbo)))

;; CF-Gateway with kimi-k2.6 returns responses in reasoning_content
;; instead of content, causing gptel to return nil.  Intercept and
;; fall back to reasoning_content when content is empty.
(defun my/gptel--cf-gateway-fix-reasoning-content (orig-fun backend response info)
  "Advice around `gptel--parse-response' to handle CF-Gateway reasoning_content."
  (let ((result (funcall orig-fun backend response info)))
    (if (and (null result)
             (eq (type-of backend) 'gptel-openai)
             (string= (gptel-backend-name backend) "CF-Gateway"))
        (let* ((choice0 (map-nested-elt response '(:choices 0)))
               (message (plist-get choice0 :message))
               (reasoning (plist-get message :reasoning_content)))
          (when (and reasoning (stringp reasoning) (not (string-empty-p reasoning)))
            (plist-put info :reasoning reasoning)
            reasoning))
      result)))

(advice-add #'gptel--parse-response :around #'my/gptel--cf-gateway-fix-reasoning-content)

(provide 'gptel-ext-backends)
;;; gptel-ext-backends.el ends here
