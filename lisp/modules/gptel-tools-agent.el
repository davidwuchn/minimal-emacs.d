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

(defvar my/gptel--subagent-temp-files nil
  "List of temp files created by subagent results.")

(defvar my/gptel--subagent-cache (make-hash-table :test 'equal)
  "Hash table for caching subagent results.
Keys are (agent-type prompt-hash), values are (timestamp . result).")

(defcustom my/gptel-subagent-model nil
  "Model to use for delegated subagents.
DEPRECATED: Subagents now use their YAML model: field. This variable is ignored."
  :type '(choice (const :tag "Same as parent" nil) symbol)
  :group 'gptel-tools-agent)

(eval-and-compile
  (require 'gptel nil t)
  (require 'gptel-agent nil t))

(require 'gptel-ext-fsm-utils)

;;; Subagent Result Cache

(defun my/gptel--subagent-cache-key (agent-type prompt)
  "Generate cache key for (AGENT-TYPE, PROMPT)."
  (list agent-type (md5 prompt)))

(defun my/gptel--subagent-cache-get (agent-type prompt)
  "Get cached result for (AGENT-TYPE, PROMPT) if still valid.
Returns nil if cache disabled, not found, or expired."
  (when (> my/gptel-subagent-cache-ttl 0)
    (let* ((key (my/gptel--subagent-cache-key agent-type prompt))
           (cached (gethash key my/gptel--subagent-cache)))
      (when cached
        (let ((timestamp (car cached))
              (result (cdr cached)))
          (if (> (- (float-time) timestamp) my/gptel-subagent-cache-ttl)
              (progn (remhash key my/gptel--subagent-cache) nil)
            result))))))

(defun my/gptel--subagent-cache-put (agent-type prompt result)
  "Cache RESULT for (AGENT-TYPE, PROMPT)."
  (when (> my/gptel-subagent-cache-ttl 0)
    (let ((key (my/gptel--subagent-cache-key agent-type prompt)))
      (puthash key (cons (float-time) result) my/gptel--subagent-cache))))

(defun my/gptel--subagent-cache-clear ()
  "Clear all cached subagent results."
  (interactive)
  (clrhash my/gptel--subagent-cache)
  (message "Subagent cache cleared."))


;; PATCH: Override gptel-agent--task to add tracking-marker for parent buffer
;; position and large-result truncation.  Uses non-streaming mode (matching
;; upstream) so the callback receives complete responses.

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
                              :stream nil)  ; Non-streaming for reliability
                        (cdr (assoc agent-type gptel-agent--agents))))
         (syms (cons 'gptel--preset (gptel--preset-syms preset)))
         (vals (mapcar (lambda (sym) (if (boundp sym) (symbol-value sym) nil)) syms)))
    (cl-progv syms vals
      (gptel--apply-preset preset)
      (let* ((parent-fsm (my/gptel--coerce-fsm gptel--fsm-last))
             (info (and parent-fsm (gptel-fsm-info parent-fsm)))
              (parent-buf (plist-get info :buffer))
              (where (or (plist-get info :tracking-marker)
                         (plist-get info :position)))
             (tracking-marker (let ((m (copy-marker where)))
                                (set-marker-insertion-type m t)
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
        (push temp-file my/gptel--subagent-temp-files)
        (when (> my/gptel-subagent-temp-file-ttl 0)
          (run-at-time my/gptel-subagent-temp-file-ttl nil
                       (lambda (f)
                         (when (file-exists-p f)
                           (delete-file f))
                         (setq my/gptel--subagent-temp-files
                               (delete f my/gptel--subagent-temp-files)))
                       temp-file))
        (funcall callback trunc-msg))
    (funcall callback result)))

(with-eval-after-load 'gptel-agent-tools
  (advice-add 'gptel-agent--task :override #'my/gptel-agent--task-override))

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





(defcustom my/gptel-subagent-backend nil
  "Backend for delegated subagents.
DEPRECATED: Subagents now use their YAML model: field and inherit backend from parent. This variable is ignored."
  :type '(choice (const :tag "Same as parent" nil) variable)
  :group 'gptel-tools-agent)

;;; Internal Variables

(defvar my/gptel--in-subagent-task nil
  "Non-nil while inside a `gptel-agent--task' call.")

;;; Context Builder

(defun my/gptel--build-subagent-context (prompt files include-history include-diff &optional origin-buf)
  "Package context for a subagent payload.
Appends contents of FILES, git diff if INCLUDE-DIFF, and recent buffer history
if INCLUDE-HISTORY to the base PROMPT.

ORIGIN-BUF is the parent chat buffer to read history from.  Defaults to
`current-buffer' if not provided, but callers should always pass it
explicitly to avoid capturing the wrong buffer."
  (let ((context ""))
    (when (and files (sequencep files))
      (let ((file-context ""))
        (cl-loop for f in (append files nil) do
                 (let ((filepath (expand-file-name f)))
                   (if (file-readable-p filepath)
                       (with-temp-buffer
                         (insert-file-contents filepath)
                         (setq file-context (concat file-context (format "<file path=\"%s\">\n%s\n</file>\n" f (buffer-string)))))
                     (setq file-context (concat file-context (format "<file path=\"%s\">\n[Error: File not found or not readable]\n</file>\n" f))))))
        (when (not (string-empty-p file-context))
          (setq context (concat context "<files>\n" file-context "</files>\n\n")))))

    (when include-diff
      (let* ((default-directory (or (and (fboundp 'project-current)
                                         (project-current)
                                         (project-root (project-current)))
                                    default-directory))
             (diff-out (with-temp-buffer
                         (call-process "git" nil t nil "diff" "HEAD")
                         (buffer-string))))
        (when (not (string-empty-p diff-out))
          (setq context (concat context "<git_diff>\n" diff-out "\n</git_diff>\n\n")))))

    (when include-history
      (let* ((src-buf (or (and (buffer-live-p origin-buf) origin-buf)
                          (current-buffer)))
             (history-text (with-current-buffer src-buf
                             (buffer-substring-no-properties
                              (max (point-min) (- (point-max) 8000))
                              (point-max)))))
        (when (not (string-empty-p history-text))
          (setq context (concat context "<parent_conversation_history>\n" history-text "\n</parent_conversation_history>\n\n")))))

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
                (when (buffer-live-p origin-buf)
                  (with-current-buffer origin-buf
                    (setq-local gptel--fsm-last parent-fsm))
                  (setq-local gptel--fsm-last parent-fsm))
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
                 (when (buffer-live-p origin-buf)
                   (with-current-buffer origin-buf
                     (setq-local gptel--fsm-last parent-fsm)))
                 (funcall callback
                          (format "Error: Task \"%s\" (%s) timed out after %ds."
                                  description agent-type my/gptel-agent-task-timeout)))))))

    (gptel-agent--task wrapped-cb agent-type description packaged-prompt)))

(cl-defun my/gptel--run-agent-tool (callback agent-name description prompt &optional files include-history include-diff)
  "Run a gptel-agent agent by name.

AGENT-NAME must exist in `gptel-agent--agents`."
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
  (my/gptel--agent-task-with-timeout callback agent-name description prompt files include-history include-diff))

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
              :description "Set to \"true\" to inject recent conversation history into subagent context.")
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
                                               'face '(:inherit bold :inherit warning))))
                     (_ (concat "○ " (plist-get todo :content)))))
                 todos "\n"))
               (todo-display
                (concat
                 (unless (= (char-before (overlay-end existing-ov)) 10) "\n")
                 gptel-agent--hrule
                 (propertize "Task list: [ "
                             'face '(:inherit font-lock-comment-face :inherit bold))
                 (propertize "TAB to toggle display ]\n" 'face 'font-lock-comment-face)
                 formatted-todos "\n"
                 gptel-agent--hrule)))
          (overlay-put existing-ov 'after-string todo-display)
          t)
      (funcall orig todos))))

(with-eval-after-load 'gptel-agent-tools
  (advice-add 'gptel-agent--write-todo :around #'my/gptel-agent--write-todo-around))

;;; Footer

(provide 'gptel-tools-agent)

;;; gptel-tools-agent.el ends here
