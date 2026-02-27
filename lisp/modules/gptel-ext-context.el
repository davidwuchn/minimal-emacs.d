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

(provide 'gptel-ext-context)
;;; gptel-ext-context.el ends here
