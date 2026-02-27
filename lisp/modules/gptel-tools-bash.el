;;; gptel-tools-bash.el --- Async Bash tool for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Async Bash tool implementation with timeout, persistent shell, and Plan mode sandbox.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)

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

                (with-current-buffer buf (erase-buffer))

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
                (process-send-string proc (format "{ %s\n} 2>&1\necho %s:$?\n" command marker)))))
        (error (finish (format "Error: %s" (error-message-string err))))))))

;;; Tool Registration

(defun gptel-tools-bash-register ()
  "Register the Bash tool with gptel."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "Bash"
     :description "Execute a Bash command (async, interruptible, timeout). Use for git/tests/builds; not for file read/edit/search."
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
