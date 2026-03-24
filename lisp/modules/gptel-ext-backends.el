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

;;; DashScope Backend with Custom Stream Parser
;;; Extends gptel-openai with more robust SSE parsing

(cl-defstruct (gptel-dashscope (:include gptel-openai)
                              (:copier nil)
                              (:constructor gptel--make-dashscope)))

(cl-defmethod gptel-curl--parse-stream ((_backend gptel-dashscope) info)
  "Parse DashScope streaming response with robust error handling.
INFO is the request info plist."
  (let ((content-strs nil))
    (condition-case err
        (while (not (eobp))
          (skip-chars-forward "\r\n")
          (when (eobp) (cl-return))
          (cond
           ((looking-at-p "\\[DONE\\]")
            (goto-char (point-max)))
           ((looking-at-p "data:")
            (forward-char 5)
            (skip-chars-forward " \t")
            (unless (looking-at-p "\\[DONE\\]")
              (condition-case nil
                  (when-let* ((response (gptel--json-read))
                              (delta (map-nested-elt response '(:choices 0 :delta))))
                    (when-let* ((content (plist-get delta :content))
                                ((stringp content))
                                ((not (string-empty-p content))))
                      (push content content-strs)))
                (error nil)))
            (forward-line 1))
           ((looking-at-p "{")
            (condition-case nil
                (when-let* ((response (gptel--json-read))
                            (delta (map-nested-elt response '(:choices 0 :delta))))
                  (when-let* ((content (plist-get delta :content))
                              ((stringp content))
                              ((not (string-empty-p content))))
                    (push content content-strs)))
              (error nil))
            (forward-line 1))
           (t (forward-line 1))))
      (error
       (message "[DashScope] Parse error at %d: %s" (point) err)))
    (apply #'concat (nreverse content-strs))))

;;;###autoload
(cl-defun gptel-make-dashscope
    (name &key curl-args stream key request-params
          (header (lambda () (when-let* ((key (gptel--get-api-key)))
                          `(("Authorization" . ,(concat "Bearer " key))))))
          (host "coding.dashscope.aliyuncs.com")
          (endpoint "/v1/chat/completions")
          models)
  "Register a DashScope backend with NAME.
This is like `gptel-make-openai' but uses a custom stream parser
that handles DashScope's SSE format differences."
  (declare (indent 1))
  (let ((backend (gptel--make-dashscope
                  :name name
                  :host host
                  :header header
                  :endpoint endpoint
                  :curl-args curl-args
                  :key key
                  :models models
                  :stream stream
                  :request-params request-params)))
    (setf (alist-get name gptel--known-backends nil nil #'equal) backend)
    backend))

;; --- Provider Backends ---
(defvar gptel--copilot (gptel-make-gh-copilot "Copilot"))

(defvar gptel--gemini
  (gptel-make-gemini "Gemini"
    :key (lambda () (my/gptel-api-key "generativelanguage.googleapis.com"))
    :stream t
    :models '(gemini-3.1-pro-preview gemini-3-flash-preview)))

(defvar gptel--minimax
  (gptel-make-openai "MiniMax"
    :host "api.minimaxi.com"
    :endpoint "/v1/chat/completions"
    :key (lambda () (my/gptel-api-key "api.minimaxi.com"))
    :stream t
    :models '(minimax-m2.5 minimax-m2.1)))

(defvar gptel--dashscope
  (gptel-make-dashscope "DashScope"
    :key (lambda () (my/gptel-api-key "coding.dashscope.aliyuncs.com"))
    :stream t
    :curl-args '("--http1.1" "--max-time" "300" "--connect-timeout" "30")
    :models '(qwen3.5-plus qwen3-max-2026-01-23 qwen3-coder-next qwen3-coder-plus kimi-k2.5 glm-5 glm-4.7 MiniMax-M2.5)))

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

(provide 'gptel-ext-backends)
;;; gptel-ext-backends.el ends here