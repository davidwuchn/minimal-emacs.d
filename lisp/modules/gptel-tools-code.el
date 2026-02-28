;;; gptel-tools-code.el --- Unified Code tools for gptel-agent -*- lexical-binding: t -*-

(require 'gptel)
(require 'treesit-agent-tools)
(require 'treesit-agent-tools-workspace)
(require 'flymake)
(require 'project)
(require 'eglot)
(require 'xref)

(defun my/gptel--lsp-active-p ()
  "Check if an LSP server is active for the current buffer."
  (and (fboundp 'eglot-current-server)
       (eglot-current-server)))

(defun my/gptel--find-usages (symbol-name)
  "Find all usages of SYMBOL-NAME in the current project.
Tries LSP references first, falls back to ripgrep.
Includes retry logic for LSP startup race conditions."
  (let* ((proj (project-current))
         (root (if proj (project-root proj) default-directory))
         (usages nil)
         (lsp-retries 3)
         (lsp-ready nil))
    ;; Try LSP first with retry logic for startup race conditions
    (when (and (my/gptel--lsp-active-p)
               (fboundp 'xref-find-references))
      ;; Wait for LSP to be fully ready (retry loop)
      (while (and (> lsp-retries 0) (not lsp-ready))
        (condition-case nil
            (progn
              (let ((refs (xref-find-references symbol-name)))
                (when refs
                  (setq lsp-ready t)
                  (setq usages
                        (mapcar (lambda (ref)
                                  (format "%s:%d: %s"
                                          (xref-location-filename (xref-item-location ref))
                                          (xref-location-line (xref-item-location ref))
                                          (xref-item-summary ref)))
                                refs)))))
          (error
           ;; LSP not ready yet, retry
           (setq lsp-retries (1- lsp-retries))
           (when (> lsp-retries 0)
             (sleep-for 0.5)))))
      ;; If LSP failed after retries, clear usages to trigger ripgrep fallback
      (unless lsp-ready
        (setq usages nil)))
    ;; Fallback to ripgrep if LSP found nothing or wasn't ready
    (unless usages
      (let ((grepper (executable-find "rg")))
        (if (not grepper)
            (setq usages (list (format "Error: ripgrep (rg) not found in PATH.\nInstall with: brew install ripgrep  (macOS)\n                 apt install ripgrep    (Ubuntu)")))
          (with-temp-buffer
            (let ((exit-code (call-process grepper nil t nil
                                           "-n" "-F" symbol-name
                                           (expand-file-name root))))
              (when (= exit-code 0)
                (goto-char (point-min))
                (setq usages nil)
                (while (not (eobp))
                  (let ((line (buffer-substring-no-properties
                               (line-beginning-position)
                               (line-end-position))))
                    (when (not (string-match-p "\\.pyc$\\|\\.elc$\\|__pycache__" line))
                      (push line usages)))
                  (forward-line 1))))))))
    (if usages
        (format "Found %d usages of '%s':\n\n%s"
                (length usages)
                symbol-name
                (string-join (nreverse usages) "\n"))
      (format "No usages found for '%s' in %s" symbol-name root))))

(defun my/gptel--run-fallback-linter (dir)
  "Run a fallback linter (flake8, eslint, etc) if LSP is not available in DIR."
  (let ((default-directory dir))
    (cond
     ((file-exists-p "package.json")
      (let ((res (shell-command-to-string "npm run lint --silent 2>/dev/null || npx eslint . 2>/dev/null")))
        (if (string-empty-p (string-trim res)) "No linter errors (ESLint)" res)))
     ((or (file-exists-p "pyproject.toml") (file-exists-p "setup.py") (directory-files dir nil "\\.py\\'"))
      (let ((res (shell-command-to-string "ruff check . 2>/dev/null || flake8 . 2>/dev/null")))
        (if (string-empty-p (string-trim res)) "No linter errors (Python)" res)))
     ((file-exists-p "Cargo.toml")
      (let ((res (shell-command-to-string "cargo check 2>&1")))
        res))
     (t "No LSP server and no standard fallback linter detected for this project."))))

(defun gptel-tools-code-register ()
  "Register the unified Code tools with gptel."
  (when (fboundp 'gptel-make-tool)
    
    (gptel-make-tool
     :name "Code_Map"
     :description "Get a high-level outline of all functions and classes defined in a file. \
Always use this first to understand the structure of a file before editing."
     :function (lambda (file_path)
                 (condition-case err
                     (with-timeout (5 (format "Error: Code_Map timed out after 5 seconds on %s" file_path))
                       (with-current-buffer (find-file-noselect file_path)
                         (let ((map (treesit-agent-get-file-map)))
                           (if map
                               (format "File map for %s:\n%s" file_path (string-join map "\n"))
                             (format "Could not generate file map for %s. Is tree-sitter enabled?" file_path)))))
                   (error (let ((msg (error-message-string err)))
                            (cond
                             ((string-match-p "treesit" msg)
                              (format "Error: tree-sitter parser not installed for this file type.\n\nTo fix: M-x treesit-install-language-grammar RET <language> RET\n\nOriginal error: %s" msg))
                             ((string-match-p "parser" msg)
                              (format "Error: No tree-sitter parser available for this file.\n\nTo fix: M-x treesit-install-language-grammar RET <language> RET\n\nOriginal error: %s" msg))
                             (t (format "Error executing Code_Map on %s: %s" file_path msg)))))))
     :args (list '(:name "file_path" :type string :description "Path to the file to map"))
     :category "gptel-agent"
     :include t)

    (gptel-make-tool
     :name "Code_Inspect"
     :description "Extract the exact, perfectly balanced code block for a specific function or class by name. \
If file_path is omitted, it will search the entire project to find the definition automatically."
     :function (lambda (node_name &optional file_path)
                 (condition-case err
                     (with-timeout (10 (format "Error: Code_Inspect timed out for '%s'" node_name))
                       (if file_path
                           (with-current-buffer (find-file-noselect file_path)
                             (let ((text (treesit-agent-extract-node node_name)))
                               (if text
                                   (format "Code block '%s' from %s:\n\n%s" node_name file_path text)
                                 (format "Error: Could not find node named '%s' in %s.\n\nTIP: Use Code_Map first to see available symbols in the file." node_name file_path))))
                         ;; Search workspace if no file provided
                         (let ((result (treesit-agent-find-workspace node_name)))
                           (if (string-match-p "ripgrep.*not found\\|executable.*rg" result)
                               (concat result "\n\nTo fix: Install ripgrep (rg):\n  macOS: brew install ripgrep\n  Ubuntu: apt install ripgrep\n  Or provide file_path to search a specific file.")
                             result))))
                   (error (let ((msg (error-message-string err)))
                            (cond
                             ((string-match-p "treesit" msg)
                              (format "Error: tree-sitter parser not installed.\n\nTo fix: M-x treesit-install-language-grammar RET <language> RET\n\nOriginal error: %s" msg))
                             ((string-match-p "ripgrep\\|rg" msg)
                              (concat msg "\n\nTo fix: Install ripgrep (rg):\n  macOS: brew install ripgrep\n  Ubuntu: apt install ripgrep\n  Check: rg --version"))
                             (t (format "Error executing Code_Inspect: %s" msg)))))))
     :args (list '(:name "node_name" :type string :description "Exact name of the function/class to read")
                 '(:name "file_path" :type string :optional t :description "Path to the file (optional)"))
     :category "gptel-agent"
     :include t)

    (gptel-make-tool
     :name "Code_Replace"
     :description "Surgically replace an exact function or class by name with new code. \
GUARANTEES perfectly balanced parentheses/brackets. You MUST use this instead of standard Edit when modifying existing functions."
     :function (lambda (file_path node_name new_code)
                 (condition-case err
                     (with-timeout (5 (format "Error: Code_Replace timed out on %s" file_path))
                       (with-current-buffer (find-file-noselect file_path)
                         (if (treesit-agent-replace-node node_name new_code)
                             (progn
                               (save-buffer)
                               (format "Successfully replaced '%s' in %s" node_name file_path))
                           (format "Error: Could not find node named '%s' to replace in %s" node_name file_path))))
                   (error (format "Error executing Code_Replace on %s: %s" file_path (error-message-string err)))))
     :args (list '(:name "file_path" :type string :description "Path to the file")
                 '(:name "node_name" :type string :description "Exact name of the function/class to replace")
                 '(:name "new_code" :type string :description "The perfectly balanced replacement code snippet"))
     :category "gptel-agent"
     :confirm t
     :include t)

     (gptel-make-tool
     :name "Code_Check"
     :description "Get project-wide diagnostics/errors. Automatically tries LSP, and falls back to CLI linters if LSP is unavailable."
     :function (lambda ()
                 (if (not (fboundp 'flymake--project-diagnostics))
                     "Error: flymake--project-diagnostics not available.\n\nThis usually means Flymake is not initialized. Try opening a source file first."
                   (let* ((proj (project-current))
                          (dir (if proj (project-root proj) default-directory))
                          (lsp-active (my/gptel--lsp-active-p))
                          (diags (and proj (flymake--project-diagnostics proj))))
                     (if (not diags)
                         (if lsp-active
                             "No compiler or LSP diagnostics found for the current project. (LSP server is running, code is clean)."
                           ;; Fallback to CLI linter if no LSP
                           (concat "Note: No LSP server running for this project.\nFalling back to CLI linter:\n\n"
                                   (my/gptel--run-fallback-linter dir)))
                       (let ((formatted
                              (mapcar (lambda (d)
                                        (let ((buf (flymake-diagnostic-buffer d))
                                              (text (flymake-diagnostic-text d))
                                              (type (flymake-diagnostic-type d))
                                              (beg (flymake-diagnostic-beg d)))
                                          (with-current-buffer buf
                                            (save-excursion
                                              (goto-char beg)
                                              (format "%s:%d [%s] %s"
                                                      (buffer-file-name buf)
                                                      (line-number-at-pos)
                                                      type text)))))
                                      diags)))
                         (string-join formatted "\n"))))))
     :args nil
     :category "gptel-agent"
     :include t)

    (gptel-make-tool
     :name "Code_Usages"
     :description "Find all usages/references of a symbol across the project. Tries LSP first, falls back to ripgrep."
     :function (lambda (node_name)
                 (condition-case err
                     (with-timeout (10 (format "Error: Code_Usages timed out for '%s'" node_name))
                       (let ((result (my/gptel--find-usages node_name)))
                         (if (string-match-p "ripgrep.*not found\\|executable.*rg" result)
                             (concat result "\n\nTIP: Or provide file_path to Code_Inspect to search a specific file instead.")
                           result)))
                   (error (format "Error executing Code_Usages: %s" (error-message-string err)))))
     :args (list '(:name "node_name" :type string :description "Symbol/function/class name to find usages for"))
     :category "gptel-agent"
     :include t)))

;; Register tool previews
(when (boundp 'gptel--tool-preview-alist)
  (defun gptel-tools-code--replace-preview-setup (arg-values _info)
    "Setup diff preview for Code_Replace tool."
    (pcase-let ((from (point))
                (`(,path ,node-name ,new-code) arg-values))
      (insert
       "(" (propertize "Code_Replace " 'font-lock-face 'font-lock-keyword-face)
       (propertize (concat "\"" (file-name-nondirectory path) "\"") 'font-lock-face 'font-lock-constant-face)
       " " (propertize (concat "\"" node-name "\"") 'font-lock-face 'font-lock-string-face)
       ")\n")
      
      (let* ((full-path (expand-file-name path))
             (old-code (when (file-readable-p full-path)
                        (with-current-buffer (find-file-noselect full-path)
                          (treesit-agent-extract-node node-name)))))
        (if old-code
            (insert
             (propertize old-code 'font-lock-face 'diff-removed
                         'line-prefix (propertize "-" 'face 'diff-removed))
             "\n"
             (propertize new-code 'font-lock-face 'diff-added
                         'line-prefix (propertize "+" 'face 'diff-added))
             "\n")
          (insert
           (propertize new-code 'font-lock-face 'font-lock-string-face)
           "\n")))
           
      (font-lock-append-text-property
       from (1- (point)) 'font-lock-face (if (fboundp 'gptel-agent--block-bg) (gptel-agent--block-bg) 'default))
      (when (fboundp 'gptel-agent--confirm-overlay)
        (gptel-agent--confirm-overlay from (point) t))))
        
  (setf (alist-get "Code_Replace" gptel--tool-preview-alist nil nil #'equal)
        #'gptel-tools-code--replace-preview-setup))

(provide 'gptel-tools-code)
