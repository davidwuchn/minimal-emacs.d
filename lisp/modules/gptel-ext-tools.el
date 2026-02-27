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
  (setq my/gptel-tools-readonly
        (my/gptel--dedup-tools-by-name
         (append
          (when (boundp 'my/gptel-plan-readonly-tools)
            (seq-filter #'identity (mapcar #'my/gptel--safe-get-tool my/gptel-plan-readonly-tools)))
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

  (setq my/gptel-tools-action
        (my/gptel--dedup-tools-by-name
         (append
          ;; Include all 17 gptel-agent tools
          (when (boundp 'my/gptel-agent-action-tools)
            (seq-filter #'identity (mapcar #'my/gptel--safe-get-tool my/gptel-agent-action-tools)))
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
          (when (boundp 'my/gptel-agent-action-tools)
            (seq-filter (lambda (tool)
                          (not (member (gptel-tool-name tool)
                                       my/gptel-agent-action-tools)))
                        my/gptel-tools-readonly)))))

  ;; Set the default tool list now that both lists are built.
  (setq-default gptel-tools my/gptel-tools-readonly))


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



(defgroup my/gptel-subagent nil
  "Subagent delegation settings (Agent/RunAgent tools)."
  :group 'gptel)

(defcustom my/gptel-agent-task-timeout 120
  "Seconds before a delegated Agent/RunAgent task is force-stopped.
If the subagent hasn't returned after this many seconds, the callback
is called with a timeout error."
  :type 'integer
  :group 'my/gptel-subagent)

(defcustom my/gptel-subagent-model 'qwen3.5-plus
  "Model to use for delegated subagents (Agent/RunAgent).
When non-nil, subagent requests use this model instead of the parent's.
Must be a symbol matching a model in `my/gptel-subagent-backend'."
  :type '(choice (const :tag "Same as parent" nil) symbol)
  :group 'my/gptel-subagent)

(defcustom my/gptel-subagent-backend 'gptel--dashscope
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


;; Build tool lists after gptel-agent-tools has registered all upstream tools.
;; Running these setq forms at top-level on a cold start causes every
;; my/gptel--safe-get-tool call to return nil (tools not yet registered),
;; producing incomplete lists.  Deferring to with-eval-after-load guarantees
;; the upstream registry is populated before we snapshot it.


;; --- Tool Profile Management ---
(defun gptel-set-tool-profile (profile)
  "Set active gptel tools."
  (interactive (list (intern (completing-read "Profile: " '(readonly action)))))
  (setq-local gptel-tools (if (eq profile 'action) my/gptel-tools-action my/gptel-tools-readonly))
  (message "gptel tools set to: %s" profile))

(defun gptel-toggle-tool-profile ()
  "Toggle between readonly and action profiles."
  (interactive)
  (if (eq gptel-tools my/gptel-tools-action)
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

(provide 'gptel-ext-tools)
;;; gptel-ext-tools.el ends here
