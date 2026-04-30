;;; gptel-ext-core.el --- Core gptel configuration and hooks -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Core configuration for gptel: project temp directory, markdown face compat,
;; plain model/mode setup, default-directory, tool registry audit, and
;; pre-serialization content sanitizer.
;;
;; REMOVED (upstream gptel now handles):
;;   - :null symbol filtering in stream insertion (gptel-openai.el:136-137)
;;   - curl parse error hardening (gptel-request.el:3007-3008)
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
;; PROJECT TEMP DIRECTORY
;; ==============================================================================
;; All tool temp files go to var/tmp/ inside user-emacs-directory.

(defun my/gptel-temp-dir ()
  "Return the temp directory in user-emacs-directory, creating it if needed."
  (let ((dir (expand-file-name "tmp/" user-emacs-directory)))
    (unless (file-directory-p dir) (make-directory dir t))
    dir))

(defun my/gptel-make-temp-file (prefix &optional dir-flag suffix)
  "Like `make-temp-file' but in var/tmp/ directory.
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

;; --- Fix gptel--file-binary-p for directories ---
;; Upstream doesn't check if path is a directory before trying to read it.
;; This causes "Read error: Is a directory" when context contains directories.

(defun my/gptel--file-binary-p-fix (orig path)
  "Fix for gptel--file-binary-p to handle directories.
ORIG is the original function, PATH is the file path."
  (if (file-directory-p path)
      nil  ; Directories are not binary files
    (funcall orig path)))

(advice-add 'gptel--file-binary-p :around #'my/gptel--file-binary-p-fix)

;; --- Forward declarations ---
(defvar gptel--openrouter) ; defined later; forward-declared for byte-compiler
(defvar gptel--minimax)   ; defined later; forward-declared for byte-compiler
(defvar gptel--moonshot)  ; defined later; forward-declared for byte-compiler
(defvar gptel--cf-gateway) ; defined later; forward-declared for byte-compiler
(defvar my/gptel--in-subagent-task) ; defined in gptel-tools-agent.el

;; ==============================================================================
;; PLAIN MODEL CONFIG + MODE HOOK
;; ==============================================================================

(defcustom my/gptel-plain-model 'minimax-m2.7-highspeed
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
             my/gptel-plain-model
             (boundp 'gptel--minimax))
    (setq-local gptel-model my/gptel-plain-model)
    (setq-local gptel-backend gptel--minimax)))

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

(with-eval-after-load 'gptel-request
  (advice-add 'gptel-curl--get-args :before #'my/gptel--pre-serialize-sanitize-messages))

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
(defun my/gptel--char-problematic-p (c)
  "Return non-nil if character C is problematic for JSON serialization.
Checks for control characters, private-use chars, and non-characters."
  (or
   (and (>= c 0) (<= c 8))
   (= c 11) (= c 12)
   (and (>= c 14) (<= c 31))
   (and (>= c #xfdd0) (<= c #xfdef))
   (and (>= c #xfff0) (<= c #xffff))
   (and (>= c #xf0000) (<= c #xffffd))
   (and (>= c #x100000) (<= c #x10fffd))))

(defun my/gptel--sanitize-string-for-json (string)
  "Sanitize STRING for JSON serialization.
Removes control characters, private-use chars, and non-characters that break json-serialize.
Also removes supplementary private-use area chars (U+F0000-U+FFFFD, U+100000-U+10FFFD)."
  (when (stringp string)
    (apply #'string (seq-filter (lambda (c) (not (my/gptel--char-problematic-p c)))
                                (string-to-list string)))))

(defun my/gptel--sanitize-tool-type-symbols (tools-vec)
  "Convert :type symbols to strings in TOOLS-VEC for JSON serialization.
gptel's tool spec allows :type as a symbol (e.g., string), but json-serialize
requires string values. Recursively processes nested :properties and :items."
  (when (vectorp tools-vec)
    (cl-loop for i from 0 below (length tools-vec)
             for tool = (aref tools-vec i)
             when (listp tool)
             do
             (when-let* ((fn-spec (plist-get tool :function))
                         ((listp fn-spec))
                         (params (plist-get fn-spec :parameters))
                         ((listp params))
                         (props (plist-get params :properties))
                         ((listp props)))
               (my/gptel--sanitize-tool-props props))))
  tools-vec)

(defun my/gptel--sanitize-type-symbol (plist)
  "If PLIST has a :type that is a symbol, convert it to a string in place."
  (let ((type-val (plist-get plist :type)))
    (when (and type-val (symbolp type-val))
      (setf (plist-get plist :type) (symbol-name type-val)))))

(defun my/gptel--sanitize-tool-props (props)
  "Recursively sanitize :type symbols in tool properties PROPS."
  (cl-loop for (key val) on props by #'cddr
           when (listp val)
           do
           (my/gptel--sanitize-type-symbol val)
           (when-let* ((items (plist-get val :items))
                       ((listp items)))
             (my/gptel--sanitize-type-symbol items)
             (when-let* ((item-props (plist-get items :properties))
                         ((listp item-props)))
               (my/gptel--sanitize-tool-props item-props)))
           (when-let* ((nested-props (plist-get val :properties))
                       ((listp nested-props)))
             (my/gptel--sanitize-tool-props nested-props))))

(defun my/gptel--pre-serialize-sanitize-messages (info _uuid _include-headers)
  "Ensure no message has nil :content and sanitize all content for JSON serialization.

nil :content is encoded as {} by json-serialize, causing a 400 Bad Request.
Also sanitizes ALL content strings that may contain problematic Unicode
that breaks json-serialize (private-use chars, non-characters).
Converts non-string content (e.g., symbols, :null) to strings.
Also sanitizes tool definitions to convert :type symbols to strings.

Handles multimodal content format: [(:type \"text\" :text \"...\")]

Runs as :before advice on `gptel-curl--get-args'."
  (when-let* ((data (plist-get info :data)))
    (let ((tools (plist-get data :tools)))
      (when (vectorp tools)
        (my/gptel--sanitize-tool-type-symbols tools)))
    (when-let* ((msgs (plist-get data :messages)))
      (cl-loop for i from 0 below (length msgs)
               for msg = (aref msgs i)
               when (listp msg)
               do
               (let* ((role (plist-get msg :role))
                      (content (plist-get msg :content))
                      (new-content nil))
                 (cond
                  ((null content)
                   (unless (plist-get msg :tool_calls)
                     (message "gptel: sanitizing nil :content on %s message" role)
                     (setq new-content "")))
                  ((eq content :null)
                   (unless (plist-get msg :tool_calls)
                     (message "gptel: sanitizing :null :content on %s message" role))
                   (setq new-content ""))
                  ((vectorp content)
                   (my/gptel--sanitize-multimodal-content content))
                  ((stringp content)
                   (let ((sanitized (my/gptel--sanitize-string-for-json content)))
                     (unless (string= sanitized content)
                       (setq new-content sanitized))))
                  (t
                   (message "gptel: converting non-string :content on %s message: %S" role content)
                   (setq new-content (format "%S" content))))
                 (when new-content
                   (aset msgs i (plist-put msg :content new-content))))))))

(defun my/gptel--sanitize-multimodal-content (content-vec)
  "Sanitize text parts in multimodal CONTENT-VEC.
CONTENT-VEC is a vector like [(:type \"text\" :text \"...\")].
Handles both symbol :type 'text and string :type \"text\"."
  (cl-loop for i from 0 below (length content-vec)
           for part = (aref content-vec i)
           when (and (listp part)
                     (member (plist-get part :type) '(text "text"))
                     (stringp (plist-get part :text)))
           do
           (let* ((text (plist-get part :text))
                  (sanitized (my/gptel--sanitize-string-for-json text)))
             (unless (string= sanitized text)
               (aset content-vec i (plist-put part :text sanitized))))))


(provide 'gptel-ext-core)
;;; gptel-ext-core.el ends here
