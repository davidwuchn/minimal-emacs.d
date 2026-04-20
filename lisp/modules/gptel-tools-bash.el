;;; gptel-tools-bash.el --- Async Bash tool for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Async Bash tool implementation with timeout, persistent shell, and Plan mode sandbox.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'gptel-ext-abort)

;;; Customization

(defgroup gptel-tools-bash nil
  "Async Bash tool for gptel-agent."
  :group 'gptel)

(defcustom my/gptel-bash-timeout 60
  "Seconds before Bash tool is force-stopped.

This prevents gptel-agent subagents (e.g. executor) from hanging forever on
interactive commands like git commit."
  :type 'integer
  :group 'gptel-tools-bash)

;;; Internal Variables

(defvar my/gptel--persistent-bash-process nil
  "Persistent background bash process for gptel-agent's Bash tool.")

(defconst my/gptel--bash-context-env-prefixes
  '("AUTO_WORKFLOW_STATUS_FILE="
    "AUTO_WORKFLOW_MESSAGES_FILE="
    "AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE="
    "AUTO_WORKFLOW_EMACS_SERVER=")
  "Environment prefixes that require a fresh persistent bash context.")

(defun my/gptel--bash-context-entry-p (entry)
  "Return non-nil when ENTRY should trigger bash process recreation."
  (and (stringp entry)
       (seq-some (lambda (prefix)
                   (string-prefix-p prefix entry))
                 my/gptel--bash-context-env-prefixes)))

(defun my/gptel--bash-context-signature ()
  "Return the persistent bash context signature for the current buffer."
  (list :directory (and (stringp default-directory)
                        (file-name-as-directory
                         (expand-file-name default-directory)))
        :env (seq-filter #'my/gptel--bash-context-entry-p process-environment)))

(defun my/gptel--reset-persistent-bash ()
  "Terminate the current persistent bash process, if any."
  (when (process-live-p my/gptel--persistent-bash-process)
    (ignore-errors
      (set-process-filter my/gptel--persistent-bash-process #'ignore))
    (ignore-errors
      (set-process-sentinel my/gptel--persistent-bash-process #'ignore))
    (ignore-errors
      (delete-process my/gptel--persistent-bash-process)))
  (setq my/gptel--persistent-bash-process nil))

(defun my/gptel--safe-bash-command-p (command)
  "Check if a Bash COMMAND is safe for Plan mode.
Returns t if safe, or a string explaining why it was rejected."
  (let* ((cmd (string-trim command))
         (forbidden-chars '(">" "<" "`" "$(" "sed -i")))
    (catch 'rejected
      ;; Check forbidden syntax
      (dolist (c forbidden-chars)
        (when (string-match-p (regexp-quote c) cmd)
          (throw 'rejected (format "Contains forbidden shell feature: %s" c))))
      (when (string-match-p "\\(?:^\\|[^&]\\)&\\(?:[^&]\\|$\\)" cmd)
        (throw 'rejected "Contains forbidden backgrounding: &"))

      ;; Split and check whitelist
      (let* ((parts (split-string cmd "\\(&&\\|||\\||\\|;\\)" t "[ \t\n\r]+"))
             (whitelist '("ls" "pwd" "tree" "file" "find" "fd" "which" "type"
                          "git status" "git diff" "git log" "git show" "git branch" "git grep" "git rev-parse" "git describe" "git remote" "git tag"
                          "grep" "rg" "cat" "head" "tail" "wc" "echo" "jq" "awk" "sort" "uniq" "cut" "tr" "xargs"
                          "pytest" "npm test" "npm run test" "cargo test" "go test" "make test" "make check" "make" "cargo" "npm" "pip" "python" "node"
                          "test" "[" "true" "false" "basename" "dirname" "realpath" "readlink")))
        (dolist (part parts)
          (let* ((clean-part (string-trim part))
                 (allowed nil))
            (dolist (w whitelist)
              (let ((len (length w)))
                (when (string-prefix-p w clean-part)
                  (let ((next-char (if (> (length clean-part) len)
                                       (substring clean-part len (1+ len))
                                     " ")))
                    (when (string-match-p "[ \t\n\r]" next-char)
                      (setq allowed t))))))
            (unless allowed
              (throw 'rejected (format "Command not in read-only whitelist: %s" clean-part)))))
        t))))

;;; Internal Helpers

(defun my/gptel--ensure-persistent-bash ()
  "Create a persistent background bash process if one doesn't exist or died.
Sets `my/gptel--persistent-bash-process' to a live process with TERM=dumb.
Recreates the shell when the workflow env or working directory changes."
  (let ((signature (my/gptel--bash-context-signature)))
    (when (and (process-live-p my/gptel--persistent-bash-process)
               (not (equal signature
                           (process-get my/gptel--persistent-bash-process
                                        'my/gptel-bash-context-signature))))
      (my/gptel--reset-persistent-bash))
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
        (process-put my/gptel--persistent-bash-process
                     'my/gptel-bash-context-signature signature)
        ;; Initialize Dumb Terminal variables to prevent interactive hanging
        (process-send-string my/gptel--persistent-bash-process
                             "export TERM=dumb PAGER=cat GIT_PAGER=cat DEBIAN_FRONTEND=noninteractive PS1=''\n")
        (sleep-for 0.1)))))

(defun my/gptel--bash-process-filter (proc output marker finish-fn)
  "Process filter for gptel persistent bash.
Accumulates OUTPUT in PROC's buffer, detects the end-of-command MARKER,
truncates oversized output, and calls FINISH-FN with the result string.
Cancels the timeout timer stored on PROC via `process-get'."
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
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
                      (let ((temp-file (my/gptel-make-temp-file "bash-" nil ".txt")))
                        (with-temp-file temp-file (insert out))
                        (concat (substring out 0 (/ max-length 2))
                                (format "\n\n... [Output truncated. Result exceeded 50,000 bytes. Full output saved to: %s\nUse Grep to search the full content or Read with offset/limit to view specific sections.] ...\n\n" temp-file)
                                (substring out (- (/ max-length 2)))))
                    out))
                 (timer (process-get proc 'my/gptel-bash-timer)))
            (when timer (cancel-timer timer))
            (if (= status 0)
                (funcall finish-fn truncated-out)
              (funcall finish-fn (format "Command failed with exit code %d:\nSTDOUT+STDERR:\n%s" status truncated-out)))))))))

;;; Bash Tool Implementation

(defun my/gptel--agent-bash-async (callback command)
  "Async replacement for gptel-agent's `Bash' tool.

Provides a persistent shell state, STDOUT truncation, dumb terminal,
and a sandbox for Plan mode.

CALLBACK is called with the result string on completion."
  (let* ((origin (current-buffer))
         (gen my/gptel--abort-generation)
         (done nil)
         ;; Sandbox check: strictly read-only when in Plan mode
         (is-plan (eq (and (boundp 'gptel--preset) gptel--preset)
                      'gptel-plan)))
    (cl-labels
        ((finish (result)
           (unless done
             (setq done t)
             (cond
              ;; Normal case: buffer alive and not aborted
              ((and (buffer-live-p origin)
                    (with-current-buffer origin
                      (= gen my/gptel--abort-generation)))
               (funcall callback result))
              ;; Buffer dead: still call callback with result (caller needs to know)
              ((not (buffer-live-p origin))
               (funcall callback result))
              ;; Aborted: call callback with error so caller can proceed
              (t
               (funcall callback (format "Error: Request aborted (generation changed)\n%s"
                                         (if (string-prefix-p "Error:" result) result
                                           (concat "Partial output:\n" result)))))))))
      (condition-case err
          (progn
            (unless (and (stringp command) (not (string-empty-p (string-trim command))))
              (error "command is empty"))

            (let ((sandbox-err (and is-plan
                                    (let ((res (my/gptel--safe-bash-command-p command)))
                                      (if (stringp res) res nil)))))
              (if sandbox-err
                  (finish (format "Error: Command rejected by Sandbox. %s.\n\nTIP: For file operations, prefer native tools (`Read`, `Grep`, `Glob`) over Bash. For shell commands, use whitelisted read-only commands (git, ls, cat, grep, etc.)." sandbox-err))

                (my/gptel--ensure-persistent-bash)

              (let* ((proc my/gptel--persistent-bash-process)
                     (buf (process-buffer proc))
                     (marker (format "gptel_cmd_done_%s" (md5 (number-to-string (random))))))

                (with-current-buffer buf (erase-buffer))

                (set-process-filter proc
                                    (lambda (p output)
                                      (my/gptel--bash-process-filter p output marker #'finish)))

                (process-put proc 'my/gptel-bash-timer
                             (run-at-time
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
                (process-send-string proc (format "{ %s\n} 2>&1\necho %s:$?\n" command marker))))))
        (error (finish (format "Error: %s" (error-message-string err))))))))

;;; Tool Registration

(defun gptel-tools-bash-register ()
  "Register the Bash tool with gptel."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "Bash"
     :description "Execute a Bash command. (Note: In Plan Mode, it is sandboxed to read-only commands. In Agent Mode, it is unrestricted.)"
     :function #'my/gptel--agent-bash-async
     :async t
     :args '((:name "command"
              :type string
              :description "Bash command string."))
     :category "gptel-agent"
     :confirm t
     :include t)))

;;; Footer

(provide 'gptel-tools-bash)

;;; gptel-tools-bash.el ends here
