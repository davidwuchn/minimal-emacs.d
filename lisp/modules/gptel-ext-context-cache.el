;;; gptel-ext-context-cache.el --- Context-window caching for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Caches model context-window sizes from gptel model tables and OpenRouter.
;; Provides `my/gptel--context-window' for other modules to query the current
;; model's context window in tokens.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)
(require 'gptel)

;;; Customization

(defgroup my/gptel-context-cache nil
  "Context-window caching for gptel models."
  :group 'gptel)

(defcustom my/gptel-default-context-window 128000
  "Fallback context window (tokens) when model metadata is unavailable.

gptel does not always know the model's true context window (especially via
OpenRouter). Auto-compaction uses this value to estimate when to compact.

Default is 128k tokens, which is common for modern models (GPT-4, Claude 3, etc).
Set lower if you use models with smaller context windows."
  :type 'integer
  :group 'my/gptel-context-cache)

(defcustom my/gptel-context-window-cache-file
  (expand-file-name "savefile/gptel-context-window-cache.el" user-emacs-directory)
  "Path to a cache file storing detected model context windows.

The cache is used when `gptel' does not provide model metadata (common with
OpenRouter-hosted model ids)."
  :type 'file
  :group 'my/gptel-context-cache)

(defcustom my/gptel-context-window-auto-refresh-enabled t
  "When non-nil, refresh context-window metadata in the background."
  :type 'boolean
  :group 'my/gptel-context-cache)

(defcustom my/gptel-context-window-auto-refresh-interval-days 7
  "Minimum number of days between background refreshes."
  :type 'integer
  :group 'my/gptel-context-cache)

(defcustom my/gptel-context-window-auto-refresh-idle-seconds 20
  "Seconds of idle time before attempting a background refresh."
  :type 'integer
  :group 'my/gptel-context-cache)

(defcustom my/gptel-openrouter-models-connect-timeout 10
  "Seconds to wait for OpenRouter model-metadata connection."
  :type 'integer
  :group 'my/gptel-context-cache)

(defcustom my/gptel-openrouter-models-max-time 60
  "Maximum seconds for the OpenRouter model-metadata request."
  :type 'integer
  :group 'my/gptel-context-cache)

;;; Internal Variables

(defvar my/gptel--context-window-cache (make-hash-table :test 'equal)
  "Hash table mapping model id string to context window tokens.")

(defvar my/gptel--context-window-cache-last-refresh nil
  "Time (as a float) when the cache was last refreshed.")

(defvar my/gptel--openrouter-context-window-fetch-inflight nil)

(defvar my/gptel--context-window-cache-data nil
  "Temporary holder for data loaded from the context-window cache file.
Must be `defvar' (not `let') so the `setq' in the cache file reaches it
under `lexical-binding: t'.")

;;; Helpers

(defun my/gptel--model-id-string (&optional model)
  "Return MODEL as a stable string id."
  (let ((m (or model gptel-model)))
    (cond
     ((stringp m) m)
     ((symbolp m) (symbol-name m))
     (t (format "%S" m)))))

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

(defun my/gptel--estimate-tokens (chars)
  "Estimate token count from CHARS. Rough heuristic: 4 chars/token."
  (/ (float chars) 4.0))

;;; Cache Persistence

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

;; Load cache at require time
(my/gptel--cache-load-context-windows)

;;; Seeding and Refresh

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

(defun my/gptel-refresh-context-window-cache ()
  "Refresh (fetch) the current model's context window into the cache."
  (interactive)
  (my/gptel--openrouter-fetch-context-window gptel-model))

;;; Public Query API

(defun my/gptel--context-window ()
  "Return model context window if available, else fall back to gptel-max-tokens.

Fallback is approximate and may be smaller than actual context."
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

;;; Auto-refresh Timer

;; Schedule the background context-window cache refresh after gptel loads.
(with-eval-after-load 'gptel
  (run-with-idle-timer my/gptel-context-window-auto-refresh-idle-seconds nil
                       #'my/gptel--auto-refresh-context-window-cache-maybe))

;;; Footer

(provide 'gptel-ext-context-cache)
;;; gptel-ext-context-cache.el ends here
