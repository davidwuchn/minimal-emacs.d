;;; treesit-agent-tools.el --- Tree-sitter tools for AI agents -*- lexical-binding: t -*-

(require 'treesit)

(require 'imenu)

(defun treesit-agent--get-root ()
  "Get the tree-sitter root node for the current buffer."
  (when (and (treesit-available-p) (treesit-parser-list))
    (treesit-buffer-root-node)))

(defun treesit-agent--find-defun (name)
  "Find a defun node by NAME in the current buffer using tree-sitter."
  (let ((root (treesit-agent--get-root))
        (regexp (bound-and-true-p treesit-defun-type-regexp)))
    (when (and root regexp)
      (let* ((tree (treesit-induce-sparse-tree root regexp))
             (nodes (treesit-agent--flatten-sparse-tree tree))
             (match nil))
        (catch 'found
          (dolist (node nodes)
            (when (equal (treesit-defun-name node) name)
              (setq match node)
              (throw 'found t))))
        match))))

(defun treesit-agent--flatten-sparse-tree (tree)
  "Flatten a sparse tree produced by `treesit-induce-sparse-tree'."
  (if (not tree)
      nil
    (let ((node (car tree))
          (children (cdr tree))
          (res nil))
      (when node (push node res))
      (dolist (child children)
        (setq res (append res (treesit-agent--flatten-sparse-tree child))))
      res)))

(defun treesit-agent-get-file-map ()
  "Return a list of all defined function/class names in the current buffer.
Useful for giving an LLM a high-level overview of a file."
  (let ((root (treesit-agent--get-root))
        (regexp (bound-and-true-p treesit-defun-type-regexp)))
    (when (and root regexp)
      (let* ((tree (treesit-induce-sparse-tree root regexp))
             (nodes (treesit-agent--flatten-sparse-tree tree))
             (names nil))
        (dolist (node nodes)
          (let ((name (treesit-defun-name node)))
            (when name
              (push name names))))
        (nreverse names)))))

(defun treesit-agent-extract-node (name)
  "Extract the exact text of the defun node named NAME."
  (let ((node (treesit-agent--find-defun name)))
    (when node
      (treesit-node-text node t))))

(defun treesit-agent-replace-node (name new-text)
  "Replace the defun node named NAME with NEW-TEXT.
Returns t on success, nil if node not found.
Throws an error if the replacement results in invalid syntax."
  (let ((node (treesit-agent--find-defun name)))
    (if node
        (let ((start (treesit-node-start node))
              (end (treesit-node-end node)))
          (goto-char start)
          (delete-region start end)
          (insert new-text)
          ;; Validate syntax after replacement
          (let ((root (treesit-agent--get-root)))
            (when (and root (treesit-node-has-error-p root))
              ;; Emacs tree-sitter will automatically update the tree upon buffer edit.
              ;; If the new tree has an error, we signal it.
              (error "AST Replacement rejected: The new code introduced a syntax error (unbalanced parentheses or invalid grammar)")))
          t)
      nil)))

(defun treesit-agent-rename-symbol (old-name new-name)
  "Rename all exact matches of OLD-NAME to NEW-NAME in the current buffer structurally."
  (let ((root (treesit-agent--get-root))
        (matches nil))
    (when root
      (treesit-search-forward 
       root
       (lambda (node)
         (when (equal (treesit-node-text node t) old-name)
           (push node matches)))
       nil t)
      ;; Sort matches by start position descending (to replace bottom-up, preserving offsets)
      (setq matches (sort matches (lambda (a b) (> (treesit-node-start a) (treesit-node-start b)))))
      (let ((count 0))
        (dolist (node matches)
          (goto-char (treesit-node-start node))
          (delete-region (treesit-node-start node) (treesit-node-end node))
          (insert new-name)
          (cl-incf count))
        count))))

(provide 'treesit-agent-tools)
