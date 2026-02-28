;;; treesit-local-xref.el --- Tree-sitter file-local xref backend -*- lexical-binding: t -*-

(require 'xref)
(require 'treesit)

(defun treesit-local-xref-backend ()
  "Tree-sitter file-local xref backend.
Provides file-local navigation using tree-sitter AST nodes."
  (when (and (treesit-available-p)
             (bound-and-true-p treesit-defun-type-regexp))
    'treesit-local))

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql treesit-local)))
  (let ((bounds (bounds-of-thing-at-point 'symbol)))
    (when bounds
      (buffer-substring-no-properties (car bounds) (cdr bounds)))))

(defun treesit-local-xref--flatten-sparse-tree (tree)
  "Flatten a sparse tree produced by `treesit-induce-sparse-tree'."
  (if (not tree)
      nil
    (let ((node (car tree))
          (children (cdr tree))
          (res nil))
      (when node (push node res))
      (dolist (child children)
        (setq res (append res (treesit-local-xref--flatten-sparse-tree child))))
      res)))

(cl-defmethod xref-backend-definitions ((_backend (eql treesit-local)) identifier)
  (let* ((tree (treesit-induce-sparse-tree (treesit-buffer-root-node) treesit-defun-type-regexp))
         (nodes (treesit-local-xref--flatten-sparse-tree tree))
         (matches nil))
    (dolist (node nodes)
      (when (equal (treesit-defun-name node) identifier)
        (let* ((pos (treesit-node-start node))
               (loc (xref-make-buffer-location (current-buffer) pos)))
          (push (xref-make-match identifier loc 0) matches))))
    (nreverse matches)))

(provide 'treesit-local-xref)
