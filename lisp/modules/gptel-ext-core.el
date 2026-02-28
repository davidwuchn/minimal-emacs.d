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

(defvar my/gptel-hidden-directives nil
  "List of directives to hide from the transient menu.")

(eval-when-compile
  (require 'gptel-openai)
  (require 'gptel-gemini)
  (require 'gptel-gh))
(require 'gptel-context)
(require 'gptel-request)
(require 'gptel-gh)
(require 'gptel-gemini)
(require 'gptel-openai)
;; (require 'gptel-openai-extras) ;; Temporarily disabled: missing dependency
(require 'recentf)
;; (add-to-list 'load-path (expand-file-name "personal" user-emacs-directory)) ;; Temporarily disabled: directory missing
;; nucleus-config is loaded independently by init.el before this file.
;; gptel-config does not require it — all nucleus calls are guarded with
;; fboundp/boundp so this file works stand-alone for testing.

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

(defvar gptel--openrouter) ; defined later; forward-declared for byte-compiler
(defvar gptel--minimax)   ; defined later; forward-declared for byte-compiler
(defvar gptel--moonshot)  ; defined later; forward-declared for byte-compiler
(defvar gptel--cf-gateway) ; defined later; forward-declared for byte-compiler

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

;; Handle nil/unknown tool calls gracefully instead of hanging the FSM.
;; When a model sends a tool call with a nil or unrecognized name, gptel's
;; `gptel--handle-tool-use' logs a message but doesn't advance the tool
;; counter, causing the FSM to hang forever.  This advice pre-marks any
;; malformed tool calls with an error result so they're skipped.
(defun my/gptel--nil-tool-call-p (tc)
  "Return non-nil when TC is a nil/null-named tool call spec."
  (let ((name (plist-get tc :name)))
    (or (null name) (eq name :null) (equal name "null"))))

(defun my/gptel--sanitize-tool-calls (fsm)
  "Remove nil/unknown-named tool calls from FSM before execution.

Two things are done for each offending entry:
1. Pre-set :result so gptel--handle-tool-use skips execution.
2. Remove the entry from :tool-use entirely so gptel--parse-tool-results
   does not emit an orphaned `tool` role message (tool_call_id=null with
   no matching tool_calls in the assistant message), which would cause a
   400 Bad Request from OpenRouter/Anthropic on the next turn."
  (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm)))
              (tool-use (plist-get info :tool-use))
              (tools (plist-get info :tools)))
    (let (pruned)
      (dolist (tc tool-use)
        (let* ((name (plist-get tc :name))
               (matched-tool (and (stringp name)
                                  (cl-find-if (lambda (ts) (string-equal-ignore-case (gptel-tool-name ts) name)) tools))))
          (if matched-tool
              (let ((correct-name (gptel-tool-name matched-tool)))
                (unless (string= name correct-name)
                  (message "gptel: repairing tool call casing %S -> %S" name correct-name)
                  (plist-put tc :name correct-name)))
            ;; Not matched: either nil or hallucinated
            (when (not (plist-get tc :result))
              (message "gptel: skipping malformed tool call (name=%S)" name)
              (plist-put tc :result
                         (format "Error: unknown or nil tool %S called by model" name))
              (push tc pruned)))))
      ;; Prune offending entries so gptel--parse-tool-results never sees them.
      ;; This prevents orphaned tool role messages (tool_call_id=null) that
      ;; cause 400 errors when the assistant message has no matching tool_calls.
      (when pruned
        (plist-put info :tool-use
                   (cl-remove-if #'my/gptel--nil-tool-call-p
                                 tool-use))
        ;; Fix A: if all tool calls were malformed and :tool-use is now empty,
        ;; gptel--handle-tool-use's when-let* will short-circuit on (ntools 0)
        ;; and never call gptel--fsm-transition, leaving the FSM stuck in TOOL
        ;; state forever.  Force it to DONE so the turn ends cleanly.
        (when (null (plist-get info :tool-use))
          (message "gptel: all tool calls were malformed, advancing FSM to DONE")
          (funcall (plist-get info :callback)
                   "gptel: turn skipped (all tool calls had nil/unknown names)" info)
          (gptel--fsm-transition fsm 'DONE))))))

(with-eval-after-load 'gptel-request
  ;; Tool-call guards
  (advice-add 'gptel--handle-tool-use     :before #'my/gptel--sanitize-tool-calls)
  (advice-add 'gptel--handle-tool-use     :before #'my/gptel--detect-doom-loop)
  ;; Curl hardening
  (advice-add 'gptel-curl--parse-response :around #'my/gptel--curl-parse-response-safe)
  ;; Dedup tools before serialization
  (advice-add 'gptel--parse-tools         :around #'my/gptel--dedup-tools-before-parse)
  ;; Reasoning/thinking content preservation
  (advice-add 'gptel--handle-wait         :after  #'my/gptel--reset-reasoning-block)
  (advice-add 'gptel-curl--get-args       :before #'my/gptel--pre-serialize-inject-reasoning)
  (advice-add 'gptel-curl--get-args       :before #'my/gptel--pre-serialize-inject-noop)
  (advice-add 'gptel--inject-prompt       :after  #'my/gptel--inject-prompt-strip-nil-tools)
  (advice-add 'gptel--inject-prompt       :after  #'my/gptel--inject-prompt-patch-reasoning))

;; --- Doom-loop detection (Fix C) ---
;; Mirrors OpenCode's doom_loop permission: if the same tool is called with the
;; same arguments 3 consecutive times, the agent is stuck.  We abort the turn
;; rather than ask (no interactive permission system in gptel), but the
;; threshold and fingerprint logic are taken directly from OpenCode's
;; packages/opencode/src/session/processor.ts (DOOM_LOOP_THRESHOLD = 3).

(defcustom my/gptel-doom-loop-threshold 3
  "Number of consecutive identical tool calls that trigger doom-loop abort.
Mirrors OpenCode's DOOM_LOOP_THRESHOLD.  Only calls with the same tool name
AND the same arguments count; different tools or different args do not."
  :type 'integer
  :group 'gptel)

(defun my/gptel--tool-call-fingerprint (tc)
  "Return a fingerprint string for tool call TC.
The fingerprint is \"NAME:MD5(ARGS)\" so two calls are considered identical
only when both the tool name and the serialized argument plist match."
  (let* ((name (or (plist-get tc :name) "nil"))
         (args (plist-get tc :args))
         (args-str (if args (format "%S" args) "nil")))
    (concat name ":" (md5 args-str))))

(cl-defun my/gptel--detect-doom-loop (fsm)
  "Abort FSM when the same tool call repeats `my/gptel-doom-loop-threshold' times.

Checks the fingerprint of each tool call in the current :tool-use list against
the rolling history stored in :doom-loop-fingerprints.  When the last N
fingerprints are identical, the turn is forcibly advanced to DONE.

This mirrors OpenCode's doom_loop detection (same tool + same args × N)."
  (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm)))
              (tool-use (plist-get info :tool-use)))
    ;; Append fingerprints for this cycle's tool calls.
    (let* ((fps (or (plist-get info :doom-loop-fingerprints) '()))
           (new-fps (mapcar #'my/gptel--tool-call-fingerprint tool-use))
           (fps (append fps new-fps)))
      (plist-put info :doom-loop-fingerprints fps)
      ;; Check whether every tool call in this cycle is a doom-loop repeat.
      (dolist (fp new-fps)
        (let* ((n my/gptel-doom-loop-threshold)
               ;; Count consecutive trailing occurrences of this fingerprint.
               (tail (reverse fps))
               (run (length (seq-take-while (lambda (f) (equal f fp)) tail))))
          (when (>= run n)
            (message "gptel: doom-loop detected — \"%s\" called %d times with identical args, aborting turn"
                     (car (split-string fp ":")) run)
            (funcall (plist-get info :callback)
                     (format "gptel: doom-loop aborted — tool \"%s\" called %d consecutive times \
with identical arguments.  Try a different approach or break the task into smaller steps."
                             (car (split-string fp ":")) run)
                     info)
            (gptel--fsm-transition fsm 'DONE)
            ;; Return immediately — transition already fired.
            (cl-return-from my/gptel--detect-doom-loop)))))))



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

;; --- Forward declarations ---
;; my/gptel--in-subagent-task, my/gptel-subagent-model, my/gptel-subagent-backend
;; are defined properly (defvar/defcustom) further below — no forward decls needed.
(defvar gptel--crowdsourced-prompts)        ; defined in gptel-transient
(defvar gptel--crowdsourced-prompts-url)    ; defined in gptel-transient
(defvar gptel--set-buffer-locally)          ; defined in gptel-transient
(declare-function gptel--set-with-scope "gptel-transient")
(declare-function gptel--edit-directive "gptel-transient")
(declare-function gptel--crowdsourced-prompts "gptel-transient")

;; --- Tool Registry Audit ---

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
  ;; model/backend override for subagents is handled by
  ;; my/gptel--agent-task-override-model via dynamic let-binding.
  (when (and (boundp 'gptel--preset) gptel--preset
             (not my/gptel--in-subagent-task)
             (bound-and-true-p gptel-mode)
             (memq gptel--preset '(gptel-plan gptel-agent)))
    ;; Audit tool registry (once per preset per buffer).
    (unless (eq my/gptel--last-audited-preset gptel--preset)
      (setq-local my/gptel--last-audited-preset gptel--preset)
      (my/gptel-audit-preset-tools gptel--preset))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel--apply-preset)
    (advice-add 'gptel--apply-preset :after #'my/gptel--after-apply-preset))
  (advice-add 'gptel--display-tool-results
              :after #'my/gptel--capture-tool-reasoning)
  (add-hook 'gptel-post-response-functions #'my/gptel-add-prompt-marker)
  (when (boundp 'gptel-mode-map)
    (define-key gptel-mode-map [remap keyboard-quit] #'my/gptel-keyboard-quit)
    ;; A dedicated abort binding (muscle memory from terminal "Ctrl-C").
    (define-key gptel-mode-map (kbd "C-c C-k") #'my/gptel-abort-here))
  (define-key gptel-mode-map (kbd "C-c C-p") #'my/gptel-add-project-files)
  (define-key gptel-mode-map (kbd "C-c C-x") #'gptel-toggle-tool-profile)
  )

;; Fix: gptel-system-prompt transient doesn't preserve the originating buffer.
;; When the [Prompt:] header button is clicked, gptel-system-prompt opens a
;; transient.  By the time the suffix fires, current-buffer may be a different
;; window's buffer.  We capture the gptel buffer at click time and pass it
;; explicitly to gptel--edit-directive via :buffer.

(defun my/gptel--suffix-system-message-in-buffer (orig &optional cancel)
  "Around-advice for `gptel--suffix-system-message': use originating gptel buffer.
Also ensures the system message is applied buffer-locally, not globally."
  (if cancel
      (funcall orig cancel)
    (let* ((buf (or (and (boundp 'my/gptel--transient-origin-buffer)
                         (buffer-live-p my/gptel--transient-origin-buffer)
                         my/gptel--transient-origin-buffer)
                    (current-buffer)))
           ;; Force buffer-local scope so C-c C-c writes to buf only,
           ;; not globally (gptel--set-buffer-locally defaults to nil
           ;; when opened from header-line rather than gptel-menu).
           (gptel--set-buffer-locally t))
      (with-current-buffer buf
        (gptel--edit-directive 'gptel--system-message
          :setup #'activate-mark
          :buffer buf
          :callback (lambda (_) (call-interactively #'gptel-menu)))))))

(defvar my/gptel--transient-origin-buffer nil
  "Buffer that opened the gptel-system-prompt transient.")

(defvar my/gptel--transient-origin-preset nil
  "Preset from the buffer that opened the gptel-system-prompt transient.
Used to show different directive menus for gptel-agent vs regular gptel.")

(with-eval-after-load 'gptel-transient
  (advice-add 'gptel--setup-directive-menu
              :around #'my/gptel--filter-directive-menu)
  (advice-add 'gptel-system-prompt :before
              (lambda (&rest _)
                (setq my/gptel--transient-origin-buffer (current-buffer))
                (setq my/gptel--transient-origin-preset
                      (and (boundp 'gptel--preset) gptel--preset))))
  (advice-add 'gptel--suffix-system-message
              :around #'my/gptel--suffix-system-message-in-buffer))

(defvar gptel-directives)

(defun my/gptel--filter-directive-menu (orig sym msg &optional external)
  "Around-advice: filter directives based on whether we're in gptel-agent or regular gptel.
For gptel-agent/gptel-plan buffers: show only nucleus-gptel-agent and nucleus-gptel-plan.
For regular gptel buffers: show all directives except hidden ones."
  (let* ((is-agent-buffer (memq my/gptel--transient-origin-preset '(gptel-plan gptel-agent)))
         (filtered
          (if is-agent-buffer
              (seq-filter (lambda (e) (memq (car e) '(nucleus-gptel-plan nucleus-gptel-agent)))
                          gptel-directives)
            (seq-remove (lambda (e) (memq (car e) (if (boundp 'my/gptel-hidden-directives) my/gptel-hidden-directives nil)))
                        gptel-directives)))
         (old-directives gptel-directives))
    (unwind-protect
        (progn
          (setq gptel-directives filtered)
          (funcall orig sym msg external))
      (setq gptel-directives old-directives))))


(defun my/gptel--csv-parse-row ()
  "Parse one RFC-4180 CSV row at point, return list of field strings.
Handles quoted fields with embedded newlines and escaped double-quotes.
Advances point to the start of the next row."
  (let (fields)
    (while (not (or (eobp) (and fields (eolp))))
      (let ((field
             (if (eq (char-after) ?\")
                 ;; Quoted field: scan for closing unescaped quote
                 (let ((start (1+ (point))) result)
                   (forward-char 1)           ; skip opening "
                   (while (not result)
                     (if (not (search-forward "\"" nil t))
                         (setq result "")     ; unterminated — give up
                       (if (eq (char-after) ?\")
                           (forward-char 1)   ; "" → escaped quote, continue
                         (setq result         ; found real closing quote
                               (buffer-substring-no-properties
                                start (1- (point)))))))
                   ;; Skip trailing comma if present
                   (when (eq (char-after) ?,) (forward-char 1))
                   (string-replace "\"\"" "\"" result))
               ;; Unquoted field: read until comma or EOL
               (let ((start (point)))
                 (skip-chars-forward "^,\n")
                 (prog1 (buffer-substring-no-properties start (point))
                   (when (eq (char-after) ?,) (forward-char 1)))))))
        (push field fields)))
    ;; Skip EOL
    (when (eolp) (forward-char 1))
    (nreverse fields)))

(with-eval-after-load 'gptel-transient
  ;; Cleaner picker: show only a short single-line preview instead of the
  ;; full multi-line prompt as annotation (which makes selection unusable).
  (defun gptel--read-crowdsourced-prompt ()
    "Pick a crowdsourced system prompt for gptel (clean single-line preview)."
    (interactive)
    (if (not (hash-table-empty-p (gptel--crowdsourced-prompts)))
        (let ((choice
               (completing-read
                "Pick and edit prompt: "
                (lambda (str pred action)
                  (if (eq action 'metadata)
                      `(metadata
                        (affixation-function .
                                             (lambda (cands)
                                               (mapcar
                                                (lambda (c)
                                                  (let* ((full (gethash c gptel--crowdsourced-prompts))
                                                         (preview (truncate-string-to-width
                                                                   (replace-regexp-in-string
                                                                    "[\n\r]+" " " (or full ""))
                                                                   60 nil nil "…")))
                                                    (list c ""
                                                          (concat (propertize " " 'display '(space :align-to 36))
                                                                  (propertize preview 'face 'completions-annotations)))))
                                                cands))))
                    (complete-with-action action gptel--crowdsourced-prompts str pred)))
                nil t)))
          (when-let* ((prompt (gethash choice gptel--crowdsourced-prompts)))
            (gptel--set-with-scope
             'gptel--system-message prompt gptel--set-buffer-locally)
            (gptel--edit-directive 'gptel--system-message
              :callback (lambda (_) (call-interactively #'gptel-menu)))))
      (message "No prompts available.")))

  ;; Replace upstream gptel--crowdsourced-prompts with a version that uses
  ;; a correct RFC-4180 parser.  The upstream gptel--read-csv-column fails on
  ;; multi-line quoted fields (common in awesome-chatgpt-prompts CSV).
  (defun gptel--crowdsourced-prompts ()
    "Acquire and read crowdsourced LLM system prompts (RFC-4180 fix)."
    (when (hash-table-p gptel--crowdsourced-prompts)
      (when (hash-table-empty-p gptel--crowdsourced-prompts)
        (unless gptel-crowdsourced-prompts-file
          (run-at-time 0 nil #'gptel-system-prompt)
          (user-error "No crowdsourced prompts available"))
        (unless (and (file-exists-p gptel-crowdsourced-prompts-file)
                     (time-less-p
                      (time-subtract (current-time) (days-to-time 14))
                      (file-attribute-modification-time
                       (file-attributes gptel-crowdsourced-prompts-file))))
          (when (y-or-n-p
                 (concat "Fetch crowdsourced system prompts from "
                         (propertize "https://github.com/f/awesome-chatgpt-prompts"
                                     'face 'link) "?"))
            (message "Fetching prompts...")
            (let ((dir (file-name-directory gptel-crowdsourced-prompts-file)))
              (unless (file-exists-p dir) (mkdir dir 'create-parents))
              (if (url-copy-file gptel--crowdsourced-prompts-url
                                 gptel-crowdsourced-prompts-file t)
                  (message "Fetching prompts... done.")
                (message "Could not retrieve new prompts.")))))
        (if (not (file-readable-p gptel-crowdsourced-prompts-file))
            (progn (message "No crowdsourced prompts available")
                   (call-interactively #'gptel-system-prompt))
          (with-temp-buffer
            (insert-file-contents gptel-crowdsourced-prompts-file)
            (goto-char (point-min))
            (my/gptel--csv-parse-row)          ; skip header row
            (while (not (eobp))
              (let* ((row (my/gptel--csv-parse-row))
                     (act (car row))
                     (prompt (cadr row)))
                (when (and (stringp act)   (not (string-empty-p act))
                           (stringp prompt)(not (string-empty-p prompt)))
                  (puthash act prompt gptel--crowdsourced-prompts)))))))
      gptel--crowdsourced-prompts)))

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



;; --- Duplicate Tool Name Guard ---
;; gptel--parse-tools maps gptel-tools directly to JSON without deduplication.
;; When gptel-tools contains two structs with the same tool name (e.g. after a
;; config reload where both safe-get-tool and gptel-make-tool resolve the same
;; name), the API receives duplicate function entries and returns 400.
;; Guard against this at serialization time by deduplicating by name.
(defun my/gptel--dedup-tools-before-parse (orig backend tools)
  "Around-advice on `gptel--parse-tools': remove duplicate tool names before parsing.
Uses last-wins so the most recently registered struct takes precedence."
  (funcall orig backend
           (let ((seen (make-hash-table :test #'equal)))
             (nreverse
              (cl-loop for tool in (nreverse (copy-sequence tools))
                       for name = (ignore-errors (gptel-tool-name tool))
                       when (and name (not (gethash name seen)))
                       do (puthash name t seen)
                       and collect tool)))))



;; --- Thinking/Reasoning Content Preservation ---
;; Moonshot/Kimi (and other thinking-enabled models) require that every assistant
;; message with tool_calls carries a reasoning_content field in the conversation
;; history.  There are two separate problems to solve:
;;
;; PROBLEM 1: :reasoning-block state leaks across requests.
;;   gptel-curl--stream-filter tracks a :reasoning-block state machine for
;;   <think>-tag based reasoning.  After the first response completes, it sets
;;   :reasoning-block to 'done.  gptel--handle-wait clears :reasoning but NOT
;;   :reasoning-block.  On the second request, the JSON-field reasoning capture
;;   in gptel-curl--parse-stream is gated by (unless (eq :reasoning-block 'done))
;;   so ALL reasoning chunks for turn 2+ are silently dropped.  Fix: reset
;;   :reasoning-block to nil on each new WAIT via :after advice on gptel--handle-wait.
;;
;; PROBLEM 2: reasoning_content missing from replayed history.
;;   Even after fixing problem 1, when the conversation is re-read from the buffer
;;   (gptel--parse-buffer) or when the in-memory data :messages is built up over
;;   multiple tool-loop cycles, the assistant+tool_calls messages may lack
;;   reasoning_content.  Fix: a single pre-serialization sweep in
;;   gptel-curl--get-args patches any remaining gaps before JSON encoding.

(defvar-local my/gptel--tool-reasoning-alist nil
  "Alist of (TOOL-CALL-ID . REASONING-STRING) for the current gptel buffer.
Populated by `my/gptel--capture-tool-reasoning' after each tool call turn
so that `my/gptel--parse-buffer-inject-reasoning' can recover reasoning_content
when re-serializing the conversation for APIs that require it (e.g. Moonshot).")

(defun my/gptel--thinking-model-p ()
  "Return the reasoning field keyword if current model has thinking/reasoning enabled.
Returns :reasoning_content for Moonshot (:thinking param),
:reasoning for OpenRouter/DeepSeek (:reasoning param), nil otherwise."
  (when (fboundp 'gptel--model-request-params)
    (let ((params (gptel--model-request-params gptel-model)))
      (cond
       ((plist-member params :thinking)  :reasoning_content)
       ((plist-member params :reasoning) :reasoning)
       (t nil)))))

(defun my/gptel--reset-reasoning-block (fsm)
  "After-advice on `gptel--handle-wait': reset :reasoning-block to nil.
gptel--handle-wait clears :reasoning but leaves :reasoning-block set to
'done from the previous response.  This blocks JSON-field reasoning chunk
capture (gated by `unless (eq :reasoning-block 'done)') for all subsequent
requests in the same FSM.  Reset it here so each new request starts fresh."
  (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm))))
    (when (plist-get info :reasoning-block)
      (plist-put info :reasoning-block nil))))



(defun my/gptel--capture-tool-reasoning (_tool-results info)
  "After tool results are displayed, store reasoning keyed by tool-call ID.
Stores the reasoning string (possibly empty) for every tool-call turn when
the active model has thinking enabled.  Empty string is stored deliberately:
Moonshot requires the field to be *present* in every assistant tool-call
message, even when the model produced no visible reasoning for that turn.
:after advice on `gptel--display-tool-results'."
  (when-let* ((start-marker (plist-get info :position))
              (buf (and (markerp start-marker) (marker-buffer start-marker))))
    (with-current-buffer buf
      ;; Only capture for thinking-enabled models.
      (when (my/gptel--thinking-model-p)
        (let ((reasoning (or (plist-get info :reasoning) "")))
          (dolist (tool-use (plist-get info :tool-use))
            (when-let* ((id (plist-get tool-use :id))
                        ((stringp id)))
              (setf (alist-get id my/gptel--tool-reasoning-alist nil nil #'equal)
                    reasoning))))))))

(defun my/gptel--parse-buffer-inject-reasoning (orig backend &optional max-entries)
  "Around-advice on `gptel--parse-buffer': inject reasoning_content into tool-call messages.
For backends where thinking is enabled (e.g. Moonshot/Kimi), every assistant
message with tool_calls must carry reasoning_content or the API returns 400.
The field is injected even as empty string when no reasoning was captured for
that turn — the API requires presence, not a non-empty value."
  (let ((prompts (funcall orig backend max-entries)))
    ;; Only act for OpenAI-compatible backends with thinking/reasoning enabled.
    (when-let* (((cl-typep backend 'gptel-openai))
                (reasoning-key (my/gptel--thinking-model-p)))
      (dolist (msg prompts)
        (when (and (listp msg)
                   (equal (plist-get msg :role) "assistant")
                   (plist-get msg :tool_calls)
                   (not (plist-get msg reasoning-key)))
          ;; Look up stored reasoning by the first tool call's ID.
          ;; Fall back to "" when not in alist — the field must be present.
          (let* ((tc (and (vectorp (plist-get msg :tool_calls))
                          (> (length (plist-get msg :tool_calls)) 0)
                          (aref (plist-get msg :tool_calls) 0)))
                 (id (and tc (plist-get tc :id)))
                 (stored (if id
                             (alist-get id my/gptel--tool-reasoning-alist
                                        :absent nil #'equal)
                           :absent))
                 (reasoning (if (or (eq stored :absent)
                                    (and (stringp stored) (string-empty-p stored)))
                                :null
                              stored)))
            (plist-put msg reasoning-key reasoning)))))
    prompts))


(with-eval-after-load 'gptel-openai
  (advice-add 'gptel--parse-buffer
              :around #'my/gptel--parse-buffer-inject-reasoning))

;; Pre-serialization safety sweep: patch any remaining gaps right before JSON
;; encoding.  Covers the buffer re-parse path and any edge cases the streaming
;; injection misses (e.g. non-streaming responses, buffer-reloads).


(defun my/gptel--pre-serialize-inject-noop (info _token)
  "Before-advice on `gptel-curl--get-args': inject dummy _noop tool for LiteLLM/Anthropic.
If tool_calls are present in message history but no active tools are selected,
many proxies crash with 400 Bad Request. We inject a dummy to satisfy validation."
  (when-let* ((data  (plist-get info :data))
              (msgs  (plist-get data :messages)))
    (let* ((tools (plist-get data :tools))
           (has-tools (and tools (> (length tools) 0))))
      (unless has-tools
        (let ((has-history-tools nil))
          (cl-loop for msg across msgs
                   do (when (and (listp msg)
                                 (or (plist-get msg :tool_calls)
                                     (equal (plist-get msg :role) "tool")))
                        (setq has-history-tools t)
                        (cl-return)))
          (when has-history-tools
            (message "gptel: history has tool_calls but no tools active; injecting dummy _noop")
            (let ((noop-tool
                   (list :type "function"
                         :function (list :name "_noop"
                                         :description "Placeholder proxy compatibility tool"
                                         :parameters (list :type "object" :properties (list :_dummy (list :type "string")))))))
              (plist-put info :data (plist-put data :tools (vector noop-tool))))))))))(defun my/gptel--pre-serialize-inject-reasoning (info _token)
  "Before-advice on `gptel-curl--get-args': ensure reasoning_content on tool-call messages.
For Moonshot (and any model with :thinking/:reasoning request-params), every
assistant message that contains tool_calls must carry a reasoning_content field."
  (let* ((model   (plist-get info :model))
         (backend (plist-get info :backend))
         (params  (and model (cl-typep backend 'gptel-openai)
                       (gptel--model-request-params model)))
         (reasoning-key
          (cond
           ((plist-member params :thinking)  :reasoning_content)
           ((plist-member params :reasoning) :reasoning)
           (t nil))))
    (when reasoning-key
      (let* ((data      (plist-get info :data))
             (msgs      (plist-get data :messages))
             (gptel-buf (plist-get info :buffer))
             (reasoning-alist
              (and gptel-buf (buffer-live-p gptel-buf)
                   (buffer-local-value 'my/gptel--tool-reasoning-alist gptel-buf))))
        (when (and msgs (> (length msgs) 0))
          (cl-loop
           for msg across msgs
           when (and (listp msg)
                     (equal (plist-get msg :role) "assistant")
                     (plist-get msg :tool_calls)
                     (not (plist-get msg reasoning-key)))
           do (let* ((tc  (and (vectorp (plist-get msg :tool_calls))
                               (> (length (plist-get msg :tool_calls)) 0)
                               (aref (plist-get msg :tool_calls) 0)))
                     (id  (and tc (plist-get tc :id)))
                     (stored (alist-get id reasoning-alist :absent nil #'equal)))
                (plist-put msg reasoning-key
                           (if (or (eq stored :absent)
                                   (and (stringp stored) (string-empty-p stored)))
                               :null
                             stored))))))))  )

;; --- Nil-named tool call guard (inject-prompt level) ---
;; gptel-curl--parse-stream injects the assistant+tool_calls message into
;; :data :messages at [DONE] time, BEFORE my/gptel--sanitize-tool-calls runs.
;; If the model emits a tool call with name=nil/"null" (an OpenRouter/litellm
;; artifact), that nil-named entry is baked into the stored assistant message.
;; On the next request, gptel--parse-buffer replays it verbatim and
;; OpenRouter/Anthropic rejects it with 400 "Invalid input".
;;
;; Fix: strip nil-named tool_calls from the assistant message at inject time,
;; before the message is appended to :data :messages.
(defun my/gptel--inject-prompt-strip-nil-tools (backend data new-prompt &rest _)
  "Strip nil/null-named tool_calls from assistant messages before injection.

Runs as :after advice on `gptel--inject-prompt'.  Prevents 400 errors from
OpenRouter/Anthropic when the model emits a tool call with a nil function name
(a known OpenRouter/litellm streaming artifact)."
  (ignore data)
  (when (cl-typep backend 'gptel-openai)
    (let ((msgs (cond
                 ((keywordp (car-safe new-prompt)) (list new-prompt))
                 ((listp new-prompt) new-prompt)
                 (t (list new-prompt)))))
      (dolist (msg msgs)
        (when (and (listp msg)
                   (equal (plist-get msg :role) "assistant"))
          (when-let* ((tcs (plist-get msg :tool_calls))
                      ((vectorp tcs)))
            (let ((filtered (cl-remove-if
                             (lambda (tc)
                               (let* ((func (plist-get tc :function))
                                      (name (and func (plist-get func :name))))
                                 (or (null name)
                                     (eq name :null)
                                     (equal name "null"))))
                             tcs)))
              (if (= (length filtered) 0)
                  ;; No valid tool calls remain — demote to plain assistant message
                  ;; so the conversation stays well-formed.
                  (progn (plist-put msg :tool_calls nil)
                         (when (eq (plist-get msg :content) :null)
                           (plist-put msg :content "")))
                (plist-put msg :tool_calls (vconcat filtered))))))))))

;; Immediate patch: stamp reasoning_content right when the message is injected
;; into data :messages so it never travels without the field.
(defun my/gptel--inject-prompt-patch-reasoning (backend data new-prompt &rest _)
  "After-advice on `gptel--inject-prompt': stamp reasoning_content on tool-call messages."
  (let* ((model-name (plist-get data :model))
         (model (and model-name
                     (if (symbolp model-name) model-name (intern model-name))))
         (params (and model (cl-typep backend 'gptel-openai)
                      (gptel--model-request-params model)))
         (reasoning-key
          (cond
           ((plist-member params :thinking)  :reasoning_content)
           ((plist-member params :reasoning) :reasoning)
           (t nil))))
    (when reasoning-key
      (let ((msgs (cond
                   ((keywordp (car-safe new-prompt)) (list new-prompt))
                   ((listp new-prompt) new-prompt)
                   (t (list new-prompt)))))
        (dolist (msg msgs)
          (when (and (listp msg)
                     (equal (plist-get msg :role) "assistant")
                     (plist-get msg :tool_calls)
                     (not (plist-get msg reasoning-key)))
            (plist-put msg reasoning-key :null))))))  )



;; --- Always-Interruptable Requests ---
;; Two layers:
;; 1) Make curl fail fast on network stalls.
;; 2) Provide a single key (C-g) that aborts the active gptel request in gptel
;;    buffers, instead of only quitting UI state.

(defgroup my/gptel-interrupt nil
  "Fast interruption and timeouts for gptel requests."
  :group 'gptel)

(defcustom my/gptel-curl-connect-timeout 10
  "Seconds to wait for curl to connect."
  :type 'integer
  :group 'my/gptel-interrupt)

(defcustom my/gptel-curl-max-time 90
  "Maximum seconds for a single gptel curl request."
  :type 'integer
  :group 'my/gptel-interrupt)

(defcustom my/gptel-curl-low-speed-time 15
  "Seconds of low-speed allowed before curl aborts."
  :type 'integer
  :group 'my/gptel-interrupt)

(defcustom my/gptel-curl-low-speed-limit 50
  "Bytes/sec threshold for curl's low-speed detection."
  :type 'integer
  :group 'my/gptel-interrupt)

(defun my/gptel--install-fast-curl-timeouts ()
  "Set `gptel-curl-extra-args' for fast failure on stalls."
  (setq gptel-curl-extra-args
        (list
         "--connect-timeout" (number-to-string my/gptel-curl-connect-timeout)
         "--max-time" (number-to-string my/gptel-curl-max-time)
         "-y" (number-to-string my/gptel-curl-low-speed-time)
         "-Y" (number-to-string my/gptel-curl-low-speed-limit)
         ;; Work around some HTTP/2/proxy stalls where we never see the first
         ;; status line ("HTTP/..."), leaving gptel stuck "waiting on headline".
         "--http1.1"
         ;; Make curl stream output as it arrives.
         "--no-buffer")))

(with-eval-after-load 'gptel-request
  (my/gptel--install-fast-curl-timeouts))




;; Used to cancel async tool callbacks after abort.
(defvar-local my/gptel--abort-generation 0
  "Monotonic counter incremented when aborting gptel activity in this buffer.")

(defvar my/gptel-prompt-marker "### "
  "Prompt marker inserted at end of a gptel buffer.")

(defun my/gptel--prompt-marker-present-at-eob-p ()
  "Return non-nil if the last non-blank line at EOB is a prompt marker." 
  (save-excursion
    (goto-char (point-max))
    (skip-chars-backward " \t\n")
    (beginning-of-line)
    (looking-at-p (concat "^" (regexp-quote my/gptel-prompt-marker)))))

(defun my/gptel--insert-prompt-marker-at-eob ()
  "Insert a single prompt marker at end of buffer." 
  (unless (my/gptel--prompt-marker-present-at-eob-p)
    (goto-char (point-max))
    ;; Keep exactly one marker line; no extra blank line.
    (unless (bolp) (insert "\n"))
    (insert my/gptel-prompt-marker)))



(defun my/gptel-abort-here ()
  "Abort any active gptel request for the current buffer.

This wraps `gptel-abort' and also kills any agent sub-processes or
introspector tasks that may be running. Safe to call even when no
request is active."
  (interactive)
  ;; Bump generation so async tool sentinels can self-cancel.
  (setq-local my/gptel--abort-generation (1+ my/gptel--abort-generation))

  ;; Abort main gptel request
  (when (fboundp 'gptel-abort)
    (ignore-errors (gptel-abort (current-buffer))))
  ;; Kill all gptel-related sub-processes.
  ;; Prefer the explicit tag `my/gptel-managed`, but also catch gptel's own curl
  ;; process (buffer is typically named " *gptel-curl*" with a leading space).
  ;; This prevents accidentally killing unrelated curl/rg processes.
  (let ((killed 0))
    (dolist (proc (process-list))
      (when (and (process-live-p proc)
                 (or (process-get proc 'my/gptel-managed)
                     ;; gptel's internal curl process is named "gptel-curl".
                     (string= (process-name proc) "gptel-curl")
                     ;; Also match by process buffer name.
                     (and (process-buffer proc)
                          (buffer-name (process-buffer proc))
                          (string-match-p "gptel-curl" (buffer-name (process-buffer proc))))
                     ;; Generic catch: gptel tool processes we create are named gptel-...
                     (string-prefix-p "gptel-" (process-name proc))))
        (cl-incf killed)
        (message "Killing gptel/subagent process: %s" (process-name proc))
        ;; Prevent sentinels/filters from writing into buffers after abort.
        (ignore-errors (set-process-filter proc #'ignore))
        (ignore-errors (set-process-sentinel proc #'ignore))
        (delete-process proc)))
    ;; Restore gptel-agent header-line with [Agent]/[Plan] toggle button
    (when (and gptel-mode gptel-use-header-line)
      (if (fboundp 'gptel-use-header-line)
          (gptel-use-header-line)
        (setq header-line-format nil)))
    ;; Add prompt marker and position cursor for next input
    (when gptel-mode
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (my/gptel--insert-prompt-marker-at-eob)
        ;; Position cursor after marker
        (when (search-backward "### " nil t)
          (goto-char (match-end 0)))))
    (message "Aborted gptel activity (%d process%s killed) - ready for next prompt"
             killed (if (= killed 1) "" "es"))))



;; --- FSM Error Recovery ---
;; Workaround for gptel FSM getting stuck on JSON parsing errors

(defun my/gptel-fix-fsm-stuck-in-type (orig-fn process status)
  "Fix gptel streaming FSM getting stuck when curl fails before headers.
If curl exits before sending HTTP headers, `gptel-curl--stream-filter`
never transitions the FSM from WAIT to TYPE. Then the cleanup sentinel
transitions it from WAIT to TYPE, leaving it stuck in TYPE forever.
This advice forces the final transition."
  (let* ((fsm (car (alist-get process (bound-and-true-p gptel--request-alist))))
         (info (and fsm (gptel-fsm-info fsm)))
         (state-before (and fsm (gptel-fsm-state fsm))))
    (funcall orig-fn process status)
    (when (and fsm
               (eq (gptel-fsm-state fsm) 'TYPE)
               (not (eq state-before 'TYPE)))
      (message "gptel: Unsticking FSM from TYPE -> next state (curl failed early)")
      (gptel--fsm-transition fsm))))

(advice-add 'gptel-curl--stream-cleanup :around #'my/gptel-fix-fsm-stuck-in-type)

;; --- Automatic Retry for Transient API Errors ---
;; Gemini often returns "Malformed JSON" due to API load or payload limits.
;; This automatically retries the request up to 3 times before failing.

(defcustom my/gptel-max-retries nil
  "Number of times to retry failed gptel requests.
If nil, retry indefinitely using exponential backoff (capped at 30s)."
  :type '(choice (const :tag "Infinite" nil) integer)
  :group 'gptel)

(defun my/gptel-auto-retry (orig-fn machine &optional new-state)
  "Intercept FSM transitions to ERRS and retry the request if transient.
Implements OpenCode-style exponential backoff for network/overload errors."
  (unless new-state (setq new-state (gptel--fsm-next machine)))
  (let* ((info (gptel-fsm-info machine))
         (error-data (plist-get info :error))
         (http-status (plist-get info :http-status))
         (retries (or (plist-get info :retries) 0)))
    (if (and (eq new-state 'ERRS)
             (or (null my/gptel-max-retries) (< retries my/gptel-max-retries))
             (or (and (stringp error-data)
                      (string-match-p "Malformed JSON\\|Could not parse HTTP\\|json-read-error\\|Empty reply\\|Timeout\\|timeout\\|curl: (28)\\|curl: (6)\\|curl: (7)\\|Bad Gateway\\|Service Unavailable\\|Gateway Timeout\\|Connection refused\\|Could not resolve host\\|Overloaded\\|overloaded\\|Too Many Requests" error-data))
                 (and (numberp http-status) (memq http-status '(408 429 500 502 503 504)))
                 ;; Catch dictionary format errors from OpenCode style backend responses
                 (and (listp error-data)
                      (string-match-p "overloaded\\|too many requests\\|rate limit\\|timeout\\|free usage limit" 
                                      (downcase (or (plist-get error-data :message) ""))))))
        (let* ((base-delay 2.0)
               (factor 2.0)
               (delay (min 30.0 (* base-delay (expt factor retries)))))
          (if my/gptel-max-retries
              (message "gptel: API failed with '%s'. Retrying (%d/%d) in %.1fs..." 
                       (if (stringp error-data) (string-trim error-data)
                         (if http-status (format "HTTP %s" http-status) "Transient API Error"))
                       (1+ retries) my/gptel-max-retries delay)
            (message "gptel: API failed with '%s'. Retrying (Attempt %d) in %.1fs..." 
                     (if (stringp error-data) (string-trim error-data)
                       (if http-status (format "HTTP %s" http-status) "Transient API Error"))
                     (1+ retries) delay))
          
          ;; Clean up partial buffer insertions if any
          (when-let* ((start-marker (plist-get info :position))
                      (tracking-marker (plist-get info :tracking-marker))
                      (buf (marker-buffer tracking-marker)))
            (when (buffer-live-p buf)
              (with-current-buffer buf
                (let ((inhibit-read-only t))
                  (delete-region start-marker tracking-marker)
                  (set-marker tracking-marker start-marker)))))
          
          ;; Reset FSM state to WAIT to trigger a fresh request
          (plist-put info :error nil)
          (plist-put info :status nil)
          (plist-put info :http-status nil)
          (plist-put info :retries (1+ retries))
          
          ;; Schedule the FSM transition asynchronously (non-blocking exponential backoff)
          (run-at-time delay nil
                       (lambda (m f-orig)
                         (funcall f-orig m 'WAIT))
                       machine orig-fn)
          ;; Return nil to abort the current transition to ERRS and let the timer take over
          nil)
      (funcall orig-fn machine new-state))))

(advice-add 'gptel--fsm-transition :around #'my/gptel-auto-retry)

;; --- Fix gptel-agent Missing FSM Handlers ---
;; `gptel-agent` defines its own handlers for background tasks but forgets to
;; include DONE, ERRS, and ABRT! This causes background agents to hang forever
;; on errors or completion because the cleanup callback is never called.

(with-eval-after-load 'gptel-agent-tools
  (add-to-list 'gptel-agent-request--handlers '(DONE . (gptel--handle-post)))
  (add-to-list 'gptel-agent-request--handlers '(ERRS . (gptel--handle-post)))
  (add-to-list 'gptel-agent-request--handlers '(ABRT . (gptel--handle-post)))
  
  ;; Make agent tasks fail loudly instead of quietly feeding errors to the LLM
  (advice-add 'gptel-agent--task :around
              (lambda (orig main-cb agent-type desc prompt)
                (let* ((main-buf (current-buffer))
                       (main-fsm (buffer-local-value 'gptel--fsm-last main-buf))
                       (new-cb (lambda (result)
                                 (if (and (stringp result) (string-match-p "^Error: Task" result))
                                     (progn
                                       (message "gptel-agent error: %s" result)
                                       (when (buffer-live-p main-buf)
                                         (with-current-buffer main-buf
                                           (let ((my/gptel--abort-generation (1+ my/gptel--abort-generation)))
                                             ;; Force FSM state to ABRT manually since gptel-abort won't find a process
                                             (when main-fsm
                                               (setf (gptel-fsm-state main-fsm) 'ABRT)
                                               (gptel--handle-abort main-fsm))
                                             (my/gptel-abort-here)))))
                                   (funcall main-cb result)))))
                  (funcall orig new-cb agent-type desc prompt)))))

(defun my/gptel--recover-fsm-on-error (_start _end)
  "Force FSM to DONE state if it has error + STOP but is still cycling.
START and END are the response positions (ignored).
This handles the case where malformed JSON leaves FSM in limbo."
  (when (boundp 'gptel--fsm-last)
    (let* ((fsm gptel--fsm-last)
           (info (and fsm (gptel-fsm-info fsm)))
           (error-msg (plist-get info :error))
           (stop-reason (plist-get info :stop-reason)))
      (when (and error-msg
                 (eq stop-reason 'STOP)
                 (not (eq (gptel-fsm-state fsm) 'DONE)))
        (message "gptel: Recovering FSM from error state: %s" error-msg)
        ;; Force state to DONE to unstick the UI
        (setf (gptel-fsm-state fsm) 'DONE)
        ;; Clear the in-progress indicator
        (force-mode-line-update t)))))

(add-hook 'gptel-post-response-functions #'my/gptel--recover-fsm-on-error)

;; --- Prompt Marker After Response ---
;; When gptel-agent finishes, add ### marker and position cursor for next prompt

(defun my/gptel-add-prompt-marker (_start end)
  "Add a prompt marker after the response and move point there.

START and END are the response region positions passed by
`gptel-post-response-functions'."
  (when (and gptel-mode
             ;; In some buffers/sentinels, `gptel--fsm' may not be bound.
             ;; Never error from a post-response hook.
             (not (condition-case nil
                      (let* ((fsm (buffer-local-value 'gptel--fsm-last (current-buffer)))
                             (info (and fsm (gptel-fsm-info fsm))))
                        (plist-get info :error))
                    (error nil))))
    (save-excursion
      (goto-char end)
      ;; Only add marker if not already present at EOB
      (my/gptel--insert-prompt-marker-at-eob))
    ;; Move cursor to end for immediate typing
    (goto-char (point-max))
    (when (search-backward "### " nil t)
      (goto-char (match-end 0)))))



;; --- SHR/SVG Rendering Hardening (gptel-agent Web Tools) ---
;; Some web pages include inline SVG that triggers libxml/SVG rendering errors
;; like: "Namespace prefix xlink for href on use is not defined".
;; gptel-agent web tools use `shr-insert-document' for text extraction; images
;; are unnecessary. Disable image rendering during these fetch callbacks.

(defgroup my/gptel-web nil
  "Web extraction tweaks for gptel-agent."
  :group 'gptel)

(defcustom my/gptel-web-inhibit-images t
  "When non-nil, inhibit images during gptel-agent web extraction."
  :type 'boolean
  :group 'my/gptel-web)

(defun my/gptel--wrap-gptel-agent-fetch-no-images (orig url url-cb tool-cb failed-msg &rest args)
  "Around-advice: inhibit SHR images during gptel-agent URL fetch callbacks."
  (let ((wrapped-url-cb
         (if my/gptel-web-inhibit-images
             (let ((orig-url-cb url-cb))
               (lambda (&rest cbargs)
                 (let ((shr-inhibit-images t))
                   (apply orig-url-cb cbargs))))
           url-cb)))
    (apply orig url wrapped-url-cb tool-cb failed-msg args)))

(defun my/gptel-auto-permit-tool-calls ()
  "Accept the current tool call and auto-permit all future ones in this buffer."
  (interactive)
  (setq-local gptel-confirm-tool-calls nil)
  (message "Auto-permitting all future tool calls in this buffer.")
  (call-interactively #'gptel--accept-tool-calls))

;; --- Enhanced Tool Call Confirmation Context ---
;; Overrides `gptel--display-tool-calls' to include arguments in the minibuffer prompt.
(defun my/gptel--display-tool-calls (tool-calls info &optional use-minibuffer)
  "Handle tool call confirmation with improved minibuffer context."
  (let* ((start-marker (plist-get info :position))
         (tracking-marker (plist-get info :tracking-marker)))
    (with-current-buffer (plist-get info :buffer)
      (if (or use-minibuffer        ;prompt for confirmation from the minibuffer
              buffer-read-only ;TEMP(tool-preview) Handle read-only buffers better
              (get-char-property
               (max (point-min) (1- (or tracking-marker start-marker)))
               'read-only))
          (let* ((minibuffer-allow-text-properties t)
                 (backend-name (gptel-backend-name (plist-get info :backend)))
                 (prompt (format "%s wants to run " backend-name)))
            (map-y-or-n-p
             (lambda (tool-call-spec)
               (let* ((tool-name (gptel-tool-name (car tool-call-spec)))
                      (args (cadr tool-call-spec))
                      (formatted-args
                       (mapconcat (lambda (arg)
                                    (cond ((stringp arg)
                                           (truncate-string-to-width arg 60 nil nil "..."))
                                          (t (prin1-to-string arg))))
                                  args " ")))
                 (concat prompt
                         (propertize tool-name 'face 'font-lock-keyword-face)
                         (if (string-empty-p formatted-args) ""
                           (concat " " (propertize formatted-args 'face 'font-lock-constant-face)))
                         ": ")))
             (lambda (tcs) (gptel--accept-tool-calls (list tcs) nil))
             tool-calls '("tool call" "tool calls" "run")
             `((?i ,(lambda (_) (save-window-excursion
                             (with-selected-window
                                 (gptel--inspect-fsm gptel--fsm-last)
                               (goto-char (point-min))
                               (when (search-forward-regexp "^:tool-use" nil t)
                                 (forward-line 0) (hl-line-highlight))
                               (use-local-map
                                (make-composed-keymap
                                 (define-keymap "q" (lambda () (interactive)
                                                      (quit-window)
                                                      (exit-recursive-edit)))
                                 (current-local-map)))
                               (recursive-edit) nil)))
                   "inspect call(s)")
               (?a ,(lambda (_)
                      (setq-local gptel-confirm-tool-calls nil)
                      (message "Auto-permitting all future tool calls in this buffer.")
                      (setq unread-command-events (listify-key-sequence "!"))
                      nil)
                   "auto-permit future calls"))))
        ;; Prompt for confirmation from the chat buffer
        (let* ((backend-name (gptel-backend-name (plist-get info :backend)))
               (actions-string
                (concat (propertize "Run tools: " 'face 'font-lock-string-face)
                        (propertize "C-c C-c" 'face 'help-key-binding)
                        (propertize ", Auto-permit: " 'face 'font-lock-string-face)
                        (propertize "C-c C-y" 'face 'help-key-binding)
                        (propertize ", Cancel request: " 'face 'font-lock-string-face)
                        (propertize "C-c C-k" 'face 'help-key-binding)
                        (propertize ", Inspect: " 'face 'font-lock-string-face)
                        (propertize "C-c C-i" 'face 'help-key-binding)))
               (confirm-strings)
               (ov-start (save-excursion
                           (goto-char start-marker)
                           (text-property-search-backward 'gptel 'response)
                           (point)))
               (preview-handlers)
               (ov (or (cdr-safe (get-char-property-and-overlay
                                  start-marker 'gptel-tool))
                       (make-overlay ov-start (or tracking-marker start-marker)
                                     nil nil nil)))
               (prompt-ov))
          ;; If the cursor is at the overlay-end, it ends up outside, so move it back
          (unless tracking-marker
            (when (= (point) start-marker) (ignore-errors (backward-char))))
          (save-excursion
            (goto-char (overlay-end ov))
            (pcase-dolist (`(,tool-spec ,arg-values _) tool-calls)
              ;; Call tool-specific confirmation prompt
              (if-let* ((funcs (cdr (assoc (gptel-tool-name tool-spec)
                                           gptel--tool-preview-alist)))
                        ((functionp (car-safe funcs))))
                  ;;preview-teardown func   preview-handle overlay/buffer
                  (push (list (cadr funcs) (funcall (car funcs) arg-values info))
                        preview-handlers)
                (push (gptel--format-tool-call (gptel-tool-name tool-spec) arg-values)
                      confirm-strings)))
            (and confirm-strings (apply #'insert (nreverse confirm-strings)))
            (add-text-properties (overlay-end ov) (1- (point))
                                 '(read-only t font-lock-fontified t))
            (setq prompt-ov (make-overlay (overlay-end ov) (point) nil t))
            (overlay-put
             prompt-ov 'before-string
             (concat "\n"
                     (propertize " " 'display `(space :align-to (- right ,(length actions-string) 2))
                                 'face '(:inherit font-lock-string-face :underline t :extend t))
                     actions-string
                     (format (propertize "\n%s wants to run:\n\n"
                                         'face 'font-lock-string-face)
                             backend-name)))
            (overlay-put
             prompt-ov 'after-string
             (concat (propertize "\n" 'face
                                 '(:inherit font-lock-string-face :underline t :extend t))))
            (overlay-put prompt-ov 'evaporate t)
            (overlay-put ov 'prompt prompt-ov)
            (move-overlay ov ov-start (point)))
          ;; Add confirmation prompt to the overlay
          (when preview-handlers (overlay-put ov 'previews preview-handlers))
          (overlay-put ov 'mouse-face 'highlight)
          (overlay-put ov 'gptel-tool tool-calls)
          (overlay-put ov 'help-echo
                       (concat "Tool call(s) requested: " actions-string))
          (let ((map (make-sparse-keymap)))
            (set-keymap-parent map gptel-tool-call-actions-map)
            (define-key map (kbd "C-c C-y") #'my/gptel-auto-permit-tool-calls)
            (overlay-put ov 'keymap map)))))))

(advice-add 'gptel--display-tool-calls :override #'my/gptel--display-tool-calls)

(defun my/gptel--hint-auto-permit-on-accept (&rest _args)
  "Show a hint about auto-permitting when the user manually accepts a tool call."
  (when (and (boundp 'gptel-confirm-tool-calls)
             gptel-confirm-tool-calls
             ;; Don't hint if it's currently executing as a subagent
             (not (bound-and-true-p my/gptel--in-subagent-task)))
    (message "Calling tool... (Hint: Use C-c C-y to auto-permit future calls in this buffer)")))

(advice-add 'gptel--accept-tool-calls :before #'my/gptel--hint-auto-permit-on-accept)

(provide 'gptel-ext-core)
;;; gptel-ext-core.el ends here
