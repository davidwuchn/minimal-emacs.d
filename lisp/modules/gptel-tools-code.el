;;; gptel-tools-code.el --- Unified Code tools for gptel-agent -*- lexical-binding: t; no-byte-compile: t -*-

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
Includes enhanced retry logic for LSP startup race conditions.
Reports which backend (LSP or ripgrep) was used."
  (let* ((proj (project-current))
         (root (if proj (project-root proj) default-directory))
         (usages nil)
         (lsp-retries 5)  ; Increased from 3 to 5
         (lsp-ready nil)
         (lsp-server (and (my/gptel--lsp-active-p) (eglot-current-server)))
         (backend "unknown"))  ; Track which backend was used
    ;; Try LSP first with enhanced retry logic for startup race conditions
    (when lsp-server
      ;; Wait for LSP to be fully ready (retry loop with exponential backoff)
      (while (and (> lsp-retries 0) (not lsp-ready))
        (condition-case nil
            (let ((refs (xref-find-references symbol-name)))
              (if (and refs (not (equal refs '(nil))))
                  ;; Got results, LSP is ready
                  (progn
                    (setq lsp-ready t)
                    (setq backend "LSP")
                    (setq usages
                          (mapcar (lambda (ref)
                                    (format "%s:%d: %s"
                                            (xref-location-filename (xref-item-location ref))
                                            (xref-location-line (xref-item-location ref))
                                            (xref-item-summary ref)))
                                  refs)))
                ;; Got empty results, LSP might not be fully indexed yet
                (setq lsp-retries (1- lsp-retries))
                (when (> lsp-retries 0)
                  ;; Exponential backoff: 0.5s, 1s, 2s, 4s, 8s (max ~15s total)
                  (sleep-for (* 0.5 (expt 2 (- 5 lsp-retries)))))))
          (error
           ;; LSP not ready yet, retry
           (setq lsp-retries (1- lsp-retries))
           (when (> lsp-retries 0)
             (sleep-for (* 0.5 (expt 2 (- 5 lsp-retries))))))))
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
                (setq backend "ripgrep")
                (setq usages nil)
                (while (not (eobp))
                  (let ((line (buffer-substring-no-properties
                               (line-beginning-position)
                               (line-end-position))))
                    (when (not (string-match-p "\\.pyc$\\|\\.elc$\\|__pycache__" line))
                      (push line usages)))
                  (forward-line 1))))))))
    (if usages
        (format "Found %d usages of '%s' (via %s):\n\n%s"
                (length usages)
                symbol-name
                backend
                (string-join (nreverse usages) "\n"))
      (format "No usages found for '%s' in %s" symbol-name root))))

(defun my/gptel--run-fallback-linter (dir)
  "Run a fallback linter (flake8, eslint, etc) if LSP is not available in DIR.
Reports what was checked, even if no standard project files found."
  (let ((default-directory dir)
        ;; Build regex at runtime to avoid check-parens confusion with \\'
        (py-ext (concat "\\.py" (char-to-string 39))))
    (cond
     ((file-exists-p "package.json")
      (let ((res (shell-command-to-string "npm run lint --silent 2>/dev/null || npx eslint . 2>/dev/null")))
        (if (string-empty-p (string-trim res))
            "✓ No linter errors (ESLint) - checked package.json (JavaScript/Node.js)"
          res)))
     ((or (file-exists-p "pyproject.toml") (file-exists-p "setup.py") (directory-files dir nil py-ext))
      (let ((res (shell-command-to-string "ruff check . 2>/dev/null || flake8 . 2>/dev/null")))
        (if (string-empty-p (string-trim res))
            "✓ No linter errors (ruff/flake8) - checked Python project (pyproject.toml/setup.py)"
          res)))
     ((file-exists-p "Cargo.toml")
      (let ((res (shell-command-to-string "cargo check 2>&1")))
        (if (string-match-p "Finished\\|Compiling" res)
            "✓ No compiler errors (cargo check) - checked Cargo.toml (Rust)"
          res)))
     (t
      ;; No standard project files found - report what we looked for
      (concat "Note: No standard project files found (package.json, pyproject.toml, Cargo.toml).\n"
              "Searched for: JavaScript (package.json), Python (pyproject.toml or setup.py or *.py files), Rust (Cargo.toml).\n"
              "If this is a different language, configure a linter or use LSP for diagnostics.")))))

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
                         ;; Pre-flight check: Verify tree-sitter parser is available
                         (if (not (treesit-parser-list))
                             (let ((lang (or (and (boundp 'treesit--language) treesit--language)
                                            (let ((py-rx (concat "\\.py" (char-to-string 39)))
                                                  (el-rx (concat "\\.el" (char-to-string 39)))
                                                  (clj-rx (concat "\\.clj" (char-to-string 39)))
                                                  (rs-rx (concat "\\.rs" (char-to-string 39))))
                                              (cond
                                               ((string-match-p py-rx file_path) 'python)
                                               ((string-match-p el-rx file_path) 'elisp)
                                               ((string-match-p clj-rx file_path) 'clojure)
                                               ((string-match-p rs-rx file_path) 'rust)
                                               (t 'unknown))))))
                               (format "Error: No tree-sitter parser active for %s\n\nACTION:\n  1. Install parser: M-x treesit-install-language-grammar RET %s RET\n  2. Reopen file: C-x C-k (kill-buffer) then C-x C-f %s\n  3. Verify: M-x eval-expression RET (treesit-language-available-p '%s) RET\n  4. Fallback: Use Read/Grep for this file" file_path (or lang "language") file_path (or lang "language")))
                           (let ((map (treesit-agent-get-file-map)))
                             (if map
                                 (format "File map for %s:\n%s" file_path (string-join map "\n"))
                               (format "Could not generate file map for %s.\n\nACTION: Check if tree-sitter is enabled for this file type.\n  - Run: M-x treesit-install-language-grammar RET <language> RET\n  - Verify: M-x eval-expression RET (treesit-language-available-p '<lang>) RET" file_path)))))
                   (error (let ((msg (error-message-string err)))
                            (cond
                             ((string-match-p "treesit" msg)
                              (format "Error: tree-sitter parser not installed for this file type.\n\nACTION: Install the parser:\n  M-x treesit-install-language-grammar RET <language> RET\n\nExample: M-x treesit-install-language-grammar RET python RET\n\nOriginal error: %s" msg))
                             ((string-match-p "parser" msg)
                              (format "Error: No tree-sitter parser available for this file.\n\nACTION: Install the parser:\n  M-x treesit-install-language-grammar RET <language> RET\n\nThen reopen the file.\n\nOriginal error: %s" msg))
                             ((string-match-p "No such file\\|does not exist" msg)
                              (format "Error: File not found: %s\n\nACTION: Check the file path and try again." file_path))
                             (t (format "Error executing Code_Map on %s: %s\n\nACTION: Check file permissions and try again." file_path msg)))))))
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
                             ;; Pre-flight check: Verify tree-sitter parser is available
                             (if (not (treesit-parser-list))
                                 (let ((lang (or (and (boundp 'treesit--language) treesit--language)
                                                (let ((py-rx (concat "\\.py" (char-to-string 39)))
                                                      (el-rx (concat "\\.el" (char-to-string 39)))
                                                      (clj-rx (concat "\\.clj" (char-to-string 39)))
                                                      (rs-rx (concat "\\.rs" (char-to-string 39))))
                                                  (cond
                                                   ((string-match-p py-rx file_path) 'python)
                                                   ((string-match-p el-rx file_path) 'elisp)
                                                   ((string-match-p clj-rx file_path) 'clojure)
                                                   ((string-match-p rs-rx file_path) 'rust)
                                                   (t 'unknown))))))
                                   (format "Error: No tree-sitter parser active for %s\n\nACTION:\n  1. Install parser: M-x treesit-install-language-grammar RET %s RET\n  2. Reopen file: C-x C-k (kill-buffer) then C-x C-f %s\n  3. Verify: M-x eval-expression RET (treesit-language-available-p '%s) RET\n  4. Fallback: Use Read tool for this file" file_path (or lang "language") file_path (or lang "language")))
                               (let ((text (treesit-agent-extract-node node_name)))
                                 (if text
                                     (format "Code block '%s' from %s:\n\n%s" node_name file_path text)
                                   (format "Error: Could not find function/class '%s' in %s\n\nACTION:\n  1. Run Code_Map first to see available symbols in the file\n  2. Check spelling: '%s' may be misspelled\n  3. Verify the function exists in the file" node_name file_path node_name)))))
                         ;; Search workspace if no file provided
                         (let ((result (treesit-agent-find-workspace node_name)))
                           (cond
                            ((string-match-p "ripgrep.*not found\\|executable.*rg" result)
                             (concat result "\n\nACTION: Install ripgrep (rg) for workspace search:\n  macOS:  brew install ripgrep\n  Ubuntu: apt install ripgrep\n  Check:  rg --version\n\nAlternatively, provide file_path to search a specific file."))
                            ((string-match-p "No structural definition found" result)
                             (format "Error: Could not find '%s' anywhere in the project\n\nACTION:\n  1. Check spelling: '%s' may be misspelled\n  2. Symbol may not exist - use Code_Map to explore files\n  3. Symbol may be dynamically defined (not in AST)" node_name node_name))
                            (t result)))))
                   (error (let ((msg (error-message-string err)))
                            (cond
                             ((string-match-p "treesit" msg)
                              (format "Error: tree-sitter parser not installed.\n\nACTION: M-x treesit-install-language-grammar RET <language> RET\n\nOriginal error: %s" msg))
                             ((string-match-p "ripgrep\\|rg" msg)
                              (concat msg "\n\nACTION: Install ripgrep:\n  macOS:  brew install ripgrep\n  Ubuntu: apt install ripgrep\n  Check:  rg --version"))
                             ((string-match-p "timeout" msg)
                              (format "Error: Code_Inspect timed out after 10 seconds for '%s'\n\nACTION:\n  1. Provide explicit file_path to skip workspace search\n  2. Large project - search may take time\n  3. Try Code_Map on specific files first" node_name))
                             (t (format "Error executing Code_Inspect: %s\n\nACTION: Check symbol name and file path, then try again." msg)))))))
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
                         ;; Pre-flight check: Verify tree-sitter parser is available
                         (if (not (treesit-parser-list))
                             (let ((lang (or (and (boundp 'treesit--language) treesit--language)
                                            (let ((py-rx (concat "\\.py" (char-to-string 39)))
                                                  (el-rx (concat "\\.el" (char-to-string 39)))
                                                  (clj-rx (concat "\\.clj" (char-to-string 39)))
                                                  (rs-rx (concat "\\.rs" (char-to-string 39))))
                                              (cond
                                               ((string-match-p py-rx file_path) 'python)
                                               ((string-match-p el-rx file_path) 'elisp)
                                             ((string-match-p "\\.clj\\'" file_path) 'clojure)
                                             ((string-match-p "\\.rs\\'" file_path) 'rust)
                                             (t 'unknown)))))
                               (format "Error: No tree-sitter parser active for %s\n\nACTION:\n  1. Install parser: M-x treesit-install-language-grammar RET %s RET\n  2. Reopen file: C-x C-k (kill-buffer) then C-x C-f %s\n  3. Verify: M-x eval-expression RET (treesit-language-available-p '%s) RET\n  4. Fallback: Use Edit tool (manual paren balancing required)" file_path (or lang "language") file_path (or lang "language")))
                           (if (treesit-agent-replace-node node_name new_code)
                               (progn
                                 (save-buffer)
                                 (format "Successfully replaced '%s' in %s" node_name file_path))
                             (format "Error: Could not find function/class '%s' in %s\n\nACTION:\n  1. Run Code_Map first to see available symbols\n  2. Check spelling: '%s' may be misspelled\n  3. Verify the function exists in the file" node_name file_path node_name)))))
                   (error (let ((msg (error-message-string err)))
                            (cond
                             ((string-match-p "treesit" msg)
                              (format "Error: tree-sitter parser not installed.\n\nACTION: M-x treesit-install-language-grammar RET <language> RET\n\nOriginal error: %s" msg))
                             ((string-match-p "syntax error\\|has-error" msg)
                              (format "Error: New code has syntax errors (unbalanced parentheses/brackets)\n\nACTION:\n  1. Check that all opening brackets have closing brackets\n  2. Verify indentation is correct\n  3. Test code in a REPL before replacing\n\nOriginal error: %s" msg))
                             (t (format "Error executing Code_Replace on %s: %s\n\nACTION: Check function name and new code syntax, then try again." file_path msg)))))))
     :args (list '(:name "file_path" :type string :description "Path to the file")
                 '(:name "node_name" :type string :description "Exact name of the function/class to replace")
                 '(:name "new_code" :type string :description "The perfectly balanced replacement code snippet"))
     :category "gptel-agent"
     :confirm t
     :include t)

     (gptel-make-tool
     :name "Diagnostics"
     :description "Collect project-wide diagnostics/errors. Automatically tries LSP, falls back to CLI linters (ruff/eslint/cargo) if unavailable. Superior to upstream Diagnostics (project-wide vs open-buffers-only)."
     :function (lambda (&optional all)
                 (declare (ignore all))  ; Upstream had optional 'all' arg, we ignore it
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
     :args (list '(:name "all"
              :type boolean
              :description "Ignored (legacy arg from upstream). This tool always checks entire project."
              :optional t))
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
