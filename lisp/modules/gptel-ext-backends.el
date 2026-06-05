;;; -*- no-byte-compile: t; lexical-binding: t; -*-

(require 'gptel)
(require 'gptel-openai)
(require 'gptel-gemini)
(require 'gptel-gh)

(defun my/gptel-api-key (host)
  "Get API key for HOST from ~/.authinfo.gpg, return nil if not found.

Uses `call-process' with `gpg --batch -d' instead of `auth-source'
to avoid pinentry failures in headless daemon mode.  This mirrors
`eca-security--decrypt-gpg-agent' which handles gpg directly."
  (let ((authinfo (expand-file-name "~/.authinfo.gpg"))
        decrypted)
    (when (file-exists-p authinfo)
      (with-temp-buffer
        (when (zerop (call-process "gpg" nil t nil
                                   "--batch" "--quiet" "--decrypt" authinfo))
          (goto-char (point-min))
          (while (re-search-forward
                  (format "^machine %s\\s-+login \\([^[:space:]]+\\)\\s-+password \\([^[:space:]]+\\)"
                          (regexp-quote host))
                  nil t)
            (setq decrypted (match-string-no-properties 2))))))
    (when decrypted
      (string-trim decrypted))))

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
    :curl-args '("--http1.1" "--max-time" "300" "--connect-timeout" "30")
    :models '(MiniMax-M3)))

(defvar gptel--dashscope
  (gptel-make-dashscope "DashScope"
    :host "coding.dashscope.aliyuncs.com"
    :key (lambda () (my/gptel-api-key "coding.dashscope.aliyuncs.com"))
    :stream t
    :curl-args '("--http1.1" "--max-time" "300" "--connect-timeout" "30")
    :models '(qwen3.6-plus qwen3.5-plus qwen3-max-2026-01-23 qwen3-coder-next qwen3-coder-plus kimi-k2.5 glm-5 glm-4.7)))

(defvar gptel--z-ai
  (gptel-make-openai "Z-AI"
    :host "open.bigmodel.cn"
    :endpoint "/api/coding/paas/v4/chat/completions"
    :key (lambda () (my/gptel-api-key "open.bigmodel.cn"))
    :stream t
    :curl-args '("--http1.1" "--max-time" "300" "--connect-timeout" "30")
    :models '(glm-5.1 glm-5 glm-4.7)))

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
    :curl-args '("--http1.1" "--max-time" "300" "--connect-timeout" "30")
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
    :curl-args '("--http1.1" "--max-time" "900" "--connect-timeout" "30")
    :models '((deepseek-v4-flash
               :request-params (:thinking (:type "enabled")))
              (deepseek-v4-pro
               :request-params (:thinking (:type "enabled")
                                :reasoning_effort "high")))))

(defvar gptel--token-plan
  (gptel-make-openai "TokenPlan"
    :host "token-plan.cn-beijing.maas.aliyuncs.com"
    :endpoint "/compatible-mode/v1/chat/completions"
    :key (lambda () (my/gptel-api-key "token-plan.cn-beijing.maas.aliyuncs.com"))
    :stream t
    :curl-args '("--http1.1" "--max-time" "300" "--connect-timeout" "30")
    :models '(qwen3.7-max qwen3.6-plus qwen3.6-flash
              deepseek-v4-pro kimi-k2.6 glm-5.1 MiniMax-M2.5)))

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

;; Many backends (CF-Gateway/kimi-k2.6, DeepSeek with thinking enabled)
;; return responses in reasoning_content instead of content, or as well
;; as content.  Capture reasoning_content whenever present and store it
;; in INFO's :reasoning slot for the executor subagent to use.
(defun my/gptel--capture-reasoning-content (orig-fun backend response info)
  "Advice around `gptel--parse-response' to capture reasoning_content.
Stores reasoning in INFO's :reasoning slot for self-evolution.
Falls back to reasoning_content when content is nil (CF-Gateway path)."
  (let ((result (funcall orig-fun backend response info)))
    (when (eq (type-of backend) 'gptel-openai)
      (let* ((choice0 (map-nested-elt response '(:choices 0)))
             (message (plist-get choice0 :message))
             (reasoning (when message
                          (or (plist-get message :reasoning_content)
                              (plist-get message :reasoning)))))
        (when (and reasoning (stringp reasoning) (not (string-empty-p reasoning)))
          (plist-put info :reasoning reasoning)
          ;; When content is nil but reasoning is present (CF-Gateway), use reasoning as result
          (when (null result)
            (setq result reasoning)))))
    result))

(advice-add #'gptel--parse-response :around #'my/gptel--capture-reasoning-content)

(provide 'gptel-ext-backends)
;;; gptel-ext-backends.el ends here
