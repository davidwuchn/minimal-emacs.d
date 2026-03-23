;;; gptel-tools-agent.el --- Subagent delegation for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Subagent delegation with timeout and model override.

(require 'cl-lib)
(require 'subr-x)

;;; Customization

(defgroup gptel-tools-agent nil
  "Subagent delegation for gptel-agent."
  :group 'gptel)

(defcustom my/gptel-agent-task-timeout nil
  "Seconds before a delegated Agent/RunAgent task is force-stopped.
Set to nil for no timeout (default)."
  :type '(choice (const :tag "No timeout" nil) integer)
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-result-limit 4000
  "Max characters to return inline from a subagent result.
Results longer than this are truncated and the full text is saved
to a temp file."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-progress-interval 10
  "Seconds between progress messages while a subagent is running."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-stream nil
  "Whether to use streaming mode for subagent requests.
When nil (default), subagents use non-streaming mode which is more reliable
on backends with streaming issues (e.g., DashScope HTTP parse errors).
When t, subagents use streaming mode for incremental display."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-temp-file-ttl 300
  "Seconds before subagent temp files are auto-deleted.
Set to 0 to disable auto-cleanup."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-cache-ttl 300
  "Time-to-live in seconds for cached subagent results.
Set to 0 to disable caching."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-cache-max-size 100
  "Maximum number of entries in the subagent cache.
When exceeded, oldest entries are evicted. Set to 0 for unlimited."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-include-history-default t
  "Default value for include_history when LLM doesn't specify.
When t (default), subagents receive recent conversation history.
When nil, subagents start with clean context unless explicitly requested."
  :type 'boolean
  :group 'gptel-tools-agent)

(defvar-local my/gptel--subagent-temp-files nil
  "Buffer-local list of temp files created by subagent results.
Each buffer manages its own temp files to avoid race conditions.")

(defvar my/gptel--global-temp-files nil
  "Global fallback list for temp files (used when no buffer context).")

(defvar my/gptel--subagent-cache (make-hash-table :test 'equal)
  "Hash table for caching subagent results.
Keys are (agent-type prompt-hash), values are (timestamp . result).")

(eval-and-compile
  (require 'gptel nil t)
  (require 'gptel-agent nil t))

(require 'gptel-ext-fsm-utils)

;;; Subagent Result Cache

(defun my/gptel--subagent-cache-key (agent-type prompt &optional files include-history include-diff)
  "Generate cache key for (AGENT-TYPE, PROMPT, FILES, INCLUDE-HISTORY, INCLUDE-DIFF).
Context parameters are included to prevent stale cache hits when the same
prompt is used with different context (files, history, diff).
Always includes all params to distinguish nil from \"false\"."
  (list agent-type
        (md5 (concat prompt
                     (format "-files:%S" (when files (sort (append files nil) #'string<)))
                     (format "-hist:%s" (or include-history "nil"))
                     (format "-diff:%s" (or include-diff "nil"))))))

(defun my/gptel--subagent-cache-get (agent-type prompt &optional files include-history include-diff)
  "Get cached result for (AGENT-TYPE, PROMPT, ...) if still valid.
Returns nil if cache disabled, not found, or expired."
  (when (> my/gptel-subagent-cache-ttl 0)
    (let* ((key (my/gptel--subagent-cache-key agent-type prompt files include-history include-diff))
           (cached (gethash key my/gptel--subagent-cache)))
      (when cached
        (let ((timestamp (car cached))
              (result (cdr cached)))
          (if (> (- (float-time) timestamp) my/gptel-subagent-cache-ttl)
              (progn (remhash key my/gptel--subagent-cache) nil)
            result))))))

(defun my/gptel--subagent-cache-put (agent-type prompt result &optional files include-history include-diff)
  "Cache RESULT for (AGENT-TYPE, PROMPT, ...).
Evicts oldest entries if cache exceeds `my/gptel-subagent-cache-max-size'."
  (when (> my/gptel-subagent-cache-ttl 0)
    (let ((key (my/gptel--subagent-cache-key agent-type prompt files include-history include-diff)))
      (puthash key (cons (float-time) result) my/gptel--subagent-cache)
      ;; Evict oldest entries if over limit
      (when (and (> my/gptel-subagent-cache-max-size 0)
                 (> (hash-table-count my/gptel--subagent-cache)
                    my/gptel-subagent-cache-max-size))
        (let ((oldest-key nil)
              (oldest-time most-positive-fixnum))
          (maphash
           (lambda (k v)
             (when (< (car v) oldest-time)
               (setq oldest-time (car v)
                     oldest-key k)))
           my/gptel--subagent-cache)
          (when oldest-key
            (remhash oldest-key my/gptel--subagent-cache)))))))

(defun my/gptel--subagent-cache-clear ()
  "Clear all cached subagent results."
  (interactive)
  (clrhash my/gptel--subagent-cache)
  (message "Subagent cache cleared."))

(defun my/gptel--subagent-cache-cleanup ()
  "Remove expired entries from cache.
Call periodically to prevent memory growth from unaccessed entries."
  (interactive)
  (let ((count 0)
        (now (float-time)))
    (maphash
     (lambda (key value)
       (when (> (- now (car value)) my/gptel-subagent-cache-ttl)
         (remhash key my/gptel--subagent-cache)
         (cl-incf count)))
     my/gptel--subagent-cache)
    (when (> count 0)
      (message "[gptel] Cleaned %d expired cache entries" count))
    count))


;; PATCH: Override gptel-agent--task to add tracking-marker for parent buffer
;; position and large-result truncation.  Respects `my/gptel-subagent-stream'
;; (default nil = non-streaming for reliability with DashScope).

(defun my/gptel-agent--task-override (main-cb agent-type description prompt)
  "Call a gptel agent to do specific compound tasks.
Like upstream `gptel-agent--task' but adds parent-buffer tracking-marker,
large-result truncation, and result caching."
  ;; Check cache first
  (let ((cached (my/gptel--subagent-cache-get agent-type prompt)))
    (when cached
      (message "[nucleus] Subagent '%s' cache hit" agent-type)
      (funcall main-cb cached)
      (cl-return-from my/gptel-agent--task-override)))
  ;; Not cached, run the subagent
  (let* ((preset (nconc (list :include-reasoning nil
                              :use-tools t
                              :use-context nil
                              :stream my/gptel-subagent-stream)
                        (cdr (assoc agent-type gptel-agent--agents))))
         (syms (cons 'gptel--preset (gptel--preset-syms preset)))
         (vals (mapcar (lambda (sym) (if (boundp sym) (symbol-value sym) nil)) syms)))
    (cl-progv syms vals
      (gptel--apply-preset preset)
      (let* ((parent-fsm (my/gptel--coerce-fsm gptel--fsm-last))
             (info (and parent-fsm (gptel-fsm-info parent-fsm)))
             (parent-buf (or (when (buffer-live-p (plist-get info :buffer))
                               (plist-get info :buffer))
                             (current-buffer)))
             (where (or (let ((tm (plist-get info :tracking-marker)))
                          (and (markerp tm) (marker-position tm) tm))
                        (let ((pos (plist-get info :position)))
                          (and (markerp pos) (marker-position pos) pos))
                        (with-current-buffer parent-buf (point-marker))))
             (tracking-marker (let ((m (copy-marker where t)))
                                (set-marker m (marker-position where) parent-buf)
                                m))
             (partial (format "%s result for task: %s\n\n"
                              (capitalize agent-type) description)))
        (gptel--update-status " Calling Agent..." 'font-font-lock-escape-face)
        (gptel-request prompt
          :context (gptel-agent--task-overlay where agent-type description)
          :fsm (gptel-make-fsm :handlers gptel-agent-request--handlers)
          :position tracking-marker
          :buffer parent-buf
          :in-place t
          :callback
          (lambda (resp info)
            (let ((ov (plist-get info :context)))
              (pcase resp
                ('nil
                 (when (overlayp ov) (delete-overlay ov))
                 (funcall main-cb
                          (format "Error: Task %s could not finish task \"%s\". \n\nError details: %S"
                                  agent-type description (plist-get info :error))))
                (`(tool-call . ,calls)
                 (unless (plist-get info :tracking-marker)
                   (plist-put info :tracking-marker tracking-marker))
                 (gptel--display-tool-calls calls info))
                (`(tool-result . ,_results)) ;; FSM handles transition
                ((pred stringp)
                 (setq partial (concat partial resp))
                 (unless (plist-get info :tool-use)
                   (when (overlayp ov) (delete-overlay ov))
                   (when-let* ((transformer (plist-get info :transformer)))
                     (setq partial (funcall transformer partial)))
                   ;; Cache the result before delivering
                   (my/gptel--subagent-cache-put agent-type prompt partial)
                   (my/gptel--deliver-subagent-result main-cb partial)))
                ('abort
                 (when (overlayp ov) (delete-overlay ov))
                 (funcall main-cb
                          (format "Error: Task \"%s\" was aborted by the user. \n%s could not finish."
                                   description agent-type)))))))))))


(defun my/gptel--deliver-subagent-result (callback result)
  "Deliver RESULT to CALLBACK, truncating large results to a temp file."
  (if (> (length result) my/gptel-subagent-result-limit)
      (let* ((temp-file (my/gptel-make-temp-file "gptel-subagent-result-" nil ".txt"))
             (trunc-msg (format "%s\n...[Result too large, truncated. Full result saved to: %s. Use Read tool if you need more]..."
                                (substring result 0 my/gptel-subagent-result-limit)
                                temp-file)))
        (with-temp-file temp-file
          (insert result))
        ;; Always push to global list for reliable cleanup.
        ;; Also push to buffer-local if available (for session tracking).
        (push temp-file my/gptel--global-temp-files)
        (when (buffer-live-p (current-buffer))
          (push temp-file my/gptel--subagent-temp-files))
        (when (> my/gptel-subagent-temp-file-ttl 0)
          (run-at-time my/gptel-subagent-temp-file-ttl nil
                       (lambda (f)
                         (when (file-exists-p f)
                           (delete-file f))
                         ;; Only modify global list - buffer-local may be inaccessible.
                         (setq my/gptel--global-temp-files
                               (delete f my/gptel--global-temp-files)))
                       temp-file))
        (funcall callback trunc-msg))
    (funcall callback result)))

(with-eval-after-load 'gptel-agent-tools
  (advice-add 'gptel-agent--task :override #'my/gptel-agent--task-override)
  (advice-add 'gptel-agent--task-overlay :around #'my/gptel-agent--task-overlay-around))

(defun my/gptel-agent--task-overlay-around (orig where &optional agent-type description)
  "Advice to fix task overlay appearing in wrong buffer.
ORIG is the original `gptel-agent--task-overlay' function.
WHERE is the position (marker or integer) for the overlay.
AGENT-TYPE and DESCRIPTION are passed through.

The upstream function creates the overlay in the current buffer,
but WHERE may be a marker pointing to a different buffer, or an
integer position that should be in the parent chat buffer.
This wrapper ensures the overlay is created in the correct buffer."
  (let* ((target-buf (cond
                      ;; Marker case: use marker's buffer
                      ((markerp where) (marker-buffer where))
                      ;; Integer case: try to get parent buffer from FSM
                      ((integerp where)
                       (let* ((parent-fsm (my/gptel--coerce-fsm gptel--fsm-last))
                              (info (and parent-fsm (gptel-fsm-info parent-fsm))))
                         (when info (plist-get info :buffer))))
                      (t nil)))
         (result
          (if (and target-buf (buffer-live-p target-buf))
              (with-current-buffer target-buf
                (funcall orig where agent-type description))
            (funcall orig where agent-type description))))
    result))

(defun my/gptel--around-agent-update (orig &rest args)
  "Wrap `gptel-agent-update' to handle our deregistration of \"Agent\".
Upstream unconditionally updates the \"Agent\" tool's enum.  We
inject a throwaway stub so upstream completes without error, then
remove it."
  ;; Ensure a stub "Agent" tool exists so upstream's enum update succeeds
  (unless (ignore-errors (gptel-get-tool "Agent"))
    (gptel-make-tool
     :name "Agent" :category "gptel-agent"
     :function #'ignore :description "stub"
     :args '((:name "subagent_type" :type string :enum ["stub"]))))
  (apply orig args)
  ;; Remove the (now-updated) Agent tool
  (when-let* ((cat (assoc "gptel-agent" gptel--known-tools)))
    (setf (alist-get "Agent" (cdr cat) nil 'remove #'equal) nil)))

(with-eval-after-load 'gptel-agent
  (advice-add 'gptel-agent-update :around #'my/gptel--around-agent-update))





;;; Internal Variables

(defvar my/gptel--in-subagent-task nil
  "Non-nil while inside a `gptel-agent--task' call.")

;;; Context Builder

(defun my/gptel--xml-escape (text)
  "Escape XML special characters in TEXT.
Prevents XML injection when inserting file contents into context tags.
Escapes &, <, >, \", and ' per XML spec."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (while (search-forward "&" nil t)
      (replace-match "&amp;"))
    (goto-char (point-min))
    (while (search-forward "<" nil t)
      (replace-match "&lt;"))
    (goto-char (point-min))
    (while (search-forward ">" nil t)
      (replace-match "&gt;"))
    (goto-char (point-min))
    (while (search-forward "\"" nil t)
      (replace-match "&quot;"))
    (goto-char (point-min))
    (while (search-forward "'" nil t)
      (replace-match "&apos;"))
    (buffer-string)))

(defun my/gptel--safe-file-p (filepath)
  "Return non-nil if FILEPATH is safe to include in subagent context.
Rejects files outside project root, symlinks, and unreadable files."
  (when-let* ((expanded (expand-file-name filepath))
              (proj (project-current))
              (proj-root (expand-file-name (project-root proj))))
    (and (file-readable-p expanded)
         (not (file-symlink-p expanded))
         (string-prefix-p proj-root expanded))))

(defun my/gptel--build-subagent-context (prompt files include-history include-diff &optional origin-buf)
  "Package context for a subagent payload.
Appends contents of FILES, git diff if INCLUDE-DIFF, and recent buffer history
if INCLUDE-HISTORY to the base PROMPT.

ORIGIN-BUF is the parent chat buffer to read history from.  Defaults to
`current-buffer' if not provided, but callers should always pass it
explicitly to avoid capturing the wrong buffer.

FILES are validated against project root for security."
  (let ((context ""))
    (when (and files (sequencep files))
      (let ((file-context ""))
        (cl-loop for f in (append files nil) do
                 (let ((filepath (expand-file-name f)))
                   (cond
                    ;; Security check: file must be within project, not a symlink
                    ((not (my/gptel--safe-file-p filepath))
                     (setq file-context (concat file-context
                                                (format "<file path=\"%s\">\n[Error: File not in project or is a symlink]\n</file>\n"
                                                        (my/gptel--xml-escape f)))))
                    ((file-readable-p filepath)
                     (with-temp-buffer
                       (insert-file-contents filepath)
                       (setq file-context (concat file-context
                                                  (format "<file path=\"%s\">\n%s\n</file>\n"
                                                          (my/gptel--xml-escape f)
                                                          (my/gptel--xml-escape (buffer-string)))))))
                    (t
                     (setq file-context (concat file-context
                                                (format "<file path=\"%s\">\n[Error: File not found or not readable]\n</file>\n"
                                                        (my/gptel--xml-escape f))))))))
        (when (not (string-empty-p file-context))
          (setq context (concat context "<files>\n" file-context "</files>\n\n")))))

    (when include-diff
      (let* ((proj-root (and (fboundp 'project-current)
                             (project-current)
                             (project-root (project-current))))
             (default-directory
              (cond
               ((and proj-root (file-in-directory-p default-directory proj-root))
                proj-root)
               ((and proj-root (file-exists-p (expand-file-name ".git" proj-root)))
                proj-root)
               (t default-directory)))
             (diff-out (with-temp-buffer
                         (condition-case err
                             (let ((exit-code (call-process "git" nil '(t nil) nil "diff" "HEAD")))
                               (unless (eq exit-code 0)
                                 (message "[gptel] git diff exit code %s" exit-code))
                               (buffer-string))
                           (error
                            (message "[gptel] git diff error: %s" (error-message-string err))
                            "")))))
        (when (not (string-empty-p diff-out))
          (setq context (concat context "<git_diff>\n"
                                (my/gptel--xml-escape diff-out)
                                "\n</git_diff>\n\n")))))

    (when include-history
      (let* ((src-buf (or (and (buffer-live-p origin-buf) origin-buf)
                          (current-buffer)))
             (history-text (with-current-buffer src-buf
                             (buffer-substring-no-properties
                              (max (point-min) (- (point-max) 8000))
                              (point-max)))))
        (when (not (string-empty-p history-text))
          (setq context (concat context "<parent_conversation_history>\n"
                                (my/gptel--xml-escape history-text)
                                "\n</parent_conversation_history>\n\n")))))

    (if (string-empty-p context)
        prompt
      (concat context "Task:\n" prompt))))

;;; Subagent Functions

(defun my/gptel--agent-task-with-timeout (callback agent-type description prompt &optional files include-history include-diff)
  "Wrapper around `gptel-agent--task' that adds a timeout and progress messages.

CALLBACK is called with the result or a timeout error."
  (let* ((done nil)
         (timeout-timer nil)
         (progress-timer nil)
         (start-time (current-time))
         (parent-fsm (buffer-local-value 'gptel--fsm-last (current-buffer)))
         (origin-buf (current-buffer))
         (packaged-prompt (my/gptel--build-subagent-context prompt files include-history include-diff origin-buf))
         (wrapped-cb
          (lambda (result)
            (unless done
              (setq done t)
              (when (timerp timeout-timer) (cancel-timer timeout-timer))
              (when (timerp progress-timer) (cancel-timer progress-timer))
              (message "[nucleus] Subagent '%s' completed in %.1fs, result-len=%d"
                       agent-type (float-time (time-since start-time))
                       (if (stringp result) (length result) 0))
              ;; Restore FSM state in origin buffer only.
              (when (buffer-live-p origin-buf)
                (with-current-buffer origin-buf
                  (setq-local gptel--fsm-last parent-fsm)))
              (funcall callback result)))))

    (message "[nucleus] Delegating to subagent '%s'%s..."
             agent-type
             (if my/gptel-agent-task-timeout
                 (format " (timeout: %ds)" my/gptel-agent-task-timeout)
               ""))

    (setq progress-timer
          (run-at-time my/gptel-subagent-progress-interval
                       my/gptel-subagent-progress-interval
                       (lambda ()
                         (unless done
                           (message "[nucleus] Subagent '%s' still running... (%.1fs elapsed)"
                                    agent-type (float-time (time-since start-time)))))))

    (when my/gptel-agent-task-timeout
      (setq timeout-timer
            (run-at-time
             my/gptel-agent-task-timeout nil
             (lambda ()
               (unless done
                 (setq done t)
                 (when (timerp progress-timer) (cancel-timer progress-timer))
                 (message "[nucleus] Subagent '%s' timed out after %ds"
                          agent-type my/gptel-agent-task-timeout)
                 ;; Restore FSM state in origin buffer only.
                 (when (buffer-live-p origin-buf)
                   (with-current-buffer origin-buf
                     (setq-local gptel--fsm-last parent-fsm)))
                 (funcall callback
                          (format "Error: Task \"%s\" (%s) timed out after %ds."
                                  description agent-type my/gptel-agent-task-timeout)))))))

    ;; Use unwind-protect to guarantee FSM restoration on synchronous errors.
    ;; Async callbacks handle their own FSM restoration.
    (unwind-protect
        (gptel-agent--task wrapped-cb agent-type description packaged-prompt)
      ;; Cleanup on synchronous error (async errors handled in wrapped-cb)
      (when (and (not done) (buffer-live-p origin-buf))
        (with-current-buffer origin-buf
          (setq-local gptel--fsm-last parent-fsm))))))

(cl-defun my/gptel--run-agent-tool (callback agent-name description prompt &optional files include-history include-diff)
  "Run a gptel-agent agent by name.

AGENT-NAME must exist in `gptel-agent--agents`.

INCLUDE-HISTORY defaults to `my/gptel-subagent-include-history-default' when nil."
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
  ;; Hard gate: executor is forbidden in Plan mode (read-only preset).
  (when (and (equal agent-name "executor")
             (boundp 'gptel--preset)
             (eq gptel--preset 'gptel-plan))
    (funcall callback
             "Error: executor is not available in Plan mode. Switch to Agent mode first.")
    (cl-return-from my/gptel--run-agent-tool))
  (unless (fboundp 'gptel-agent--task)
    (funcall callback "Error: gptel-agent task runner not available")
    (cl-return-from my/gptel--run-agent-tool))
  ;; Apply default for include-history when not specified
  (let ((include-history (or include-history
                             (when my/gptel-subagent-include-history-default "true"))))
    (my/gptel--agent-task-with-timeout callback agent-name description prompt files include-history include-diff)))

;;; Tool Registration

(defun gptel-tools-agent-register ()
  "Register RunAgent tool with gptel."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "RunAgent"
     :description "Run a gptel-agent subagent by name (e.g. explorer, researcher, executor, reviewer)"
     :function #'my/gptel--run-agent-tool
     :args '((:name "agent_name"
               :type string
               :description "Agent name (e.g. 'researcher', 'introspector', 'executor', 'explorer', 'reviewer')"
               :enum ["explorer" "researcher" "introspector" "executor" "reviewer"])
             (:name "description"
              :type string
              :description "Short task label")
             (:name "prompt"
              :type string
              :description "Full task prompt")
             (:name "files"
              :type array
              :items (:type string)
              :optional t
              :description "Optional list of file paths to inject into the subagent context.")
             (:name "include_history"
              :type string
              :optional t
              :description "Set to \"false\" to exclude conversation history. Default: history IS included (see my/gptel-subagent-include-history-default).")
             (:name "include_diff"
              :type string
              :optional t
              :description "Set to \"true\" to inject git diff HEAD into subagent context."))
     :category "gptel-agent"
:async t
      :confirm t
      :include t)))

;;; TodoWrite Overlay Fix for Subagent Context

(defvar gptel-agent--hrule)  ; from gptel-agent-tools

(defvar-local my/gptel--todo-overlay nil
  "Buffer-local cache for TodoWrite overlay.
Avoids scanning entire buffer on each update.")

(defun my/gptel-agent--write-todo-around (orig todos)
  "Advice to fix TodoWrite overlay updates in subagent context.
Uses cached overlay reference for O(1) lookup instead of O(n) buffer scan."
  (setq gptel-agent--todos todos)
  (let* ((info (gptel-fsm-info gptel--fsm-last))
         (pos (or (plist-get info :tracking-marker)
                  (plist-get info :position)))
         (buf (plist-get info :buffer))
         (existing-ov (and buf
                           (buffer-live-p buf)
                           (with-current-buffer buf
                             (or my/gptel--todo-overlay
                                 (setq my/gptel--todo-overlay
                                       (cl-find-if
                                        (lambda (ov) (overlay-get ov 'gptel-agent--todos))
                                        (overlays-in (point-min) (point-max)))))))))
    (if existing-ov
        (let* ((formatted-todos
                (mapconcat
                 (lambda (todo)
                   (pcase (plist-get todo :status)
                     ("completed"
                      (concat "✓ " (propertize (plist-get todo :content)
                                               'face '(:inherit shadow :strike-through t))))
                     ("in_progress"
                      (concat "● " (propertize (plist-get todo :activeForm)
                                               'face '(:inherit (bold warning)))))
                     (_ (concat "○ " (plist-get todo :content)))))
                 todos "\n"))
               (todo-display
                (concat
                 (unless (= (char-before (overlay-end existing-ov)) 10) "\n")
                 gptel-agent--hrule
                 (propertize "Task list: [ "
                             'face '(:inherit (font-lock-comment-face bold)))
                 (propertize "TAB to toggle display ]\n" 'face 'font-lock-comment-face)
                 formatted-todos "\n"
                 gptel-agent--hrule)))
          (overlay-put existing-ov 'after-string todo-display)
          t)
      (funcall orig todos))))

(with-eval-after-load 'gptel-agent-tools
  (advice-add 'gptel-agent--write-todo :around #'my/gptel-agent--write-todo-around))

;;; Auto-Workflow (Semi-Autonomous Overnight Experiments)

(declare-function magit-worktree-branch "magit-worktree")
(declare-function magit-worktree-delete "magit-worktree")
(declare-function magit-git-success "magit-git")
(declare-function gptel-benchmark-analyze "gptel-benchmark-subagent")
(declare-function gptel-benchmark-grade "gptel-benchmark-subagent")
(declare-function gptel-benchmark-compare "gptel-benchmark-subagent")
(declare-function gptel-benchmark-eight-keys-score "gptel-benchmark-principles")

;;; Configuration

(defcustom gptel-auto-workflow-targets
  '("gptel-ext-retry.el" "gptel-ext-context.el" "gptel-tools-code.el")
  "Target files for scheduled auto-workflow runs."
  :type '(repeat string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-worktree-base "var/tmp/experiments"
  "Base directory for auto-workflow worktrees."
  :type 'directory
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-time-budget 900
  "Time budget per experiment in seconds (default: 15 min)."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-max-per-target 10
  "Maximum experiments per target."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-no-improvement-threshold 3
  "Stop after N consecutive no-improvements."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-use-subagents t
  "Use analyzer/grader/comparator subagents."
  :type 'boolean
  :group 'gptel-tools-agent)

;;; State

(defvar gptel-auto-workflow--worktree-dir nil)
(defvar gptel-auto-workflow--current-branch nil)
(defvar gptel-auto-experiment--results nil)
(defvar gptel-auto-experiment--best-score nil)
(defvar gptel-auto-experiment--no-improvement-count 0)

;;; Worktree Management

(defun gptel-auto-workflow--branch-name (target &optional experiment-id)
  "Generate branch name for TARGET. Optional EXPERIMENT-ID for experiments."
  (let* ((basename (file-name-sans-extension (file-name-nondirectory target)))
         (name (car (last (split-string basename "-")))))
    (if experiment-id
        (format "optimize/%s-exp%d" name experiment-id)
      (format "optimize/%s" name))))

(defun gptel-auto-workflow-create-worktree (target &optional experiment-id)
  "Create worktree for TARGET. EXPERIMENT-ID creates numbered branch."
  (let* ((branch (gptel-auto-workflow--branch-name target experiment-id))
         (worktree-dir (expand-file-name
                        (format "%s/%s" gptel-auto-workflow-worktree-base branch))))
    (condition-case err
        (progn
          (make-directory (file-name-directory worktree-dir) t)
          (magit-worktree-branch worktree-dir branch "main")
          (message "[auto-workflow] Created: %s" branch)
          (setq gptel-auto-workflow--worktree-dir worktree-dir
                gptel-auto-workflow--current-branch branch)
          worktree-dir)
      (error
       (message "[auto-workflow] Failed to create worktree: %s" err)
       nil))))

(defun gptel-auto-workflow-delete-worktree ()
  "Delete current worktree if exists."
  (when (and gptel-auto-workflow--worktree-dir
             (file-exists-p gptel-auto-workflow--worktree-dir))
    (condition-case err
        (magit-worktree-delete gptel-auto-workflow--worktree-dir)
      (error
       (message "[auto-workflow] Failed to delete worktree: %s" err)))
    (setq gptel-auto-workflow--worktree-dir nil
          gptel-auto-workflow--current-branch nil)))

;;; Benchmark & Evaluation

(defun gptel-auto-experiment-benchmark ()
  "Run nucleus verification + Eight Keys scoring."
  (let* ((start (float-time))
         (default-directory (or gptel-auto-workflow--worktree-dir
                                (expand-file-name user-emacs-directory)))
         (verify-result (call-process "bash" nil nil nil
                                      (expand-file-name "scripts/verify-nucleus.sh"
                                                        (expand-file-name user-emacs-directory)))))
    (list :passed (zerop verify-result)
          :time (- (float-time) start)
          :eight-keys (when (zerop verify-result)
                        (gptel-auto-experiment--eight-keys-score)))))

(defun gptel-auto-experiment--eight-keys-score ()
  "Get Eight Keys overall score from current codebase."
  (when (fboundp 'gptel-benchmark-eight-keys-score)
    (let* ((output (shell-command-to-string
                    (format "cd %s && git diff HEAD~1 --stat 2>/dev/null || echo 'no changes'"
                            (or gptel-auto-workflow--worktree-dir
                                (expand-file-name user-emacs-directory)))))
           (scores (gptel-benchmark-eight-keys-score output)))
      (alist-get 'overall scores))))

;;; Subagent Integrations

(defun gptel-auto-experiment-analyze (previous-results callback)
  "Analyze patterns from PREVIOUS-RESULTS. Call CALLBACK with analysis."
  (if (and gptel-auto-experiment-use-subagents
           (fboundp 'gptel-benchmark-analyze)
           previous-results)
      (gptel-benchmark-analyze
       previous-results
       "Experiment patterns"
       callback)
    (funcall callback nil)))

(defun gptel-auto-experiment-grade (output callback)
  "Grade experiment OUTPUT. LLM decides quality threshold."
  (if (and gptel-auto-experiment-use-subagents
           (fboundp 'gptel-benchmark-grade))
      (gptel-benchmark-grade
       output
       '("hypothesis clearly stated"
         "change is minimal"
         "tests mentioned")
       '("large refactor"
         "changed security files"
         "no hypothesis")
       callback)
    (funcall callback (list :score 100 :passed t))))

(defun gptel-auto-experiment-decide (before after callback)
  "Compare BEFORE vs AFTER. CALLBACK receives keep/discard decision with reasoning."
  (if (and gptel-auto-experiment-use-subagents
           (fboundp 'gptel-benchmark-compare))
      (gptel-benchmark-compare
       before after
       "Experiment comparison"
       (lambda (result)
         (let* ((winner (plist-get result :winner))
                (keep (string= winner "B"))
                (analysis (plist-get result :analysis))
                (rec (plist-get result :recommendation)))
           (funcall callback
                    (list :keep keep
                          :reasoning rec
                          :analysis analysis
                          :improvement (plist-get result :improvement))))))
    (let ((score-before (plist-get before :score))
          (score-after (plist-get after :score)))
      (funcall callback
               (list :keep (> score-after score-before)
                     :reasoning (format "Score: %.2f → %.2f" score-before score-after)
                     :improvement (list :score (- score-after score-before)))))))

;;; Prompt Building

(defun gptel-auto-experiment-build-prompt (target experiment-id max-experiments analysis baseline)
  "Build prompt for experiment EXPERIMENT-ID on TARGET."
  (let* ((git-history (shell-command-to-string
                       (format "cd %s && git log --oneline -20 2>/dev/null || echo 'no history'"
                               (or gptel-auto-workflow--worktree-dir
                                   (expand-file-name user-emacs-directory)))))
         (patterns (when analysis (plist-get analysis :patterns)))
         (suggestions (when analysis (plist-get analysis :recommendations))))
    (format "You are running experiment %d of %d to optimize %s.

## Previous Experiment Analysis
%s

## Suggestions
%s

## Git History (recent commits)
%s

## Current Baseline
Overall Eight Keys score: %.2f

## Objective
Improve the Eight Keys score for %s.
Focus on one improvement at a time.
Make minimal, targeted changes.

## Constraints
- Time budget: %d minutes
- Immutable files: early-init.el, pre-early-init.el, lisp/eca-security.el
- Must pass tests: ./scripts/verify-nucleus.sh

## Instructions
1. First, write your HYPOTHESIS: What change might improve the score? Why?
2. Implement the change minimally
3. Run tests to verify

Format your hypothesis at the start as:
HYPOTHESIS: [your hypothesis here]"
            experiment-id max-experiments target
            (or patterns "No previous experiments")
            (or suggestions "None")
            git-history
            (or baseline 0.5)
            target
            (/ gptel-auto-experiment-time-budget 60))))

;;; TSV Logging (Explainable)

(defun gptel-auto-experiment-log-tsv (run-id experiment)
  "Append EXPERIMENT to results.tsv for RUN-ID."
  (let* ((base-dir (expand-file-name user-emacs-directory))
         (file (expand-file-name
                (format "%s/%s/results.tsv" gptel-auto-workflow-worktree-base run-id)
                base-dir)))
    (make-directory (file-name-directory file) t)
    (unless (file-exists-p file)
      (with-temp-file file
        (insert "experiment_id\ttarget\thypothesis\tscore_before\tscore_after\tdelta\tdecision\tduration\tgrader_quality\tgrader_reason\tcomparator_reason\tanalyzer_patterns\n")))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-max))
      (insert (format "%s\t%s\t%s\t%.2f\t%.2f\t%+.2f\t%s\t%d\t%s\t%s\t%s\t%s\n"
                      (or (plist-get experiment :id) "?")
                      (or (plist-get experiment :target) "?")
                      (or (plist-get experiment :hypothesis) "unknown")
                      (or (plist-get experiment :score-before) 0)
                      (or (plist-get experiment :score-after) 0)
                      (- (or (plist-get experiment :score-after) 0)
                         (or (plist-get experiment :score-before) 0))
                      (if (plist-get experiment :kept) "kept" "discarded")
                      (or (plist-get experiment :duration) 0)
                      (or (plist-get experiment :grader-quality) "?")
                      (or (plist-get experiment :grader-reason) "N/A")
                      (or (plist-get experiment :comparator-reason) "N/A")
                      (or (plist-get experiment :analyzer-patterns) "N/A")))
      (write-region (point-min) (point-max) file))))

;;; Dynamic Stop

(defun gptel-auto-experiment-should-stop-p (threshold)
  "Check if should stop based on no-improvement count >= THRESHOLD."
  (>= gptel-auto-experiment--no-improvement-count threshold))

;;; Single Experiment

(defun gptel-auto-experiment-run (target experiment-id max-experiments baseline previous-results callback)
  "Run single experiment. Call CALLBACK with result plist."
  (message "[auto-experiment] Starting %d/%d for %s" experiment-id max-experiments target)
  (let* ((worktree (gptel-auto-workflow-create-worktree target experiment-id))
         (start-time (float-time))
         (timeout-timer nil)
         (finished nil)
         (result nil))
    (if (not worktree)
        (funcall callback (list :target target :error "Failed to create worktree"))
      ;; Step 1: Analyze previous results
      (gptel-auto-experiment-analyze
       previous-results
       (lambda (analysis)
         (let* ((patterns (when analysis (plist-get analysis :patterns)))
                (prompt (gptel-auto-experiment-build-prompt
                         target experiment-id max-experiments analysis baseline)))
           ;; Step 2: Run code agent with timeout
           (setq timeout-timer
                 (run-with-timer gptel-auto-experiment-time-budget nil
                                 (lambda ()
                                   (unless finished
                                     (setq finished t)
                                     (gptel-auto-workflow-delete-worktree)
                                     (funcall callback
                                              (list :target target
                                                    :id experiment-id
                                                    :error "timeout"))))))
           (my/gptel--run-agent-tool
            (lambda (agent-output)
              (when timeout-timer (cancel-timer timeout-timer))
              (unless finished
                ;; Step 3: Grade output (LLM decides threshold)
                (gptel-auto-experiment-grade
                 agent-output
                 (lambda (grade)
                   (let* ((grade-score (plist-get grade :score))
                          (grade-passed (plist-get grade :passed))
                          (hypothesis (gptel-auto-experiment--extract-hypothesis agent-output)))
                     (if (not grade-passed)
                         ;; Early discard
                         (progn
                           (setq finished t)
                           (gptel-auto-workflow-delete-worktree)
                           (let ((exp-result (list :target target
                                                   :id experiment-id
                                                   :hypothesis hypothesis
                                                   :score-before baseline
                                                   :score-after 0
                                                   :kept nil
                                                   :duration (- (float-time) start-time)
                                                   :grader-quality grade-score
                                                   :grader-reason (plist-get grade :details)
                                                   :comparator-reason "early-discard"
                                                   :analyzer-patterns (format "%s" patterns))))
                             (gptel-auto-experiment-log-tsv
                              (format-time-string "%Y-%m-%d") exp-result)
                             (funcall callback exp-result)))
                       ;; Step 4: Run benchmark
                       (let* ((bench (gptel-auto-experiment-benchmark))
                              (passed (plist-get bench :passed))
                              (score-after (plist-get bench :eight-keys)))
                         (if (not passed)
                             ;; Tests failed
                             (progn
                               (setq finished t)
                               (magit-git-success "checkout" "--" ".")
                               (gptel-auto-workflow-delete-worktree)
                               (let ((exp-result (list :target target
                                                       :id experiment-id
                                                       :hypothesis hypothesis
                                                       :score-before baseline
                                                       :score-after 0
                                                       :kept nil
                                                       :duration (- (float-time) start-time)
                                                       :grader-quality grade-score
                                                       :grader-reason (plist-get grade :details)
                                                       :comparator-reason "tests-failed"
                                                       :analyzer-patterns (format "%s" patterns))))
                                 (gptel-auto-experiment-log-tsv
                                  (format-time-string "%Y-%m-%d") exp-result)
                                 (funcall callback exp-result)))
                           ;; Step 5: Compare (decide keep/discard)
                           (gptel-auto-experiment-decide
                            (list :score baseline)
                            (list :score score-after :output agent-output)
                            (lambda (decision)
                              (setq finished t)
                              (let* ((keep (plist-get decision :keep))
                                     (reasoning (plist-get decision :reasoning))
                                     (exp-result (list :target target
                                                       :id experiment-id
                                                       :hypothesis hypothesis
                                                       :score-before baseline
                                                       :score-after score-after
                                                       :kept keep
                                                       :duration (- (float-time) start-time)
                                                       :grader-quality grade-score
                                                       :grader-reason (plist-get grade :details)
                                                       :comparator-reason reasoning
                                                       :analyzer-patterns (format "%s" patterns))))
                                (if keep
                                    ;; Commit
                                    (let ((msg (format "◈ Optimize %s: %s\n\nHYPOTHESIS: %s\nExperiment %d/%d. Score: %.2f → %.2f"
                                                       target
                                                       (gptel-auto-experiment--summarize hypothesis)
                                                       hypothesis
                                                       experiment-id max-experiments
                                                       baseline score-after)))
                                      (magit-git-success "add" "-A")
                                      (magit-git-success "commit" "-m" msg)
                                      (setq gptel-auto-experiment--best-score score-after
                                            gptel-auto-experiment--no-improvement-count 0))
                                  ;; Discard
                                  (progn
                                    (magit-git-success "checkout" "--" ".")
                                    (cl-incf gptel-auto-experiment--no-improvement-count)))
                                (gptel-auto-experiment-log-tsv
                                 (format-time-string "%Y-%m-%d") exp-result)
                                (gptel-auto-workflow-delete-worktree)
                                (funcall callback exp-result))))))))))))
            "code"
            (format "Experiment %d: optimize %s" experiment-id target)
            prompt
            nil "false" nil)))))))

(defun gptel-auto-experiment--extract-hypothesis (output)
  "Extract HYPOTHESIS from agent OUTPUT."
  (if (string-match "HYPOTHESIS:\\s-*\\([^\n]+\\)" output)
      (match-string 1 output)
    "No hypothesis stated"))

(defun gptel-auto-experiment--summarize (hypothesis)
  "Create short summary of HYPOTHESIS."
  (let ((words (split-string hypothesis)))
    (string-join (cl-subseq words 0 (min 6 (length words))) " ")))

;;; Experiment Loop

(defun gptel-auto-experiment-loop (target callback)
  "Run experiments for TARGET until stop condition. Call CALLBACK with results."
  (setq gptel-auto-experiment--results nil
        gptel-auto-experiment--best-score nil
        gptel-auto-experiment--no-improvement-count 0)
  (let ((baseline (gptel-auto-experiment-benchmark))
        (max-exp gptel-auto-experiment-max-per-target)
        (threshold gptel-auto-experiment-no-improvement-threshold))
    (setq gptel-auto-experiment--best-score (plist-get baseline :eight-keys))
    (message "[auto-experiment] Baseline for %s: %.2f" target gptel-auto-experiment--best-score)
    (cl-labels ((run-next (exp-id)
                  (if (or (> exp-id max-exp)
                          (gptel-auto-experiment-should-stop-p threshold))
                      (progn
                        (message "[auto-experiment] Done with %s: %d experiments, best score %.2f"
                                 target (length gptel-auto-experiment--results)
                                 (or gptel-auto-experiment--best-score 0))
                        (funcall callback (nreverse gptel-auto-experiment--results)))
                    (gptel-auto-experiment-run
                     target exp-id max-exp
                     gptel-auto-experiment--best-score
                     gptel-auto-experiment--results
                     (lambda (result)
                       (push result gptel-auto-experiment--results)
                       (run-next (1+ exp-id)))))))
      (run-next 1))))

;;; Main Entry Point

(defun gptel-auto-workflow-run (&optional targets)
  "Run ~32 experiments overnight (dynamic stop per target).

Each target runs up to gptel-auto-experiment-max-per-target experiments.
Stops early if gptel-auto-experiment-no-improvement-threshold consecutive
experiments show no improvement.

Uses subagents:
- analyzer: detect patterns, guide hypotheses
- grader: validate experiment quality (LLM decides threshold)
- comparator: decide keep/discard with reasoning

Results logged to var/tmp/experiments/{date}/results.tsv

Cron: emacsclient -e '(gptel-auto-workflow-run)'
Manual: M-x gptel-auto-workflow-run"
  (interactive)
  (unless (require 'magit-worktree nil t)
    (user-error "magit-worktree is required"))
  (unless (require 'magit-git nil t)
    (user-error "magit-git is required"))
  (let* ((targets (or targets gptel-auto-workflow-targets))
         (run-id (format-time-string "%Y-%m-%d"))
         (all-results '()))
    (message "[auto-workflow] Starting %s with %d targets" run-id (length targets))
    (dolist (target targets)
      (gptel-auto-experiment-loop
       target
       (lambda (results)
         (setq all-results (append all-results results)))))
    (message "[auto-workflow] Complete: %d total experiments"
             (length all-results))
    (message "[auto-workflow] Results: %s/%s/results.tsv"
             gptel-auto-workflow-worktree-base run-id)))

;;; Footer

(provide 'gptel-tools-agent)

;;; gptel-tools-agent.el ends here
