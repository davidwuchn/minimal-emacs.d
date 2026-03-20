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

;; --- Provider Backends ---
(defvar gptel--copilot (gptel-make-gh-copilot "Copilot"))

(defvar gptel--gemini
  (gptel-make-gemini "Gemini"
    :key (lambda () (my/gptel-api-key "generativelanguage.googleapis.com"))
    :stream t
    :models '(gemini-3.1-pro-preview gemini-3-flash-preview)))

;; DISABLED temporarily - OpenRouter causing HTTP parse errors
;; (defvar gptel--openrouter
;;   (gptel-make-openai "OpenRouter"
;;     :host "openrouter.ai"
;;     :endpoint "/api/v1/chat/completions"
;;     :key (lambda () (my/gptel-api-key "api.openrouter.com"))
;;     :stream t
;;     :models '(openai/gpt-5.2-codex z-ai/glm-5 anthropic/claude-sonnet-4.6)))

(defvar gptel--minimax
  (gptel-make-openai "MiniMax"
    :host "api.minimaxi.com"
    :endpoint "/v1/chat/completions"
    :key (lambda () (my/gptel-api-key "api.minimaxi.com"))
    :stream t
    :models '(minimax-m2.5 minimax-m2.1)))

(defvar gptel--dashscope
  (gptel-make-openai "DashScope"
    :host "coding.dashscope.aliyuncs.com"
    :endpoint "/v1/chat/completions"
    :key (lambda () (my/gptel-api-key "coding.dashscope.aliyuncs.com"))
    :stream t
    :curl-args '("--http1.1" "--max-time" "100")
    :models '((qwen3.5-plus :capabilities (media) :mime-types ("image/jpeg" "image/png" "image/webp" "image/gif" "image/bmp" "application/pdf"))
              (kimi-k2.5 :capabilities (media) :mime-types ("image/jpeg" "image/png" "image/webp" "image/gif" "image/bmp" "application/pdf"))
              (qwen3-max-2026-01-23 :capabilities (media) :mime-types ("image/jpeg" "image/png" "image/webp" "image/gif" "image/bmp" "application/pdf"))
              (qwen3-coder-next :capabilities (media) :mime-types ("image/jpeg" "image/png" "image/webp" "image/gif" "image/bmp" "application/pdf"))
              (qwen3-coder-plus :capabilities (media) :mime-types ("image/jpeg" "image/png" "image/webp" "image/gif" "image/bmp" "application/pdf"))
              glm-5 glm-4.7 MiniMax-M2.5)))

(defvar gptel--moonshot
  (gptel-make-openai "Moonshot"
    :host "api.kimi.com"
    :endpoint "/coding/v1/chat/completions"
    :key (lambda () (my/gptel-api-key "api.kimi.com"))
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
    :key (lambda () (my/gptel-api-key "api.deepseek.com"))
    :stream t
    :models '(deepseek-chat deepseek-reasoner)))

(defvar gptel--cf-gateway
  (gptel-make-openai "CF-Gateway"
    :host "gateway.ai.cloudflare.com"
    :endpoint "/v1/e68f70855c32831717611057ed23aa46/mindward/workers-ai/v1/chat/completions"
    :key (lambda () (my/gptel-api-key "gateway.ai.cloudflare.com"))
    :stream t
    :models '(\@cf/zai-org/glm-4.7-flash \@cf/openai/whisper \@cf/openai/whisper-large-v3-turbo)))

;; --- Helper Functions ---

(provide 'gptel-ext-backends)
;;; gptel-ext-backends.el ends here
