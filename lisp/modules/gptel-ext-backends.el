;;; -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'project)
(require 'url)
(require 'url-parse)
(require 'url-util)
(require 'json)
(require 'dom)
(require 'diff)
(require 'gptel)
(eval-when-compile
  (require 'gptel-openai)
  (require 'gptel-gemini)
  (require 'gptel-gh))
(require 'gptel-context)
(require 'gptel-request)
(require 'gptel-gh)
(require 'gptel-gemini)
(require 'gptel-openai)
;; (require 'gptel-openai-extras)

;; --- Provider Backends ---
(defvar gptel--copilot (gptel-make-gh-copilot "Copilot"))

(defvar gptel--gemini
  (gptel-make-gemini "Gemini"
    :key (lambda () (gptel-api-key-from-auth-source "generativelanguage.googleapis.com" "api"))
    :stream t
    :models '(gemini-3.1-pro-preview gemini-3-flash-preview)))

(defvar gptel--openrouter
  (gptel-make-openai "OpenRouter"
    :host "openrouter.ai"
    :endpoint "/api/v1/chat/completions"
    :key (lambda () (gptel-api-key-from-auth-source "api.openrouter.com" "api"))
    :stream t
    :models '(openai/gpt-5.2-codex z-ai/glm-5 anthropic/claude-sonnet-4.6)))

(defvar gptel--minimax
  (gptel-make-openai "MiniMax"
    :host "api.minimaxi.com"
    :endpoint "/v1/chat/completions"
    :key (lambda () (gptel-api-key-from-auth-source "api.minimaxi.com" "api"))
    :stream t
    :models '(minimax-m2.5 minimax-m2.1)))

(defvar gptel--dashscope
  (gptel-make-openai "DashScope"
    :host "coding.dashscope.aliyuncs.com"
    :endpoint "/v1/chat/completions"
    :key (lambda () (gptel-api-key-from-auth-source "coding.dashscope.aliyuncs.com" "api"))
    :stream t
    :models '(qwen3.5-plus kimi-k2.5 glm-5 MiniMax-M2.5 qwen3-max-2026-01-23 qwen3-coder-next qwen3-coder-plus glm-4.7)))

(defvar gptel--moonshot
  (gptel-make-openai "Moonshot"
    :host "api.kimi.com"
    :endpoint "/coding/v1/chat/completions"
    :key (lambda () (gptel-api-key-from-auth-source "api.kimi.com" "api"))
    :header (lambda ()
              `(("Authorization" . ,(concat "Bearer " (gptel--get-api-key)))
                ("User-Agent"    . "KimiCLI/1.3")))
    :stream t
    :curl-args '("--http1.1")
    :models '((kimi-k2.5
               :request-params (:reasoning (:effort "high")
                                           :thinking  (:type "enabled")))
              kimi-for-coding)))

(defvar gptel--deepseek
  (gptel-make-openai "DeepSeek"
    :host "api.deepseek.com"
    :endpoint "/chat/completions"
    :key (lambda () (gptel-api-key-from-auth-source "api.deepseek.com" "api"))
    :stream t
    :models '(deepseek-chat deepseek-reasoner)))

(defvar gptel--cf-gateway
  (gptel-make-openai "CF-Gateway"
    :host "gateway.ai.cloudflare.com"
    :endpoint "/v1/e68f70855c32831717611057ed23aa46/mindward/workers-ai/v1/chat/completions"
    ;; Auth source entry: machine gateway.ai.cloudflare.com login api password <CF_AIG_TOKEN>
    :key (lambda () (gptel-api-key-from-auth-source "gateway.ai.cloudflare.com" "api"))
    :stream t
    :models '(\@cf/zai-org/glm-4.7-flash \@cf/openai/whisper \@cf/openai/whisper-large-v3-turbo)))

;; --- Model Resolution ---
(defconst my/gptel-preferred-models
  `((,gptel--openrouter . anthropic/claude-sonnet-4.6)
    (,gptel--gemini     . gemini-3.1-pro-preview)
    (,gptel--moonshot   . kimi-k2.5)
    (,gptel--copilot    . github-copilot/gpt-5.3-codex)
    (,gptel--cf-gateway . \@cf/zai-org/glm-4.7-flash)
    (,gptel--dashscope  . qwen3.5-plus)))

(defun my/gptel-resolve-model (&optional backend requested)
  "Resolve REQUESTED model for BACKEND."
  (let* ((backend (or backend gptel-backend))
         (requested (or requested 'auto)))
    (if (not (eq requested 'auto))
        requested
      (or (alist-get backend my/gptel-preferred-models)
          (car-safe (gptel-backend-models backend))))))

;; --- Helper Functions ---

(provide 'gptel-ext-backends)
;;; gptel-ext-backends.el ends here
