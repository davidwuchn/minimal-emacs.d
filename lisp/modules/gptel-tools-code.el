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
    ;; Try LSP first with enhanced retry logic for startup race conditions.
    ;; Uses xref-backend-references (programmatic API) instead of
    ;; xref-find-references (interactive command that pops a UI buffer).
    (when lsp-server
      ;; Wait for LSP to be fully ready (retry loop with exponential backoff)
      (while (and (> lsp-retries 0) (not lsp-ready))
        (condition-case nil
            (let* ((backend-type (xref-find-backend))
                   (refs (and backend-type
                              (xref-backend-references backend-type symbol-name))))
              (if (and refs (listp refs))
                  ;; Got results, LSP is ready
                  (progn
                    (setq lsp-ready t)
                    (setq backend "LSP")
                    (setq usages
                          (mapcar (lambda (ref)
                                    (let ((loc (xref-item-location ref)))
                                      (format "%s:%d: %s"
                                              (xref-location-group loc)
                                              (xref-location-line loc)
                                              (xref-item-summary ref))))
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
                                           "--no-ignore" "-n" "-F"
                                           "--glob" "!*.elc"
                                           "--glob" "!var/elpa/"
                                           symbol-name
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
  ;; Build regex at runtime to avoid check-parens confusion with \\
  (let ((default-directory dir)
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

(defun my/gptel--detect-treesit-language (file-path)
  "Detect tree-sitter language for FILE-PATH from extension.
Returns a symbol like \\='python, \\='elisp, etc., or \\='unknown."
  (or (and (boundp 'treesit--language) treesit--language)
      (let ((py-rx (concat "\\.py" (char-to-string 39)))
            (el-rx (concat "\\.el" (char-to-string 39)))
            (clj-rx (concat "\\.clj" (char-to-string 39)))
            (rs-rx (concat "\\.rs" (char-to-string 39))))
        (cond
         ((string-match-p py-rx file-path) 'python)
         ((string-match-p el-rx file-path) 'elisp)
         ((string-match-p clj-rx file-path) 'clojure)
         ((string-match-p rs-rx file-path) 'rust)
         (t 'unknown)))))

(defun my/gptel--treesit-error-message (msg file-path)
  "Format a user-friendly error message for tree-sitter errors.
MSG is the original error message, FILE-PATH is the file being operated on."
  (cond
   ((string-match-p "treesit" msg)
    (format "Error: tree-sitter parser not installed for this file type.\n\nACTION: Install the parser:\n  M-x treesit-install-language-grammar RET <language> RET\n\nExample: M-x treesit-install-language-grammar RET python RET\n\nOriginal error: %s" msg))
   ((string-match-p "parser" msg)
    (format "Error: No tree-sitter parser available for this file.\n\nACTION: Install the parser:\n  M-x treesit-install-language-grammar RET <language> RET\n\nThen reopen the file.\n\nOriginal error: %s" msg))
   ((string-match-p "No such file\\|does not exist" msg)
    (format "Error: File not found: %s\n\nACTION: Check the file path and try again." file-path))
   (t nil)))

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
                         (treesit-agent--ensure-parser file_path)
                         ;; Pre-flight check: Verify tree-sitter parser is available
                          (if (not (treesit-parser-list))
                              (let ((lang (my/gptel--detect-treesit-language file_path)))
                                (format "Error: No tree-sitter parser active for %s\n\nACTION:\n  1. Install parser: M-x treesit-install-language-grammar RET %s RET\n  2. Reopen file: C-x C-k (kill-buffer) then C-x C-f %s\n  3. Verify: M-x eval-expression RET (treesit-language-available-p '%s) RET\n  4. Fallback: Use Read/Grep for this file" file_path (or lang "language") file_path (or lang "language")))
                            (let ((map (treesit-agent-get-file-map)))
                              (if map
                                  (format "File map for %s:\n%s" file_path (string-join map "\n"))
                                (format "Could not generate file map for %s.\n\nACTION: Check if tree-sitter is enabled for this file type.\n  - Run: M-x treesit-install-language-grammar RET <language> RET\n  - Verify: M-x eval-expression RET (treesit-language-available-p '<lang>) RET" file_path))))))
                    (error (let* ((msg (error-message-string err))
                                  (friendly (my/gptel--treesit-error-message msg file_path)))
                             (or friendly
                                 (format "Error executing Code_Map on %s: %s\n\nACTION: Check file permissions and try again." file_path msg))))))
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
                             (treesit-agent--ensure-parser file_path)
                              ;; Pre-flight check: Verify tree-sitter parser is available
                              (if (not (treesit-parser-list))
                                  (let ((lang (my/gptel--detect-treesit-language file_path)))
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
                    (error (let* ((msg (error-message-string err))
                                  (friendly (my/gptel--treesit-error-message msg (or file_path ""))))
                             (or friendly
                                 (cond
                                  ((string-match-p "ripgrep\\|rg" msg)
                                   (concat msg "\n\nACTION: Install ripgrep:\n  macOS:  brew install ripgrep\n  Ubuntu: apt install ripgrep\n  Check:  rg --version"))
                                  ((string-match-p "timeout" msg)
                                   (format "Error: Code_Inspect timed out after 10 seconds for '%s'\n\nACTION:\n  1. Provide explicit file_path to skip workspace search\n  2. Large project - search may take time\n  3. Try Code_Map on specific files first" node_name))
                                   (t (format "Error executing Code_Inspect: %s\n\nACTION: Check symbol name and file path, then try again." msg))))))))
     :args (list '(:name "node_name" :type string :description "Exact name of the function/class to read")
                 '(:name "file_path" :type string :optional t :description "Path to the file (optional)"))
     :category "gptel-agent"
     :include t)

    ;; Tree-sitter powered replacement
    (gptel-make-tool
     :name "Code_Replace"
     :description "Surgically replace an exact function or class by name with new code. \
GUARANTEES perfectly balanced parentheses/brackets. You MUST use this instead of standard Edit when modifying existing functions."
     :function (lambda (file_path node_name new_code)
                 (condition-case err
                     (with-timeout (5 (format "Error: Code_Replace timed out on %s" file_path))
                       (with-current-buffer (find-file-noselect file_path)
                         ;; Sync buffer with disk before operating — prevents
                         ;; "changed since visited" prompts when multiple
                         ;; Code_Replace calls target the same file in sequence.
                         (when (and (buffer-file-name)
                                    (file-exists-p (buffer-file-name))
                                    (not (verify-visited-file-modtime)))
                           (revert-buffer t t t))
                         (treesit-agent--ensure-parser file_path)
                          ;; Pre-flight check: Verify tree-sitter parser is available
                          (if (not (treesit-parser-list))
                              (let ((lang (my/gptel--detect-treesit-language file_path)))
                                (format "Error: No tree-sitter parser active for %s\n\nACTION:\n  1. Install parser: M-x treesit-install-language-grammar RET %s RET\n  2. Reopen file: C-x C-k (kill-buffer) then C-x C-f %s\n  3. Verify: M-x eval-expression RET (treesit-language-available-p '%s) RET\n  4. Fallback: Use Edit tool (manual paren balancing required)" file_path (or lang "language") file_path (or lang "language")))
                           (let ((old-code (treesit-agent-extract-node node_name)))
                             ;; Guard: reject likely-truncated replacements.
                             ;; If old code is non-trivial (>5 lines) and new code
                             ;; is <20% the size, the LLM probably sent just a
                             ;; signature without the body.
                             (if (and old-code
                                      (> (length old-code) 200)
                                      (< (length new_code) (* 0.2 (length old-code))))
                                 (format "Error: Replacement rejected — new code (%d chars) is suspiciously shorter than original (%d chars).\nThis usually means the function body was truncated.\n\nACTION: Provide the COMPLETE replacement including the full function body."
                                         (length new_code) (length old-code))
                               (if (treesit-agent-replace-node node_name new_code)
                                   (progn
                                     ;; Suppress supersession warnings during save —
                                     ;; we just synced the buffer above, so any disk
                                     ;; change is from our own prior Code_Replace call.
                                     (cl-letf (((symbol-function 'ask-user-about-supersession-threat) #'ignore))
                                       (save-buffer))
                                     (format "Successfully replaced '%s' in %s" node_name file_path))
                              (format "Error: Could not find function/class '%s' in %s\n\nACTION:\n  1. Run Code_Map first to see available symbols\n  2. Check spelling: '%s' may be misspelled\n  3. Verify the function exists in the file" node_name file_path node_name)))))))
                    (error (let* ((msg (error-message-string err))
                                  (friendly (my/gptel--treesit-error-message msg file_path)))
                             (or friendly
                                 (cond
                                  ((string-match-p "syntax error\\|has-error" msg)
                                   (format "Error: New code has syntax errors (unbalanced parentheses/brackets)\n\nACTION:\n  1. Check that all opening brackets have closing brackets\n  2. Verify indentation is correct\n  3. Test code in a REPL before replacing\n\nOriginal error: %s" msg))
                                   (t (format "Error executing Code_Replace on %s: %s\n\nACTION: Check function name and new code syntax, then try again." file_path msg))))))))
     :args (list '(:name "file_path" :type string :description "Path to the file")
                 '(:name "node_name" :type string :description "Exact name of the function/class to replace")
                 '(:name "new_code" :type string :description "The perfectly balanced replacement code snippet"))
     :category "gptel-agent"
     :confirm t
     :include t)

    (gptel-make-tool
     :name "Diagnostics"
     :description "Collect project-wide diagnostics (errors and warnings) via LSP/Flymake. \
Falls back to CLI linters (ruff/eslint/cargo) when no LSP is available.

With optional argument `all`, also collect notes and low-severity diagnostics."
     :function (lambda (&optional all)
                 (if (not (fboundp 'flymake--project-diagnostics))
                     "Error: flymake--project-diagnostics not available.\n\nThis usually means Flymake is not initialized. Try opening a source file first."
                   (let* ((proj (project-current))
                          (dir (if proj (project-root proj) default-directory))
                          (lsp-active (my/gptel--lsp-active-p))
                          (diags (and proj (flymake--project-diagnostics proj)))
                          ;; Filter by severity: :error and :warning by default,
                          ;; include :note when `all' is non-nil.
                          (high-severity '(:error :warning))
                          (filtered
                           (seq-filter
                            (lambda (d)
                              (let ((type (flymake-diagnostic-type d)))
                                (or (memq type high-severity)
                                    (and all (eq type :note)))))
                            diags)))
                     (if (not filtered)
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
                                              (let ((line-text
                                                     (string-trim
                                                      (buffer-substring-no-properties
                                                       (line-beginning-position)
                                                       (line-end-position)))))
                                                (format "%s:%d [%s] %s\n  %s"
                                                        (buffer-file-name buf)
                                                        (line-number-at-pos)
                                                        type text line-text))))))
                                      filtered)))
                         (format "Found %d diagnostic(s)%s:\n\n%s"
                                 (length formatted)
                                 (if all " (including notes)" "")
                                 (string-join formatted "\n\n")))))))
     :args (list '(:name "all"
                         :type boolean
                         :description "When true, also collect notes and low-severity diagnostics. Default: only errors and warnings."
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

  (defun gptel-tools-code--make-unified-diff (path old-code new-code)
    "Generate a unified diff between OLD-CODE and NEW-CODE for PATH.
Uses the system `diff' command to produce a real unified diff with
context lines and proper hunks, suitable for `diff-mode'.
Falls back to a naive all-remove/all-add diff if `diff' is unavailable."
    (let ((filename (file-name-nondirectory path))
          (old-file (my/gptel-make-temp-file "code-replace-old-"))
          (new-file (my/gptel-make-temp-file "code-replace-new-")))
      (unwind-protect
          (progn
            (with-temp-file old-file (insert old-code))
            (with-temp-file new-file (insert new-code))
            (let ((diff-output
                   (with-temp-buffer
                     (call-process "diff" nil t nil
                                   "-u"
                                   (concat "--label=a/" filename)
                                   (concat "--label=b/" filename)
                                   old-file new-file)
                     (buffer-string))))
              (if (string-empty-p diff-output)
                  (format "--- a/%s\n+++ b/%s\n(no differences)\n" filename filename)
                diff-output)))
        (ignore-errors (delete-file old-file))
        (ignore-errors (delete-file new-file)))))

  (defun gptel-tools-code--replace-preview-setup (arg-values _info)
    "Setup diff preview for Code_Replace tool.

Shows a compact inline summary in the chat buffer and opens a
*Code_Replace Preview* buffer in a side window with a unified diff
in `diff-mode'.  Returns the preview buffer as the handle for teardown."
    (pcase-let ((from (point))
                (`(,path ,node-name ,new-code) arg-values))
      ;; --- Inline summary in chat buffer ---
      (insert
       "(" (propertize "Code_Replace " 'font-lock-face 'font-lock-keyword-face)
       (propertize (concat "\"" (file-name-nondirectory path) "\"")
                   'font-lock-face 'font-lock-constant-face)
       " " (propertize (concat "\"" node-name "\"")
                       'font-lock-face 'font-lock-string-face)
       ")")
      (let* ((full-path (expand-file-name path))
             (old-code (when (file-readable-p full-path)
                         (with-current-buffer (find-file-noselect full-path)
                           (treesit-agent--ensure-parser full-path)
                           (treesit-agent-extract-node node-name))))
             (preview-buf (get-buffer-create "*Code_Replace Preview*")))
        ;; Insert a compact note pointing to the diff buffer
        (if old-code
            (insert " "
                    (propertize (format "[%d -> %d lines]"
                                        (length (split-string old-code "\n"))
                                        (length (split-string new-code "\n")))
                                'font-lock-face 'font-lock-doc-face))
          (insert " " (propertize "[new]" 'font-lock-face 'font-lock-doc-face)))
        (insert "\n")

        ;; Background styling for inline part
        (font-lock-append-text-property
         from (1- (point)) 'font-lock-face
         (if (fboundp 'gptel-agent--block-bg) (gptel-agent--block-bg) 'default))
        (when (fboundp 'gptel-agent--confirm-overlay)
          (gptel-agent--confirm-overlay from (point) t))

        ;; --- Side window with unified diff ---
        (with-current-buffer preview-buf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (if old-code
                (insert (gptel-tools-code--make-unified-diff path old-code new-code))
              ;; No old code found — show the new code as all additions
              (insert (format "--- /dev/null\n+++ b/%s\n@@ -0,0 +1,%d @@\n%s\n"
                              (file-name-nondirectory path)
                              (length (split-string new-code "\n"))
                              (mapconcat (lambda (l) (concat "+" l))
                                         (split-string new-code "\n") "\n"))))
            (diff-mode)
            (font-lock-ensure)
            (goto-char (point-min))
            (setq buffer-read-only t)))
        (display-buffer preview-buf
                        '((display-buffer-in-side-window)
                          (side . right)
                          (window-width . 0.5)
                          (preserve-size . (t . nil))))
        ;; Return the buffer as the handle for teardown
        preview-buf)))

  (defun gptel-tools-code--replace-preview-teardown (preview-buf)
    "Close the Code_Replace preview buffer and its window."
    (when (buffer-live-p preview-buf)
      (when-let* ((win (get-buffer-window preview-buf t)))
        (delete-window win))
      (kill-buffer preview-buf)))

  (setf (alist-get "Code_Replace" gptel--tool-preview-alist nil nil #'equal)
        (list #'gptel-tools-code--replace-preview-setup
              #'gptel-tools-code--replace-preview-teardown)))

(provide 'gptel-tools-code)
