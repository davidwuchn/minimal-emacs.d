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

;; ==============================================================================
;; TOOL SECURITY & ROUTING (NUCLEUS HYBRID SANDBOX)
;; ==============================================================================

(defun my/is-inside-workspace (path)
  "Check if PATH is strictly inside the current project root."
  (let* ((workspace (file-name-as-directory (file-truename (if-let ((proj (and (featurep 'project) (project-current nil)))) (project-root proj) default-directory))))
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
    ("Preview" (nth 0 args))
    (_ nil)))

(defun my/gptel-tool-acl-check (tool-name args)
  "Return an error string if the tool call violates ACL rules, else nil."
  (let* ((preset (and (boundp 'gptel--preset) gptel--preset))
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

(provide 'gptel-ext-security)
;;; gptel-ext-security.el ends here
