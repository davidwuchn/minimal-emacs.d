;;; treesit-agent-tools-workspace.el --- Workspace AST tools -*- lexical-binding: t -*-

(require 'treesit-agent-tools)
(require 'project)

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
      (let ((exit-code (call-process grepper nil t nil "-l" "-F" symbol-name (expand-file-name root))))
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
                (let ((node-text (treesit-agent-extract-node symbol-name)))
                  (when node-text
                    (push (format "==== %s ====\n%s" (file-relative-name file root) node-text) results)))))
          (error nil))))
    
    (if results
        (string-join (nreverse results) "\n\n")
      (format "No structural definition found for '%s' in %s" symbol-name root))))

(provide 'treesit-agent-tools-workspace)
