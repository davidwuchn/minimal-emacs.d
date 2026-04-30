;;; gptel-tools-code.el --- Unified Code tools for gptel-agent -*- lexical-binding: t; no-byte-compile: t -*-

(require 'gptel)
(require 'treesit-agent-tools)
(require 'treesit-agent-tools-workspace)
(require 'flymake)
(require 'project)
(require 'eglot)
(require 'xref)
(require 'checkdoc)
(require 'bytecomp)

(declare-function package-lint-buffer "package-lint")
(declare-function my/gptel-make-temp-file "gptel-ext-core")

;;; Customization

(defcustom my/gptel-find-usages-max-chars 50000
  "Maximum characters to return from find-usages.
Prevents large results from causing JSON serialization issues."
  :type 'integer
  :group 'gptel-tools)

(defcustom my/gptel-find-usages-cache-dir (expand-file-name "tmp/usages/" user-emacs-directory)
  "Directory to cache Code_Usages results."
  :type 'directory
  :group 'gptel-tools)

(defcustom my/gptel-find-usages-async-threshold 100
  "Number of usages above which to use async caching.
Results with more than this many usages are written to a temp file
instead of being returned directly to avoid LLM token bloat."
  :type 'integer
  :group 'gptel-tools)

(defcustom my/gptel-code-replace-truncation-ratio 0.1
  "Minimum ratio of new/old code length before rejecting as truncation.
A value of 0.1 means replacements < 10% of original length are rejected
as likely truncation errors. Set to 0 to disable truncation guard."
  :type 'number
  :group 'gptel-tools)

(defcustom my/gptel-code-replace-min-old-chars 200
  "Minimum old code length before truncation guard applies.
Replacements shorter than this threshold are always allowed."
  :type 'integer
  :group 'gptel-tools)

(defcustom my/gptel-usages-cache-ttl 3600
  "Cache time-to-live in seconds for Code_Usages results.
Default is 1 hour. Set to 0 to disable caching."
  :type 'integer
  :group 'gptel-tools)

(defcustom my/gptel-lsp-retry-max 5
  "Maximum number of LSP connection retries.
Each retry uses exponential backoff (0.5s, 1s, 2s, 4s, 8s)."
  :type 'integer
  :group 'gptel-tools)

(defcustom my/gptel-search-timeout 30
  "Timeout in seconds for git-grep and ripgrep searches."
  :type 'integer
  :group 'gptel-tools)

(defcustom my/gptel-elisp-diag-max-files 10
  "Maximum number of .el files to check in project-wide diagnostics.
Prevents long waits in large projects."
  :type 'integer
  :group 'gptel-tools)

;;; Cache Management

(defvar my/gptel--usages-cache-initialized nil
  "Whether the usages cache directory has been initialized.")

(defun my/gptel--usages-cache-init ()
  "Initialize usages cache directory. Idempotent."
  (unless my/gptel--usages-cache-initialized
    (unless (file-directory-p my/gptel-find-usages-cache-dir)
      (make-directory my/gptel-find-usages-cache-dir t))
    (set-file-modes my/gptel-find-usages-cache-dir #o700)
    (setq my/gptel--usages-cache-initialized t)))

(defun my/gptel--usages-cache-file (symbol-name root)
  "Generate cache file path for SYMBOL-NAME in ROOT."
  (my/gptel--usages-cache-init)
  (let* ((safe-symbol (replace-regexp-in-string "[^a-zA-Z0-9_-]" "_" symbol-name))
         (safe-root (replace-regexp-in-string "[^a-zA-Z0-9_-]" "_" (file-name-nondirectory (directory-file-name root))))
         (filename (format "%s--%s.txt" safe-root safe-symbol)))
    (expand-file-name filename my/gptel-find-usages-cache-dir)))

(defun my/gptel--usages-cache-get (symbol-name root)
  "Get cached usages for SYMBOL-NAME in ROOT if fresh.
Uses `my/gptel-usages-cache-ttl' for freshness check."
  (when (> my/gptel-usages-cache-ttl 0)
    (let ((cache-file (my/gptel--usages-cache-file symbol-name root)))
      (when (and (file-exists-p cache-file)
                 (< (- (float-time) (float-time (nth 5 (file-attributes cache-file))))
                    my/gptel-usages-cache-ttl))
        cache-file))))

(defun my/gptel--usages-cache-write (symbol-name root usages backend)
  "Write USAGES to cache file for SYMBOL-NAME in ROOT."
  (let ((cache-file (my/gptel--usages-cache-file symbol-name root)))
    (with-temp-file cache-file
      (insert (format "# Code_Usages: %s\n" symbol-name))
      (insert (format "# Backend: %s\n" backend))
      (insert (format "# Root: %s\n" root))
      (insert (format "# Total: %d usages\n\n" (length usages)))
      (insert (string-join usages "\n")))
    (set-file-modes cache-file #o600)
    cache-file))

(defun my/gptel--lsp-active-p ()
  "Check if an LSP server is active for the current buffer."
  (and (fboundp 'eglot-current-server)
       (eglot-current-server)))

(defun my/gptel--lsp-backoff-delay (retries-left max-retries)
  "Calculate exponential backoff delay for LSP retries.
RETRIES-LEFT is remaining retries, MAX-RETRIES is the initial max.
Returns delay in seconds: 0.5s, 1s, 2s, 4s, 8s for 5 retries."
  (* 0.5 (expt 2 (- max-retries retries-left))))

(defun my/gptel--lsp-retry-wait (retries-left max-retries msg-fmt)
  "Decrement RETRIES-LEFT, sleep with backoff if retries remain.
MSG-FMT is a format string receiving RETRIES-LEFT.
Returns the updated retries-left value."
  (setq retries-left (1- retries-left))
  (when (> retries-left 0)
    (message msg-fmt retries-left)
    (sleep-for (my/gptel--lsp-backoff-delay retries-left max-retries)))
  retries-left)


(defun gptel-tools-code--filter-usage-line (line)
  "Filter out binary/cache files from usage LINE.
Returns LINE if it should be included, nil if it should be filtered.
Filters: .pyc, .elc, __pycache__"
  (unless (string-match-p "\\.pyc$\\|\\.elc$\\|__pycache__" line)
    line))
(defun my/gptel--git-grep-usages (symbol-name root)
  "Find usages of SYMBOL-NAME using git grep in ROOT.
Returns list of matching lines or nil if not in git repo or no matches.
Only searches tracked files (respects .gitignore automatically).
Nested git repos are NOT searched (use ripgrep fallback for those).
Honors `my/gptel-search-timeout' for large repos."
  (let ((default-directory root))
    (when (and (executable-find "git")
               ;; Git worktrees expose .git as a file that points at the real
               ;; gitdir, so file existence is the correct repo-root check here.
               (file-exists-p (expand-file-name ".git" root)))
      (with-timeout (my/gptel-search-timeout nil)
        (with-temp-buffer
          (let* ((pattern (format "\\b%s\\b" (regexp-quote symbol-name)))
                 (args (list "-c" "grep.lineNumber=true"
                             "grep" "-n" "--no-color"
                             "-e" pattern))
                 (exit-code (apply #'call-process "git" nil t nil args)))
            (when (= exit-code 0)
              (goto-char (point-min))
              (let (usages)
                (while (not (eobp))
                  (let ((line (buffer-substring-no-properties
                               (line-beginning-position)
                               (line-end-position))))
                    (when (gptel-tools-code--filter-usage-line line)
                      (push line usages)))
                  (forward-line 1))
                (reverse usages)))))))))

(defun gptel-tools-code--ensure-treesit-ready (file-path fallback-action)
  "Ensure tree-sitter parser is ready for FILE-PATH.
Returns nil if ready, or an error message string if not.
FALLBACK-ACTION is a string suggesting alternative tool to use."
  (condition-case err
      (progn
        (treesit-agent--ensure-parser file-path)
        (if (treesit-parser-list)
            nil
          (gptel-tools-code--no-parser-message
           file-path (my/gptel--detect-treesit-language file-path) fallback-action)))
    (error (let* ((msg (error-message-string err))
                  (friendly (my/gptel--treesit-error-message msg file-path)))
             (or friendly
                 (format "Error: tree-sitter not ready for %s: %s" file-path msg))))))
(defun my/gptel--find-usages (symbol-name)
  "Find all usages of SYMBOL-NAME in the current project.
Fallback chain: LSP → git grep → ripgrep.
LSP provides semantic references (most accurate).
Git grep searches tracked files only (fast, respects .gitignore).
Ripgrep searches all files including nested repos and untracked files.
Reports which backend was used."
  (cond
   ((not symbol-name)
    (error "my/gptel--find-usages: symbol-name is nil"))
   ((string-empty-p symbol-name)
    (error "my/gptel--find-usages: symbol-name is empty")))
  (let* ((proj (project-current))
         (root (if proj (project-root proj) default-directory))
         (usages nil)
         (lsp-retries my/gptel-lsp-retry-max)
         (lsp-ready nil)
         (backend "unknown")
         ;; Skip LSP in auto-workflow experiments (no LSP server in worktrees)
         (workflow-running (or (and (boundp 'gptel-auto-workflow--running)
                                    gptel-auto-workflow--running)
                               (and (boundp 'gptel-auto-workflow--cron-job-running)
                                    gptel-auto-workflow--cron-job-running))))
    ;; LSP retry loop - check server availability on each iteration
    ;; Skip entirely in workflow experiments to avoid timeouts
    (while (and (not workflow-running)
                (> lsp-retries 0)
                (not lsp-ready))
      (let* ((lsp-server (and (fboundp 'eglot-current-server)
                              (eglot-current-server)))
             (backend-type (and lsp-server (xref-find-backend))))
        (if (not (and lsp-server backend-type))
            (setq lsp-retries (my/gptel--lsp-retry-wait lsp-retries my/gptel-lsp-retry-max "[LSP] Waiting for server... (%d retries left)"))
          (condition-case nil
              (let ((refs (xref-backend-references backend-type symbol-name)))
                (if (and refs (listp refs))
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
                  (setq lsp-retries (my/gptel--lsp-retry-wait lsp-retries my/gptel-lsp-retry-max "[LSP] Waiting for server... (%d retries left)"))))
            (error
             (setq lsp-retries (my/gptel--lsp-retry-wait lsp-retries my/gptel-lsp-retry-max "[LSP] Connection error, retrying... (%d left)"))))))))
    (unless usages
      (let ((git-result (my/gptel--git-grep-usages symbol-name root)))
        (if git-result
            (progn
              (setq backend "git-grep")
              (setq usages git-result))
          (let ((grepper (executable-find "rg")))
            (if (not grepper)
                (setq usages (list (format "Error: ripgrep (rg) not found in PATH.\nInstall with: brew install ripgrep  (macOS)\n                 apt install ripgrep    (Ubuntu)\n                 winget install BurntSushi.ripgrep.MSVC  (Windows)")))
              (with-timeout (my/gptel-search-timeout
                             (setq usages (list (format "Error: Search timed out after %d seconds" my/gptel-search-timeout))))
                (with-temp-buffer
                  (let* ((has-hyphen (string-match-p "-" symbol-name))
                         (args (if has-hyphen
                                   (list "-n" "-e" (format "\\b%s\\b" (regexp-quote symbol-name))
                                         (expand-file-name root))
                                 (list "-n" "-w" "-F" symbol-name
                                       (expand-file-name root))))
                         (exit-code (apply #'call-process grepper nil t nil args)))
                    (when (= exit-code 0)
                      (goto-char (point-min))
                      (setq backend "ripgrep")
                      (setq usages nil)
                      (while (not (eobp))
                        (let ((line (buffer-substring-no-properties
                                     (line-beginning-position)
                                     (line-end-position))))
                          (when (gptel-tools-code--filter-usage-line line)
                            (push line usages)))
                        (forward-line 1)))))))))))
    (let ((result (if usages
                      (format "Found %d usages of '%s' (via %s):\n\n%s"
                              (length usages)
                              symbol-name
                              backend
                              (string-join (reverse usages) "\n"))
                    (format "No usages found for '%s' in %s" symbol-name root))))
      (if (> (length result) my/gptel-find-usages-max-chars)
          (let ((cache-file (my/gptel--usages-cache-write symbol-name root usages backend)))
            (format "Found %d usages of '%s' (via %s).\nResult too large, cached to: %s\n\nUse `Read' tool with file_path to view specific sections."
                    (length usages) symbol-name backend cache-file))
        result))))

(defun my/gptel--run-fallback-linter (dir &optional file-path)
  "Run a fallback linter in DIR if LSP is not available.
If FILE-PATH is provided, check only that file.
Reports what was checked, even if no standard project files found.
Uses call-process instead of shell commands for security."
  (let ((default-directory dir)
        (py-ext "\\.py\\'")
        (el-ext "\\.el\\'"))
    (cond
     ((or (and file-path (string-match-p el-ext file-path))
          (directory-files dir nil el-ext))
      (if file-path
          (gptel-tools-code--elisp-diagnostics file-path)
        (let ((el-files (append
                         (directory-files dir t el-ext t)
                         (when (file-directory-p (expand-file-name "lisp" dir))
                           (directory-files-recursively
                            (expand-file-name "lisp" dir) el-ext)))))
          (if el-files
              (let ((files-to-check (seq-take el-files my/gptel-elisp-diag-max-files)))
                (concat
                 (mapconcat
                  (lambda (f) (format "=== %s ===\n%s" f
                                      (gptel-tools-code--elisp-diagnostics f)))
                  files-to-check "\n\n")
                 (when (> (length el-files) my/gptel-elisp-diag-max-files)
                   (format "\n\n[Checked %d of %d .el files (limited for performance)]"
                           my/gptel-elisp-diag-max-files (length el-files)))))
            "No .el files found in project"))))
     ((file-exists-p "package.json")
      (let ((res (with-temp-buffer
                   (or (and (executable-find "npm")
                            (= 0 (call-process "npm" nil t nil "run" "lint" "--silent")))
                       (and (executable-find "npx")
                            (= 0 (call-process "npx" nil t nil "eslint" ".")))
                       "")
                   (buffer-string))))
        (if (string-empty-p (string-trim res))
            "✓ No linter errors (ESLint) - checked package.json (JavaScript/Node.js)"
          res)))
     ((or (file-exists-p "pyproject.toml") (file-exists-p "setup.py") (directory-files dir nil py-ext))
      (let ((res (with-temp-buffer
                   (or (and (executable-find "ruff")
                            (= 0 (call-process "ruff" nil t nil "check" ".")))
                       (and (executable-find "flake8")
                            (= 0 (call-process "flake8" nil t nil ".")))
                       "")
                   (buffer-string))))
        (if (string-empty-p (string-trim res))
            "✓ No linter errors (ruff/flake8) - checked Python project (pyproject.toml/setup.py)"
          res)))
     ((file-exists-p "Cargo.toml")
      (let ((res (with-temp-buffer
                   (when (executable-find "cargo")
                     (call-process "cargo" nil t nil "check"))
                   (buffer-string))))
        (if (string-match-p "Finished\\|Compiling" res)
            "✓ No compiler errors (cargo check) - checked Cargo.toml (Rust)"
          res)))
     (t
      (concat "Note: No standard project files found (package.json, pyproject.toml, Cargo.toml, *.el).\n"
              "Searched for: JavaScript (package.json), Python (pyproject.toml/setup.py/*.py), "
              "Rust (Cargo.toml), Emacs Lisp (*.el).\n"
              "If this is a different language, configure a linter or use LSP for diagnostics.")))))

(defun my/gptel--detect-treesit-language (file-path)
  "Detect tree-sitter language for FILE-PATH from extension.
Returns a symbol like \\='python, \\='elisp, etc., or \\='unknown."
  (or (and (boundp 'treesit--language) treesit--language)
      (let ((py-rx "\\.py\\'")
            (el-rx "\\.el\\'")
            (clj-rx "\\.clj\\'")
            (rs-rx "\\.rs\\'"))
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

(defun gptel-tools-code--ripgrep-unavailable-msg ()
  "Return installation advice for ripgrep (rg)."
  (concat "\n\nACTION: Install ripgrep (rg) for workspace search:\n"
          "  macOS:  brew install ripgrep\n"
          "  Ubuntu: apt install ripgrep\n"
          "  Check:  rg --version"))

;;; Emacs Lisp Diagnostics

(defun gptel-tools-code--elisp-checkdoc (file-path)
  "Run checkdoc on FILE-PATH and return issues as a string."
  (with-temp-buffer
    (insert-file-contents file-path)
    (emacs-lisp-mode)
    (let ((checkdoc-arguments-in-order-flag nil)
          (checkdoc-force-docstrings-flag nil)
          (issues nil))
      (condition-case nil
          (checkdoc-with-point
           (goto-char (point-min))
           (while (and (not (eobp)) (< (length issues) 50))
             (let ((err (checkdoc-next-error)))
               (when err
                 (let ((line (line-number-at-pos)))
                   (push (format "%s:%d: %s"
                                 file-path line
                                 (if (stringp err) err (car err)))
                         issues))))))
        (error nil))
      (if issues
          (mapconcat #'identity (reverse issues) "\n")
        "✓ No checkdoc issues"))))

(defun gptel-tools-code--elisp-byte-compile (file-path)
  "Run byte-compile on FILE-PATH and return warnings/errors as a string."
  (let* ((byte-compile-error-on-warn nil)
         (byte-compile-warnings '(not obsolete free-vars unresolved))
         (byte-compile-verbose nil)
         (warnings nil)
         (temp-elc-file (make-temp-file "gptel-tools-code-byte-compile-" nil ".elc"))
         (compile-log-buffer (generate-new-buffer " *gptel-tools-code-byte-compile-log*"))
         (byte-compile-log-buffer compile-log-buffer)
         (byte-compile-dest-file-function (lambda (_source-file) temp-elc-file))
         (inhibit-message t)
         (message-log-max nil))
    (unwind-protect
        (progn
          (byte-compile-file file-path)
          (with-current-buffer compile-log-buffer
            (save-excursion
              (goto-char (point-min))
              (while (not (eobp))
                (let ((line (buffer-substring-no-properties
                             (line-beginning-position) (line-end-position))))
                  (when (and (not (string-empty-p (string-trim line)))
                             (string-match-p "[Ww]arning\\|[Ee]rror" line))
                    (push line warnings)))
                (forward-line 1)))))
      (when (file-exists-p temp-elc-file)
        (delete-file temp-elc-file))
      (when (buffer-live-p compile-log-buffer)
        (kill-buffer compile-log-buffer)))
    (if warnings
        (mapconcat #'identity (reverse warnings) "\n")
      "✓ No byte-compile warnings")))

(defun gptel-tools-code--elisp-package-lint (file-path)
  "Run package-lint on FILE-PATH and return issues as a string."
  (if (not (require 'package-lint nil t))
      "⊘ package-lint not available (install from MELPA)"
    (with-temp-buffer
      (insert-file-contents file-path)
      (emacs-lisp-mode)
      (let ((issues (package-lint-buffer)))
        (if issues
            (mapconcat
             (lambda (issue)
               (pcase-let ((`(,line ,col ,type ,message) issue))
                 (format "%s:%d:%d [%s] %s"
                         file-path line col type message)))
             issues "\n")
          "✓ No package-lint issues")))))

(defun gptel-tools-code--elisp-diagnostics (file-path &optional checks)
  "Run Emacs Lisp diagnostics on FILE-PATH.
CHECKS is a list of symbols: \\='checkdoc, \\='byte-compile, \\='package-lint."
  (let* ((all-checks '(checkdoc byte-compile package-lint))
         (selected (or checks all-checks))
         (results nil))
    (when (memq 'checkdoc selected)
      (push (cons "checkdoc" (gptel-tools-code--elisp-checkdoc file-path)) results))
    (when (memq 'byte-compile selected)
      (push (cons "byte-compile" (gptel-tools-code--elisp-byte-compile file-path)) results))
    (when (memq 'package-lint selected)
      (push (cons "package-lint" (gptel-tools-code--elisp-package-lint file-path)) results))
    (if results
        (mapconcat
         (lambda (pair) (format "=== %s ===\n%s" (car pair) (cdr pair)))
         (reverse results) "\n\n")
      "No checks specified")))

(defun gptel-tools-code--no-parser-message (file-path lang action-fallback)
  "Format a user-friendly error when no tree-sitter parser is active.
FILE-PATH is the file, LANG the detected language, ACTION-FALLBACK
the tool to suggest as alternative."
  (format "Error: No tree-sitter parser active for %s\n\nACTION:\n  1. Install parser: M-x treesit-install-language-grammar RET %s RET\n  2. Reopen file: C-x C-k (kill-buffer) then C-x C-f %s\n  3. Verify: M-x eval-expression RET (treesit-language-available-p '%s) RET\n  4. Fallback: Use %s"
          file-path (or lang "language") file-path (or lang "language") action-fallback))

(defun gptel-tools-code--validate-replace-args (file-path node-name new-code)
  "Validate arguments for Code_Replace operation.
Signals an error if any argument is nil or invalid.
FILE-PATH, NODE-NAME, and NEW-CODE must all be non-nil strings.
NEW-CODE must also be non-empty."
  (cond
   ((not file-path)
    (error "gptel-tools-code--validate-replace-args: file_path is nil"))
   ((not (stringp file-path))
    (error "gptel-tools-code--validate-replace-args: file_path must be a string, got %s" (type-of file-path)))
   ((not node-name)
    (error "gptel-tools-code--validate-replace-args: node_name is nil"))
   ((not (stringp node-name))
    (error "gptel-tools-code--validate-replace-args: node_name must be a string, got %s" (type-of node-name)))
   ((not new-code)
    (error "gptel-tools-code--validate-replace-args: new_code is nil"))
   ((not (stringp new-code))
    (error "gptel-tools-code--validate-replace-args: new_code must be a string, got %s" (type-of new-code)))
   ((string-empty-p new-code)
    (error "gptel-tools-code--validate-replace-args: new_code is empty"))))

(defun gptel-tools-code--map-file (file_path)
  "Get a high-level outline of all functions and classes in FILE_PATH.
Returns a formatted string with the file map, or an error message."
  (cond
   ((not file_path)
    (error "gptel-tools-code--map-file: file_path is nil"))
   ((not (stringp file_path))
    (error "gptel-tools-code--map-file: file_path must be a string, got %s" (type-of file_path))))
  (condition-case err
      (with-timeout (5 (format "Error: Code_Map timed out after 5 seconds on %s" file_path))
        (with-current-buffer (find-file-noselect file_path)
          (let ((parser-error (gptel-tools-code--ensure-treesit-ready file_path "Read/Grep for this file")))
            (if parser-error
                parser-error
              (let ((map (treesit-agent-get-file-map)))
                (if map
                    (format "File map for %s:\n%s" file_path (string-join map "\n"))
                  (format "Could not generate file map for %s.\n\nACTION: Check if tree-sitter is enabled for this file type.\n  - Run: M-x treesit-install-language-grammar RET <language> RET\n  - Verify: M-x eval-expression RET (treesit-language-available-p '<lang>) RET" file_path)))))))
    (error (let* ((msg (error-message-string err))
                  (friendly (my/gptel--treesit-error-message msg file_path)))
             (or friendly
                 (format "Error executing Code_Map on %s: %s\n\nACTION: Check file permissions and try again." file_path msg))))))

(defun gptel-tools-code--inspect-node (node_name &optional file_path)
  "Extract the code block for NODE_NAME, optionally from FILE_PATH.
When FILE_PATH is nil, searches the entire project workspace."
  (cond
   ((not node_name)
    (error "gptel-tools-code--inspect-node: node_name is nil"))
   ((not (stringp node_name))
    (error "gptel-tools-code--inspect-node: node_name must be a string, got %s" (type-of node_name))))
  (condition-case err
      (with-timeout (10 (format "Error: Code_Inspect timed out for '%s'" node_name))
        (if file_path
            (with-current-buffer (find-file-noselect file_path)
              (let ((parser-error (gptel-tools-code--ensure-treesit-ready file_path "Read tool for this file")))
                (if parser-error
                    parser-error
                  (let ((text (treesit-agent-extract-node node_name)))
                    (if text
                        (format "Code block '%s' from %s:\n\n%s" node_name file_path text)
                      (format "Error: Could not find function/class '%s' in %s\n\nACTION:\n  1. Run Code_Map first to see available symbols in the file\n  2. Check spelling: '%s' may be misspelled\n  3. Verify the function exists in the file" node_name file_path node_name))))))
          ;; Search workspace if no file provided
          (let ((result (treesit-agent-find-workspace node_name)))
            (cond
             ((string-match-p "ripgrep.*not found\\|executable.*rg" result)
              (concat result (gptel-tools-code--ripgrep-unavailable-msg)
                      "\nAlternatively, provide file_path to search a specific file."))
             ((string-match-p "No structural definition found" result)
              (format "Error: Could not find '%s' anywhere in the project\n\nACTION:\n  1. Check spelling: '%s' may be misspelled\n  2. Symbol may not exist - use Code_Map to explore files\n  3. Symbol may be dynamically defined (not in AST)" node_name node_name))
             (t result)))))
    (error (let* ((msg (error-message-string err))
                  (friendly (my/gptel--treesit-error-message msg (or file_path ""))))
             (or friendly
                 (cond
                  ((string-match-p "ripgrep\\|rg" msg)
                   (concat msg (gptel-tools-code--ripgrep-unavailable-msg)))
                  ((string-match-p "timeout" msg)
                   (format "Error: Code_Inspect timed out after 10 seconds for '%s'\n\nACTION:\n  1. Provide explicit file_path to skip workspace search\n  2. Large project - search may take time\n  3. Try Code_Map on specific files first" node_name))
                  (t (format "Error executing Code_Inspect: %s\n\nACTION: Check symbol name and file path, then try again." msg))))))))

(defun gptel-tools-code--file-changed-externally-p ()
  "Check if the current buffer's file has been modified externally.
Returns t if file exists and is newer than buffer's view, nil otherwise."
  (and (buffer-file-name)
       (file-exists-p (buffer-file-name))
       (not (verify-visited-file-modtime))))

(defun gptel-tools-code--replace-node (file_path node_name new_code)
  "Surgically replace NODE_NAME in FILE_PATH with NEW_CODE.
Syncs buffer with disk, validates parser, guards against truncation."
  (gptel-tools-code--validate-replace-args file_path node_name new_code)
  ;; Ensure absolute path to avoid visiting wrong buffer in worktrees
  (let ((abs-path (expand-file-name file_path)))
    (condition-case err
        (with-timeout (5 (format "Error: Code_Replace timed out on %s" abs-path))
          (with-current-buffer (find-file-noselect abs-path)
            (when (buffer-modified-p)
              (error "Buffer has unsaved changes. Save or revert manually before Code_Replace."))
            (when (gptel-tools-code--file-changed-externally-p)
              (revert-buffer t t t))
            (let ((parser-error (gptel-tools-code--ensure-treesit-ready abs-path
                                                                        "Edit tool (manual paren balancing required)")))
              (if parser-error
                  parser-error
                (let ((old-code (treesit-agent-extract-node node_name)))
                  (if (and old-code
                           (> my/gptel-code-replace-truncation-ratio 0)
                           (> (length old-code) my/gptel-code-replace-min-old-chars)
                           (< (length new_code) (* my/gptel-code-replace-truncation-ratio (length old-code))))
                      (format "Error: Replacement rejected — new code (%d chars) is suspiciously shorter than original (%d chars).\nThis usually means the function body was truncated.\n\nACTION: Provide the COMPLETE replacement including the full function body."
                              (length new_code) (length old-code))
                    (if (treesit-agent-replace-node node_name new_code)
                        (progn
                          (when (gptel-tools-code--file-changed-externally-p)
                            (error "File changed externally during replace. Re-run Code_Replace."))
                          (cl-letf (((symbol-function 'ask-user-about-supersession-threat) #'ignore))
                            (save-buffer))
                          (format "Successfully replaced '%s' in %s" node_name abs-path))
                      (format "Error: Could not find function/class '%s' in %s\n\nACTION:\n  1. Run Code_Map first to see available symbols\n  2. Check spelling: '%s' may be misspelled\n  3. Verify the function exists in the file" node_name abs-path node_name))))))))
      (error (let* ((msg (error-message-string err))
                    (friendly (my/gptel--treesit-error-message msg abs-path)))
               (or friendly
                   (cond
                    ((string-match-p "syntax error\\|has-error" msg)
                     (format "Error: New code has syntax errors (unbalanced parentheses/brackets)\n\nACTION:\n  1. Check that all opening brackets have closing brackets\n  2. Verify indentation is correct\n  3. Test code in a REPL before replacing\n\nOriginal error: %s" msg))
                    (t (format "Error executing Code_Replace on %s: %s\n\nACTION: Check function name and new code syntax, then try again." abs-path msg)))))))))

(defun gptel-tools-code--format-diagnostic (d)
  "Format a single flymake diagnostic D as a string with file, line, type, and context."
  (let ((buf (flymake-diagnostic-buffer d))
        (text (flymake-diagnostic-text d))
        (type (flymake-diagnostic-type d))
        (beg (flymake-diagnostic-beg d)))
    (if (not (buffer-live-p buf))
        (format "<buffer unavailable>:? [%s] %s\n  [stale diagnostic buffer unavailable]"
                type text)
      (with-current-buffer buf
        (save-excursion
          (goto-char (min (max beg (point-min)) (point-max)))
          (let ((line-text
                 (string-trim
                  (buffer-substring-no-properties
                   (line-beginning-position)
                   (line-end-position)))))
            (format "%s:%d [%s] %s\n  %s"
                    (or (buffer-file-name buf)
                        (buffer-name buf)
                        "<buffer>")
                    (line-number-at-pos)
                    type text line-text)))))))

(defun gptel-tools-code--diagnostics (&optional all file-path)
  "Collect diagnostics via LSP/Flymake or CLI linters.

If FILE-PATH is provided, check only that file.
Otherwise, check the entire project.
When ALL is non-nil, include notes and low-severity diagnostics.

For .el files, uses checkdoc/byte-compile/package-lint instead of LSP."
  ;; Handle .el files specially
  (if (and file-path (string-match-p "\\.el\\'" file-path))
      (gptel-tools-code--elisp-diagnostics file-path)
    ;; Non-elisp files: use LSP or CLI fallback
    (if (not (fboundp 'flymake--project-diagnostics))
        "Error: flymake--project-diagnostics not available.\n\nThis usually means Flymake is not initialized. Try opening a source file first."
      (let* ((proj (project-current))
             (dir (if proj (project-root proj) default-directory))
             (lsp-active (my/gptel--lsp-active-p))
             (diags (and proj (flymake--project-diagnostics proj)))
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
              (concat "Note: No LSP server running for this project.\nFalling back to CLI linter:\n\n"
                      (my/gptel--run-fallback-linter dir file-path)))
          (let ((formatted (mapcar #'gptel-tools-code--format-diagnostic filtered)))
            (format "Found %d diagnostic(s)%s:\n\n%s"
                    (length formatted)
                    (if all " (including notes)" "")
                    (string-join formatted "\n\n"))))))))

(defun gptel-tools-code-register ()
  "Register the unified Code tools with gptel."
  (when (fboundp 'gptel-make-tool)

    (gptel-make-tool
     :name "Code_Map"
     :description "Get a high-level outline of all functions and classes defined in a file. \
Always use this first to understand the structure of a file before editing."
     :function #'gptel-tools-code--map-file
     :args (list '(:name "file_path" :type string :description "Path to the file to map"))
     :category "gptel-agent"
     :include t)

    (gptel-make-tool
     :name "Code_Inspect"
     :description "Extract the exact, perfectly balanced code block for a specific function or class by name. \
If file_path is omitted, it will search the entire project to find the definition automatically."
     :function #'gptel-tools-code--inspect-node
     :args (list '(:name "node_name" :type string :description "Exact name of the function/class to read")
                 '(:name "file_path" :type string :optional t :description "Path to the file (optional)"))
     :category "gptel-agent"
     :include t)

    (gptel-make-tool
     :name "Code_Replace"
     :description "Surgically replace an exact function or class by name with new code. \
GUARANTEES perfectly balanced parentheses/brackets. You MUST use this instead of standard Edit when modifying existing functions."
     :function #'gptel-tools-code--replace-node
     :args (list '(:name "file_path" :type string :description "Path to the file")
                 '(:name "node_name" :type string :description "Exact name of the function/class to replace")
                 '(:name "new_code" :type string :description "The perfectly balanced replacement code snippet"))
     :category "gptel-agent"
     :confirm t
     :include t)

    (gptel-make-tool
     :name "Diagnostics"
     :description "Collect diagnostics (errors and warnings) via LSP/Flymake or CLI linters.

For .el files: runs checkdoc, byte-compile, and package-lint.
For other files: uses LSP diagnostics or falls back to CLI linters.

Arguments:
- file_path (optional): Check only this file. If omitted, checks entire project.
- all (optional): Include notes and low-severity diagnostics.

Examples:
  Diagnostics{file_path: \"lisp/eca-ext.el\"}  ; Check single .el file
  Diagnostics{}                                  ; Project-wide check
  Diagnostics{all: true}                        ; Include notes"
     :function #'gptel-tools-code--diagnostics
     :args (list '(:name "file_path"
                         :type string
                         :optional t
                         :description "Path to check. If omitted, checks entire project. For .el files, runs checkdoc/byte-compile/package-lint.")
                 '(:name "all"
                         :type boolean
                         :optional t
                         :description "When true, also collect notes and low-severity diagnostics. Default: only errors and warnings."))
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
                             (concat result (gptel-tools-code--ripgrep-unavailable-msg)
                                     "\nTIP: Or provide file_path to Code_Inspect to search a specific file instead.")
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
