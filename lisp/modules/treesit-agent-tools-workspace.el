;;; treesit-agent-tools-workspace.el --- Workspace AST tools -*- lexical-binding: t -*-

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

(defun treesit-agent-find-workspace (symbol-name)
  "Search the entire project workspace for SYMBOL-NAME and return its AST nodes.
Uses ripgrep to find candidate files, then extracts the exact AST blocks."
  (let* ((proj (project-current))
         (root (if proj (project-root proj) default-directory))
         (grepper (executable-find "rg"))
         (candidates nil)
         (results nil))
    (unless grepper
      (error "ripgrep (rg) is required for workspace-wide AST searches"))
    
    ;; 1. Use ripgrep to find candidate files very quickly
    (with-temp-buffer
      (let ((exit-code (call-process grepper nil t nil
                                     "--no-ignore" "-l" "-F"
                                     "--glob" "!*.elc"
                                     "--glob" "!var/elpa/"
                                     symbol-name (expand-file-name root))))
        (when (= exit-code 0)
          (goto-char (point-min))
          (while (not (eobp))
            (push (buffer-substring-no-properties (line-beginning-position) (line-end-position)) candidates)
            (forward-line 1)))))
    
    ;; 2. Map over candidates and extract AST blocks
    (dolist (file (nreverse candidates))
      (when (file-readable-p file)
        (condition-case nil
            (with-timeout (2 nil)
              (with-current-buffer (find-file-noselect file)
                (treesit-agent--ensure-parser file)
                (let ((node-text (treesit-agent-extract-node symbol-name)))
                  (when node-text
                    (push (format "==== %s ====\n%s" (file-relative-name file root) node-text) results)))))
          (error nil))))
    
    (if results
        (string-join (nreverse results) "\n\n")
      (format "No structural definition found for '%s' in %s" symbol-name root))))

(provide 'treesit-agent-tools-workspace)
