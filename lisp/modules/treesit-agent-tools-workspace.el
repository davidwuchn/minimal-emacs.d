;;; treesit-agent-tools-workspace.el --- Workspace AST tools -*- no-byte-compile: t; lexical-binding: t; -*-

(require 'treesit-agent-tools)
(require 'project)

(defun treesit-agent--ensure-parser (file)
  "Ensure a tree-sitter parser is active for FILE's buffer.
When `find-file-noselect' does not activate a *-ts-mode (e.g. batch mode
or missing `major-mode-remap-alist'), try to create a parser from the file
extension."
  (unless (treesit-parser-list)
    (let* ((ext (file-name-extension file))
           (lang (cond
                  ((member ext '("el" "elisp")) 'elisp)
                  ((member ext '("py" "pyw"))    'python)
                  ((member ext '("rs"))          'rust)
                  ((member ext '("clj" "cljs" "cljc" "edn")) 'clojure)
                  ((member ext '("js" "mjs"))    'javascript)
                  ((member ext '("ts"))          'typescript)
                  ((member ext '("tsx"))         'tsx)
                  ((member ext '("rb"))          'ruby)
                  ((member ext '("go"))          'go)
                  ((member ext '("c" "h"))       'c)
                  ((member ext '("cpp" "cc" "cxx" "hpp")) 'cpp)
                  ((member ext '("java"))        'java)
                  ((member ext '("lua"))         'lua))))
      (when (and lang (treesit-language-available-p lang))
        (treesit-parser-create lang)))))

(defcustom treesit-agent-workspace-max-candidates 20
  "Maximum number of candidate files to scan in workspace searches.
Prevents hangs on large projects with many matches."
  :type 'integer
  :group 'treesit-agent)

(defcustom treesit-agent-workspace-search-timeout 10
  "Maximum seconds for entire workspace search.
Prevents hangs when many candidate files exist."
  :type 'integer
  :group 'treesit-agent)

(defun treesit-agent-find-workspace (symbol-name)
  "Search the entire project workspace for SYMBOL-NAME and return its AST nodes.
Uses ripgrep to find candidate files, then extracts the exact AST blocks.

;; ASSUMPTION: ripgrep (rg) is installed and on PATH
;; ASSUMPTION: project-root returns a valid directory
;; BEHAVIOR: Limits candidates to `treesit-agent-workspace-max-candidates'
;; BEHAVIOR: Wraps entire search in `treesit-agent-workspace-search-timeout'
;; BEHAVIOR: Collects per-file errors instead of silently swallowing them
;; EDGE CASE: nil/empty symbol-name signals user-error
;; EDGE CASE: Timeout returns partial results found so far
;; EDGE CASE: Files that error during parsing are reported in output
;; TEST: (treesit-agent-find-workspace \"treesit-agent-find-workspace\") should return AST nodes
;; TEST: Large projects should not hang due to candidate limit and timeout"
  (unless (and (stringp symbol-name) (> (length symbol-name) 0))
    (user-error "symbol-name must be a non-empty string, got: %S" symbol-name))
  (let* ((proj (project-current))
         (root (if proj (project-root proj) default-directory))
         (grepper (executable-find "rg"))
         (candidates nil)
         (results nil)
         (errors nil)
         (timed-out nil))
    (unless grepper
      (error "ripgrep (rg) is required for workspace-wide AST searches"))

    ;; 1. Use ripgrep to find candidate files very quickly
    (with-temp-buffer
      (let ((exit-code (call-process grepper nil t nil
                                     "-l" "-F"
                                     symbol-name (expand-file-name root))))
        (when (= exit-code 0)
          (goto-char (point-min))
          (while (and (not (eobp))
                      (< (length candidates) treesit-agent-workspace-max-candidates))
            (push (buffer-substring-no-properties (line-beginning-position) (line-end-position)) candidates)
            (forward-line 1)))))

    ;; 2. Map over candidates and extract AST blocks (bounded by overall timeout)
    (with-timeout (treesit-agent-workspace-search-timeout
                   (setq timed-out t))
      (dolist (file (nreverse candidates))
        (when (file-readable-p file)
          (condition-case err
              (with-timeout (2 nil)
                (let ((buf (find-file-noselect file)))
                  (unwind-protect
                      (with-current-buffer buf
                        (treesit-agent--ensure-parser file)
                        (let ((node-text (treesit-agent-extract-node symbol-name)))
                          (when node-text
                            (push (format "==== %s ====\n%s" (file-relative-name file root) node-text) results))))
                    (when (buffer-live-p buf)
                      (kill-buffer buf)))))
            (error
             (push (cons (file-relative-name file root) (error-message-string err)) errors))))))

    ;; 3. Build output with optional error report
    (let ((output (when results (string-join (nreverse results) "\n\n")))
          (error-report (when errors
                          (concat ";; Errors in " (number-to-string (length errors)) " file(s):\n"
                                  (string-join
                                   (mapcar (lambda (e) (format ";;   %s: %s" (car e) (cdr e)))
                                           (nreverse errors))
                                   "\n")))))
      (cond
       ((and output timed-out)
        (concat output "\n\n;; WARNING: search timed out after "
                (number-to-string treesit-agent-workspace-search-timeout)
                "s, results may be incomplete"
                (when error-report (concat "\n" error-report))))
       ((and output error-report)
        (concat output "\n\n" error-report))
       (output
        output)
       (timed-out
        (concat (format "Search timed out after %ds — no structural definition found for '%s' in %s"
                        treesit-agent-workspace-search-timeout symbol-name root)
                (when error-report (concat "\n" error-report))))
       (error-report
        (concat (format "No structural definition found for '%s' in %s" symbol-name root)
                "\n" error-report))
       (t
        (format "No structural definition found for '%s' in %s" symbol-name root))))))

(provide 'treesit-agent-tools-workspace)
