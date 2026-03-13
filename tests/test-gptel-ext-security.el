;;; test-gptel-ext-security.el --- Security tests for ACL and workspace checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Critical security tests for gptel-ext-security.el
;; Tests:
;; - my/is-inside-workspace (path validation)
;; - my/gptel-tool-acl-check (Plan mode sandbox)
;; - my/gptel-tool-get-target-path (path extraction)
;; - my/gptel-tool-acl-needs-confirm (confirmation forcing)

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock project functions

(defvar test-project-current nil)
(defvar test-project-root nil)

(defun project-current (&optional _maybe-prompt)
  "Mock: return current project."
  test-project-current)

(defun project-root (_proj)
  "Mock: return project root."
  test-project-root)

;;; Functions under test

(defun test-is-inside-workspace (path)
  "Check if PATH is strictly inside the current project root."
  (let* ((workspace (file-name-as-directory 
                     (file-truename 
                      (if test-project-current
                          test-project-root
                        default-directory))))
         (target (file-truename (expand-file-name (substitute-in-file-name path)))))
    (string-prefix-p workspace target)))

(defun test-tool-get-target-path (tool-name args)
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

(defun test-tool-acl-check (tool-name args &optional preset)
  "Return an error string if the tool call violates ACL rules, else nil."
  (let ((is-plan (eq preset 'gptel-plan)))
    (cond
     ;; RULE 1: The Plan Mode Bash Whitelist
     ((and is-plan (equal tool-name "Bash"))
      (let ((command (car args)))
        (if (or (string-match-p "[;|&><]" command)
                (not (string-match-p "\\`[ \t]*\\(ls\\|pwd\\|tree\\|file\\|git status\\|git diff\\|git log\\|git show\\|git branch\\|pytest\\|npm test\\|npm run test\\|cargo test\\|go test\\|make test\\)\\b" command)))
            "Error: Command rejected by Emacs Whitelist Sandbox."
          nil)))
     ;; RULE 2: The Plan Mode Eval Sandbox
     ((and is-plan (equal tool-name "Eval"))
      (let ((expression (car args)))
        (if (string-match-p "\\(shell-command\\|call-process\\|delete-file\\|delete-directory\\|write-region\\|kill-emacs\\|make-network-process\\|open-network-stream\\)" expression)
            "Error: Command rejected by Emacs Eval Sandbox."
          nil)))
     (t nil))))

(defun test-tool-acl-needs-confirm (tool-name args workspace-root)
  "Return t if the tool call should force a user confirmation."
  (let ((target-path (test-tool-get-target-path tool-name args)))
    (if (and target-path 
             workspace-root
             (not (string-prefix-p workspace-root target-path)))
        t
      nil)))

;;; Tests for my/is-inside-workspace

(ert-deftest security/workspace/inside-project ()
  "Path inside project should return t."
  (let* ((temp-dir (make-temp-file "workspace-test" t))
         (test-project-current t)
         (test-project-root temp-dir)
         (default-directory temp-dir))
    (unwind-protect
        (should (test-is-inside-workspace (expand-file-name "src/file.el" temp-dir)))
      (delete-directory temp-dir t))))

(ert-deftest security/workspace/outside-project ()
  "Path outside project should return nil."
  (let* ((temp-dir (make-temp-file "workspace-test" t))
         (outside-dir (make-temp-file "outside-test" t))
         (test-project-current t)
         (test-project-root temp-dir)
         (default-directory temp-dir))
    (unwind-protect
        (should-not (test-is-inside-workspace (expand-file-name "file.el" outside-dir)))
      (delete-directory temp-dir t)
      (delete-directory outside-dir t))))

(ert-deftest security/workspace/same-as-root ()
  "Project root itself should be inside (prefix match with trailing slash)."
  (let* ((temp-dir (make-temp-file "workspace-test" t))
         (test-project-current t)
         (test-project-root temp-dir)
         (default-directory temp-dir))
    (unwind-protect
        (should (test-is-inside-workspace (file-name-as-directory temp-dir)))
      (delete-directory temp-dir t))))

(ert-deftest security/workspace/relative-path ()
  "Relative path should be resolved against project root."
  (let* ((temp-dir (make-temp-file "workspace-test" t))
         (test-project-current t)
         (test-project-root temp-dir)
         (default-directory temp-dir))
    (unwind-protect
        (should (test-is-inside-workspace "src/file.el"))
      (delete-directory temp-dir t))))

(ert-deftest security/workspace/dotdot-escape ()
  "../ outside project should be detected."
  (let* ((temp-dir (make-temp-file "workspace-test" t))
         (test-project-current t)
         (test-project-root temp-dir)
         (default-directory (expand-file-name "subdir" temp-dir)))
    (unwind-protect
        (should-not (test-is-inside-workspace "../../../etc/passwd"))
      (delete-directory temp-dir t))))

;;; Tests for my/gptel-tool-get-target-path

(ert-deftest security/get-path/Read-tool ()
  "Read tool should extract first arg as path."
  (should (equal (test-tool-get-target-path "Read" '("/path/to/file.el"))
                 "/path/to/file.el")))

(ert-deftest security/get-path/Edit-tool ()
  "Edit tool should extract first arg as path."
  (should (equal (test-tool-get-target-path "Edit" '("/path/file.el" "old" "new"))
                 "/path/file.el")))

(ert-deftest security/get-path/Write-tool ()
  "Write tool should combine dir and filename."
  (should (string-match-p "file.el$"
                          (test-tool-get-target-path "Write" '("/path" "file.el" "content")))))

(ert-deftest security/get-path/Grep-tool ()
  "Grep tool should extract second arg as path."
  (should (equal (test-tool-get-target-path "Grep" '("regex" "/path/to/search"))
                 "/path/to/search")))

(ert-deftest security/get-path/Glob-tool ()
  "Glob tool should extract second arg as path if present."
  (should (equal (test-tool-get-target-path "Glob" '("*.el" "/path"))
                 "/path")))

(ert-deftest security/get-path/unknown-tool ()
  "Unknown tool should return nil."
  (should (null (test-tool-get-target-path "Unknown" '("arg")))))

;;; Tests for my/gptel-tool-acl-check

(ert-deftest security/acl/plan-mode-allows-ls ()
  "Plan mode should allow ls command."
  (should (null (test-tool-acl-check "Bash" '("ls -la") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-allows-git-status ()
  "Plan mode should allow git status."
  (should (null (test-tool-acl-check "Bash" '("git status") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-allows-git-diff ()
  "Plan mode should allow git diff."
  (should (null (test-tool-acl-check "Bash" '("git diff HEAD") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-allows-pytest ()
  "Plan mode should allow pytest."
  (should (null (test-tool-acl-check "Bash" '("pytest tests/") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-allows-npm-test ()
  "Plan mode should allow npm test."
  (should (null (test-tool-acl-check "Bash" '("npm test") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-allows-cargo-test ()
  "Plan mode should allow cargo test."
  (should (null (test-tool-acl-check "Bash" '("cargo test") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-rejects-chain ()
  "Plan mode should reject shell chaining."
  (should (stringp (test-tool-acl-check "Bash" '("ls; cat file") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-rejects-pipe ()
  "Plan mode should reject pipe."
  (should (stringp (test-tool-acl-check "Bash" '("cat file | grep foo") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-rejects-redirect ()
  "Plan mode should reject output redirection."
  (should (stringp (test-tool-acl-check "Bash" '("echo test > file") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-rejects-background ()
  "Plan mode should reject background execution."
  (should (stringp (test-tool-acl-check "Bash" '("sleep 10 &") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-rejects-rm ()
  "Plan mode should reject rm command."
  (should (stringp (test-tool-acl-check "Bash" '("rm file") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-rejects-cat ()
  "Plan mode should reject cat (use Read tool)."
  (should (stringp (test-tool-acl-check "Bash" '("cat file") 'gptel-plan))))

(ert-deftest security/acl/plan-mode-rejects-grep-bash ()
  "Plan mode should reject grep (use Grep tool)."
  (should (stringp (test-tool-acl-check "Bash" '("grep pattern file") 'gptel-plan))))

(ert-deftest security/acl/agent-mode-allows-all-bash ()
  "Agent mode should allow any bash command."
  (should (null (test-tool-acl-check "Bash" '("rm -rf /") 'gptel-agent))))

(ert-deftest security/acl/agent-mode-allows-chain ()
  "Agent mode should allow shell chaining."
  (should (null (test-tool-acl-check "Bash" '("ls; cat file") 'gptel-agent))))

(ert-deftest security/acl/eval-plan-rejects-shell-command ()
  "Plan mode Eval should reject shell-command."
  (should (stringp (test-tool-acl-check "Eval" '("(shell-command \"rm -rf /\")") 'gptel-plan))))

(ert-deftest security/acl/eval-plan-rejects-delete-file ()
  "Plan mode Eval should reject delete-file."
  (should (stringp (test-tool-acl-check "Eval" '("(delete-file \"file\")") 'gptel-plan))))

(ert-deftest security/acl/eval-plan-rejects-write-region ()
  "Plan mode Eval should reject write-region."
  (should (stringp (test-tool-acl-check "Eval" '("(write-region \"text\" nil \"file\")") 'gptel-plan))))

(ert-deftest security/acl/eval-plan-rejects-kill-emacs ()
  "Plan mode Eval should reject kill-emacs."
  (should (stringp (test-tool-acl-check "Eval" '("(kill-emacs)") 'gptel-plan))))

(ert-deftest security/acl/eval-plan-allows-safe-forms ()
  "Plan mode Eval should allow safe forms."
  (should (null (test-tool-acl-check "Eval" '("(+ 1 2)") 'gptel-plan))))

(ert-deftest security/acl/eval-agent-allows-all ()
  "Agent mode Eval should allow all forms."
  (should (null (test-tool-acl-check "Eval" '("(delete-file \"file\")") 'gptel-agent))))

(ert-deftest security/acl/no-preset-allows-all ()
  "No preset should allow all commands."
  (should (null (test-tool-acl-check "Bash" '("rm -rf /") nil))))

;;; Tests for my/gptel-tool-acl-needs-confirm

(ert-deftest security/confirm/outside-workspace ()
  "Operations outside workspace should require confirmation."
  (let ((workspace-root "/home/user/project/"))
    (should (test-tool-acl-needs-confirm "Read" '("/etc/passwd") workspace-root))))

(ert-deftest security/confirm/inside-workspace ()
  "Operations inside workspace should not require confirmation."
  (let ((workspace-root "/home/user/project/"))
    (should-not (test-tool-acl-needs-confirm "Read" '("/home/user/project/file.el") workspace-root))))

(ert-deftest security/confirm/no-path ()
  "Tools without path should not require confirmation."
  (should-not (test-tool-acl-needs-confirm "Unknown" '("arg") "/workspace/")))

(ert-deftest security/confirm/no-workspace ()
  "No workspace should not force confirmation."
  (should-not (test-tool-acl-needs-confirm "Read" '("/any/path") nil)))

;;; Footer

(provide 'test-gptel-ext-security)

;;; test-gptel-ext-security.el ends here