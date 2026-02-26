;;; gptel-config.el --- Clean, modular gptel configuration -*- lexical-binding: t; -*-

;;; Table of Contents:
;;   L24   Compatibility shims (markdown faces)
;;   L36   Backend forward-declarations & defvars
;;   L40   Mode hooks, display & temperature defaults
;;   L96   FSM hardening (nil-tool guard, doom-loop, reasoning preservation)
;;   L741  Interrupt infrastructure & curl timeouts
;;   L840  Abort machinery & async tool implementations (bash/grep/glob/edit)
;;   L1290 Tool registration (with-eval-after-load 'gptel-agent-tools)
;;   L1713 Self-tests
;;   L1825 Prompt marker & SHR/SVG hardening
;;   L1879 Provider backends (OpenRouter, Gemini, Moonshot, DeepSeek…)
;;   L1925 Model resolution
;;   L1942 Context window cache & auto-refresh
;;   L2162 Auto-compact & planning file creation
;;   L2357 Learning integration (instinct tracking, git-commit hook)
;;   L2433 Utility helpers (find-buffers, web, search)
;;   L2554 Patch infrastructure (ApplyPatch, preview tools)
;;   L2667 Subagent & ApplyPatch defgroups/defcustoms
;;   L3125 Tool helpers, lists, profile management
;;   L3409 Configuration defaults & keybindings

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
  ;; C-c C-a: never ask again for tool calls
  (define-key gptel-mode-map (kbd "C-c C-a") #'my/gptel-tool-confirmation-never)
  ;; Make the binding work even when point is on the tool overlay.
  (when (boundp 'gptel-tool-call-actions-map)
    (define-key gptel-tool-call-actions-map (kbd "C-c C-a") #'my/gptel-tool-confirmation-never)
    (define-key gptel-tool-call-actions-map (kbd "C-c C-A") #'my/gptel-tool-confirmation-auto))
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

(with-eval-after-load 'gptel-transient
  (advice-add 'gptel--setup-directive-menu
              :around #'my/gptel--filter-directive-menu)
  (advice-add 'gptel-system-prompt :before
              (lambda (&rest _)
                (setq my/gptel--transient-origin-buffer (current-buffer))))
  (advice-add 'gptel--suffix-system-message
              :around #'my/gptel--suffix-system-message-in-buffer))

(defun my/gptel--filter-directive-menu (orig sym msg &optional external)
  "Around-advice: hide internal nucleus directives from the transient picker."
  (let ((gptel-directives
         (seq-remove (lambda (e) (memq (car e) '(nucleus-gptel-agent nucleus-gptel-plan
                                                                     Plan Agent)))
                     gptel-directives)))
    (funcall orig sym msg external)))

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
        (setq header-line-format nil))
      (when (and (fboundp 'gptel--apply-preset) header-line-format)
        (when (fboundp 'nucleus--header-line-apply-preset-label)
          (nucleus--header-line-apply-preset-label))))
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

;; --- Interruptible Grep Tool Override ---
;; gptel-agent's built-in Grep uses `call-process', which is hard to abort
;; cleanly.  Override it with an async implementation so C-g can reliably stop
;; ripgrep and prevent late tool results from getting inserted.

(defcustom my/gptel-grep-timeout 20
  "Seconds before Grep tool is force-stopped."
  :type 'integer
  :group 'my/gptel-interrupt)

(defcustom my/gptel-glob-timeout 20
  "Seconds before Glob tool is force-stopped."
  :type 'integer
  :group 'my/gptel-interrupt)

(defcustom my/gptel-edit-timeout 30
  "Seconds before Edit (patch mode) tool is force-stopped."
  :type 'integer
  :group 'my/gptel-interrupt)

(defcustom my/gptel-bash-timeout 60
  "Seconds before Bash tool is force-stopped.

This prevents gptel-agent subagents (e.g. executor) from hanging forever on
interactive commands like git commit."
  :type 'integer
  :group 'my/gptel-interrupt)

(defvar my/gptel--persistent-bash-process nil
  "Persistent background bash process for gptel-agent's Bash tool.")

(defun my/gptel--agent-bash-async (callback command)
  "Async replacement for gptel-agent's `Bash' tool.
Provides a persistent shell state, STDOUT truncation, dumb terminal,
and a sandbox for Plan mode."
  (let* ((origin (current-buffer))
         (gen my/gptel--abort-generation)
         (done nil)
         ;; Sandbox check: strictly read-only when in Plan mode
         (is-plan (eq (and (fboundp 'nucleus--effective-preset)
                           (nucleus--effective-preset))
                      'gptel-plan)))
    (cl-labels
        ((finish (result)
           (unless done
             (setq done t)
             (when (and (buffer-live-p origin)
                        (with-current-buffer origin
                          (= gen my/gptel--abort-generation)))
               (funcall callback result)))))
      (condition-case err
          (progn
            (unless (and (stringp command) (not (string-empty-p (string-trim command))))
              (error "command is empty"))
            
            (if (and is-plan
                     (or (string-match-p "[;|&><]" command)
                         (not (string-match-p "\\`[ \t]*\\(ls\\|pwd\\|tree\\|file\\|git status\\|git diff\\|git log\\|git show\\|git branch\\|pytest\\|npm test\\|npm run test\\|cargo test\\|go test\\|make test\\)\\b" command))))
                (finish (format "Error: Command rejected by Emacs Whitelist Sandbox. In Plan mode, you may only use simple read-only commands (ls, git status, tree, etc.). Shell chaining (; | &) and output redirection (> <) are strictly forbidden. \n\nIMPORTANT: Do not use Bash to read or search files (no cat/grep/find); use the native `Read`, `Grep`, and `Glob` tools instead. If you truly must run a build or script, ask the user to say \"go\" to switch to Execution mode."))
              
              (unless (and my/gptel--persistent-bash-process
                           (process-live-p my/gptel--persistent-bash-process))
                (let ((buf (get-buffer-create " *gptel-persistent-bash*")))
                  (with-current-buffer buf (erase-buffer))
                  (setq my/gptel--persistent-bash-process
                        (make-process
                         :name "gptel-bash"
                         :buffer buf
                         :command '("bash" "--norc" "--noprofile")
                         :connection-type 'pipe
                         :noquery t))
                  (process-put my/gptel--persistent-bash-process 'my/gptel-managed t)
                  ;; Initialize Dumb Terminal variables to prevent interactive hanging
                  (process-send-string my/gptel--persistent-bash-process
                                       "export TERM=dumb PAGER=cat GIT_PAGER=cat DEBIAN_FRONTEND=noninteractive PS1=''\n")
                  (sleep-for 0.1)))
              
              (let* ((proc my/gptel--persistent-bash-process)
                     (buf (process-buffer proc))
                     (marker (format "gptel_cmd_done_%s" (md5 (number-to-string (random)))))
                     (timer nil))
                
                (with-current-buffer buf
                  (erase-buffer))
                
                (set-process-filter proc
                                    (lambda (p output)
                                      (when (buffer-live-p (process-buffer p))
                                        (with-current-buffer (process-buffer p)
                                          (goto-char (point-max))
                                          (insert output)
                                          (let ((content (buffer-string)))
                                            ;; Regex tolerates potential \r or \n from terminal variations
                                            (when (string-match (format "%s:\\([0-9]+\\)[ \r\n]*\\'" marker) content)
                                              (let* ((status (string-to-number (match-string 1 content)))
                                                     (out (substring content 0 (match-beginning 0)))
                                                     (out (string-trim out))
                                                     (max-length 50000)
                                                     (truncated-out
                                                      (if (> (length out) max-length)
                                                          (let* ((temp-dir (expand-file-name "gptel-agent-temp" (temporary-file-directory)))
                                                                 (temp-file (expand-file-name
                                                                             (format "bash-%s-%s.txt"
                                                                                     (format-time-string "%Y%m%d-%H%M%S")
                                                                                     (random 10000))
                                                                             temp-dir)))
                                                            (unless (file-directory-p temp-dir) (make-directory temp-dir t))
                                                            (with-temp-file temp-file (insert out))
                                                            (concat (substring out 0 (/ max-length 2))
                                                                    (format "\n\n... [Output truncated. Result exceeded 50,000 bytes. Full output saved to: %s\nUse Grep to search the full content or Read with offset/limit to view specific sections.] ...\n\n" temp-file)
                                                                    (substring out (- (/ max-length 2)))))
                                                        out)))
                                                (if timer (cancel-timer timer))
                                                (if (= status 0)
                                                    (finish truncated-out)
                                                  (finish (format "Command failed with exit code %d:\nSTDOUT+STDERR:\n%s" status truncated-out))))))))))
                
                (setq timer (run-at-time
                             my/gptel-bash-timeout nil
                             (lambda (p)
                               (when (process-live-p p)
                                 ;; For timeouts, we must kill the hung persistent process
                                 ;; and force a fresh shell on the next call.
                                 (ignore-errors (set-process-filter p #'ignore))
                                 (ignore-errors (set-process-sentinel p #'ignore))
                                 (delete-process p))
                               (finish (format "Error: Bash timed out after %ss" my/gptel-bash-timeout)))
                             proc))
                
                ;; Wrap command in {} to catch errors and safely output the exit code marker
                (process-send-string proc (format "{ %s\n} 2>&1\necho %s:$?\n" command marker))
                )))
        (error (finish (format "Error: %s" (error-message-string err))))))))

(defun my/gptel--agent-grep-async (callback regex path &optional glob context-lines)
  "Async replacement for gptel-agent's `Grep' tool.

Calls CALLBACK exactly once unless the buffer has been aborted, in which case
results are dropped."
  (let* ((origin (current-buffer))
         (gen my/gptel--abort-generation))
    (condition-case err
        (progn
          (unless (and (stringp regex) (not (string-empty-p (string-trim regex))))
            (error "regex is empty"))
          (unless (and (stringp path) (file-readable-p path))
            (error "File or directory %s is not readable" path))
          (let* ((grepper (or (executable-find "rg") (executable-find "grep")))
                 (_ (unless grepper (error "ripgrep/grep not available")))
                 (cmd (file-name-sans-extension (file-name-nondirectory grepper)))
                 (context-lines (if (natnump context-lines) context-lines 0))
                 (context-lines (min 15 context-lines))
                 (expanded-path (expand-file-name (substitute-in-file-name path)))
                 (args
                  (cond
                   ((string= "rg" cmd)
                    (delq nil (list "--sort=modified"
                                    (format "--context=%d" context-lines)
                                    (and glob (format "--glob=%s" glob))
                                    "--max-count=1000"
                                    "--heading" "--line-number"
                                    "-e" regex
                                    expanded-path)))
                   ((string= "grep" cmd)
                    (delq nil (list "--recursive"
                                    (format "--context=%d" context-lines)
                                    (and glob (format "--include=%s" glob))
                                    "--max-count=1000"
                                    "--line-number" "--regexp" regex
                                    expanded-path)))
                   (t (error "failed to identify grepper"))))
                 (buf (generate-new-buffer " *gptel-grep*"))
                 (done nil)
                 (finish
                  (lambda (result)
                    (unless done
                      (setq done t)
                      (when (buffer-live-p buf) (kill-buffer buf))
                      (when (and (buffer-live-p origin)
                                 (with-current-buffer origin
                                   (= gen my/gptel--abort-generation)))
                        (funcall callback result))))))
            (let ((proc
                   (make-process
                    :name "gptel-grep"
                    :buffer buf
                    :command (cons grepper args)
                    :noquery t
                    :connection-type 'pipe
                    :sentinel
                    (lambda (p _event)
                      (when (memq (process-status p) '(exit signal))
                        (let* ((status (process-exit-status p))
                               (out (with-current-buffer buf (buffer-string))))
                          (funcall finish
                                   (if (= status 0)
                                       (string-trim out)
                                     (string-trim
                                      (format "Error: search failed with exit-code %d. Tool output:\n\n%s"
                                              status out))))))))))
              (process-put proc 'my/gptel-managed t)
              (run-at-time
               my/gptel-grep-timeout nil
               (lambda (p)
                 (when (process-live-p p)
                   (ignore-errors (set-process-filter p #'ignore))
                   (ignore-errors (set-process-sentinel p #'ignore))
                   (delete-process p))
                 (funcall finish "Error: search timed out."))
               proc))))
      (error
       (funcall callback (format "Error: %s" (error-message-string err)))))))

(defun my/gptel--agent-glob--maybe-truncate (text)
  "Return TEXT, truncating and persisting to a temp file if needed."
  (if (<= (length text) 20000)
      text
    (let* ((temp-dir (expand-file-name "gptel-agent-temp" (temporary-file-directory)))
           (temp-file (expand-file-name
                       (format "glob-%s-%s.txt"
                               (format-time-string "%Y%m%d-%H%M%S")
                               (random 10000))
                       temp-dir)))
      (unless (file-directory-p temp-dir) (make-directory temp-dir t))
      (with-temp-file temp-file (insert text))
      (with-temp-buffer
        (insert text)
        (let ((orig-size (buffer-size))
              (orig-lines (line-number-at-pos (point-max)))
              (max-lines 50))
          (goto-char (point-min))
          (insert (format "Glob results too large (%d chars, %d lines) for context window.\nStored in: %s\n\nFirst %d lines:\n\n"
                          orig-size orig-lines temp-file max-lines))
          (forward-line max-lines)
          (delete-region (point) (point-max))
          (goto-char (point-max))
          (insert (format "\n\n[Use Read tool with file_path=\"%s\" to view full results]"
                          temp-file))
          (buffer-string))))))

(defun my/gptel--agent-glob-async (callback pattern &optional path depth)
  "Async replacement for gptel-agent's `Glob' tool.

Calls CALLBACK exactly once unless the buffer has been aborted, in which case
results are dropped."
  (let* ((origin (current-buffer))
         (gen my/gptel--abort-generation)
         (buf nil)
         (done nil))
    (cl-labels
        ((finish (result)
           (unless done
             (setq done t)
             (when (buffer-live-p buf) (kill-buffer buf))
             (when (and (buffer-live-p origin)
                        (with-current-buffer origin
                          (= gen my/gptel--abort-generation)))
               (funcall callback result)))))
      (condition-case err
          (progn
            (when (string-empty-p pattern)
              (error "Error: pattern must not be empty"))
            (if path
                (unless (and (file-readable-p path) (file-directory-p path))
                  (error "Error: path %s is not readable" path))
              (setq path "."))
            (unless (executable-find "tree")
              (error "Error: Executable `tree` not found. This tool cannot be used"))
            (let* ((full-path (expand-file-name path))
                   (args (list "-l" "-f" "-i" "-I" ".git"
                               "--sort=mtime" "--ignore-case"
                               "--prune" "-P" pattern full-path))
                   (args (if (natnump depth)
                             (nconc args (list "-L" (number-to-string depth)))
                           args)))
              (setq buf (generate-new-buffer " *gptel-glob*"))
              (let ((proc
                     (make-process
                      :name "gptel-glob"
                      :buffer buf
                      :command (cons "tree" args)
                      :noquery t
                      :connection-type 'pipe
                      :sentinel
                      (lambda (p _event)
                        (when (memq (process-status p) '(exit signal))
                          (let* ((status (process-exit-status p))
                                 (out (with-current-buffer buf (buffer-string))))
                            (setq out
                                  (if (= status 0)
                                      out
                                    (concat
                                     (format "Glob failed with exit code %d\n.STDOUT:\n\n" status)
                                     out)))
                            (finish (my/gptel--agent-glob--maybe-truncate out))))))))
                (process-put proc 'my/gptel-managed t)
                (run-at-time
                 my/gptel-glob-timeout nil
                 (lambda (p)
                   (when (process-live-p p)
                     (ignore-errors (set-process-filter p #'ignore))
                     (ignore-errors (set-process-sentinel p #'ignore))
                     (delete-process p))
                   (finish "Error: glob timed out."))
                 proc))))
        (error
         (finish (format "Error: %s" (error-message-string err))))))))

(defun my/gptel--agent--strip-diff-fences (text)
  "Strip leading/trailing fenced code block markers from TEXT, if present."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (when (looking-at-p "^ *```\\(diff\\|patch\\)?\\s-*$")
      (delete-line))
    (goto-char (point-max))
    (forward-line -1)
    (when (looking-at-p "^ *```\\s-*$")
      (delete-line))
    (string-trim-right (buffer-string))))

(defun my/gptel--agent-edit-async (callback path &optional old-str new-str-or-diff diffp)
  "Async replacement for gptel-agent's `Edit' tool.

This is only truly async/interruptible for patch mode (DIFFP true). For simple
string replacements it executes synchronously then calls CALLBACK.

Calls CALLBACK exactly once unless the buffer has been aborted, in which case
results are dropped."
  (let* ((origin (current-buffer))
         (gen my/gptel--abort-generation)
         (done nil)
         (finish
          (lambda (result)
            (unless done
              (setq done t)
              ;; Always deliver error results so the FSM doesn't hang.
              ;; A dropped error leaves gptel waiting forever for a callback
              ;; that will never arrive.  Only drop *success* results when the
              ;; request has been aborted (generation mismatch / dead buffer).
              (when (or (and (stringp result) (string-prefix-p "Error" result))
                        (and (buffer-live-p origin)
                             (with-current-buffer origin
                               (= gen my/gptel--abort-generation))))
                (funcall callback result))))))
    (condition-case err
        (progn
          (unless (file-readable-p path)
            (error "Error: File or directory %s is not readable" path))
          (unless new-str-or-diff
            (error "Required argument `new_str' missing"))
          (let ((patch-mode (and diffp (not (eq diffp :json-false)))))
            (if (not patch-mode)
                (funcall finish
                         (gptel-agent--edit-files path old-str new-str-or-diff diffp))
              (unless (executable-find "patch")
                (error "Error: Command \"patch\" not available, cannot apply diffs"))
              (let* ((out-buf (generate-new-buffer " *gptel-patch*"))
                     (target (expand-file-name path))
                     (default-directory
                      (if (file-directory-p target)
                          (file-name-as-directory target)
                        (file-name-directory target)))
                     (patch-options '("--forward" "--verbose" "--batch"))
                     (patch-text (my/gptel--agent--strip-diff-fences new-str-or-diff))
                     (patch-text (if (string-suffix-p "\n" patch-text)
                                     patch-text
                                   (concat patch-text "\n"))))
                (with-temp-buffer
                  (insert patch-text)
                  (goto-char (point-min))
                  (when (fboundp 'gptel-agent--fix-patch-headers)
                    (gptel-agent--fix-patch-headers))
                  (setq patch-text (buffer-string)))
                (let ((proc
                       (make-process
                        :name "gptel-patch"
                        :buffer out-buf
                        :command (cons "patch" patch-options)
                        :noquery t
                        :connection-type 'pipe
                        :sentinel
                        (lambda (p _event)
                          (when (memq (process-status p) '(exit signal))
                            (let* ((status (process-exit-status p))
                                   (out (with-current-buffer out-buf (buffer-string))))
                              (when (buffer-live-p out-buf) (kill-buffer out-buf))
                              (if (= status 0)
                                  (funcall finish
                                           (format
                                            "Diff successfully applied to %s.\nPatch command options: %s\nPatch STDOUT:\n%s"
                                            target patch-options (string-trim out)))
                                (funcall finish
                                         (format
                                          "Error: Failed to apply diff to %s (exit status %s).\nPatch command options: %s\nPatch STDOUT:\n%s"
                                          target status patch-options (string-trim out))))))))))
                  (process-put proc 'my/gptel-managed t)
                  (process-send-string proc patch-text)
                  (process-send-eof proc)
                  (run-at-time
                   my/gptel-edit-timeout nil
                   (lambda (p buf)
                     (when (process-live-p p)
                       (ignore-errors (set-process-filter p #'ignore))
                       (ignore-errors (set-process-sentinel p #'ignore))
                       (delete-process p))
                     (when (buffer-live-p buf) (kill-buffer buf))
                     (funcall finish "Error: edit/patch timed out."))
                   proc out-buf))))))
      (error
       (funcall finish (format "Error: %s" (error-message-string err)))))))

(defun my/gptel--safe-get-tool (name)
  "Return tool NAME from gptel registry, or nil if missing.

`gptel-get-tool' signals an error when NAME is not registered yet.  During
startup, tool definitions may not have been loaded/registered; we treat missing
tools as nil and let custom tool definitions below provide replacements."
  (condition-case nil
      (gptel-get-tool name)
    (error nil)))

(defun my/gptel--dedup-tools-by-name (tools)
  "Return TOOLS with duplicates by tool name removed (last registration wins).
Guards against reload-time duplication where `gptel-make-tool' and
`my/gptel--safe-get-tool' both resolve the same name to different structs."
  (let ((seen (make-hash-table :test #'equal)))
    ;; Walk in reverse so last definition wins after we reverse back.
    (nreverse
     (cl-loop for tool in (nreverse (copy-sequence tools))
              for name = (ignore-errors (gptel-tool-name tool))
              when (and name (not (gethash name seen)))
              do (puthash name t seen)
              and collect tool))))

(with-eval-after-load 'gptel-agent-tools
  ;; Override the built-in tool definition (same name/category).
  (gptel-make-tool
   :name "Bash"
   :description "Execute a Bash command (async, interruptible, timeout). Use for git/tests/builds; not for file read/edit/search."
   :function #'my/gptel--agent-bash-async
   :async t
   :args '(( :name "command"
             :type string
             :description "Bash command string."))
   :category "gptel-agent"
   :confirm t
   :include t)

  ;; Override the built-in tool definition (same name/category).
  (gptel-make-tool
   :name "Grep"
   :description "Search file contents under a path (async)."
   :function #'my/gptel--agent-grep-async
   :async t
   :args '(( :name "regex"
             :type string)
           ( :name "path"
             :type string)
           ( :name "glob"
             :type string
             :optional t)
           ( :name "context_lines"
             :optional t
             :type integer
             :maximum 15))
   :category "gptel-agent"
   :include t)
  (gptel-make-tool
   :name "Glob"
   :description "Find files by glob pattern (async)."
   :function #'my/gptel--agent-glob-async
   :async t
   :args '(( :name "pattern"
             :type string
             :description "Glob pattern.")
           ( :name "path"
             :type string
             :optional t)
           ( :name "depth"
             :type integer
             :optional t))
   :category "gptel-agent"
   :include t)
  (gptel-make-tool
   :name "Edit"
   :description "Replace text or apply a unified diff (async)."
   :function #'my/gptel--agent-edit-async
   :async t
   :args '(( :name "path"
             :type string)
           ( :name "old_str"
             :type string
             :optional t)
           ( :name "new_str"
             :type string)
           ( :name "diff"
             :type boolean
             :optional t))
   :category "gptel-agent"
   :confirm t
   :include t)
  (gptel-make-tool
   :name "Write"
   :category "gptel-agent"
   :function (lambda (path filename content)
               "Create a new file safely. Refuses to overwrite existing files."
               (let ((filepath (expand-file-name filename path)))
                 (if (file-exists-p filepath)
                     (error "File already exists: %s. Use Edit or Insert instead of Write." filepath)
                   (with-temp-file filepath
                     (insert content))
                   (format "Created new file: %s" filepath))))
   :description "Create a new file with the specified content. SAFETY: refuses to overwrite existing files. Use Edit or Insert for existing files."
   :args (list '(:name "path" :type string :description "Directory path (use \".\" for current)")
               '(:name "filename" :type string :description "Name of the file to create")
               '(:name "content" :type string :description "Content to write"))
   :confirm t
   :include t)
  ;; Token-efficient schema descriptions (keep names/args/types identical).
  (gptel-make-tool
   :name "Read"
   :function #'gptel-agent--read-file-lines
   :description "Read file contents by line range."
   :args '(( :name "file_path" :type string)
           ( :name "start_line" :type integer :optional t)
           ( :name "end_line" :type integer :optional t))
   :category "gptel-agent"
   :include t)

  (gptel-make-tool
   :name "Insert"
   :function #'gptel-agent--insert-in-file
   :description "Insert text at a line number in a file."
   :args '(( :name "path" :type string)
           ( :name "line_number" :type integer)
           ( :name "new_str" :type string))
   :category "gptel-agent"
   :confirm t
   :include t)

  (gptel-make-tool
   :name "Mkdir"
   :function #'gptel-agent--make-directory
   :description "Create a directory under a parent directory."
   :args (list '( :name "parent" :type "string")
               '( :name "name" :type "string"))
   :category "gptel-agent"
   :confirm t
   :include t)

  (gptel-make-tool
   :name "Eval"
   :function (lambda (expression)
               (let ((standard-output (generate-new-buffer " *gptel-agent-eval-elisp*"))
                     (result nil) (output nil))
                 (unwind-protect
                     (condition-case err
                         (progn
                           (setq result (eval (read expression) t))
                           (when (> (buffer-size standard-output) 0)
                             (setq output (with-current-buffer standard-output (buffer-string))))
                           (concat
                            (format "Result:\n%S" result)
                            (and output (format "\n\nSTDOUT:\n%s" output))))
                       ((error user-error)
                        (concat
                         (format "Error: eval failed with error %S: %S"
                                 (car err) (cdr err))
                         (and output (format "\n\nSTDOUT:\n%s" output)))))
                   (kill-buffer standard-output))))
   :description "Evaluate a single Elisp expression."
   :args '(( :name "expression" :type string))
   :category "gptel-agent"
   :confirm t
   :include t)

  (gptel-make-tool
   :name "WebSearch"
   :function 'gptel-agent--web-search-eww
   :description "Search the web (returns top results)."
   :args '((:name "query" :type string)
           (:name "count" :type integer :optional t))
   :include t
   :async t
   :category "gptel-agent")

  (gptel-make-tool
   :name "WebFetch"
   :function #'gptel-agent--read-url
   :description "Fetch and read the text of a URL."
   :args '(( :name "url" :type "string"))
   :async t
   :include t
   :category "gptel-agent")

  (gptel-make-tool
   :name "YouTube"
   :function #'gptel-agent--yt-read-url
   :description "Fetch YouTube description and transcript."
   :args '((:name "url" :type "string"))
   :category "gptel-agent"
   :async t
   :include t)

  (gptel-make-tool
   :name "TodoWrite"
   :function #'gptel-agent--write-todo
   :description "Update a session todo list."
   :args
   '(( :name "todos"
       :type array
       :items
       ( :type object
         :properties
         (:content ( :type string :minLength 1)
                   :status ( :type string :enum ["pending" "in_progress" "completed"])
                   :activeForm ( :type string :minLength 1)))))
   :category "gptel-agent")

  (gptel-make-tool
   :name "Skill"
   :function #'my/gptel--skill-tool
   :description "Load a skill by name."
   :args '(( :name "skill" :type string)
           ( :name "args" :type string :optional t))
   :category "gptel-agent"
   :include t)

  (gptel-make-tool
   :name "Agent"
   :function #'my/gptel--agent-task-with-timeout
   :description "Run a delegated subagent task."
   :args '(( :name "subagent_type" :type string :enum ["researcher" "introspector"])
           ( :name "description" :type string)
           ( :name "prompt" :type "string"))
   :category "gptel-agent"
   :async t
   :confirm t
   :include t)
  (when (fboundp 'gptel-agent--fetch-with-timeout)
    (unless (advice-member-p
             #'my/gptel--wrap-gptel-agent-fetch-no-images
             'gptel-agent--fetch-with-timeout)
      (advice-add 'gptel-agent--fetch-with-timeout
                  :around
                  #'my/gptel--wrap-gptel-agent-fetch-no-images)))
  (advice-add 'gptel-agent--task :around #'my/gptel--agent-task-override-model)
  (setq nucleus-tools-readonly
        (my/gptel--dedup-tools-by-name
         (append
          (when (boundp 'nucleus--gptel-plan-readonly-tools)
            (seq-filter #'identity (mapcar #'my/gptel--safe-get-tool nucleus--gptel-plan-readonly-tools)))
          (list
           (gptel-make-tool
            :name "find_buffers_and_recent"
            :category "gptel-agent"
            :function #'my/find-buffers-and-recent
            :description "Find open buffers and recent files matching a pattern"
            :args (list '(:name "pattern" :type string :description "Regex pattern (empty for all)")))

           (gptel-make-tool
            :name "describe_symbol"
            :function (lambda (sym)
                        (describe-symbol (intern sym))
                        (with-current-buffer "*Help*" (buffer-string)))
            :description "Show Emacs Lisp documentation for a symbol"
            :args (list '(:name "sym" :type string :description "Symbol name")))))))

  (setq nucleus-tools-action
        (my/gptel--dedup-tools-by-name
         (append
          ;; Include all 17 gptel-agent tools
          (when (boundp 'nucleus--gptel-agent-action-tools)
            (seq-filter #'identity (mapcar #'my/gptel--safe-get-tool nucleus--gptel-agent-action-tools)))
          (list
           (gptel-make-tool
            :name "run_shell_command"
            :category "gptel-agent"
            :async t
            :function (lambda (callback cmd &optional dir)
                        (let* ((default-directory (if dir (expand-file-name dir) default-directory))
                               (buf (generate-new-buffer " *gptel-shell*"))
                               (timeout 15.0)
                               (done nil))
                          (cl-labels ((finish (res)
                                        (unless done
                                          (setq done t)
                                          (funcall callback res)
                                          (when (buffer-live-p buf) (kill-buffer buf)))))
                            (condition-case err
                                (let ((proc (start-process-shell-command "gptel-shell" buf cmd)))
                                  (process-put proc 'my/gptel-managed t)
                                  (set-process-sentinel
                                   proc
                                   (lambda (p _event)
                                     (when (memq (process-status p) '(exit signal))
                                       (finish (with-current-buffer buf (string-trim (buffer-string)))))))
                                  ;; Timeout handler
                                  (run-at-time timeout nil
                                               (lambda (p)
                                                 (when (process-live-p p)
                                                   (delete-process p)
                                                   (finish (with-current-buffer buf 
                                                             (concat (string-trim (buffer-string)) 
                                                                     "\n[Process killed after 15s timeout]")))))
                                               proc))
                              (error (finish (format "Error starting shell command: %s" err)))))))
            :description "Execute a shell command (git, diff, wc, etc.)"
            :args (list '(:name "cmd" :type string :description "Shell command")
                        '(:name "dir" :type string :description "Working directory" :optional t))
            :confirm t)

           ;; Alias for gptel-agent presets, which refer to ApplyPatch.
           (gptel-make-tool
            :name "ApplyPatch"
            :category "gptel-agent"
            :async t
            :function #'my/gptel--apply-patch-dispatch
            :description "Apply a unified diff or OpenCode envelope patch."
            :args (list '(:name "patch" :type string :description "Unified diff content"))
            :confirm t)

           (gptel-make-tool
            :name "compact_chat"
            :category "gptel-agent"
            :function (lambda (summary)
                        (or summary ""))
            :description "Accept a compacted summary payload (no-op)."
            :args (list '(:name "summary" :type string :description "Compacted summary")))



           (gptel-make-tool
            :name "preview_file_change"
            :async t
            :category "gptel-agent"
            :function (lambda (callback path &optional original replacement)
                        (let* ((full-path (expand-file-name path))
                               (orig (or original
                                         (when (file-readable-p full-path)
                                           (with-temp-buffer
                                             (insert-file-contents full-path)
                                             (buffer-string)))))
                               (new (or replacement "")))
                          (if (not orig)
                              (funcall callback
                                       (format "Error: Cannot read original content for %s"
                                               path))
                            (my/gptel--preview-enqueue
                             (current-buffer) path orig new callback))))
            :description "Preview file changes step-by-step using magit (or diff-mode fallback).
When multiple files are previewed, step through them one at a time:
  n  show next file
  q  abort remaining previews"
            :args (list '(:name "path" :type string :description "Target file path")
                        '(:name "original" :type string
                                :description "Original content (optional; read from disk if omitted)"
                                :optional t)
                        '(:name "replacement" :type string :description "Replacement content"))
            :confirm t)


           (gptel-make-tool
            :name "preview_patch"
            :async t
            :category "gptel-agent"
            :function (lambda (callback patch)
                        (my/gptel--preview-patch-async
                         patch
                         (current-buffer)
                         callback
                         ;; on-confirm: user has reviewed — don't apply, just ack
                         (lambda (cb) (funcall cb "Patch reviewed. Not applied."))
                         ;; on-abort
                         (lambda (cb) (funcall cb "Patch preview aborted."))
                         ;; header
                         "  Patch preview — n reviewed    q abort"))
            :description "Preview a unified diff for review without applying it.
Press n to confirm reviewed (agent continues), q to abort."
            :args (list '(:name "patch" :type string :description "Unified diff content")))
           (gptel-make-tool
            :name "list_skills"
            :category "gptel-agent"
            :function (lambda (&optional dir)
                        "List available skills by reading SKILL.md frontmatter."
                        (let* ((root (expand-file-name (or dir (expand-file-name "assistant/skills" (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory)))))
                               (skill-dirs (when (file-directory-p root)
                                             (seq-filter
                                              (lambda (path)
                                                (file-exists-p (expand-file-name "SKILL.md" path)))
                                              (directory-files root t "^[^.]" t)))))
                          (if (not skill-dirs)
                              "No skills found."
                            (string-join
                             (mapcar
                              (lambda (dir)
                                (let* ((file (expand-file-name "SKILL.md" dir))
                                       (text (with-temp-buffer
                                               (insert-file-contents file)
                                               (buffer-string)))
                                       (name (when (string-match "^name:\s-*\(.+\)$" text)
                                               (string-trim (match-string 1 text))))
                                       (desc (when (string-match "^description:\s-*\(.+\)$" text)
                                               (string-trim (match-string 1 text)))))
                                  (format "%s: %s" (or name (file-name-nondirectory dir)) (or desc ""))))
                              skill-dirs)
                             "\n"))))
            :description "List available skills."
            :args (list '(:name "dir" :type string :description "Skills root directory" :optional t)))

           (gptel-make-tool
            :name "load_skill"
            :category "gptel-agent"
            :function (lambda (name &optional dir)
                        "Load SKILL.md content for NAME."
                        (let* ((name (my/gptel--normalize-skill-id name))
                               (name (downcase name))
                               (root (expand-file-name (or dir (expand-file-name "assistant/skills" user-emacs-directory))))
                               (path (expand-file-name (concat name "/SKILL.md") root)))
                          (if (file-readable-p path)
                              (with-temp-buffer
                                (insert-file-contents path)
                                (buffer-string))
                            (format "Skill not found: %s" name))))
            :description "Load skill instructions from SKILL.md."
            :args (list '(:name "name" :type string :description "Skill id")
                        '(:name "dir" :type string :description "Skills root directory" :optional t)))

           (gptel-make-tool
            :name "create_skill"
            :category "gptel-agent"
            :function (lambda (skillName userPrompt &optional dir)
                        "Create a new skill directory with SKILL.md based on user prompt."
                        (let* ((root (expand-file-name (or dir (expand-file-name "assistant/skills" (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory)))))
                               (name (string-trim skillName))
                               (skill-dir (expand-file-name name root))
                               (skill-file (expand-file-name "SKILL.md" skill-dir))
                               (valid-name (string-match-p "\`[a-z0-9]+\(?:-[a-z0-9]+\)*\'" name)))
                          (unless valid-name
                            (user-error "Invalid skill name: %s" name))
                          (let ((content (format "---\nname: %s\ndescription: %s\nversion: 1.0.0\nλ: action.identifier\n---\n\nengage nucleus:\n[φ fractal euler tao pi mu] | [Δ λ ∞/0 | ε/φ Σ/μ c/h] | OODA\nHuman ⊗ AI\n\n# %s\n\n## Identity\n\nYou are a [role]. Your mindset is shaped by:\n- **Figure A** - key principle\n- **Figure B** - key principle\n\nYour tone is [quality]; your goal is [outcome].\n\n---\n\n## Core Principle\n\nOne paragraph defining the unique value this skill provides.\n\n---\n\n## Procedure\n\n```\nλ(input).transform ⟺ [\n  step_one(input),\n  step_two(result),\n  step_three(result),\n  output(result)\n]\n```\n\n---\n\n## Decision Matrix\n\n| Input Pattern | Action | Output |\n|---------------|--------|--------|\n| Pattern A | Do X | Result |\n| Pattern B | Do Y | Result |\n| Pattern C | Do Z | Result |\n\n---\n\n## Examples\n\n**Good Input**: \"Specific, actionable request\"\n```\nResponse format\n```\n\n**Bad Input**: \"Vague, slop request\"\n```\nResponse format\n```\n\n---\n\n## Verification\n\n```\nλ(output).verify ⟺ [\n  check_one(output) AND\n  check_two(output) AND\n  check_three(output)\n]\n```\n\n**Before output, verify**:\n- [ ] Check one completed\n- [ ] Check two completed\n- [ ] Check three completed\n\n---\n\n## Eight Keys Reference\n\n| Key | Symbol | Signal | Anti-Pattern | Skill-Specific Application |\n|-----|--------|--------|--------------|---------------------------|\n| **Vitality** | φ | Organic, non-repetitive | Mechanical rephrasing | [Customize: How does this skill add fresh value?] |\n| **Clarity** | fractal | Explicit assumptions | \"Handle properly\" | [Customize: What bounds are defined?] |\n| **Purpose** | e | Actionable function | Abstract descriptions | [Customize: What concrete output?] |\n| **Wisdom** | τ | Foresight over speed | Premature optimization | [Customize: When should you measure first?] |\n| **Synthesis** | π | Holistic integration | Fragmented thinking | [Customize: How are components integrated?] |\n| **Directness** | μ | Cut pleasantries | Polite evasion | [Customize: How do you cut through noise?] |\n| **Truth** | ∃ | Favor reality | Surface agreement | [Customize: What data must be shown?] |\n| **Vigilance** | ∀ | Defensive constraint | Accepting manipulation | [Customize: What must be validated?] |\n\n---\n\n## Summary\n\n**When to use this skill**:\n1. Trigger condition\n2. Trigger condition\n3. Trigger condition\n\n**Framework eliminates slop, not adds process.**\n" name userPrompt name)))
                            (make-directory skill-dir t)
                            (write-region content nil skill-file)
                            (format "Created skill: %s" skill-file))))
            :description "Create a skill from a name and prompt."
            :args (list '(:name "skillName" :type string :description "Skill name")
                        '(:name "userPrompt" :type string :description "User prompt")
                        '(:name "dir" :type string :description "Skills root directory" :optional t))))

          ;; Finally, ensure the custom readonly tools are also here if not already included.
          (when (boundp 'nucleus--gptel-agent-action-tools)
            (seq-filter (lambda (tool)
                          (not (member (gptel-tool-name tool)
                                       nucleus--gptel-agent-action-tools)))
                        nucleus-tools-readonly)))))

  ;; Set the default tool list now that both lists are built.
  (setq-default gptel-tools nucleus-tools-readonly))


(defun my/gptel-keyboard-quit ()
  "In gptel buffers, abort the request then quit.

This makes C-g reliably stop long-hanging tool calls / curl stalls."
  (interactive)
  (my/gptel-abort-here)
  (keyboard-quit))

(defun my/gptel-selftest-abort-grep ()
  "Self-test: start Grep tool, then abort, and report if callback ran.

This runs the configured gptel-agent Grep tool asynchronously, aborts after a
short delay, and verifies that the Grep callback does not run after abort.

Run this in any buffer (ideally a gptel buffer)."
  (interactive)
  (let ((origin (current-buffer))
        (called nil))
    (setq-local my/gptel--abort-generation 0)
    (my/gptel--agent-grep-async
     (lambda (_res) (setq called t))
     "defun" (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory) "*.el" 0)
    (run-at-time
     0.05 nil
     (lambda ()
       (when (buffer-live-p origin)
         (with-current-buffer origin
           (my/gptel-abort-here)))
       (run-at-time
        0.4 nil
        (lambda ()
          (message "gptel selftest: Grep callback called? %S (expected nil)" called)))))))

(defun my/gptel-selftest-abort-glob ()
  "Self-test: start Glob tool, then abort, and report if callback ran after abort.

This starts an async Glob, aborts after a short delay, and verifies that any
callback does not run *after* the abort time. A callback that runs before abort
is not treated as a failure (it just means the operation completed quickly)."
  (interactive)
  (let ((origin (current-buffer))
        (called-time nil)
        (abort-time nil))
    (setq-local my/gptel--abort-generation 0)
    (my/gptel--agent-glob-async
     (lambda (_res) (setq called-time (float-time)))
     "*" (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory) 6)
    (run-at-time
     0.05 nil
     (lambda ()
       (setq abort-time (float-time))
       (when (buffer-live-p origin)
         (with-current-buffer origin
           (my/gptel-abort-here)))
       (run-at-time
        0.6 nil
        (lambda ()
          (let ((after (and abort-time called-time (> called-time abort-time))))
            (message
             "gptel selftest: Glob callback after abort? %S (called=%S abort=%S)"
             after called-time abort-time)
            (when after
              (message "gptel selftest: Glob FAILED (callback ran after abort)")))))))))

(defun my/gptel-selftest-abort-edit-patch ()
  "Self-test: start Edit in patch mode, abort, and ensure no callback after abort.

Creates a temporary file, starts an Edit tool call in diff/patch mode, aborts
shortly after, then checks whether the callback ran after abort.

Note: patch may complete before abort on fast systems; that is not treated as a
failure."
  (interactive)
  (let* ((origin (current-buffer))
         (called-time nil)
         (abort-time nil)
         (dir (make-temp-file "gptel-edit-selftest-" t))
         (file (expand-file-name "file.txt" dir))
         (orig "AAA\n")
         (patch (string-join
                 (list "--- file.txt"
                       "+++ file.txt"
                       "@@ -1,1 +1,1 @@"
                       "-AAA"
                       "+BBB"
                       "")
                 "\n")))
    (with-temp-file file (insert orig))
    (setq-local my/gptel--abort-generation 0)
    (my/gptel--agent-edit-async
     (lambda (_res) (setq called-time (float-time)))
     file nil patch t)
    (run-at-time
     0.02 nil
     (lambda ()
       (setq abort-time (float-time))
       (when (buffer-live-p origin)
         (with-current-buffer origin
           (my/gptel-abort-here)))
       (run-at-time
        0.8 nil
        (lambda ()
          (unwind-protect
              (let ((failed (and abort-time called-time (> called-time abort-time))))
                (message
                 "gptel selftest: Edit(patch) callback after abort? %S (called=%S abort=%S)"
                 (and abort-time called-time (> called-time abort-time))
                 called-time abort-time)
                (when failed
                  (message "gptel selftest: Edit(patch) FAILED (callback ran after abort)")))
            (ignore-errors (delete-directory dir t)))))))))

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
  (gptel-make-deepseek "DeepSeek"
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
    (,gptel--copilot    . github-copilot/gpt-5.2)
    (,gptel--cf-gateway . \@cf/zai-org/glm-4.7-flash)))

(defun nucleus-resolve-model (&optional backend requested)
  "Resolve REQUESTED model for BACKEND."
  (let* ((backend (or backend gptel-backend))
         (requested (or requested 'auto)))
    (if (not (eq requested 'auto))
        requested
      (or (alist-get backend my/gptel-preferred-models)
          (car-safe (gptel-backend-models backend))))))

;; --- Helper Functions ---

(defgroup my/gptel-auto-compact nil
  "Auto-compact gptel buffers when context grows too large."
  :group 'gptel)

(defcustom my/gptel-default-context-window 32768
  "Fallback context window (tokens) when model metadata is unavailable.

gptel does not always know the model's true context window (especially via
OpenRouter).  Auto-compaction uses this value to estimate when to compact."
  :type 'integer)

(defcustom my/gptel-context-window-cache-file
  (expand-file-name "savefile/gptel-context-window-cache.el" user-emacs-directory)
  "Path to a cache file storing detected model context windows.

The cache is used when `gptel' does not provide model metadata (common with
OpenRouter-hosted model ids)."
  :type 'file)

(defvar my/gptel--context-window-cache (make-hash-table :test 'equal)
  "Hash table mapping model id string to context window tokens.")

(defvar my/gptel--context-window-cache-last-refresh nil
  "Time (as a float) when the cache was last refreshed.")

(defcustom my/gptel-context-window-auto-refresh-enabled t
  "When non-nil, refresh context-window metadata in the background."
  :type 'boolean)

(defcustom my/gptel-context-window-auto-refresh-interval-days 7
  "Minimum number of days between background refreshes."
  :type 'integer)

(defcustom my/gptel-context-window-auto-refresh-idle-seconds 20
  "Seconds of idle time before attempting a background refresh."
  :type 'integer)

;; Schedule the background context-window cache refresh after gptel loads.
;; This must be here (after the defcustom above) not in the consolidated
;; with-eval-after-load 'gptel block at line 306, which runs before this
;; defcustom is evaluated when gptel is already loaded at require time.
(with-eval-after-load 'gptel
  (run-with-idle-timer my/gptel-context-window-auto-refresh-idle-seconds nil
                       #'my/gptel--auto-refresh-context-window-cache-maybe))

(defcustom my/gptel-openrouter-models-connect-timeout 10
  "Seconds to wait for OpenRouter model-metadata connection."
  :type 'integer)

(defcustom my/gptel-openrouter-models-max-time 60
  "Maximum seconds for the OpenRouter model-metadata request." 
  :type 'integer)

(defvar my/gptel--openrouter-context-window-fetch-inflight nil)

(defun my/gptel--model-id-string (&optional model)
  "Return MODEL as a stable string id." 
  (let ((m (or model gptel-model)))
    (cond
     ((stringp m) m)
     ((symbolp m) (symbol-name m))
     (t (format "%S" m)))))

(defun my/gptel--cache-put-context-window (model-id window)
  "Persist WINDOW for MODEL-ID in the cache." 
  (when (and (stringp model-id) (integerp window) (> window 0))
    (puthash model-id window my/gptel--context-window-cache)
    (make-directory (file-name-directory my/gptel-context-window-cache-file) t)
    (condition-case err
        (with-temp-file my/gptel-context-window-cache-file
          (insert ";; Auto-generated; model context windows cache\n")
          (insert (format ";; Updated: %s\n\n" (format-time-string "%Y-%m-%d %H:%M:%S")))
          (insert "(setq my/gptel--context-window-cache-data\n      '")
          (let (alist)
            (maphash (lambda (k v) (push (cons k v) alist)) my/gptel--context-window-cache)
            (prin1 (sort alist (lambda (a b) (string< (car a) (car b)))) (current-buffer)))
          (insert ")\n")
          (insert (format "(setq my/gptel--context-window-cache-last-refresh %S)\n"
                          (float-time (current-time)))))
      (error
       (message "gptel context-window cache: failed to write %s (%s)"
                my/gptel-context-window-cache-file
                (error-message-string err))))))

(defvar my/gptel--context-window-cache-data nil
  "Temporary holder for data loaded from the context-window cache file.
Must be `defvar' (not `let') so the `setq' in the cache file reaches it
under `lexical-binding: t'.")

(defun my/gptel--cache-load-context-windows ()
  "Load cached context windows from `my/gptel-context-window-cache-file'." 
  (when (file-readable-p my/gptel-context-window-cache-file)
    (condition-case err
        (progn
          (setq my/gptel--context-window-cache-data nil)
          (load my/gptel-context-window-cache-file nil t)
          (when (listp my/gptel--context-window-cache-data)
            (dolist (kv my/gptel--context-window-cache-data)
              (when (and (consp kv) (stringp (car kv)) (integerp (cdr kv)))
                (puthash (car kv) (cdr kv) my/gptel--context-window-cache))))
          (setq my/gptel--context-window-cache-data nil))
      (error
       (message "gptel context-window cache: failed to load %s (%s)"
                my/gptel-context-window-cache-file
                (error-message-string err))))))

(my/gptel--cache-load-context-windows)

(defun my/gptel--normalize-context-window (n)
  "Normalize gptel context-window value N to tokens.

Some gptel model tables encode context windows in *thousands* of tokens, and may
use floats (e.g. 8.192 for 8192 tokens).  OpenRouter's `context_length' is in
raw tokens."
  (cond
   ((not (numberp n)) nil)
   ;; Heuristic: values under 5000 represent "thousands of tokens".
   ;; Ex: 128 => 128k tokens, 8.192 => 8192 tokens.
   ((< n 5000) (round (* n 1000)))
   (t (round n))))

(defun my/gptel--seed-cache-from-gptel-model-tables ()
  "Seed context-window cache from gptel's built-in model tables." 
  (dolist (var '(gptel--gemini-models gptel--gh-models))
    (when (boundp var)
      (dolist (entry (symbol-value var))
        (when (and (consp entry) (symbolp (car entry)))
          (let* ((model (car entry))
                 (plist (cdr entry))
                 (cw (plist-get plist :context-window))
                 (tokens (my/gptel--normalize-context-window cw))
                 (id (my/gptel--model-id-string model)))
            (when (and (stringp id) (integerp tokens) (> tokens 0))
              (puthash id tokens my/gptel--context-window-cache))))))))

(defun my/gptel--auto-refresh-context-window-cache-maybe ()
  "Refresh context window cache if stale (non-blocking)." 
  (when my/gptel-context-window-auto-refresh-enabled
    (let* ((last my/gptel--context-window-cache-last-refresh)
           (age-days (and (numberp last)
                          (/ (- (float-time (current-time)) last) 86400.0)))
           (stale (or (not (numberp age-days))
                      (>= age-days (max 1 my/gptel-context-window-auto-refresh-interval-days)))))
      (when stale
        (setq my/gptel--context-window-cache-last-refresh (float-time (current-time)))
        ;; Seed from built-in tables (Gemini + Copilot) without network.
        (my/gptel--seed-cache-from-gptel-model-tables)
        ;; Fetch OpenRouter in the background when applicable.
        (when (and (boundp 'gptel--openrouter)
                   (eq gptel-backend gptel--openrouter))
          (my/gptel--openrouter-fetch-context-window gptel-model))
        ;; Persist cache with updated refresh timestamp.
        (my/gptel--cache-put-context-window (my/gptel--model-id-string gptel-model)
                                            (or (gethash (my/gptel--model-id-string gptel-model)
                                                         my/gptel--context-window-cache)
                                                my/gptel-default-context-window))))))


(cl-defun my/gptel--openrouter-fetch-context-window (&optional model)
  "Fetch context window for MODEL from OpenRouter and cache it.

Runs asynchronously; returns nil immediately." 
  (let* ((model-id (my/gptel--model-id-string model))
         (url "https://openrouter.ai/api/v1/models"))
    (when (and (not my/gptel--openrouter-context-window-fetch-inflight)
               (stringp model-id)
               (executable-find "curl"))
      (setq my/gptel--openrouter-context-window-fetch-inflight t)
      (let* ((key (ignore-errors (gptel-api-key-from-auth-source "api.openrouter.com" "api")))
             (buf (generate-new-buffer " *gptel-openrouter-models*")))
        (unless (and (stringp key) (not (string-empty-p key)))
          (setq my/gptel--openrouter-context-window-fetch-inflight nil)
          (when (buffer-live-p buf) (kill-buffer buf))
          (message "OpenRouter context-window: no API key found in auth-source")
          (cl-return-from my/gptel--openrouter-fetch-context-window nil))
        (let* ((cmd (list "curl"
                          "--silent" "--show-error" "--fail"
                          "--connect-timeout" (number-to-string my/gptel-openrouter-models-connect-timeout)
                          "--max-time" (number-to-string my/gptel-openrouter-models-max-time)
                          "--http1.1"
                          "-H" (concat "Authorization: Bearer " key)
                          "-H" "Accept: application/json"
                          url))
               (proc
                (make-process
                 :name "gptel-openrouter-models"
                 :buffer buf
                 :command cmd
                 :noquery t
                 :connection-type 'pipe
                 :sentinel
                 (lambda (p _event)
                   (when (memq (process-status p) '(exit signal))
                     (setq my/gptel--openrouter-context-window-fetch-inflight nil)
                     (unwind-protect
                         (if (not (= (process-exit-status p) 0))
                             (message "OpenRouter context-window: fetch failed (exit %d)" (process-exit-status p))
                           (with-current-buffer buf
                             (goto-char (point-min))
                             (condition-case err
                                 (let* ((json-object-type 'alist)
                                        (json-array-type 'list)
                                        (json-key-type 'symbol)
                                        (obj (json-parse-buffer :object-type 'alist :array-type 'list :null-object nil :false-object nil))
                                        (data (alist-get 'data obj))
                                        (entry (seq-find (lambda (e)
                                                           (let ((id (alist-get 'id e)))
                                                             (and (stringp id) (string= id model-id))))
                                                         data))
                                        (cw (and entry (alist-get 'context_length entry))))
                                   (if (and (integerp cw) (> cw 0))
                                       (progn
                                         (my/gptel--cache-put-context-window model-id cw)
                                         (message "OpenRouter context-window cached: %s -> %d" model-id cw))
                                     (message "OpenRouter context-window: model not found or missing context_length: %s" model-id)))
                               (error
                                (message "OpenRouter context-window: parse failed (%s)" (error-message-string err))))))
                       (when (buffer-live-p buf) (kill-buffer buf))))))))
          (process-put proc 'my/gptel-managed t)
          nil)))))

(defun my/gptel-refresh-context-window-cache ()
  "Refresh (fetch) the current model's context window into the cache." 
  (interactive)
  (my/gptel--openrouter-fetch-context-window gptel-model))

(defcustom my/gptel-auto-compact-enabled t
  "Whether to auto-compact gptel buffers when they grow too large."
  :type 'boolean)

(defcustom my/gptel-auto-compact-threshold 0.75
  "Fraction of context window at which to compact."
  :type 'number)

(defcustom my/gptel-auto-compact-min-chars 4000
  "Minimum buffer size (chars) before auto-compacting."
  :type 'integer)

(defvar-local my/gptel-auto-compact-running nil
  "Non-nil while auto-compaction is in progress for this buffer.")

(defcustom my/gptel-auto-compact-min-interval 45
  "Minimum seconds between auto-compactions per buffer."
  :type 'integer)

(defvar-local my/gptel-auto-compact-last-run nil
  "Time of the last auto-compaction for this buffer.")

(defcustom my/gptel-auto-plan-enabled t
  "Whether to auto-create planning files for multi-step tasks."
  :type 'boolean)

(defcustom my/gptel-auto-plan-min-steps 3
  "Minimum numbered steps to trigger planning file creation."
  :type 'integer)

(defcustom my/gptel-auto-plan-safe-root nil
  "Optional safe root directory for auto-plan files.

When nil, auto-plan uses the project root if available and otherwise
falls back to `default-directory` only when it is not a home or temp dir.
"
  :type '(choice (const :tag "Auto" nil) directory))

(defvar-local my/gptel-planning-files-created nil
  "Non-nil when planning files have been created for this buffer.")

(defun my/gptel--estimate-tokens (chars)
  "Estimate token count from CHARS. Rough heuristic: 4 chars/token."
  (/ (float chars) 4.0))

(defun my/gptel--context-window ()
  "Return model context window if available, else fall back to gptel-max-tokens.

Fallback is approximate and may be smaller than actual context.
"
  (let* ((model gptel-model)
         (model-id (my/gptel--model-id-string model))
         (window nil))
    ;; 1) Prefer our cache (for OpenRouter-style model ids).
    (when (and (stringp model-id)
               (gethash model-id my/gptel--context-window-cache))
      (setq window (gethash model-id my/gptel--context-window-cache)))
    (dolist (var '(gptel--openai-models gptel--gemini-models gptel--gh-models gptel--anthropic-models))
      (when (and (boundp var) (not window))
        (let ((entry (assq model (symbol-value var))))
          (when entry
            (setq window (my/gptel--normalize-context-window
                          (plist-get (cdr entry) :context-window)))))))
    ;; 2) If OpenRouter is in use and no metadata/cached value, fetch it.
    (when (and (not window)
               (boundp 'gptel--openrouter)
               (eq gptel-backend gptel--openrouter)
               (stringp model-id))
      (my/gptel--openrouter-fetch-context-window model))
    (or window
        gptel-max-tokens
        my/gptel-default-context-window)))

(defun my/gptel--compact-safe-p ()
  "Return non-nil if auto-compact is safe for the current buffer."
  (let ((elapsed (and my/gptel-auto-compact-last-run
                      (float-time (time-subtract (current-time)
                                                 my/gptel-auto-compact-last-run)))))
    (and (not my/gptel-auto-compact-running)
         (or (null elapsed)
             (>= elapsed my/gptel-auto-compact-min-interval)))))

(defun my/gptel--auto-compact-needed-p ()
  "Return non-nil when current buffer should be compacted."
  (let* ((chars (buffer-size))
         (tokens (my/gptel--estimate-tokens chars))
         (window (my/gptel--context-window))
         (threshold (* window my/gptel-auto-compact-threshold)))
    (and my/gptel-auto-compact-enabled
         (bound-and-true-p gptel-mode)
         (my/gptel--compact-safe-p)
         (>= chars my/gptel-auto-compact-min-chars)
         (>= tokens threshold))))

(defun my/gptel--count-numbered-steps (text)
  "Count numbered steps like \"1.\" or \"2)\" in TEXT."
  (let ((count 0)
        (pos 0))
    (while (string-match "^\\s-*\\([0-9]+\\)[.)]" text pos)
      (setq count (1+ count))
      (setq pos (match-end 0)))
    count))

(defun my/gptel--planning-signal-p (text)
  "Return non-nil when TEXT looks like a multi-step plan."
  (or (string-match-p "\\b\\(Steps\\|Plan\\|Phases\\)\\b" text)
      (> (length text) 400)))

(defun my/gptel--planning-files-present-p (dir)
  "Return non-nil if planning files already exist in DIR."
  (and (file-exists-p (expand-file-name "task_plan.md" dir))
       (file-exists-p (expand-file-name "findings.md" dir))
       (file-exists-p (expand-file-name "progress.md" dir))))

(defun my/gptel--home-or-temp-dir-p (dir)
  "Return non-nil when DIR is home or temporary."
  (let* ((dir (file-truename (file-name-as-directory dir)))
         (home (file-truename (file-name-as-directory (expand-file-name "~"))))
         (tmp (file-truename (file-name-as-directory temporary-file-directory))))
    (or (string= dir home)
        (string= dir tmp)
        (string-prefix-p tmp dir))))

(defun my/gptel--resolve-planning-dir ()
  "Return a safe directory for planning files or nil if unsafe."
  (cond
   ((and my/gptel-auto-plan-safe-root
         (file-directory-p my/gptel-auto-plan-safe-root))
    (file-name-as-directory (expand-file-name my/gptel-auto-plan-safe-root)))
   ((project-current)
    (project-root (project-current)))
   ((and (stringp default-directory)
         (file-directory-p default-directory)
         (not (my/gptel--home-or-temp-dir-p default-directory)))
    default-directory)
   (t nil)))

(defun my/gptel--maybe-create-planning-files (text)
  "Create planning files when TEXT contains multi-step instructions."
  (when (and my/gptel-auto-plan-enabled
             (bound-and-true-p gptel-mode)
             (not my/gptel-planning-files-created)
             (my/gptel--planning-signal-p text)
             (>= (my/gptel--count-numbered-steps text) my/gptel-auto-plan-min-steps))
    (when-let ((dir (my/gptel--resolve-planning-dir)))
      (let ((plan (expand-file-name "task_plan.md" dir))
            (findings (expand-file-name "findings.md" dir))
            (progress (expand-file-name "progress.md" dir)))
        (unless (my/gptel--planning-files-present-p dir)
          (with-temp-file plan
            (insert "# Task Plan\n\n## Goal\n- \n\n## Phases\n- [ ] Phase 1\n\n## Errors Encountered\n| Error | Attempt | Resolution |\n| --- | --- | --- |\n"))
          (with-temp-file findings
            (insert "# Findings\n\n"))
          (with-temp-file progress
            (insert "# Progress\n\n")))
        (setq my/gptel-planning-files-created t)))))

(defun my/gptel--directive-text (sym)
  "Resolve directive SYM to a string."
  (let ((val (alist-get sym gptel-directives)))
    (cond
     ((functionp val) (funcall val))
     ((stringp val) val)
     (t nil))))

(defun my/gptel-auto-compact (_start _end)
  "Compact current gptel buffer when it grows too large."
  (when (my/gptel--auto-compact-needed-p)
    (let ((system (my/gptel--directive-text 'compact))
          (buf (current-buffer)))
      (when system
        (setq my/gptel-auto-compact-running t)
        (gptel-request (buffer-string)
          :system system
          :buffer buf
          :callback (lambda (response _info)
                      (with-current-buffer buf
                        (setq my/gptel-auto-compact-running nil)
                        (setq my/gptel-auto-compact-last-run (current-time))
                        (when (stringp response)
                          (let ((inhibit-read-only t))
                            (erase-buffer)
                            (insert response))))))))))

(add-hook 'gptel-post-response-functions #'my/gptel-auto-compact)

(add-hook 'gptel-post-response-functions
          (lambda (_start _end)
            (my/gptel--maybe-create-planning-files (buffer-string))))

(defun my/learning--update-instinct (path)
  "Update evidence and last-accessed in instinct frontmatter at PATH."
  (when (file-readable-p path)
    (let* ((text (with-temp-buffer
                   (insert-file-contents path)
                   (buffer-string)))
           (case-fold-search nil))
      (when (string-match "\\`---\n\\([\\s\\S]*?\n\\)---\n" text)
        (let* ((front (match-string 1 text))
               (rest (substring text (match-end 0)))
               (date (format-time-string "%Y-%m-%d"))
               (front (if (string-match "^evidence:\\s-*\\([0-9]+\\)" front)
                          (replace-regexp-in-string
                           "^evidence:\\s-*\\([0-9]+\\)"
                           (lambda (_m)
                             (format "evidence: %d"
                                     (1+ (string-to-number (match-string 1 front)))))
                           front)
                        (concat front "evidence: 1\n")))
               (front (if (string-match "^last-accessed:" front)
                          (replace-regexp-in-string
                           "^last-accessed:.*$"
                           (format "last-accessed: %s" date)
                           front)
                        (concat front "last-accessed: " date "\n")))
               (updated (concat "---\n" front "---\n" rest)))
          (with-temp-file path
            (insert updated)))))))

(defun my/learning-auto-evolve-after-commit ()
  "Auto-evolve instincts touched in the latest commit.

If LEARNING.md was updated, increment all instincts referenced via
learning-ref: LEARNING.md#slug.
"
  (let* ((repo (or (and (boundp 'git-commit-repository)
                        git-commit-repository)
                   default-directory))
         (default-directory repo)
         (paths (condition-case nil
                    (process-lines "git" "diff" "--name-only" "HEAD~1")
                  (error nil)))
         (learning-updated (seq-find (lambda (p) (string-match-p "\\`LEARNING.md\\'" p)) paths)))
    (dolist (rel paths)
      (when (string-match-p "\\`instincts/" rel)
        (my/learning--update-instinct (expand-file-name rel repo))))
    (when learning-updated
      (let* ((learning-path (expand-file-name "LEARNING.md" repo))
             (learning-text (when (file-readable-p learning-path)
                              (with-temp-buffer
                                (insert-file-contents learning-path)
                                (buffer-string))))
             (slugs (when learning-text
                      (let ((pos 0)
                            (refs '()))
                        (while (string-match "^### \\(.+\\)$" learning-text pos)
                          (push (format "LEARNING.md#%s" (match-string 1 learning-text)) refs)
                          (setq pos (match-end 0)))
                        refs))))
        (when slugs
          (let* ((instincts-dir (expand-file-name "instincts" repo))
                 (files (when (file-directory-p instincts-dir)
                          (directory-files-recursively instincts-dir "\\.md\\'"))))
            (dolist (file files)
              (when (and (file-readable-p file)
                         (let* ((text (with-temp-buffer
                                        (insert-file-contents file)
                                        (buffer-string))))
                           (seq-some (lambda (ref)
                                       (string-match-p (regexp-quote ref) text))
                                     slugs)))
                (my/learning--update-instinct file)))))))))

(with-eval-after-load 'git-commit
  (add-hook 'git-commit-finish-hook #'my/learning-auto-evolve-after-commit))

(defun my/find-buffers-and-recent (pattern)
  "Find open buffers and recently opened files matching PATTERN."
  (let* ((pattern (if (string-empty-p pattern) "." pattern))
         (bufs (delq nil (mapcar (lambda (b)
                                   (let ((name (buffer-name b)) (file (buffer-file-name b)))
                                     (when (and (not (string-prefix-p " " name))
                                                (or (string-match-p pattern name)
                                                    (and file (string-match-p pattern file))))
                                       (format "  %s%s (%s)" name (if (buffer-modified-p b) "*" "") (or file "")))))
                                 (buffer-list))))
         (recs (progn (recentf-mode 1)
                      (seq-filter (lambda (f) (string-match-p pattern (file-name-nondirectory f))) recentf-list))))
    (concat (when bufs (format "Open Buffers:\n%s\n\n" (string-join bufs "\n")))
            (when recs (format "Recent Files:\n%s" (string-join (mapcar (lambda (f) (format "  %s" f)) recs) "\n"))))))

;; --- Utility helpers (external / gptel-tool use only) ---
;; These functions are not referenced within this file.  They are called by
;; name from gptel tool lambdas or agent prompts at runtime.  Do not remove.

(defun my/read-file-or-buffer (source &optional start-line end-line)
  "Read SOURCE (file or buffer) with optional line bounds."
  (with-temp-buffer
    (condition-case err
        (cond
         ((get-buffer source) (insert-buffer-substring source))
         ((and (file-readable-p (expand-file-name source))
               (not (file-directory-p (expand-file-name source))))
          (insert-file-contents (expand-file-name source)))
         (t (insert (format "Error: Cannot read source (or is directory): %s\n" source))))
      (error (insert (format "Error: %s\n" (error-message-string err)))))
    (let* ((start (max 1 (or start-line 1)))
           (end (or end-line (+ start 500)))
           (current 1)
           (lines '()))
      (goto-char (point-min))
      (while (and (not (eobp)) (<= current end))
        (when (>= current start)
          (push (format "L%d: %s" current (buffer-substring-no-properties (line-beginning-position) (line-end-position))) lines))
        (forward-line 1)
        (cl-incf current))
      (format "Source: %s\n%s" source (string-join (nreverse lines) "\n")))))

(defun my/search-project (callback pattern &optional dir ctx)
  "Search using ripgrep asynchronously."
  (if (not (executable-find "rg"))
      (funcall callback "Error: ripgrep not installed")
    (let* ((default-directory (expand-file-name (or dir default-directory)))
           (ctx-args (if ctx (list "-C" (number-to-string ctx)) nil))
           (args (append '("--line-number" "--no-heading" "--with-filename" "--") ctx-args (list pattern ".")))
           (buf (generate-new-buffer " *rg-async*"))
           (proc (make-process
                  :name "rg-async"
                  :buffer buf
                  :command (cons "rg" args)
                  :sentinel (lambda (p _event)
                              (when (memq (process-status p) '(exit signal))
                                (let ((res (with-current-buffer buf
                                             (string-trim (buffer-string)))))
                                  (kill-buffer buf)
                                  (funcall callback (if (string-empty-p res) "No matches found." res))))))))
      (process-put proc 'my/gptel-managed t)
      proc)))

(defun my/web-read-url (callback url)
  "Fetch URL text asynchronously."
  (let ((url-request-extra-headers '(("User-Agent" . "Mozilla/5.0"))))
    (url-retrieve url
                  (lambda (status)
                    (if (plist-get status :error)
                        (funcall callback (format "Error fetching URL: %s" (plist-get status :error)))
                      (goto-char (point-min))
                      (re-search-forward "^$" nil 'move)
                      (let ((res (if (fboundp 'libxml-parse-html-region)
                                     (with-temp-buffer
                                       (shr-insert-document (libxml-parse-html-region (point) (point-max)))
                                       (buffer-string))
                                   (buffer-substring-no-properties (point) (point-max)))))
                        (funcall callback (string-trim res))))
                    (kill-buffer (current-buffer)))
                  nil t t)))


(defun my/web-search-ddg-fallback (callback query)
  "Fallback web search using DuckDuckGo HTML endpoint via `url-retrieve`.

Returns a plain-text list of up to ~5 results.
IMPORTANT: must call CALLBACK exactly once."
  (let* ((url-request-extra-headers
          '(("User-Agent" . "Mozilla/5.0")
            ("Accept" . "text/html")))
         ;; Using the html endpoint to avoid heavy JS.
         (url (concat "https://duckduckgo.com/html/?q=" (url-hexify-string query))))
    (url-retrieve
     url
     (lambda (status)
       (unwind-protect
           (if (plist-get status :error)
               (funcall callback (format "Error fetching DuckDuckGo: %S" (plist-get status :error)))
             (goto-char (point-min))
             (re-search-forward "^$" nil 'move)
             (let* ((dom (and (fboundp 'libxml-parse-html-region)
                              (libxml-parse-html-region (point) (point-max)))))
               (if (not dom)
                   (funcall callback "Error: HTML parser unavailable (no libxml).")
                 (let* ((links (dom-by-class dom "result__a"))
                        (items (seq-take links 5))
                        (lines
                         (mapcar
                          (lambda (a)
                            (let ((title (string-trim (dom-texts a " ")))
                                  (href (dom-attr a 'href)))
                              (format "%s\n%s" title href)))
                          items)))
                   (funcall callback
                            (if lines
                                (string-join lines "\n\n")
                              "No results."))))))
         (when (buffer-live-p (current-buffer))
           (kill-buffer (current-buffer)))))
     nil t t)))

(defun my/gptel--extract-patch (text)
  "Extract all unified diff blocks from TEXT.
Collects content from blocks starting with '--- a/' or '--- b/'.
Strips surrounding markdown chatter."
  (let ((pos 0)
        (patches '()))
    (while (string-match "\\(?:^\\|\n\\)\\(--- [ab]/[^\n]+\n\\+\\+\\+ [ab]/[^\n]+\n\\(?:@@ -[0-9,]+ \\+[0-9,]+ @@.*\n\\(?:[ +\\-].*\n\\|\\\\.*\n\\)*\\)+\\)" text pos)
      (push (match-string 1 text) patches)
      (setq pos (match-end 1)))
    (if patches
        (string-join (nreverse patches) "\n")
      ;; Fallback: try the older, looser matching if the strict regex fails
      (cond
       ((string-match "^--- [ab]/" text)
        (let ((start (match-beginning 0)))
          (if (string-match "^```\\(?:diff\\|patch\\)?\n" (substring text 0 start))
              (let ((content (substring text start)))
                (if (string-match "\n```" content)
                    (substring content 0 (match-beginning 0))
                  content))
            (substring text start))))
       ((string-match "\n--- [ab]/" text)
        (let ((start (1+ (match-beginning 0))))
          (if (string-match "^```\\(?:diff\\|patch\\)?\n" (substring text 0 start))
              (let ((content (substring text start)))
                (if (string-match "\n```" content)
                    (substring content 0 (match-beginning 0))
                  content))
            (substring text start))))
       (t text)))))

(defun my/gptel--parse-git-apply-errors (output)
  "Parse OUTPUT from git apply to extract specific hunk failures and path issues."
  (let ((errors '()))
    (with-temp-buffer
      (insert output)
      (goto-char (point-min))
      ;; Path not found
      (while (re-search-forward "error: \\([^:\n]+\\): No such file or directory" nil t)
        (push (list :path (match-string 1) :type :not-found) errors))
      ;; Hunk failure
      (goto-char (point-min))
      (while (re-search-forward "error: patch failed: \\([^:\n]+\\):\\([0-9]+\\)" nil t)
        (push (list :path (match-string 1) :line (match-string 2) :type :hunk-failed) errors))
      ;; Context failure
      (goto-char (point-min))
      (while (re-search-forward "error: \\([^:\n]+\\): patch does not apply" nil t)
        (push (list :path (match-string 1) :type :context-mismatch) errors)))
    (nreverse errors)))

(defun my/gptel--find-correct-path (wrong-path)
  "Try to find a correct path for WRONG-PATH in the current project."
  (let* ((proj (project-current))
         ;; Strip git prefixes a/ or b/
         (clean-path (if (string-match "\\`[ab]/" wrong-path)
                         (substring wrong-path 2)
                       wrong-path))
         (base (file-name-nondirectory clean-path))
         (files (and proj (project-files proj))))
    (when files
      (or (seq-find (lambda (f) (string-suffix-p clean-path f)) files)
          (seq-find (lambda (f) (string-suffix-p base f)) files)))))

(defun my/gptel--preview-patch-core (patch &optional displayp)
  "Populate *gptel-patch-preview* with PATCH in diff-mode.

When DISPLAYP is non-nil (default), display the preview buffer.
Always uses `diff-mode' — magit-diff-mode requires git-parsed output
and cannot render raw unified diff text properly."
  (let ((clean-patch (my/gptel--extract-patch patch))
        (buf (get-buffer-create "*gptel-patch-preview*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert clean-patch)
        (diff-mode)
        (setq-local buffer-read-only t)))
    (when (or (null displayp) displayp)
      (display-buffer buf))
    "Patch previewed in *gptel-patch-preview* buffer."))

(defun my/gptel--preview-patch-async (patch gptel-buf callback on-confirm on-abort header)
  "Show PATCH in *gptel-patch-preview*, install n/q stepper, wait for user.

GPTEL-BUF is the originating gptel buffer (for abort-generation guard).
CALLBACK is the gptel async tool callback — fired by ON-CONFIRM or ON-ABORT.
ON-CONFIRM is a unary function called with CALLBACK when user presses n.
ON-ABORT   is a unary function called with CALLBACK when user presses q or
           kills the preview buffer.
HEADER is the string shown in the preview buffer's header-line.

Unlike the file-change queue, patch preview is always a single step — no
queue, no step numbering.  The stepper state uses :on-confirm/:on-abort so
`my/gptel--preview-next' and `my/gptel--preview-quit' dispatch correctly."
  (my/gptel--preview-patch-core patch t)
  (when-let ((buf (get-buffer "*gptel-patch-preview*")))
    (with-current-buffer buf
      ;; Install state with custom confirm/abort thunks.
      (setq-local my/gptel--preview-stepper-state
                  (list :gptel-buf  gptel-buf
                        :path       "*gptel-patch-preview*"
                        :callback   callback
                        :on-confirm on-confirm
                        :on-abort   on-abort))
      (setq header-line-format header)
      (my/gptel--preview-stepper-mode 1)
      ;; Kill-buffer guard: closing the buffer without n/q treats it as q.
      (add-hook 'kill-buffer-hook
                (lambda ()
                  (when my/gptel--preview-stepper-mode
                    (my/gptel--preview-quit)))
                nil t))))

(defgroup my/gptel-subagent nil
  "Subagent delegation settings (Agent/RunAgent tools)."
  :group 'gptel)

(defcustom my/gptel-agent-task-timeout 120
  "Seconds before a delegated Agent/RunAgent task is force-stopped.
If the subagent hasn't returned after this many seconds, the callback
is called with a timeout error."
  :type 'integer
  :group 'my/gptel-subagent)

(defcustom my/gptel-subagent-model 'minimax-m2.5
  "Model to use for delegated subagents (Agent/RunAgent).
When non-nil, subagent requests use this model instead of the parent's.
Must be a symbol matching a model in `my/gptel-subagent-backend'."
  :type '(choice (const :tag "Same as parent" nil) symbol)
  :group 'my/gptel-subagent)

(defcustom my/gptel-subagent-backend nil
  "Backend for delegated subagents.
When nil, defaults to `gptel--gemini'.  Set to a backend variable
like `gptel--openrouter' to route subagent traffic differently."
  :type '(choice (const :tag "Gemini (default)" nil) variable)
  :group 'my/gptel-subagent)

(defvar my/gptel--in-subagent-task nil
  "Non-nil while inside a `gptel-agent--task' call.
Used by the post-preset hook to override the model for subagents.")

(defun my/gptel--agent-task-override-model (orig &rest args)
  "Around-advice for `gptel-agent--task': override model/backend for subagents.

Uses dynamic `let' to bind `gptel-model' and `gptel-backend' so the
override unwinds cleanly when the call returns (even though the actual
request is async, `gptel-with-preset' inside `gptel-agent--task'
captures the values at call time)."
  (let* ((my/gptel--in-subagent-task t)
         (gptel-model (if my/gptel-subagent-model
                          (if (stringp my/gptel-subagent-model)
                              (intern my/gptel-subagent-model)
                            my/gptel-subagent-model)
                        gptel-model))
         (gptel-backend (if my/gptel-subagent-model
                            (let ((b my/gptel-subagent-backend))
                              (or (and (symbolp b) (boundp b) (symbol-value b))
                                  b
                                  (and (boundp 'gptel--minimax) gptel--minimax)
                                  gptel-backend))
                          gptel-backend)))
    (when my/gptel-subagent-model
      (message "gptel subagent: using %s/%s"
               (gptel-backend-name gptel-backend) gptel-model))
    (apply orig args)))


(defun my/gptel--agent-task-with-timeout (callback agent-type description prompt)
  "Wrapper around `gptel-agent--task' that adds a timeout.
If the subagent doesn't return within `my/gptel-agent-task-timeout' seconds,
CALLBACK is called with a timeout error."
  (let* ((done nil)
         (timer nil)
         (parent-fsm (buffer-local-value 'gptel--fsm-last (current-buffer)))
         (origin-buf (current-buffer))
         (wrapped-cb
          (lambda (result)
            (unless done
              (setq done t)
              (when (timerp timer) (cancel-timer timer))
              (when (buffer-live-p origin-buf)
                (with-current-buffer origin-buf
                  (setq-local gptel--fsm-last parent-fsm))
                (setq-local gptel--fsm-last parent-fsm))
              (funcall callback result)))))
    (setq timer
          (run-at-time
           my/gptel-agent-task-timeout nil
           (lambda ()
             (unless done
               (setq done t)
               (when (buffer-live-p origin-buf)
                 (with-current-buffer origin-buf
                   (let ((my/gptel--abort-generation (1+ my/gptel--abort-generation)))
                     (my/gptel-abort-here))
                   (setq-local gptel--fsm-last parent-fsm))
                 (setq-local gptel--fsm-last parent-fsm))
               (funcall callback
                        (format "Error: Agent task \"%s\" (%s) timed out after %ds. \
Try a simpler prompt or use inline tools instead of delegation."
                                description agent-type my/gptel-agent-task-timeout))))))
    (gptel-agent--task wrapped-cb agent-type description prompt)))

(defgroup my/gptel-applypatch nil
  "ApplyPatch tool behavior."
  :group 'gptel)

(defcustom my/gptel-applypatch-timeout 30
  "Seconds before ApplyPatch is force-stopped."
  :type 'integer
  :group 'my/gptel-applypatch)

(defcustom my/gptel-applypatch-auto-preview t
  "When non-nil (default), show *gptel-patch-preview* and wait for user
confirmation (n to apply, q to abort) before applying the patch.

When nil, apply immediately without any preview gate — useful for
headless or automated ApplyPatch calls."
  :type 'boolean
  :group 'my/gptel-applypatch)

(defcustom my/gptel-applypatch-precheck t
  "When non-nil, run a dry-run check before applying a patch.

For git repos this uses `git apply --check`. For non-git it uses
`patch --dry-run`." 
  :type 'boolean
  :group 'my/gptel-applypatch)

(defun my/gptel--patch-looks-like-unified-diff-p (text)
  "Return non-nil when TEXT looks like a unified diff." 
  (and (stringp text)
       (or (string-match-p "^diff --git " text)
           (and (string-match-p "^--- " text)
                (string-match-p "^\\+\\+\\+ " text)))))

(defun my/gptel--patch-looks-like-envelope-p (text)
  "Return non-nil when TEXT looks like an OpenCode apply_patch envelope."
  (and (stringp text) (string-match-p "^\\*\\*\\* Begin Patch" text)))

(defun my/gptel--applypatch--safe-path (root rel)
  "Return absolute path for REL under ROOT, or signal error."
  (let* ((root (file-name-as-directory (expand-file-name root)))
         (rel (string-trim (format "%s" (or rel "")))))
    (when (or (string-empty-p rel) (file-name-absolute-p rel) (string-prefix-p "~" rel))
      (error "ApplyPatch: invalid path %S" rel))
    (let* ((abs (expand-file-name rel root))
           (rt (file-truename root))
           (pt (file-truename (file-name-directory abs))))
      (unless (string-prefix-p rt pt) (error "ApplyPatch: path escapes root: %S" rel))
      abs)))

(defun my/gptel--applypatch--count-occurrences (hay needle)
  "Count non-overlapping occurrences of NEEDLE in HAY."
  (let ((count 0) (pos 0))
    (while (and (stringp hay) (stringp needle) (not (string-empty-p needle))
                (setq pos (string-match (regexp-quote needle) hay pos)))
      (setq count (1+ count) pos (+ pos (length needle))))
    count))

(defun my/gptel--applypatch--replace-unique (text old new &optional label)
  "Replace OLD with NEW in TEXT, requiring exactly one match."
  (let* ((label (or label "replace"))
         (n (my/gptel--applypatch--count-occurrences text old)))
    (cond
     ((= n 1) (replace-regexp-in-string (regexp-quote old) new text t t))
     ((= n 0) (error "ApplyPatch: %s (old not found)" label))
     (t (error "ApplyPatch: %s (matched %d times)" label n)))))

(defun my/gptel--applypatch--strip-plus (lines)
  "Return content from LINES prefixed with '+'."
  (let (out)
    (dolist (l lines (nreverse out))
      (cond ((string-prefix-p "+" l) (push (substring l 1) out))
            ((string-empty-p l) (push "" out))
            (t (error "ApplyPatch: Add expects '+' lines, got: %S" l))))))

(defun my/gptel--applypatch--parse-envelope (text)
  "Parse OpenCode envelope TEXT into an op list."
  (let* ((lines (split-string text "\n" nil)) (i 0) (ops nil) (cur nil))
    (cl-labels
        ((flush () (when cur (push cur ops) (setq cur nil)))
         (pfx (p s) (and (stringp s) (string-prefix-p p s)))
         (path (p s) (string-trim (substring s (length p)))))
      (unless (and lines (pfx "*** Begin Patch" (car lines)))
        (error "ApplyPatch: missing '*** Begin Patch'"))
      (setq i 1)
      (while (< i (length lines))
        (let ((l (nth i lines)))
          (cond
           ((pfx "*** End Patch" l) (flush) (setq i (length lines)))
           ((pfx "*** Add File:" l) (flush) (setq cur (list :op 'add :path (path "*** Add File:" l) :lines nil)))
           ((pfx "*** Delete File:" l) (flush) (push (list :op 'delete :path (path "*** Delete File:" l)) ops))
           ((pfx "*** Update File:" l) (flush) (setq cur (list :op 'update :path (path "*** Update File:" l) :move-to nil :lines nil)))
           ((pfx "*** Move to:" l)
            (unless (and cur (eq (plist-get cur :op) 'update)) (error "ApplyPatch: Move without Update"))
            (plist-put cur :move-to (path "*** Move to:" l)))
           ((pfx "*** " l) (error "ApplyPatch: unknown header: %S" l))
           (t (when cur (plist-put cur :lines (append (plist-get cur :lines) (list l)))))))
        (setq i (1+ i)))
      (flush) (nreverse ops))))

(defun my/gptel--applypatch--apply-envelope (root text)
  "Apply OpenCode envelope TEXT under ROOT. Returns a summary string."
  (let* ((ops (my/gptel--applypatch--parse-envelope text))
         (adds 0) (updates 0) (deletes 0) (moves 0) (touched nil))
    (dolist (op ops)
      (pcase (plist-get op :op)
        ('add
         (let* ((p (my/gptel--applypatch--safe-path root (plist-get op :path)))
                (lines (my/gptel--applypatch--strip-plus (or (plist-get op :lines) '())))
                (content (string-join lines "\n")))
           (make-directory (file-name-directory p) t)
           (when (file-exists-p p) (error "ApplyPatch: Add target exists: %s" (file-relative-name p root)))
           (write-region content nil p nil 'silent) (cl-incf adds)
           (push (file-relative-name p root) touched)))
        ('delete
         (let ((p (my/gptel--applypatch--safe-path root (plist-get op :path))))
           (unless (file-exists-p p) (error "ApplyPatch: Delete target missing: %s" (file-relative-name p root)))
           (delete-file p) (cl-incf deletes) (push (file-relative-name p root) touched)))
        ('update
         (let* ((src (my/gptel--applypatch--safe-path root (plist-get op :path)))
                (dst-rel (plist-get op :move-to))
                (dst (and dst-rel (my/gptel--applypatch--safe-path root dst-rel)))
                (lines (or (plist-get op :lines) '())))
           (unless (file-exists-p src) (error "ApplyPatch: Update target missing: %s" (file-relative-name src root)))
           (when dst (make-directory (file-name-directory dst) t) (rename-file src dst nil) (cl-incf moves) (setq src dst) (push (file-relative-name src root) touched))
           (when lines
             (let ((ft (with-temp-buffer (insert-file-contents src) (buffer-string)))
                   (hunks nil) (ca nil) (clines nil))
               (cl-labels ((fh () (when clines (push (list :anchor ca :lines clines) hunks)) (setq ca nil clines nil)))
                 (dolist (l lines) (if (string-prefix-p "@@" l) (progn (fh) (setq ca (string-trim (substring l 2)))) (setq clines (append clines (list l)))))
                 (fh))
               (setq hunks (nreverse hunks))
               (unless hunks (setq hunks (list (list :anchor nil :lines lines))))
               (dolist (h hunks)
                 (let ((anc (plist-get h :anchor)) (chg (plist-get h :lines)) ol nl)
                   (dolist (c chg)
                     (cond ((string-prefix-p "-" c) (push (substring c 1) ol))
                           ((string-prefix-p "+" c) (push (substring c 1) nl))
                           ((string-empty-p c) nil)
                           (t (error "ApplyPatch: line must start with +/-: %S" c))))
                   (setq ol (nreverse ol) nl (nreverse nl))
                   (cond
                    (ol (setq ft (my/gptel--applypatch--replace-unique ft (string-join ol "\n") (string-join nl "\n") (format "update %s" (file-relative-name src root)))))
                    (nl (unless (and (stringp anc) (not (string-empty-p anc))) (error "ApplyPatch: insertion needs @@ anchor"))
                        (with-temp-buffer (insert ft) (goto-char (point-min)) (unless (search-forward anc nil t) (error "ApplyPatch: anchor not found: %S" anc)) (end-of-line) (insert "\n" (string-join nl "\n") "\n") (setq ft (buffer-string)))))))
               (write-region ft nil src nil 'silent)))
           (cl-incf updates) (push (file-relative-name src root) touched)))
        (_ (error "ApplyPatch: unknown op %S" (plist-get op :op)))))
    (setq touched (delete-dups (nreverse touched)))
    (string-join (seq-filter #'identity (list (format "Envelope applied: add=%d update=%d delete=%d move=%d" adds updates deletes moves) (and touched (format "Files: %s" (string-join touched ", "))))) "\n")))

(defun my/gptel--apply-patch-dispatch (callback patch)
  "Dispatch PATCH to either envelope or unified diff handler.
This is the top-level ApplyPatch tool function."
  (let* ((clean (my/gptel--extract-patch patch))
         (root (if-let ((proj (project-current nil)))
                   (expand-file-name (project-root proj))
                 (expand-file-name default-directory))))
    (if (my/gptel--patch-looks-like-envelope-p clean)
        (condition-case env-err
            (funcall callback (my/gptel--applypatch--apply-envelope root clean))
          (error (funcall callback (format "ApplyPatch envelope error: %s" (error-message-string env-err)))))
      ;; Unified diff: delegate to the original async handler.
      (my/gptel--apply-patch-core callback patch))))

(defun my/gptel--patch-has-absolute-paths-p (text)
  "Return non-nil when TEXT contains absolute paths.

We reject these to avoid applying patches outside the project root." 
  (and (stringp text)
       (or (string-match-p "^--- /" text)
           (string-match-p "^\\+\\+\\+ /" text)
           (string-match-p "^diff --git /" text)
           (string-match-p "/Users/" text))))

(defun my/gptel--apply-patch-core (callback patch)
  "Apply PATCH (unified diff) at the Emacs project root asynchronously.
Runs the application and produces actionable errors on failure.
Prefers `git apply` if in a git repository; otherwise uses `patch`."
  (condition-case err
      (progn
        (unless (or (executable-find "git") (executable-find "patch"))
          (error "ApplyPatch: neither 'git' nor 'patch' executable found"))
        (unless (and (stringp patch) (not (string-empty-p (string-trim patch))))
          (error "ApplyPatch: patch text is empty"))

        (let* ((clean-patch (my/gptel--extract-patch patch))
               (patch-file (make-temp-file "gptel-patch-"))
               (root (if-let ((proj (project-current nil)))
                         (expand-file-name (project-root proj))
                       (expand-file-name default-directory)))
               (default-directory (file-name-as-directory root))
               (is-git (and (executable-find "git")
                            (file-exists-p (expand-file-name ".git" root))))
               (backend (if is-git "git" "patch"))
               (buf (generate-new-buffer (format " *gptel-patch-%s*" backend)))
               (done nil)
               (timer nil)
               (finish
                (lambda (msg)
                  (unless done
                    (setq done t)
                    (when (timerp timer) (cancel-timer timer))
                    (when (buffer-live-p buf) (kill-buffer buf))
                    (when (file-exists-p patch-file) (delete-file patch-file))
                    (funcall callback msg)))))

          ;; Validation (before showing preview — fail fast on bad input)
          (when (string-match-p "^\\*\\*\\* Begin Patch" clean-patch)
            (error "ApplyPatch expects unified diff (--- a/... +++ b/...), not '*** Begin Patch' envelope"))
          (unless (my/gptel--patch-looks-like-unified-diff-p clean-patch)
            (error "ApplyPatch: patch does not look like a unified diff"))
          (when (my/gptel--patch-has-absolute-paths-p clean-patch)
            (error "ApplyPatch: patch contains absolute paths; use repo-relative a/... and b/..."))

          (with-temp-file patch-file (insert clean-patch))

          (cl-labels
              ((format-failure (status out)
                 (let* ((errors (my/gptel--parse-git-apply-errors out))
                        (hints '()))
                   (dolist (err errors)
                     (cond
                      ((eq (plist-get err :type) :not-found)
                       (let ((path (plist-get err :path)))
                         (push (format "- File not found: %s" path) hints)
                         (when-let ((suggested (my/gptel--find-correct-path path)))
                           (push (format "  Suggestion: Did you mean '%s'?" suggested) hints))))
                      ((eq (plist-get err :type) :hunk-failed)
                       (push (format "- Hunk failed at %s:%s. Check context/line numbers."
                                     (plist-get err :path) (plist-get err :line))
                             hints))
                      ((eq (plist-get err :type) :context-mismatch)
                       (push (format "- Context mismatch in %s. Regenerate with more context."
                                     (plist-get err :path))
                             hints))))
                   (string-join
                    (seq-filter
                     #'identity
                     (list
                      (format "Patch application failed (status %d) using %s." status backend)
                      ""
                      (if (string-empty-p out) "(no output)" out)
                      ""
                      "Structured Analysis:"
                      (if hints (string-join (nreverse hints) "\n") "No specific hints available.")
                      ""
                      "General Advice:"
                      "- Ensure paths use git-style prefixes: 'a/...' and 'b/...'."
                      "- Ensure you're patching from repo root (this tool uses the Emacs project root)."
                      "- If the file changed, regenerate the diff with more context lines."))
                    "\n")))

               (run-backend (args kind next)
                 (with-current-buffer buf (let ((inhibit-read-only t)) (erase-buffer)))
                 (let ((proc
                        (make-process
                         :name (format "gptel-%s-%s" backend kind)
                         :buffer buf
                         :command (cons backend args)
                         :connection-type 'pipe
                         :noquery t
                         :sentinel
                         (lambda (p _event)
                           (when (memq (process-status p) '(exit signal))
                             (let* ((status (process-exit-status p))
                                    (out (with-current-buffer buf (string-trim (buffer-string)))))
                               (cond
                                ((= status 0)
                                 (if next
                                     (funcall next)
                                   (funcall finish
                                            (format "Patch applied successfully using %s.\n\n%s"
                                                    backend (if (string-empty-p out) "(no output)" out)))))
                                (t
                                 (funcall finish (format-failure status out)))))))))))
                 (process-put proc 'my/gptel-managed t)
                 proc))

            (do-apply ()
                      ;; Start timeout only when actually applying.
                      (setq timer
                            (run-at-time
                             my/gptel-applypatch-timeout nil
                             (lambda ()
                               (funcall finish
                                        (format "ApplyPatch: timed out after %ss"
                                                my/gptel-applypatch-timeout)))))
                      (let ((check-args (if is-git
                                            (list "apply" "--check" "--verbose" patch-file)
                                          (list "--dry-run" "-p1" "-N" "-i" patch-file)))
                            (apply-args (if is-git
                                            (list "apply" "--verbose" "--whitespace=fix" patch-file)
                                          (list "--batch" "-p1" "-N" "-i" patch-file))))
                        (if my/gptel-applypatch-precheck
                            (run-backend check-args "check"
                                         (lambda () (run-backend apply-args "apply" nil)))
                          (run-backend apply-args "apply" nil)))))

          ;; When auto-preview is enabled (default): show diff and wait for
          ;; the user to confirm (n) or abort (q) before applying.
          ;; When nil (headless/automated): apply immediately without gate.
          (if my/gptel-applypatch-auto-preview
              (my/gptel--preview-patch-async
               patch (current-buffer) callback
               ;; on-confirm: user pressed n → run git apply
               (lambda (cb)
                 ;; Rebind finish to use the provided callback so the
                 ;; cl-labels closure sees the right callback reference.
                 (setq finish (lambda (msg)
                                (unless done
                                  (setq done t)
                                  (when (timerp timer) (cancel-timer timer))
                                  (when (buffer-live-p buf) (kill-buffer buf))
                                  (when (file-exists-p patch-file)
                                    (delete-file patch-file))
                                  (funcall cb msg))))
                 (do-apply))
               ;; on-abort: user pressed q → clean up and report
               (lambda (cb)
                 (setq done t)
                 (when (timerp timer) (cancel-timer timer))
                 (when (buffer-live-p buf) (kill-buffer buf))
                 (when (file-exists-p patch-file) (delete-file patch-file))
                 (funcall cb "ApplyPatch aborted by user."))
               ;; header
               "  Apply patch? — n apply    q abort")
            ;; Headless path: apply immediately, no preview gate.
            (my/gptel--preview-patch-core patch nil)
            (do-apply))))
    (error (funcall callback (format "Error initiating patch application: %s" (error-message-string err))))))

(cl-defun my/gptel--run-agent-tool (callback agent-name description prompt)
  "Run a gptel-agent agent by name.

This bypasses the built-in gptel-agent Agent tool enum so you can run
agents like explorer.

AGENT-NAME must exist in `gptel-agent--agents`.  DESCRIPTION is a short
 label; PROMPT is the full task prompt.  CALLBACK is called exactly once
 with the final agent output."
  (unless (require 'gptel-agent nil t)
    (funcall callback "Error: gptel-agent is not available")
    (cl-return-from my/gptel--run-agent-tool))
  (unless (and (boundp 'gptel-agent--agents) gptel-agent--agents)
    (ignore-errors (gptel-agent-update)))
  (unless (and (stringp agent-name) (not (string-empty-p (string-trim agent-name))))
    (funcall callback "Error: agent-name is empty")
    (cl-return-from my/gptel--run-agent-tool))
  (unless (assoc agent-name gptel-agent--agents)
    (funcall callback
             (format "Error: unknown agent %S. Known agents: %s"
                     agent-name
                     (string-join (sort (mapcar #'car gptel-agent--agents) #'string<) ", ")))
    (cl-return-from my/gptel--run-agent-tool))
  (unless (fboundp 'gptel-agent--task)
    (funcall callback "Error: gptel-agent task runner not available (gptel-agent--task)")
    (cl-return-from my/gptel--run-agent-tool))
  ;; Reuse the same timeout + model wrapper as the Agent tool.
  (my/gptel--agent-task-with-timeout callback agent-name description prompt))

;; Define custom RunAgent tool early so it's available for both readonly and action profiles
(defvar my/gptel--runagent-tool
  (gptel-make-tool
   :name "RunAgent"
   :category "gptel-agent"
   :async t
   :function #'my/gptel--run-agent-tool
   :description "Run a gptel-agent agent by name (e.g. explorer)"
   :args (list '(:name "agent-name" :type string :description "Agent name (from gptel-agent--agents)")
               '(:name "description" :type string :description "Short task label")
               '(:name "prompt" :type string :description "Full task prompt"))
   :confirm t)
  "Custom RunAgent tool for delegation.")

;; --- Tool Definitions (Read-Only) ---
;; NOTE: use `setq` so re-evaluating this buffer actually refreshes the tool list.

;; Tool lists are canonical in nucleus-config.el



(defun my/gptel--normalize-skill-id (s)
  "Normalize a skill id string S.

This makes skill lookup resilient to smart quotes, surrounding quotes,
and whitespace.  Returns a (possibly empty) string." 
  (let* ((s (format "%s" (or s "")))
         (s (string-trim s))
         ;; Replace curly quotes with ASCII equivalents.
         (s (replace-regexp-in-string "[“”]" "\"" s t t))
         (s (replace-regexp-in-string "[‘’]" "'" s t t))
         (s (string-trim s)))
    ;; Strip surrounding single or double quotes.
    (when (>= (length s) 2)
      (let ((a (aref s 0))
            (b (aref s (1- (length s)))))
        (when (or (and (eq a ?\") (eq b ?\"))
                  (and (eq a ?') (eq b ?')))
          (setq s (substring s 1 (1- (length s))))
          (setq s (string-trim s)))))
    s))

(defun my/gptel--skill-tool (skill &optional args)
  "Wrapper for gptel-agent Skill tool.

Normalizes SKILL and refreshes skills once on miss." 
  (let* ((skill (my/gptel--normalize-skill-id skill))
         (skill-lc (downcase skill))
         (try (lambda (k)
                (car-safe (alist-get k gptel-agent--skills nil nil #'string-equal))))
         (hit (or (funcall try skill) (funcall try skill-lc))))
    (when (and (not hit) (fboundp 'gptel-agent-update))
      (ignore-errors (gptel-agent-update))
      (setq hit (or (funcall try skill) (funcall try skill-lc))))
    (if (not hit)
        (format "Error: skill %s not found." (if (string-empty-p skill) "<empty>" skill))
      ;; Delegate to upstream loader for body/path rewriting.
      (gptel-agent--get-skill (if (funcall try skill) skill skill-lc) args))))





;; --- Tool Definitions (Action) ---
;; --- Step-through preview infrastructure ---
;; preview_file_change is async: each call enqueues a (path orig new
;; callback) entry on the gptel buffer.  A 0.15 s idle timer lets
;; parallel tool calls batch up before the first step fires.  The user
;; steps through with n / q in a transient minor mode installed on the
;; diff buffer; each n fires that entry's callback so the FSM advances.

;; Buffer-local vars live on the gptel agent buffer.
(defvar-local my/gptel--preview-queue nil
  "Pending preview steps (newest first).
Each entry: (path orig new callback).")

(defvar-local my/gptel--preview-active nil
  "Non-nil while step-through preview is running.")

(defvar-local my/gptel--preview-step-count 0
  "Number of steps shown in the current preview batch.")

(defvar-local my/gptel--preview-temp-files nil
  "Temp files for the current preview step; cleaned up on advance.")

;; State plist stored buffer-locally on the diff buffer.
(defvar-local my/gptel--preview-stepper-state nil
  "Plist: :gptel-buf :path :callback for the current diff buffer step.")

(defun my/gptel--preview-update-header (step total path)
  "Set header-line in current buffer to show step progress."
  (setq header-line-format
        (format "  Preview [%d/%d]: %s    n next    q abort all"
                step total (file-name-nondirectory path))))

(defun my/gptel--preview-cleanup-temp-files (gptel-buf)
  "Delete temp files recorded on GPTEL-BUF."
  (when (buffer-live-p gptel-buf)
    (with-current-buffer gptel-buf
      (dolist (f my/gptel--preview-temp-files)
        (ignore-errors (delete-file f)))
      (setq my/gptel--preview-temp-files nil))))

(defun my/gptel--preview-next ()
  "Advance to the next preview step (bound to n in diff buffer).

If the stepper state has an :on-confirm thunk, calls it with the callback
\(patch tools use this to run git apply on confirm).  Otherwise fires the
default file-change result message."
  (interactive)
  (when-let* ((state my/gptel--preview-stepper-state)
              (gptel-buf (plist-get state :gptel-buf))
              (callback  (plist-get state :callback))
              (path      (plist-get state :path)))
    (my/gptel--preview-stepper-mode -1)
    (if-let ((on-confirm (plist-get state :on-confirm)))
        ;; Patch tool path: on-confirm is responsible for calling callback.
        (funcall on-confirm callback)
      ;; File-change path: fire default result and advance queue.
      (funcall callback (format "Preview shown for %s" path))
      (my/gptel--preview-step gptel-buf))))

(defun my/gptel--preview-quit ()
  "Abort the current preview step and all queued ones (bound to q).

If the stepper state has an :on-abort thunk, calls it with the callback.
Otherwise fires the default abort messages for file-change tools."
  (interactive)
  (when-let* ((state my/gptel--preview-stepper-state)
              (gptel-buf (plist-get state :gptel-buf))
              (callback  (plist-get state :callback))
              (path      (plist-get state :path)))
    (my/gptel--preview-stepper-mode -1)
    (if-let ((on-abort (plist-get state :on-abort)))
        ;; Patch tool path: on-abort is responsible for calling callback.
        (funcall on-abort callback)
      ;; File-change path: drain queue and fire default abort messages.
      (when (buffer-live-p gptel-buf)
        (with-current-buffer gptel-buf
          (dolist (entry my/gptel--preview-queue)
            (ignore-errors (funcall (nth 3 entry) "Preview aborted by user")))
          (setq my/gptel--preview-queue   nil
                my/gptel--preview-active  nil
                my/gptel--preview-step-count 0)
          (my/gptel--preview-cleanup-temp-files gptel-buf)))
      (funcall callback
               (format "Preview shown for %s (remaining previews aborted)" path)))))

(define-minor-mode my/gptel--preview-stepper-mode
  "Transient minor mode for gptel step-through file preview.
Press n to advance to the next file, q to abort all remaining previews."
  :lighter " Preview"
  :keymap (let ((m (make-sparse-keymap)))
            (define-key m (kbd "n") #'my/gptel--preview-next)
            (define-key m (kbd "q") #'my/gptel--preview-quit)
            m))

(defun my/gptel--preview-install-stepper (diff-buf gptel-buf path callback step total)
  "Install stepper mode and kill-guard on DIFF-BUF for one preview step."
  (with-current-buffer diff-buf
    (setq-local my/gptel--preview-stepper-state
                (list :gptel-buf gptel-buf
                      :path      path
                      :callback  callback))
    (my/gptel--preview-update-header step total path)
    (my/gptel--preview-stepper-mode 1)
    ;; Guard: if the diff buffer is killed without n/q, treat as quit.
    (add-hook 'kill-buffer-hook
              (lambda ()
                (when my/gptel--preview-stepper-mode
                  (my/gptel--preview-quit)))
              nil t)))

(defun my/gptel--preview-show-step (gptel-buf path orig new callback step total)
  "Display one preview step, install stepper, then wait for user."
  ;; Clean up previous step's temp files.
  (my/gptel--preview-cleanup-temp-files gptel-buf)
  (if (and (featurep 'magit) (fboundp 'magit-diff-paths))
      ;; Magit path: named temp files so the header shows BASE.EXT.
      (let* ((base      (file-name-base path))
             (ext       (file-name-extension path t)) ; includes "."
             (orig-file (make-temp-file
                         (format "gptel-orig-%s" base) nil ext))
             (new-file  (make-temp-file
                         (format "gptel-new-%s"  base) nil ext)))
        (with-temp-file orig-file (insert (or orig "")))
        (with-temp-file new-file  (insert (or new  "")))
        (with-current-buffer gptel-buf
          (setq my/gptel--preview-temp-files
                (list orig-file new-file)))
        ;; Show magit diff without stealing focus.
        (let ((magit-display-buffer-noselect t))
          (magit-diff-paths orig-file new-file))
        (when-let ((diff-buf (magit-get-mode-buffer 'magit-diff-mode)))
          (my/gptel--preview-install-stepper
           diff-buf gptel-buf path callback step total)))
    ;; Fallback: Emacs built-in diff-mode.
    (let* ((orig-file (make-temp-file "gptel-orig-"))
           (new-file  (make-temp-file "gptel-new-")))
      (with-temp-file orig-file (insert (or orig "")))
      (with-temp-file new-file  (insert (or new  "")))
      (with-current-buffer gptel-buf
        (setq my/gptel--preview-temp-files
              (list orig-file new-file)))
      (let ((diff-buf (diff-no-select orig-file new-file "-u" 'no-async)))
        (my/gptel--preview-install-stepper
         diff-buf gptel-buf path callback step total)
        (display-buffer diff-buf)))))

(defun my/gptel--preview-step (gptel-buf)
  "Show the next queued preview step, or finish if queue is empty."
  (when (buffer-live-p gptel-buf)
    (with-current-buffer gptel-buf
      (if (null my/gptel--preview-queue)
          ;; Batch complete — reset state.
          (setq my/gptel--preview-active     nil
                my/gptel--preview-step-count 0)
        (setq my/gptel--preview-active t)
        ;; Queue is newest-first (push order); oldest = last element.
        (let* ((entry    (car (last my/gptel--preview-queue)))
               (rest     (butlast my/gptel--preview-queue))
               (path     (nth 0 entry))
               (orig     (nth 1 entry))
               (new      (nth 2 entry))
               (callback (nth 3 entry))
               (step     (cl-incf my/gptel--preview-step-count))
               ;; total = steps already shown + remaining (incl. this)
               (total    (+ my/gptel--preview-step-count
                            (length rest))))
          (setq my/gptel--preview-queue rest)
          (my/gptel--preview-show-step
           gptel-buf path orig new callback step total))))))

(defun my/gptel--preview-enqueue (gptel-buf path orig new callback)
  "Add a preview step to GPTEL-BUF's queue and start if idle."
  (when (buffer-live-p gptel-buf)
    (with-current-buffer gptel-buf
      (push (list path orig new callback) my/gptel--preview-queue))
    (unless (buffer-local-value 'my/gptel--preview-active gptel-buf)
      ;; 0.15 s delay lets parallel tool calls batch before first step.
      (run-with-idle-timer 0.15 nil #'my/gptel--preview-step gptel-buf))))



;; Build tool lists after gptel-agent-tools has registered all upstream tools.
;; Running these setq forms at top-level on a cold start causes every
;; my/gptel--safe-get-tool call to return nil (tools not yet registered),
;; producing incomplete lists.  Deferring to with-eval-after-load guarantees
;; the upstream registry is populated before we snapshot it.


;; --- Tool Profile Management ---
(defun gptel-set-tool-profile (profile)
  "Set active gptel tools."
  (interactive (list (intern (completing-read "Profile: " '(readonly action)))))
  (setq-local gptel-tools (if (eq profile 'action) nucleus-tools-action nucleus-tools-readonly))
  (message "gptel tools set to: %s" profile))

(defun gptel-toggle-tool-profile ()
  "Toggle between readonly and action profiles."
  (interactive)
  (if (eq gptel-tools nucleus-tools-action)
      (gptel-set-tool-profile 'readonly)
    (gptel-set-tool-profile 'action)))

(defun my/gptel-apply-preset-here (preset)
  "Apply gptel PRESET in the current buffer.

This is a convenience wrapper around `gptel--apply-preset' that uses
buffer-local variables."
  (interactive
   (list
    (intern
     (completing-read "gptel preset: "
                      '(gptel-plan gptel-agent)
                      nil t))))
  (unless (fboundp 'gptel--apply-preset)
    (user-error "gptel preset application not available (gptel--apply-preset)"))
  (gptel--apply-preset
   preset
   (lambda (sym val)
     (set (make-local-variable sym) val)))
  (force-mode-line-update t))

;; --- Configuration Defaults ---
;; gptel-agent buffers use Gemini + gemini-3.1-pro-preview (set via preset).
;; Plain gptel buffers use Moonshot + kimi-k2.5 (set via mode hook).
;; The global default drives both the gptel-agent preset resolution and
;; the buffer-name prompt in M-x gptel.  Set it to Moonshot so the prompt
;; shows *Moonshot* instead of *OpenRouter*.
(setq gptel-backend gptel--moonshot
      gptel-model 'kimi-k2.5)

;; Control tool confirmation:
;; 'auto -> respect the `:confirm t` flag on individual tools
;; nil   -> auto-execute ALL tools without prompting
;; t     -> always prompt for ALL tools
;;
;; Default: never ask (matches `C-c C-a` "never ask again").
(setq gptel-confirm-tool-calls 'auto)
(setq-default gptel-confirm-tool-calls 'auto)



;; --- Keybindings & UI Helpers ---
(defun my/gptel-add-project-files ()
  "Select and add project files to gptel context."
  (interactive)
  (if-let* ((proj (project-current))
            (files (project-files proj))
            (selected (completing-read-multiple "Add context files: " files)))
      (progn
        (dolist (f selected)
          (gptel-add-file f))
        (message "Added %d files to gptel context." (length selected)))
    (user-error "Not in a project or no files selected")))

(defun my/gptel-tool-confirmation-never ()
  "Disable tool call confirmation everywhere.

Sets `gptel-confirm-tool-calls' to nil globally (and for existing gptel
buffers) so tool calls never pause for confirmation." 
  (interactive)
  (setq gptel-confirm-tool-calls nil)
  (setq-default gptel-confirm-tool-calls nil)
  (dolist (b (buffer-list))
    (with-current-buffer b
      (when (derived-mode-p 'gptel-mode)
        (setq-local gptel-confirm-tool-calls nil))))
  (message "gptel Tool Confirmation: OFF (Auto-executes everything)"))

(defun my/gptel-tool-confirmation-auto ()
  "Restore default tool call confirmation behavior.

Sets `gptel-confirm-tool-calls' to 'auto globally (and for existing gptel
buffers) so each tool's :confirm flag decides." 
  (interactive)
  (setq gptel-confirm-tool-calls 'auto)
  (setq-default gptel-confirm-tool-calls 'auto)
  (dolist (b (buffer-list))
    (with-current-buffer b
      (when (derived-mode-p 'gptel-mode)
        (setq-local gptel-confirm-tool-calls 'auto))))
  (message "gptel Tool Confirmation: AUTO (Respects tool flags)"))


(provide 'gptel-config)
;;; gptel-config.el ends here

;; ==============================================================================
;; TOOL SECURITY & ROUTING (NUCLEUS HYBRID SANDBOX)
;; ==============================================================================

(defun my/is-inside-workspace (path)
  "Check if PATH is strictly inside the current project root."
  (let* ((workspace (file-name-as-directory (file-truename (if (fboundp 'nucleus--project-root) (nucleus--project-root) default-directory))))
         (target (file-truename (expand-file-name (substitute-in-file-name path)))))
    (string-prefix-p workspace target)))

(defun my/gptel-tool-get-target-path (tool-name args)
  "Extract the target file path from a tool call's ARGS based on TOOL-NAME."
  (pcase tool-name
    ("Read" (nth 0 args))
    ("Edit" (nth 0 args))
    ("Insert" (nth 0 args))
    ("Write" (expand-file-name (nth 1 args) (nth 0 args)))
    ("Mkdir" (expand-file-name (nth 1 args) (nth 0 args)))
    ("Grep" (nth 1 args))
    ("Glob" (if (> (length args) 1) (nth 1 args) default-directory))
    ("preview_file_change" (nth 0 args))
    (_ nil)))

(defun my/gptel-tool-acl-check (tool-name args)
  "Return an error string if the tool call violates ACL rules, else nil."
  (let* ((preset (and (fboundp 'nucleus--effective-preset) (nucleus--effective-preset)))
         (is-plan (eq preset 'gptel-plan)))
    (cond
     ;; RULE 1: The Plan Mode Bash Whitelist
     ((and is-plan (equal tool-name "Bash"))
      (let ((command (car args)))
        (if (or (string-match-p "[;|&><]" command)
                (not (string-match-p "\\`[ \t]*\\(ls\\|pwd\\|tree\\|file\\|git status\\|git diff\\|git log\\|git show\\|git branch\\|pytest\\|npm test\\|npm run test\\|cargo test\\|go test\\|make test\\)\\b" command)))
            "Error: Command rejected by Emacs Whitelist Sandbox. In Plan mode, you may only use simple read-only commands (ls, git status, tree, etc.). Shell chaining (; | &) and output redirection (> <) are strictly forbidden. \n\nIMPORTANT: Do not use Bash to read or search files (no cat/grep/find); use the native `Read`, `Grep`, and `Glob` tools instead. If you truly must run a build or script, ask the user to say \"go\" to switch to Execution mode."
          nil)))

     ;; RULE 2: The Plan Mode Eval Sandbox
     ((and is-plan (equal tool-name "Eval"))
      (let ((expression (car args)))
        (if (string-match-p "\\(shell-command\\|call-process\\|delete-file\\|delete-directory\\|write-region\\|kill-emacs\\|make-network-process\\|open-network-stream\\|f-write\\|f-delete\\|f-touch\\)" expression)
            "Error: Command rejected by Emacs Eval Sandbox. Destructive Lisp functions are forbidden in Plan mode."
          nil)))

     ;; Default Allow
     (t nil))))

(defun my/gptel-tool-acl-needs-confirm (tool-name args)
  "Return t if the tool call should force a user confirmation."
  (let ((target-path (my/gptel-tool-get-target-path tool-name args)))
    (if (and target-path (not (my/is-inside-workspace target-path)))
        t ;; Force confirmation for out-of-workspace changes
      nil)))

(defun my/gptel-tool-router-advice (orig-fn &rest slots)
  "Intercept `gptel-make-tool' to wrap functions with a global ACL router."
  (let* ((name (plist-get slots :name))
         (orig-func (plist-get slots :function))
         (async (plist-get slots :async))
         (orig-confirm (plist-get slots :confirm)))
    
    ;; Wrap the execution function to check the blacklist first
    (setq slots
          (plist-put slots :function
                     (if async
                         (lambda (callback &rest args)
                           (if-let ((err (my/gptel-tool-acl-check name args)))
                               (funcall callback err)
                             (apply orig-func callback args)))
                       (lambda (&rest args)
                         (if-let ((err (my/gptel-tool-acl-check name args)))
                             (error "%s" err) ;; gptel catches `error` and sends string to LLM
                           (apply orig-func args))))))
    
    ;; Wrap the confirmation flag to enforce workspace boundaries
    (setq slots
          (plist-put slots :confirm
                     (lambda (&rest args)
                       (or (my/gptel-tool-acl-needs-confirm name args)
                           (and (functionp orig-confirm) (apply orig-confirm args))
                           (and (not (functionp orig-confirm)) orig-confirm)))))
    
    (apply orig-fn slots)))

(advice-add 'gptel-make-tool :around #'my/gptel-tool-router-advice)
