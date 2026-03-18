;;; gptel-ext-core.el --- Core gptel configuration and hooks -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Core configuration for gptel: project temp directory, markdown face compat,
;; plain model/mode setup, default-directory, tool registry audit, curl parse
;; hardening, and pre-serialization content sanitizer.
;;
;; Extracted modules (loaded separately via gptel-config.el):
;;   gptel-ext-streaming.el     — jit-lock protection during streaming
;;   gptel-ext-tool-sanitize.el — nil tool call handling, doom-loop, dedup
;;   gptel-ext-reasoning.el     — thinking/reasoning content preservation
;;   gptel-ext-retry.el         — auto-retry with exponential backoff, compaction
;;   gptel-ext-transient.el     — transient menu fixes, crowdsourced prompts
;;   gptel-ext-abort.el         — curl timeouts, abort, prompt markers
;;   gptel-ext-tool-confirm.el  — enhanced tool call confirmation UI
;;   gptel-ext-fsm.el           — FSM error recovery and agent handler fixes

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'project)
(require 'gptel)
(require 'gptel-request)
(require 'gptel-openai)

;; ==============================================================================
;; GPT-AGENT COMPATIBILITY SHIMS
;; ==============================================================================
;; gptel-agent (20260308) expects functions from newer gptel versions.
;; These stubs provide compatibility.

(declare-function gptel-fsm-info "gptel")

(unless (fboundp 'gptel--handle-pre-tool)
  (defun gptel--handle-pre-tool (_fsm)
    "Compatibility shim: pre-tool handler for gptel-agent.
Does nothing in older gptel versions."
    nil))

(unless (fboundp 'gptel--handle-post-tool)
  (defun gptel--handle-post-tool (_fsm)
    "Compatibility shim: post-tool handler for gptel-agent.
Does nothing in older gptel versions."
    nil))

(unless (fboundp 'gptel--handle-tool-result)
  (defun gptel--handle-tool-result (_fsm)
    "Compatibility shim: tool-result handler for gptel-agent.
Does nothing in older gptel versions."
    nil))

;; ==============================================================================
;; PROJECT TEMP DIRECTORY
;; ==============================================================================
;; All tool temp files go to <project-root>/temp/ instead of system /tmp.
;; This keeps them inside the workspace boundary so the security ACL
;; doesn't force user confirmation for LLM read-back operations.

(defun my/gptel-temp-dir ()
  "Return the project-local temp directory, creating it if needed.
Falls back to `temporary-file-directory' if no project is found."
  (let* ((root (if-let ((proj (project-current nil)))
                   (expand-file-name (project-root proj))
                 default-directory))
         (dir (expand-file-name "temp/" root)))
    (unless (file-directory-p dir) (make-directory dir t))
    dir))

(defun my/gptel-make-temp-file (prefix &optional dir-flag suffix)
  "Like `make-temp-file' but in the project temp/ directory.
PREFIX, DIR-FLAG, and SUFFIX are passed to `make-temp-file'."
  (let ((temporary-file-directory (my/gptel-temp-dir)))
    (make-temp-file prefix dir-flag suffix)))

;; --- Markdown Face Compatibility ---
;; Some markdown-mode versions only define heading faces up to level 6.
;; When content contains 7+ hash headings (e.g. "####### Title"), font-lock may
;; try to use `markdown-header-face-7` and error repeatedly.
;; Define the missing faces as aliases inheriting from level 6.
(with-eval-after-load 'markdown-mode
  (dolist (n '(7 8 9))
    (let ((face (intern (format "markdown-header-face-%d" n))))
      (unless (facep face)
        (make-face face)
        (set-face-attribute face nil :inherit 'markdown-header-face-6)))))

;; --- Forward declarations ---
(defvar gptel--openrouter) ; defined later; forward-declared for byte-compiler
(defvar gptel--minimax)   ; defined later; forward-declared for byte-compiler
(defvar gptel--moonshot)  ; defined later; forward-declared for byte-compiler
(defvar gptel--cf-gateway) ; defined later; forward-declared for byte-compiler
(defvar my/gptel--in-subagent-task) ; defined in gptel-tools-agent.el

;; ==============================================================================
;; PLAIN MODEL CONFIG + MODE HOOK
;; ==============================================================================

(defcustom my/gptel-plain-model 'kimi-k2.5
  "Model for plain `gptel' buffers (no preset / non-agent sessions).
Set to nil to use the global `gptel-model' default."
  :type '(choice (const :tag "Global default" nil) symbol)
  :group 'gptel)

(defun my/gptel--apply-plain-model ()
  "Set plain-gptel model/backend for buffers without an active preset.
Runs deferred after gptel-mode activates so gptel-agent has had a chance
to apply its preset (the system message is already pinned buffer-locally
by `my/gptel--mode-hook-setup' before this runs)."
  (when (and (bound-and-true-p gptel-mode)
             (not (bound-and-true-p gptel--preset))
             my/gptel-plain-model)
    (setq-local gptel-model my/gptel-plain-model)
    (setq-local gptel-backend gptel--moonshot)
    ))

(defun my/gptel--mode-hook-setup ()
  "Setup hook for gptel-mode buffers."
  (when (fboundp 'flycheck-mode) (flycheck-mode -1))
  (when (fboundp 'flymake-mode) (flymake-mode -1))
  ;; Upstream gptel uses `(get model :capabilities)' which requires a symbol.
  ;; OpenRouter and other backends may set gptel-model to a string, causing
  ;; `wrong-type-argument symbolp' in header-line redisplay.  Intern it.
  (when (stringp gptel-model)
    (setq-local gptel-model (intern gptel-model)))
  ;; Immediately make gptel--system-message buffer-local so that any
  ;; subsequent global (set ...) calls from other buffers' preset switches
  ;; cannot bleed in.  For plain gptel buffers (no preset), pin it to the
  ;; upstream default now; the model/backend are set deferred (after
  ;; gptel-agent may apply its preset to this buffer).
  (let ((default-msg (cdr (assq 'default gptel-directives))))
    (when default-msg
      (setq-local gptel--system-message default-msg)))
  ;; Defer model/backend assignment until after gptel-agent preset is applied.
  (let ((buf (current-buffer)))
    (run-with-idle-timer 0 nil
                         (lambda ()
                           (when (buffer-live-p buf)
                             (with-current-buffer buf
                               (my/gptel--apply-plain-model)))))))

(add-hook 'gptel-mode-hook #'my/gptel--mode-hook-setup)

(add-hook 'gptel-post-stream-hook #'gptel-auto-scroll)
(add-hook 'gptel-post-response-functions #'gptel-end-of-response)

;; Lower temperature for reliable tool calling (1.0 causes malformed tool calls).
(setq gptel-temperature 0.5)

;; Uncomment to enable full request/response logging in *gptel-log* buffer.
;; Useful for diagnosing 400 errors — shows exact JSON sent to the API.
;; (setq gptel-log-level 'debug)

;; ==============================================================================
;; DEFAULT DIRECTORY
;; ==============================================================================

(defun my/gptel--set-default-directory-to-project-root ()
  "Set `default-directory` to the current project root when available.

This gives gptel tools a stable repo root context so the agent doesn't
need to ask for it explicitly."
  (when-let ((proj (project-current nil)))
    ;; Normalize away abbreviations like "~" to reduce model confusion.
    (setq-local default-directory
                (file-name-as-directory
                 (expand-file-name (project-root proj))))))

(add-hook 'gptel-mode-hook #'my/gptel--set-default-directory-to-project-root)

;; ==============================================================================
;; TOOL REGISTRY AUDIT
;; ==============================================================================

(defvar-local my/gptel--last-audited-preset nil
  "Last gptel preset audited in this buffer.")

(defun my/gptel--known-tool-names ()
  "Return a list of tool names registered in `gptel--known-tools`."
  (when (boundp 'gptel--known-tools)
    (cl-loop for (_cat . tools) in gptel--known-tools
             append (mapcar #'car tools))))

(defun my/gptel--preset-tool-names (preset)
  "Return tool names declared by PRESET.

PRESET is a preset symbol like `gptel-agent` or `gptel-plan`."
  (when (and (fboundp 'gptel-get-preset) preset)
    (when-let* ((plist (gptel-get-preset preset))
                (tools (plist-get plist :tools)))
      (cond
       ((null tools) nil)
       ((and (listp tools) (seq-every-p #'stringp tools)) tools)
       (t nil)))))

(defun my/gptel-audit-preset-tools (&optional preset)
  "Check that tools referenced by PRESET exist in gptel's tool registry.

Prints a non-fatal warning message when tools are missing.
When PRESET is nil, defaults to `gptel--preset` when available."
  (interactive)
  (let* ((preset (or preset
                     (and (boundp 'gptel--preset) gptel--preset)))
         (preset-tools (my/gptel--preset-tool-names preset))
         (known (my/gptel--known-tool-names)))
    (cond
     ((not preset)
      (message "gptel audit: no preset in this buffer"))
     ((not (listp preset-tools))
      (message "gptel audit: preset %S has no :tools list" preset))
     ((not (listp known))
      (message "gptel audit: tool registry not initialized"))
     (t
      (let* ((missing (seq-filter (lambda (name) (not (member name known)))
                                  preset-tools)))
        (if missing
            (message "gptel audit: preset %S missing tools: %s"
                     preset (string-join missing ", "))
          (message "gptel audit: preset %S tools OK (%d)" preset (length preset-tools))))))))

(defun my/gptel--after-apply-preset (&rest _)
  "Post-preset hook: audit the tool registry for the active preset.

Runs as :after advice on `gptel--apply-preset'.  Nucleus-side work
\(sanity check, header refresh) is handled by `nucleus--after-apply-preset'
registered in nucleus-config."
  ;; model/backend override for subagents is handled by dynamic let-bindings
  ;; in my/gptel--agent-task-with-timeout (gptel-tools-agent.el).
  (when (and (boundp 'gptel--preset) gptel--preset
             (not my/gptel--in-subagent-task)
             (bound-and-true-p gptel-mode)
             (memq gptel--preset '(gptel-plan gptel-agent)))
    ;; Audit tool registry (once per preset per buffer).
    (unless (eq my/gptel--last-audited-preset gptel--preset)
      (setq-local my/gptel--last-audited-preset gptel--preset)
      (my/gptel-audit-preset-tools gptel--preset))))

;; ==============================================================================
;; ADVICE & HOOK REGISTRATION
;; ==============================================================================

(with-eval-after-load 'gptel
  (when (fboundp 'gptel--apply-preset)
    (advice-add 'gptel--apply-preset :after #'my/gptel--after-apply-preset))
  (define-key gptel-mode-map (kbd "C-c C-p") #'my/gptel-add-project-files)
  (define-key gptel-mode-map (kbd "C-c C-x") #'gptel-toggle-tool-profile))

;; --- Curl Response Parse Hardening ---
;; gptel uses curl's -w token marker to locate the header/body boundary.
;; When curl fails early, the marker may be missing and gptel throws an
;; uncaught `search-failed` from the process sentinel.  Convert this into a
;; normal gptel error so the UI can show it and keep running.

(defun my/gptel--curl-parse-response-safe (orig proc-info)
  "Around-advice: convert uncaught errors in curl response parsing to gptel errors."
  (condition-case err
      (funcall orig proc-info)
    (search-failed
     (list nil
           "000"
           "(curl) Could not parse HTTP response (missing curl token marker)."
           (format "curl token missing: %s" (error-message-string err))))
    (error
     (list nil
           "000"
           "(curl) Could not parse HTTP response (unexpected parser error)."
           (format "curl parser error: %s" (error-message-string err))))))

(with-eval-after-load 'gptel-request
  ;; Curl hardening
  (advice-add 'gptel-curl--parse-response :around #'my/gptel--curl-parse-response-safe)
  ;; Pre-serialization content sanitizer
  (advice-add 'gptel-curl--get-args       :before #'my/gptel--pre-serialize-sanitize-messages))

;; ==============================================================================
;; PRE-SERIALIZATION CONTENT SANITIZER
;; ==============================================================================
;; json-serialize encodes Elisp nil as {} (empty object), not null or "".
;; Any message with :content nil will cause a DashScope/OpenAI 400:
;;   "Invalid type for 'messages.[N].content': expected string or array, got object"
;; This runs as :before advice on gptel-curl--get-args to catch any nil :content
;; that slipped through earlier guards (e.g. in the inject-prompt-strip-nil-tools
;; path when :content was nil rather than :null).

;; Last-resort nil guard before JSON encoding: catches any nil :content that
;; slipped through earlier guards, preventing 400 Bad Request from APIs.
(defun my/gptel--pre-serialize-sanitize-messages (info _token)
  "Ensure no message has nil :content before JSON serialization.

nil :content is encoded as {} by json-serialize, causing a 400 Bad Request
from DashScope and OpenAI-compatible APIs that expect a string or array.

Runs as :before advice on `gptel-curl--get-args'.  Coerces nil :content to
an empty string on messages that have no :tool_calls (i.e. text-role messages).
Messages with :tool_calls legitimately have :content :null which is fine."
  (when-let* ((data (plist-get info :data))
              (msgs (plist-get data :messages)))
    (cl-loop for msg across msgs
             when (and (listp msg)
                       (null (plist-get msg :content))
                       ;; :tool_calls present means the assistant is calling tools;
                       ;; its :content is intentionally :null — leave it alone.
                       ;; But if it's nil with no tool_calls, it will serialize badly.
                       (null (plist-get msg :tool_calls)))
             do (progn
                  (message "gptel: sanitizing nil :content on %s message"
                           (plist-get msg :role))
                  (plist-put msg :content "")))))


(provide 'gptel-ext-core)
;;; gptel-ext-core.el ends here
