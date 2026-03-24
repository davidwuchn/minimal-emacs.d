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

(declare-function gptel--preset-syms "gptel")
(declare-function gptel--apply-preset "gptel")
(declare-function gptel-fsm-info "gptel")
(declare-function gptel--update-status "gptel")
(declare-function gptel-request "gptel")
(declare-function gptel-make-fsm "gptel")
(declare-function gptel--display-tool-calls "gptel")
(declare-function gptel-get-tool "gptel")
(declare-function gptel-make-tool "gptel")
(declare-function my/gptel--coerce-fsm "gptel-ext-fsm-utils")

(defvar gptel--fsm-last nil)
(defvar gptel-agent--agents nil)
(defvar gptel-agent-request--handlers nil)

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
  "Run agent AGENT-TYPE with CALLBACK, adding timeout and progress messages.

Uses gptel-with-preset + gptel-request instead of gptel-agent--task
for better compatibility with DashScope backend."
  (let* ((done nil)
         (timeout-timer nil)
         (progress-timer nil)
         (start-time (current-time))
         (origin-buf (current-buffer))
         (packaged-prompt (my/gptel--build-subagent-context prompt files include-history include-diff origin-buf))
         (agent-config (cdr (assoc agent-type gptel-agent--agents)))
         (accumulated-result nil)
         (wrapped-cb
          (lambda (result info)
            (when (stringp result)
              (setq accumulated-result (concat (or accumulated-result "") result)))
            (when (and (not done) (stringp result) (not (plist-get info :tool-use)))
              (setq done t)
              (when (timerp timeout-timer) (cancel-timer timeout-timer))
              (when (timerp progress-timer) (cancel-timer progress-timer))
              (message "[nucleus] Subagent '%s' completed in %.1fs, result-len=%d"
                       agent-type (float-time (time-since start-time))
                       (length accumulated-result))
              (funcall callback accumulated-result)))))

    (unless agent-config
      (funcall callback (format "Error: unknown agent '%s'" agent-type))
      (cl-return-from my/gptel--agent-task-with-timeout))

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
                 (funcall callback
                          (format "Error: Task \"%s\" (%s) timed out after %ds."
                                  description agent-type my/gptel-agent-task-timeout)))))))

    (condition-case err
        (gptel-with-preset agent-config
          (gptel-request packaged-prompt
            :callback wrapped-cb))
      (error
       (message "[nucleus] gptel-request ERROR: %S" err)
       (funcall callback (format "Error: %S" err))))))

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
  "Time budget per experiment in seconds (default: 15 min).
Should be >= curl timeout (300s) + retry delays."
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

(defcustom gptel-auto-experiment-lite-mode nil
  "Use lite-executor (4 tools) instead of executor (27 tools).
Lite mode is much faster on slow APIs like DashScope because
the tool definitions payload is much smaller."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-mock-mode nil
  "When non-nil, mock subagent responses for testing.
Useful for testing callback chain without API calls."
  :type 'boolean
  :group 'gptel-tools-agent)

;;; State

(defvar gptel-auto-workflow--worktree-dir nil)
(defvar gptel-auto-workflow--current-branch nil)
(defvar gptel-auto-experiment--results nil)
(defvar gptel-auto-experiment--best-score nil)
(defvar gptel-auto-experiment--no-improvement-count 0)
(defvar gptel-auto-workflow--current-target nil
  "Current target file for experiment scoring.")
(defvar gptel-auto-experiment--learnings nil
  "Accumulated learnings from experiments in this session.")

;;; Learning System (Mementum Integration)

(defun gptel-auto-experiment--learn (result)
  "Learn from experiment RESULT. Store to mementum if significant."
  (let* ((kept (plist-get result :kept))
         (delta (or (plist-get result :delta) 0))
         (hypothesis (plist-get result :hypothesis))
         (target (plist-get result :target)))
    ;; Track in-session learnings
    (when kept
      (push (format "[%s] %s → +%.2f"
                    (file-name-nondirectory target)
                    (gptel-auto-experiment--summarize hypothesis)
                    delta)
            gptel-auto-experiment--learnings)
      (message "[auto-exp] ✅ Learned: %s" (car gptel-auto-experiment--learnings)))
    ;; Store to mementum if significant improvement (gate-2: effort > 1-attempt, likely_recur)
    (when (and kept (> delta 0.02))
      (gptel-auto-experiment--store-memory result))))

(defun gptel-auto-experiment--store-memory (result)
  "Store RESULT as mementum memory if gates pass."
  (let* ((mementum-dir "mementum/memories")
         (target (plist-get result :target))
         (hypothesis (plist-get result :hypothesis))
         (delta (or (plist-get result :delta) 0))
         (score-before (plist-get result :score-before))
         (score-after (plist-get result :score-after))
         (slug (format "auto-exp-%s-%s"
                       (file-name-sans-extension (file-name-nondirectory target))
                       (format-time-string "%Y%m%d-%H%M%S")))
         (content (format "# Auto-Experiment Learning

## Improvement
%s

## Metrics
- Target: %s
- Score: %.2f → %.2f (Δ +%.2f)
- Kept: yes

## Context
This improvement was discovered through autonomous experimentation.
The hypothesis was validated by quality score increase.
"
                          hypothesis target score-before score-after delta)))
    ;; gate-1: helps(future_AI_session) - yes, patterns are reusable
    ;; gate-2: effort > 1_attempt - yes, experiments are expensive
    (when (file-exists-p mementum-dir)
      (let ((file (expand-file-name (concat slug ".md") mementum-dir)))
        (with-temp-file file
          (insert content))
        (message "[auto-exp] 💡 Stored memory: %s" slug)
        ;; Commit with mementum symbol
        (let ((default-directory (gptel-auto-workflow--base-dir)))
          (shell-command
           (format "git add %s && git commit -m \"💡 %s: +%.2f quality score\"" file slug delta)))))))

(defun gptel-auto-experiment--recall-learnings (target)
  "Recall past learnings for TARGET from mementum/git history."
  (let* ((target-name (file-name-nondirectory target))
         (default-directory (gptel-auto-workflow--base-dir))
         (memories (shell-command-to-string
                    (format "git log --oneline -20 --grep='auto-exp' --grep='%s' --all-match 2>/dev/null || true"
                            (file-name-sans-extension target-name)))))
    (when (string-empty-p memories)
      (setq memories (shell-command-to-string
                      (format "git log --oneline -10 -- mementum/memories/auto-exp-%s* 2>/dev/null || true"
                              (file-name-sans-extension target-name)))))
    (unless (string-empty-p memories)
      memories)))

(defun gptel-auto-experiment--get-learnings ()
  "Get relevant learnings for current target."
  (when gptel-auto-experiment--learnings
    (string-join (cl-subseq gptel-auto-experiment--learnings
                            0 (min 5 (length gptel-auto-experiment--learnings)))
                 "\n")))

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
  (let* ((base-dir (gptel-auto-workflow--base-dir))
         (branch (gptel-auto-workflow--branch-name target experiment-id))
         (worktree-dir (expand-file-name
                        (format "%s/%s" gptel-auto-workflow-worktree-base branch)
                        base-dir))
         (default-directory base-dir))
    (setq gptel-auto-workflow--worktree-dir nil
          gptel-auto-workflow--current-branch nil)
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
  "Delete current worktree if exists.
Also kills any stale magit buffers referencing old worktrees."
  (let* ((main-repo (gptel-auto-workflow--base-dir))
         (default-directory main-repo))
    ;; Kill stale magit buffers from previous experiments
    (dolist (b (buffer-list))
      (when (and (buffer-live-p b)
                 (string-match-p "magit: retry-exp" (buffer-name b)))
        (kill-buffer b)))
    (when (and gptel-auto-workflow--worktree-dir
               (file-exists-p gptel-auto-workflow--worktree-dir))
      (let ((dir gptel-auto-workflow--worktree-dir)
            (branch gptel-auto-workflow--current-branch))
        (setq gptel-auto-workflow--worktree-dir nil
              gptel-auto-workflow--current-branch nil)
        (condition-case err
            (progn
              (when (file-exists-p dir)
                (delete-directory dir t))
              (magit-git-success "worktree" "prune")
              (when branch
                (magit-git-success "branch" "-D" branch)))
          (error
           (message "[auto-workflow] Failed to delete worktree: %s" err)))))))

;;; Benchmark & Evaluation

(defun gptel-auto-experiment-benchmark ()
  "Run verification + compute quality score from byte-compile/checkdoc."
  (let* ((start (float-time))
         (base-dir (gptel-auto-workflow--base-dir))
         (worktree (or gptel-auto-workflow--worktree-dir base-dir))
         ;; Don't set default-directory to non-existent dir
         (default-directory (if (file-exists-p worktree) worktree base-dir))
         (verify-result (call-process "bash" nil nil nil
                                      (expand-file-name "scripts/verify-nucleus.sh"
                                                        base-dir)))
         (quality-score (when (zerop verify-result)
                          (gptel-auto-experiment--quality-score))))
    (list :passed (zerop verify-result)
          :time (- (float-time) start)
          :eight-keys quality-score
          :quality quality-score)))

(defun gptel-auto-experiment--quality-score ()
  "Compute quality score from checkdoc and missing docs.
Score = 1.0 - (checkdoc*0.01 + missing-docs*0.005)
Minimum score is 0.1."
  (let* ((target (or gptel-auto-workflow--current-target ""))
         (worktree (or gptel-auto-workflow--worktree-dir
                       (gptel-auto-workflow--base-dir)))
         (score 1.0)
         (checkdoc-issues 0)
         (missing-docs 0))
    (when (string-match "\\.el$" target)
      (let* ((file (expand-file-name target worktree)))
        (when (file-exists-p file)
          ;; Count checkdoc issues (safe, doesn't need byte-compile)
          (condition-case nil
              (with-temp-buffer
                (insert-file-contents file)
                (emacs-lisp-mode)
                (setq checkdoc-issues (length (checkdoc-current-buffer t))))
            (error 0))
          ;; Count undocumented functions
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (while (re-search-forward "(defun \\([^ ]+\\)" nil t)
              (forward-line)
              (unless (looking-at-p "\\s-*\"")
                (cl-incf missing-docs))))))
      ;; Calculate score
      (setq score (- 1.0
                     (* checkdoc-issues 0.01)
                     (* missing-docs 0.005)))
      (message "[auto-exp] Quality: %d checkdoc, %d missing docs → %.2f"
                checkdoc-issues missing-docs score)
      (max 0.1 (min 1.0 score)))))

(defun gptel-auto-experiment--eight-keys-score ()
  "Alias for quality-score. Kept for compatibility."
  (gptel-auto-experiment--quality-score))

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
    (let ((score-before (or (plist-get before :score) 0.5))
          (score-after (or (plist-get after :score) 0.5)))
      (funcall callback
               (list :keep (> score-after score-before)
                     :reasoning (format "Score: %.2f → %.2f" score-before score-after)
                     :improvement (list :score (- score-after score-before)))))))

;;; Prompt Building

(defun gptel-auto-experiment-build-prompt (target experiment-id max-experiments analysis baseline)
  "Build prompt for experiment EXPERIMENT-ID on TARGET."
  (let* ((base-dir (gptel-auto-workflow--base-dir))
         (worktree (or gptel-auto-workflow--worktree-dir base-dir))
         (target-file (expand-file-name target worktree))
         (git-history (shell-command-to-string
                       (format "cd %s && git log --oneline -10 2>/dev/null || echo 'no history'"
                               worktree)))
         (patterns (when analysis (plist-get analysis :patterns)))
         (suggestions (when analysis (plist-get analysis :recommendations)))
         (file-analysis (gptel-auto-experiment--analyze-file target-file))
         (past-learnings (gptel-auto-experiment--recall-learnings target)))
    (format "You are running experiment %d of %d to improve %s.

## IMPORTANT: Work Directory
All file operations must use FULL PATH:
- Target file: %s
- Work directory: %s

## Current File Analysis
%s

## Quality Score: %.2f (higher is better)
Score formula: 1.0 - (errors*0.1 + warnings*0.02 + checkdoc*0.01 + missing-docs*0.005)

## Past Successful Improvements
%s

## Previous Experiments
%s

## Suggestions
%s

## Recent Commits
%s

## Objective
Make ONE specific improvement to increase the quality score.
Focus on: adding docstrings, fixing warnings, simplifying code, or removing dead code.

## Constraints
- Time budget: %d minutes
- Immutable files: early-init.el, pre-early-init.el, lisp/eca-security.el
- Must pass tests: ./scripts/verify-nucleus.sh
- Maximum 5 tool calls
- ALL file paths must be FULL paths (see Work Directory above)

## Instructions
1. Read the target file using full path: %s
2. Identify ONE specific improvement (e.g., add docstring to function X)
3. Make the change using the SAME full path
4. Run Diagnostics to verify no new errors

Start with:
HYPOTHESIS: Adding docstring to [function] will improve maintainability."
            experiment-id max-experiments target
            target-file worktree
            file-analysis
            (or baseline 0.5)
            (or past-learnings "None yet - first run for this file")
            (or patterns "None yet")
            (or suggestions "None")
            git-history
            (/ gptel-auto-experiment-time-budget 60)
            target-file)))

(defun gptel-auto-experiment--analyze-file (file)
  "Analyze FILE for quality issues. Return string summary."
  (when (file-exists-p file)
    (let* ((content (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))
           (lines (length (split-string content "\n")))
           (defuns 0)
           (undoc-fns 0)
           (issues '()))
      ;; Count functions and undocumented ones
      (with-temp-buffer
        (insert content)
        (goto-char (point-min))
        (while (re-search-forward "(defun \\([^ ]+\\)" nil t)
          (cl-incf defuns)
          (forward-line)
          (unless (looking-at-p "\\s-*\"")
            (cl-incf undoc-fns)
            (push (format "Undocumented: %s" (match-string 1)) issues)))
        ;; Check for common issues in the temp buffer
        (goto-char (point-min))
        (when (re-search-forward "(save-excursion\n *)" nil t)
          (push "Has empty save-excursion blocks" issues))
        (goto-char (point-min))
        (when (> (count-matches "(condition-case" (point-min) (point-max)) 3)
          (push "Many condition-case blocks" issues))
        (goto-char (point-min))
        (when (> (count-matches "(interactive)" (point-min) (point-max)) 10)
          (push "Many interactive commands" issues)))
      (format "Lines: %d, Functions: %d, Undocumented: %d\nIssues: %s"
              lines defuns undoc-fns
              (if issues (string-join (nreverse issues) "; ") "None")))))

;;; TSV Logging (Explainable)

(defun gptel-auto-experiment-log-tsv (run-id experiment)
  "Append EXPERIMENT to results.tsv for RUN-ID."
  (let* ((base-dir (gptel-auto-workflow--base-dir))
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
      (message "[auto-exp] Step 1: Analyzing previous results...")
      (gptel-auto-experiment-analyze
       previous-results
       (lambda (analysis)
         (message "[auto-exp] Step 1 callback called: analysis=%S" analysis)
         (let* ((patterns (when analysis (plist-get analysis :patterns)))
                (prompt (gptel-auto-experiment-build-prompt
                         target experiment-id max-experiments analysis baseline)))
           (message "[auto-exp] Step 2: Running executor with %ds timeout..." gptel-auto-experiment-time-budget)
(setq timeout-timer
                  (run-with-timer gptel-auto-experiment-time-budget nil
                                  (lambda ()
                                    (unless finished
                                      (message "[auto-exp] TIMEOUT after %ds" gptel-auto-experiment-time-budget)
                                      (setq finished t)
                                      (gptel-auto-workflow-delete-worktree)
                                      (let ((exp-result (list :target target
                                                              :id experiment-id
                                                              :hypothesis "timeout"
                                                              :score-before baseline
                                                              :score-after 0
                                                              :kept nil
                                                              :duration gptel-auto-experiment-time-budget
                                                              :grader-quality 0
                                                              :grader-reason "timeout"
                                                              :comparator-reason "timeout"
                                                              :analyzer-patterns "timeout")))
                                        (gptel-auto-experiment-log-tsv
                                         (format-time-string "%Y-%m-%d") exp-result))
                                      (funcall callback
                                               (list :target target
                                                     :id experiment-id
                                                     :error "timeout"))))))
           (message "[auto-exp] mock-mode=%s" gptel-auto-experiment-mock-mode)
           (if gptel-auto-experiment-mock-mode
               (run-with-timer 1 nil
                               (lambda ()
                                 (let ((mock-output (format "HYPOTHESIS: Mock optimization for %s\n\nThis is a mock response for testing the callback chain." target)))
                                   (message "[auto-exp] MOCK MODE: simulating agent response")
                                   (when timeout-timer (cancel-timer timeout-timer))
                                   (unless finished
                                     (message "[auto-exp] Step 2 DONE (mock): %d chars" (length mock-output))
                                     (gptel-auto-experiment-grade
                                      mock-output
                                      (lambda (grade)
                                        (message "[auto-exp] Step 3 DONE: grade=%S passed=%S"
                                                 (plist-get grade :score) (plist-get grade :passed))
                                        (let* ((grade-score (plist-get grade :score))
                                               (grade-passed (plist-get grade :passed))
                                               (hypothesis (gptel-auto-experiment--extract-hypothesis mock-output)))
                                          (if (not grade-passed)
                                              (progn
                                                (message "[auto-exp] Early discard (grade failed)")
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
                                                                        :grader-reason "mock-grade-failed"
                                                                        :comparator-reason "early-discard"
                                                                        :analyzer-patterns "mock"))))
                                                  (gptel-auto-experiment-log-tsv
                                                   (format-time-string "%Y-%m-%d") exp-result)
                                                  (funcall callback exp-result)))
                                            (message "[auto-exp] Step 4: Running benchmark...")
                                            (let* ((bench (list :passed t :eight-keys 0.75))
                                                   (passed (plist-get bench :passed))
                                                   (score-after (or (plist-get bench :eight-keys) baseline)))
                                              (message "[auto-exp] Step 4 DONE: passed=%S score=%S" passed score-after)
                                              (if (not passed)
                                                  (progn
                                                    (message "[auto-exp] Tests failed, discarding")
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
                                                                            :grader-reason "mock"
                                                                            :comparator-reason "tests-failed"
                                                                            :analyzer-patterns "mock"))))
                                                      (gptel-auto-experiment-log-tsv
                                                       (format-time-string "%Y-%m-%d") exp-result)
                                                      (funcall callback exp-result)))
                                                (message "[auto-exp] Step 5: Deciding keep/discard...")
                                                (gptel-auto-experiment-decide
                                                 (list :score baseline)
                                                 (list :score score-after :output mock-output)
                                                 (lambda (decision)
                                                   (message "[auto-exp] Step 5 DONE: keep=%S" (plist-get decision :keep))
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
                                                                            :grader-reason "mock"
                                                                            :comparator-reason reasoning
:analyzer-patterns "mock")))
                                                      (message "[auto-exp] Logging TSV (final)...")
                                                      (gptel-auto-experiment-log-tsv
                                                       (format-time-string "%Y-%m-%d") exp-result)
                                                      (gptel-auto-workflow-delete-worktree)
                                                      (message "[auto-exp] Experiment %d COMPLETE (mock)" experiment-id)
                                                      (funcall callback exp-result))))))))))))
            (my/gptel--run-agent-tool
            (lambda (agent-output)
              (message "[auto-exp] Step 2 DONE: agent returned %d chars" (length agent-output))
              (when timeout-timer (cancel-timer timeout-timer))
              (unless finished
                (message "[auto-exp] Step 3: Grading output...")
                (gptel-auto-experiment-grade
                 agent-output
                 (lambda (grade)
                   (message "[auto-exp] Step 3 DONE: grade=%S passed=%S" 
                            (plist-get grade :score) (plist-get grade :passed))
                   (let* ((grade-score (plist-get grade :score))
                          (grade-passed (plist-get grade :passed))
                          (hypothesis (gptel-auto-experiment--extract-hypothesis agent-output)))
                     (if (not grade-passed)
                         (progn
                           (message "[auto-exp] Early discard (grade failed)")
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
                             (message "[auto-exp] Logging TSV (early-discard)...")
                             (gptel-auto-experiment-log-tsv
                              (format-time-string "%Y-%m-%d") exp-result)
                             (funcall callback exp-result)))
                       (message "[auto-exp] Step 4: Running benchmark...")
                       (let* ((bench (gptel-auto-experiment-benchmark))
                              (passed (plist-get bench :passed))
                              (score-after (plist-get bench :eight-keys)))
                         (message "[auto-exp] Step 4 DONE: passed=%S score=%S" passed score-after)
                         (if (not passed)
                             (progn
                               (message "[auto-exp] Tests failed, discarding")
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
                                 (message "[auto-exp] Logging TSV (tests-failed)...")
                                 (gptel-auto-experiment-log-tsv
                                  (format-time-string "%Y-%m-%d") exp-result)
                                 (funcall callback exp-result)))
                           (message "[auto-exp] Step 5: Deciding keep/discard...")
                           (gptel-auto-experiment-decide
                            (list :score baseline)
                            (list :score score-after :output agent-output)
                            (lambda (decision)
                              (message "[auto-exp] Step 5 DONE: keep=%S" (plist-get decision :keep))
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
                                    (let ((msg (format "◈ Optimize %s: %s\n\nHYPOTHESIS: %s\nExperiment %d/%d. Score: %.2f → %.2f"
                                                       target
                                                       (gptel-auto-experiment--summarize hypothesis)
                                                       hypothesis
                                                       experiment-id max-experiments
                                                       baseline score-after)))
                                      (message "[auto-exp] KEEPING changes, committing...")
                                      (magit-git-success "add" "-A")
                                      (magit-git-success "commit" "-m" msg)
                                      (setq gptel-auto-experiment--best-score score-after
                                            gptel-auto-experiment--no-improvement-count 0))
                                  (progn
                                    (message "[auto-exp] DISCARDING changes")
                                    (magit-git-success "checkout" "--" ".")
                                    (cl-incf gptel-auto-experiment--no-improvement-count)))
                                (message "[auto-exp] Logging TSV (final)...")
                                (gptel-auto-experiment-log-tsv
                                 (format-time-string "%Y-%m-%d") exp-result)
                                (gptel-auto-workflow-delete-worktree)
                                (message "[auto-exp] Experiment %d COMPLETE" experiment-id)
                                (funcall callback exp-result))))))))))))
            (if gptel-auto-experiment-lite-mode "lite-executor" "executor")
            (format "Experiment %d: optimize %s" experiment-id target)
            prompt
            nil "false" nil))))))))

(defun gptel-auto-experiment--extract-hypothesis (output)
  "Extract HYPOTHESIS from agent OUTPUT."
  (cond
   ;; Look for explicit HYPOTHESIS: marker
   ((string-match "HYPOTHESIS:\\s-*\\([^\n]+\\)" output)
    (string-trim (match-string 1 output)))
   ;; Look for first sentence/paragraph
   ((string-match "^\\([^.\n]+[.!?]\\)" output)
    (string-trim (match-string 1 output)))
   ;; Use first 100 chars
   ((> (length output) 50)
    (format "%s..." (substring output 0 (min 50 (length output)))))
   (t "No hypothesis stated")))

(defun gptel-auto-experiment--summarize (hypothesis)
  "Create short summary of HYPOTHESIS."
  (let ((words (split-string hypothesis)))
    (string-join (cl-subseq words 0 (min 6 (length words))) " ")))

;;; Experiment Loop

(defun gptel-auto-experiment-loop (target callback)
  "Run experiments for TARGET until stop condition. Call CALLBACK with results."
  (setq gptel-auto-experiment--results nil
        gptel-auto-experiment--best-score nil
        gptel-auto-experiment--no-improvement-count 0
        gptel-auto-workflow--current-target target)
  (let ((baseline (gptel-auto-experiment-benchmark))
        (max-exp gptel-auto-experiment-max-per-target)
        (threshold gptel-auto-experiment-no-improvement-threshold))
    (setq gptel-auto-experiment--best-score (or (plist-get baseline :eight-keys) 0.5))
    (message "[auto-experiment] Baseline for %s: %s" target (or gptel-auto-experiment--best-score "N/A"))
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
                       (gptel-auto-experiment--learn result)
                       (push result gptel-auto-experiment--results)
                       (run-next (1+ exp-id)))))))
      (run-next 1))))

;;; Mock Test (no API)

(defun gptel-auto-experiment-test-mock ()
  "Test the experiment callback chain with mocked responses.
Does not call the API. Useful for verifying TSV logging and cleanup."
  (interactive)
  (let* ((target "lisp/modules/gptel-ext-retry.el")
         (worktree (gptel-auto-workflow-create-worktree target 1))
         (start-time (float-time))
         (mock-output "HYPOTHESIS: Add caching to gptel-auto-experiment-benchmark to avoid redundant git calls.\n\nI will add a cache variable and memoize the benchmark results.")
         (baseline 0.5)
         (result nil))
    (if (not worktree)
        (message "[mock-test] Failed to create worktree")
      (unwind-protect
          (progn
            (message "[mock-test] Worktree created: %s" worktree)
            (message "[mock-test] Simulating grade step...")
            (let* ((hypothesis (gptel-auto-experiment--extract-hypothesis mock-output))
                   (grade (list :score 85 :passed t))
                   (bench (gptel-auto-experiment-benchmark))
                   (score-after (or (plist-get bench :eight-keys) baseline)))
              (message "[mock-test] Hypothesis: %s" hypothesis)
              (message "[mock-test] Grade: score=%S passed=%S" 
                       (plist-get grade :score) (plist-get grade :passed))
              (message "[mock-test] Benchmark: passed=%S score=%S" 
                       (plist-get bench :passed) score-after)
              (message "[mock-test] Simulating decide step...")
              (let* ((keep (> score-after baseline))
                     (decision (list :keep keep :reasoning "Mock decision"))
                     (exp-result (list :target target
                                       :id 1
                                       :hypothesis hypothesis
                                       :score-before baseline
                                       :score-after score-after
                                       :kept keep
                                       :duration (- (float-time) start-time)
                                       :grader-quality (plist-get grade :score)
                                       :grader-reason "Mock grader"
                                       :comparator-reason (plist-get decision :reasoning)
                                       :analyzer-patterns "mock patterns")))
                (message "[mock-test] Decision: keep=%S" keep)
                (message "[mock-test] Logging TSV...")
                (gptel-auto-experiment-log-tsv (format-time-string "%Y-%m-%d") exp-result)
                (setq result exp-result)
                (message "[mock-test] SUCCESS! Result: %S" result))))
        (progn
          (message "[mock-test] Cleaning up worktree...")
          (gptel-auto-workflow-delete-worktree)))
      result)))

(defun gptel-auto-experiment-test-full-cycle ()
  "Test the full experiment cycle with mock mode enabled.
Runs gptel-auto-experiment-run with mocked subagent response."
  (interactive)
  (let ((gptel-auto-experiment-mock-mode t)
        (gptel-auto-experiment-max-per-target 1)
        (gptel-auto-experiment-use-subagents nil))
    (gptel-auto-experiment-loop
     "lisp/modules/gptel-ext-retry.el"
     (lambda (results)
       (message "[full-cycle-test] COMPLETE! Results: %S" results)))))

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
  ;; Clean up stale state from previous runs
  (setq gptel-auto-workflow--worktree-dir nil
        gptel-auto-workflow--current-branch nil)
  (dolist (b (buffer-list))
    (when (and (buffer-live-p b)
               (string-match-p "magit: retry-exp\\|magit: optimize" (buffer-name b)))
      (kill-buffer b)))
  (let* ((targets (or targets gptel-auto-workflow-targets))
         (run-id (format-time-string "%Y-%m-%d"))
         (all-results '()))
    (message "[auto-workflow] Starting %s with %d targets" run-id (length targets))
    (cl-labels ((run-next-target (remaining)
                  (if (null remaining)
                      (progn
                        (message "[auto-workflow] Complete: %d total experiments"
                                 (length all-results))
                        (message "[auto-workflow] Results: %s/%s/results.tsv"
                                 gptel-auto-workflow-worktree-base run-id))
                    (gptel-auto-experiment-loop
                     (car remaining)
                     (lambda (results)
                       (setq all-results (append all-results results))
                       (run-next-target (cdr remaining)))))))
      (run-next-target targets))))

;;; Autonomous Research Agent (program.md + skills + mementum)

(defcustom gptel-auto-workflow-program-file "docs/auto-workflow-program.md"
  "Path to program.md (human-editable objectives)."
  :type 'file
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-skills-dir "mementum/knowledge"
  "Directory containing optimization-skills/ and mutations/."
  :type 'directory
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--program nil
  "Parsed program.md content.")

(defvar gptel-auto-workflow--skills nil
  "Loaded optimization skills for current run.")

(defun gptel-auto-workflow--base-dir ()
  "Return the project base directory.
Uses `minimal-emacs-user-directory' if available, else `user-emacs-directory'."
  (if (boundp 'minimal-emacs-user-directory)
      minimal-emacs-user-directory
    user-emacs-directory))

(defun gptel-auto-workflow-load-program ()
  "Load and parse docs/auto-workflow-program.md."
  (let* ((file (expand-file-name gptel-auto-workflow-program-file
                                 (gptel-auto-workflow--base-dir)))
         (content (when (file-exists-p file)
                    (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string))))
         (targets '())
         (immutable '())
         (mutations '()))
    (when content
      (with-temp-buffer
        (insert content)
        (goto-char (point-min))
        (when (re-search-forward "^## Targets" nil t)
          (when (re-search-forward "^```" nil t)
            (forward-line 1)
            (while (and (not (looking-at "```")) (not (eobp)))
              (let ((line (string-trim (thing-at-point 'line t))))
                (when (and (> (length line) 0) (not (string-match-p "^#" line)))
                  (push line targets)))
              (forward-line 1))))
        (goto-char (point-min))
        (when (re-search-forward "^### Immutable Files" nil t)
          (when (re-search-forward "^```" nil t)
            (forward-line 1)
            (while (and (not (looking-at "```")) (not (eobp)))
              (let ((line (string-trim (thing-at-point 'line t))))
                (when (> (length line) 0)
                  (push line immutable)))
              (forward-line 1))))
        (goto-char (point-min))
        (when (re-search-forward "^Allowed mutation types:" nil t)
          (forward-line 1)
          (while (and (not (looking-at "^##")) (not (eobp)))
            (when (looking-at "- \\[x\\] \\([a-z-]+\\)")
              (push (match-string 1) mutations))
            (forward-line 1)))))
    (list :targets (nreverse targets)
          :immutable (nreverse immutable)
          :mutations (nreverse mutations)
          :file file)))

(defun gptel-auto-workflow-skill-path (target type)
  "Get skill path for TARGET. TYPE is 'target or 'mutation."
  (let* ((name (file-name-sans-extension (file-name-nondirectory target)))
         (skill-name (car (last (split-string name "-")))))
    (if (eq type 'target)
        (format "%s/optimization-skills/%s.md" gptel-auto-workflow-skills-dir skill-name)
      (format "%s/mutations/%s.md" gptel-auto-workflow-skills-dir target))))

(defun gptel-auto-workflow-skill-load (skill-file)
  "Load skill from SKILL-FILE."
  (let ((file (expand-file-name skill-file (gptel-auto-workflow--base-dir))))
    (when (file-exists-p file)
      (let ((content (with-temp-buffer
                       (insert-file-contents file)
                       (buffer-string)))
            (skill (list :file skill-file)))
        (when (string-match "^phi:[[:space:]]*\\([0-9.]+\\)" content)
          (plist-put skill :phi (string-to-number (match-string 1 content))))
        (when (string-match "^mutation-skills:[[:space:]]*\n\\(\\(?:  - .+\n\\)+\\)" content)
          (let ((refs (match-string 1 content)))
            (plist-put skill :mutation-skills
                       (mapcar (lambda (line)
                                 (string-trim (replace-regexp-in-string "^  - " "" line)))
                               (split-string refs "\n" t)))))
        (plist-put skill :content content)
        skill))))

(defun gptel-auto-workflow-recall-skills (target)
  "Load target skill + referenced mutation skills for TARGET."
  (let* ((target-skill-file (gptel-auto-workflow-skill-path target 'target))
         (target-skill (gptel-auto-workflow-skill-load target-skill-file))
         (mutation-skills '()))
    (when target-skill
      (dolist (ref (plist-get target-skill :mutation-skills))
        (let ((ms (gptel-auto-workflow-skill-load ref)))
          (when ms (push ms mutation-skills)))))
    (list :target-skill target-skill
          :mutation-skills (nreverse mutation-skills))))

(defun gptel-auto-workflow-skill-suggest-hypothesis (skills)
  "Get suggested hypothesis from SKILLS."
  (let* ((target-skill (plist-get skills :target-skill))
         (content (when target-skill (plist-get target-skill :content))))
    (when (and content (string-match "^## Next Hypothesis\n\n\\(.+\\)" content))
      (match-string 1 content))))

(defun gptel-auto-workflow-orient ()
  "Orient for auto-workflow run. Load program.md and skills."
  (let ((program (gptel-auto-workflow-load-program)))
    (setq gptel-auto-workflow--program program)
    (message "[autonomous] Loaded program: %d targets"
             (length (plist-get program :targets)))
    (let ((skills '()))
      (dolist (target (plist-get program :targets))
        (push (cons target (gptel-auto-workflow-recall-skills target)) skills))
      (setq gptel-auto-workflow--skills skills))
    program))

;;; Skill Evolution (Continuity + Compounding)

(defun gptel-auto-workflow-detect-mutation (hypothesis)
  "Detect mutation type from HYPOTHESIS string."
  (cond
   ((string-match-p "cache\\|Cache\\|memoize\\|memo" hypothesis) "caching")
   ((string-match-p "lazy\\|defer\\|on-demand\\|delay" hypothesis) "lazy-init")
   ((string-match-p "simplif\\|remove\\|merge\\|reduce\\|eliminate" hypothesis) "simplification")
   (t "unknown")))

(defun gptel-auto-workflow-update-target-skill (target results)
  "Update TARGET skill file with RESULTS from night."
  (let* ((skill-file (gptel-auto-workflow-skill-path target 'target))
         (file (expand-file-name skill-file (gptel-auto-workflow--base-dir))))
    (when (file-exists-p file)
      (let* ((content (with-temp-buffer
                        (insert-file-contents file)
                        (buffer-string)))
             (by-mutation (make-hash-table :test 'equal))
             (successful '())
             (failed '())
             (best-hypothesis nil)
             (best-delta 0)
             (total-kept 0)
             (score-before nil)
             (score-after nil))
        (dolist (r results)
          (let* ((hypothesis (or (plist-get r :hypothesis) ""))
                 (mutation (gptel-auto-workflow-detect-mutation hypothesis))
                 (kept (plist-get r :kept))
                 (delta (or (plist-get r :delta) 0)))
            (when (and kept (> delta best-delta))
              (setq best-delta delta
                    best-hypothesis hypothesis))
            (when kept (cl-incf total-kept))
            (unless score-before
              (setq score-before (plist-get r :score-before)))
            (when (and kept (plist-get r :score-after))
              (setq score-after (plist-get r :score-after)))
            (puthash mutation (cons r (gethash mutation by-mutation)) by-mutation)))
        (maphash
         (lambda (mutation mutation-results)
           (let* ((kept-count (cl-count-if (lambda (r) (plist-get r :kept)) mutation-results))
                  (total (length mutation-results))
                  (success-rate (if (> total 0) (/ (* 100 kept-count) total) 0))
                  (kept-results (cl-remove-if-not (lambda (r) (plist-get r :kept)) mutation-results))
                  (avg-delta (if kept-results
                                 (/ (apply #'+ (mapcar (lambda (r) (or (plist-get r :delta) 0)) kept-results))
                                    (length kept-results))
                               0))
                  (best (car (sort kept-results (lambda (a b)
                                                   (> (or (plist-get a :delta) 0)
                                                      (or (plist-get b :delta) 0))))))
                  (best-hyp (when best (plist-get best :hypothesis))))
             (if (>= success-rate 50)
                 (push (list mutation success-rate avg-delta best-hyp) successful)
               (when (< success-rate 50)
                 (push (list mutation success-rate 
                             (if (< success-rate 50) "Low success rate" ""))
                       failed)))))
         by-mutation)
        (with-temp-buffer
          (insert content)
          (goto-char (point-min))
          (when (re-search-forward "^runs:[[:space:]]*\\([0-9]+\\)" nil t)
            (replace-match (format "runs: %d" (1+ (string-to-number (match-string 1))))))
          (goto-char (point-min))
          (when (re-search-forward "^phi:[[:space:]]*\\([0-9.]+\\)" nil t)
            (let* ((total (length results))
                   (new-phi (if (> total 0) (/ (float total-kept) total) 0.5)))
              (replace-match (format "phi: %.2f" new-phi))))
          (goto-char (point-min))
          (when (re-search-forward "^## Successful Mutations" nil t)
            (forward-line 3)
            (delete-region (point) (when (re-search-forward "^## " nil t) (match-beginning 0)))
            (backward-char 1)
            (dolist (s (nreverse successful))
              (insert (format "| %s | %.0f%% | %+.2f | %s |\n"
                              (nth 0 s) (nth 1 s) (nth 2 s) (or (nth 3 s) "-")))))
          (goto-char (point-min))
          (when (re-search-forward "^## Failed Mutations" nil t)
            (forward-line 3)
            (delete-region (point) (when (re-search-forward "^## " nil t) (match-beginning 0)))
            (backward-char 1)
            (dolist (f (nreverse failed))
              (insert (format "| %s | %.0f%% | %s |\n"
                              (nth 0 f) (nth 1 f) (nth 2 f)))))
          (goto-char (point-min))
          (when (re-search-forward "^## Nightly History" nil t)
            (forward-line 3)
            (let ((date (format-time-string "%Y-%m-%d"))
                  (exp-count (length results)))
              (insert (format "| %s | %d | %d | %.2f | %.2f | %+.2f |\n"
                              date exp-count total-kept
                              (or score-before 0)
                              (or score-after 0)
                              (if (and score-before score-after)
                                  (- score-after score-before)
                                0)))))
          (goto-char (point-min))
          (when (re-search-forward "^## Next Hypothesis" nil t)
            (forward-line 1)
            (delete-region (point) (when (re-search-forward "^## " nil t) (match-beginning 0)))
            (backward-char 1)
            (insert (format "\n%s\n" (or best-hypothesis "(Run more experiments)"))))
          (write-region (point-min) (point-max) file))))))

(defun gptel-auto-workflow-update-mutation-skill (mutation-type all-results)
  "Update MUTATION-TYPE skill file with ALL-RESULTS."
  (let* ((skill-file (format "%s/mutations/%s.md"
                             gptel-auto-workflow-skills-dir mutation-type))
         (file (expand-file-name skill-file (gptel-auto-workflow--base-dir))))
    (when (file-exists-p file)
      (let* ((content (with-temp-buffer
                        (insert-file-contents file)
                        (buffer-string)))
             (relevant (cl-remove-if-not
                        (lambda (r)
                          (let ((hyp (or (plist-get r :hypothesis) "")))
                            (eq (gptel-auto-workflow-detect-mutation hyp)
                                (intern mutation-type))))
                        all-results))
             (kept-relevant (cl-remove-if-not (lambda (r) (plist-get r :kept)) relevant))
             (total (length relevant))
             (kept-count (length kept-relevant))
             (success-rate (if (> total 0) (/ (* 100 kept-count) total) 0))
             (avg-delta (if kept-relevant
                            (/ (apply #'+ (mapcar (lambda (r) (or (plist-get r :delta) 0)) kept-relevant))
                               (length kept-relevant))
                          0))
             (history-rows '()))
        (dolist (r kept-relevant)
          (push (list (plist-get r :target)
                      (format-time-string "%Y-%m-%d")
                      (plist-get r :hypothesis)
                      (plist-get r :delta))
                history-rows))
        (with-temp-buffer
          (insert content)
          (goto-char (point-min))
          (when (re-search-forward "^phi:[[:space:]]*\\([0-9.]+\\)" nil t)
            (replace-match (format "phi: %.2f" (/ success-rate 100.0))))
          (goto-char (point-min))
          (when (re-search-forward "^## Success History" nil t)
            (forward-line 3)
            (dolist (row (nreverse history-rows))
              (insert (format "| %s | %s | %s | %+.2f |\n"
                              (nth 0 row) (nth 1 row)
                              (truncate-string-to-width (or (nth 2 row) "-") 40 nil nil "...")
                              (or (nth 3 row) 0)))))
          (goto-char (point-min))
          (when (re-search-forward "^## Statistics" nil t)
            (forward-line 6)
            (delete-region (point) (line-end-position))
            (insert (format "| Total uses | %d |" total))
            (forward-line 1)
            (delete-region (point) (line-end-position))
            (insert (format "| Success rate | %.0f%% |" success-rate))
            (forward-line 1)
            (delete-region (point) (line-end-position))
            (insert (format "| Avg delta | %+.2f |" avg-delta)))
          (write-region (point-min) (point-max) file))))))

(defun gptel-auto-workflow-metabolize (run-id all-results)
  "Synthesize RUN-ID ALL-RESULTS to mementum + evolve skills."
  (let ((memory-dir (expand-file-name "mementum/memories"
                                       (gptel-auto-workflow--base-dir)))
        (by-target (make-hash-table :test 'equal)))
    (make-directory memory-dir t)
    (let ((file (expand-file-name (format "auto-workflow-%s.md" run-id) memory-dir)))
      (with-temp-file file
        (insert (format "---\ntitle: Auto-Workflow %s\ndate: %s\n---\n\n" run-id run-id))
        (insert (format "# Auto-Workflow: %s\n\n" run-id))
        (insert "## Summary\n\n")
        (let ((kept (cl-count-if (lambda (r) (plist-get r :kept)) all-results))
              (total (length all-results)))
          (insert (format "- Experiments: %d\n" total))
          (insert (format "- Kept: %d\n" kept))
          (insert (format "- Discarded: %d\n\n" (- total kept))))
        (insert "## Key Learnings\n\n")
        (dolist (r (cl-remove-if-not (lambda (r) (plist-get r :kept)) all-results))
          (insert (format "- **%s**: %s\n"
                          (plist-get r :target)
                          (or (plist-get r :hypothesis) "unknown"))))))
    (message "[autonomous] Memory: mementum/memories/auto-workflow-%s.md" run-id)
    (dolist (r all-results)
      (let ((target (plist-get r :target)))
        (puthash target (cons r (gethash target by-target)) by-target)))
    (maphash
     (lambda (target results)
       (gptel-auto-workflow-update-target-skill target results))
     by-target)
    (let ((mutation-types '()))
      (dolist (r all-results)
        (let ((mutation (gptel-auto-workflow-detect-mutation
                         (or (plist-get r :hypothesis) ""))))
          (when (not (member mutation mutation-types))
            (push mutation mutation-types))))
      (dolist (mutation-type mutation-types)
        (when (not (equal mutation-type "unknown"))
          (gptel-auto-workflow-update-mutation-skill mutation-type all-results))))
    (message "[autonomous] Skills evolved: %d targets, %d mutation types"
             (hash-table-count by-target)
             (length (cl-remove "unknown" (hash-table-keys by-target))))))

(defun gptel-auto-workflow-run-autonomous ()
  "Run Autonomous Research Agent with program.md + skills + mementum.

Flow:
  1. orient() - load program.md + skills
  2. run experiments with skill guidance
  3. metabolize() - synthesize to mementum

Cron: emacsclient -e '(gptel-auto-workflow-run-autonomous)'
Manual: M-x gptel-auto-workflow-run-autonomous"
  (interactive)
  (unless (require 'magit-worktree nil t)
    (user-error "magit-worktree is required"))
  (unless (require 'magit-git nil t)
    (user-error "magit-git is required"))
  (let* ((program (gptel-auto-workflow-orient))
         (targets (plist-get program :targets))
         (run-id (format-time-string "%Y-%m-%d"))
         (all-results '()))
    (if (null targets)
        (message "[autonomous] No targets in %s" gptel-auto-workflow-program-file)
      (message "[autonomous] Starting %s with %d targets" run-id (length targets))
      (dolist (target targets)
        (gptel-auto-experiment-loop
         target
         (lambda (results)
           (setq all-results (append all-results results)))))
      (gptel-auto-workflow-metabolize run-id all-results)
      (message "[autonomous] Complete: %d experiments" (length all-results)))))

;;; Mementum Optimization

(defvar gptel-mementum-index-file "mementum/.index"
  "Path to recall index file.")

(defun gptel-mementum-build-index ()
  "Build recall index from all knowledge files.
Creates .index file with topic → file mapping for O(1) lookup."
  (let* ((index-file (expand-file-name gptel-mementum-index-file
                                        (gptel-auto-workflow--base-dir)))
         (knowledge-dir (expand-file-name "mementum/knowledge"
                                          (gptel-auto-workflow--base-dir)))
         (index (make-hash-table :test 'equal)))
    (when (file-exists-p knowledge-dir)
      (dolist (file (directory-files-recursively knowledge-dir "\\.md$"))
        (let ((content (with-temp-buffer
                         (insert-file-contents file)
                         (buffer-string)))
              (filename (file-relative-name file knowledge-dir)))
          (dolist (keyword '("caching" "lazy" "simplification" "retry" "context"
                             "code" "nucleus" "learning" "pattern" "evolution"
                             "safety" "upstream" "skill" "benchmark"))
            (when (string-match-p (regexp-quote keyword) content)
              (puthash keyword
                       (cons filename (gethash keyword index))
                       index))))))
    (with-temp-file index-file
      (insert "# Mementum Recall Index\n")
      (insert "# Auto-generated. Do not edit.\n\n")
      (maphash
       (lambda (keyword files)
         (insert (format "%s: %s\n" keyword (string-join (delete-dups files) ", "))))
       index))
    (message "[mementum] Index built: %d keywords" (hash-table-count index))))

(defun gptel-mementum-recall (query)
  "Quick lookup for QUERY in recall index.
Returns list of matching files."
  (let* ((index-file (expand-file-name gptel-mementum-index-file
                                        (gptel-auto-workflow--base-dir)))
         (result '()))
    (when (file-exists-p index-file)
      (with-temp-buffer
        (insert-file-contents index-file)
        (goto-char (point-min))
        (when (re-search-forward (format "^%s: " (regexp-quote query)) nil t)
          (let ((line (buffer-substring-no-properties (point) (line-end-position))))
            (setq result (split-string line ",\\s-*")))))
    (or result
        (progn
          (message "[mementum] Index miss, using git grep for: %s" query)
          (let ((default-directory (gptel-auto-workflow--base-dir)))
            (split-string
             (shell-command-to-string
              (format "git grep -l '%s' -- mementum/knowledge/ 2>/dev/null || true" query))
             "\n" t))))))

(defun gptel-mementum-decay-skills ()
  "Apply decay to skill files not tested in 4+ weeks.
Run weekly via cron."
  (let* ((skills-dir (expand-file-name "mementum/knowledge/optimization-skills"
                                        (gptel-auto-workflow--base-dir)))
         (mutations-dir (expand-file-name "mementum/knowledge/mutations"
                                          (gptel-auto-workflow--base-dir)))
         (now (float-time))
         (four-weeks (* 4 7 24 60 60))
         (decayed 0)
         (archived 0))
    (dolist (dir (list skills-dir mutations-dir))
      (when (file-exists-p dir)
        (dolist (file (directory-files dir t "\\.md$"))
          (let ((content (with-temp-buffer
                           (insert-file-contents file)
                           (buffer-string))))
            (when (string-match "^last-tested:[[:space:]]*\\([0-9-]+\\)" content)
              (let* ((date-str (match-string 1 content))
                     (last-tested (encode-time 0 0 0 (string-to-number (substring date-str 8 10))
                                               (string-to-number (substring date-str 5 7))
                                               (string-to-number (substring date-str 0 4))))
                     (age (- now (float-time last-tested))))
                (when (> age four-weeks)
                  (let ((new-phi (max 0.3 (- (if (string-match "^phi:[[:space:]]*\\([0-9.]+\\)" content)
                                                  (string-to-number (match-string 1 content))
                                                0.5)
                                              0.02))))
                    (if (< new-phi 0.3)
                        (progn
                          (let ((archive-dir (expand-file-name "archive" dir)))
                            (make-directory archive-dir t)
                            (rename-file file (expand-file-name (file-name-nondirectory file) archive-dir))
                            (cl-incf archived)))
                      (with-temp-buffer
                        (insert content)
                        (goto-char (point-min))
                        (when (re-search-forward "^phi:[[:space:]]*[0-9.]+" nil t)
                          (replace-match (format "phi: %.2f" new-phi)))
                        (write-region (point-min) (point-max) file)
                        (cl-incf decayed))))))))))))
    (message "[mementum] Decay: %d decayed, %d archived" decayed archived)))

(defun gptel-mementum-check-synthesis-candidates ()
  "Check for topics with ≥3 memories and suggest synthesis.
Returns list of synthesis candidates."
  (let* ((memories-dir (expand-file-name "mementum/memories"
                                          (gptel-auto-workflow--base-dir)))
         (by-topic (make-hash-table :test 'equal))
         (candidates '()))
    (when (file-exists-p memories-dir)
      (dolist (file (directory-files memories-dir t "\\.md$"))
        (let ((slug (file-name-sans-extension (file-name-nondirectory file))))
          (dolist (topic (split-string slug "[-_]"))
            (when (> (length topic) 3)
              (puthash topic (cons file (gethash topic by-topic)) by-topic)))))
      (maphash
       (lambda (topic files)
         (when (>= (length files) 3)
           (push (list :topic topic :count (length files) :files files) candidates)))
       by-topic))
    (when candidates
      (message "[mementum] Synthesis candidates: %s"
               (mapcar (lambda (c) (plist-get c :topic)) candidates)))
    candidates))

(defun gptel-mementum-weekly-job ()
  "Weekly mementum maintenance: decay + index rebuild + synthesis check."
  (interactive)
  (message "[mementum] Starting weekly maintenance...")
  (gptel-mementum-build-index)
  (gptel-mementum-decay-skills)
  (let ((candidates (gptel-mementum-check-synthesis-candidates)))
    (when candidates
      (message "[mementum] Synthesis candidates found: %d" (length candidates))))
  (message "[mementum] Weekly maintenance complete."))

(provide 'gptel-tools-agent)

;;; gptel-tools-agent.el ends here
