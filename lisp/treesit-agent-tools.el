;;; treesit-agent-tools.el --- Tree-sitter tools for AI agents -*- lexical-binding: t -*-

(require 'treesit)

(require 'imenu)

(defun treesit-agent--get-root ()
  "Get the tree-sitter root node for the current buffer."
  (when (and (treesit-available-p) (treesit-parser-list))
    (treesit-buffer-root-node)))

(defun treesit-agent--get-defun-regexp ()
  "Get the appropriate defun type regexp for the current buffer.
Provides fallback regexps for languages that don't set treesit-defun-type-regexp."
  (or (bound-and-true-p treesit-defun-type-regexp)
      ;; Fallback for Elisp (regexp matches node type string, not a query)
      (and (derived-mode-p 'emacs-lisp-mode 'emacs-lisp-ts-mode)
           "function_definition")
      ;; Fallback for Clojure family (check parser language since mode might not be set)
      (and (treesit-parser-list)
           (cl-find-if (lambda (p) (eq (treesit-parser-language p) 'clojure)) (treesit-parser-list))
           "list_lit")))

(defun treesit-agent--get-defun-name (node)
  "Get the name of a defun NODE.
Provides fallback for languages where treesit-defun-name returns nil."
  (or (and (fboundp 'treesit-defun-name) (treesit-defun-name node))
      ;; Fallback for Elisp: get the name child node (field name must be string)
      (let ((name-node (treesit-node-child-by-field-name node "name")))
        (when name-node
          (treesit-node-text name-node t)))
      ;; Fallback for Clojure: list_lit nodes have ( defn name ... ) structure
      (and (equal (treesit-node-type node) "list_lit")
           (>= (treesit-node-child-count node) 3)
           (let* ((defn-node (treesit-node-child node 1))
                  (name-node (treesit-node-child node 2)))
             (when (and defn-node name-node
                        (equal (treesit-node-type defn-node) "sym_lit")
                        (member (treesit-node-text defn-node t) '("defn" "defn-" "defmacro" "defrecord" "deftype" "defmulti" "defmethod")))
               ;; For defrecord/deftype, the name is the symbol after defn
               (treesit-node-text name-node t))))))

(defun treesit-agent--find-defun (name)
  "Find a defun node by NAME in the current buffer using tree-sitter."
  (let ((root (treesit-agent--get-root))
        (regexp (treesit-agent--get-defun-regexp)))
    (when (and root regexp)
      (let* ((tree (treesit-induce-sparse-tree root regexp))
             (nodes (treesit-agent--flatten-sparse-tree tree))
             (match nil))
        (catch 'found
          (dolist (node nodes)
            ;; Filter out non-definition nodes for Clojure
            (when (or (not (treesit-agent--clojure-parser-p))
                      (treesit-agent--is-clojure-def-node node))
              (when (equal (treesit-agent--get-defun-name node) name)
                (setq match node)
                (throw 'found t)))))
        match))))

(defun treesit-agent--clojure-parser-p ()
  "Check if current buffer has a Clojure tree-sitter parser."
  (and (treesit-parser-list)
       (cl-find-if (lambda (p) (eq (treesit-parser-language p) 'clojure)) (treesit-parser-list))))

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

(defun treesit-agent--is-clojure-def-node (node)
  "Check if NODE is a Clojure definition (defn, defmacro, defrecord, etc)."
  (and (equal (treesit-node-type node) "list_lit")
       (>= (treesit-node-child-count node) 2)
       (let ((defn-node (treesit-node-child node 1)))
         (and (equal (treesit-node-type defn-node) "sym_lit")
              (member (treesit-node-text defn-node t)
                      '("defn" "defn-" "defmacro" "defrecord" "deftype" "defmulti" "defmethod" "def"))))))

(defun treesit-agent-get-file-map ()
  "Return a list of all defined function/class names in the current buffer.
 Useful for giving an LLM a high-level overview of a file."
  (let ((root (treesit-agent--get-root))
        (regexp (treesit-agent--get-defun-regexp)))
    (when (and root regexp)
      (let* ((tree (treesit-induce-sparse-tree root regexp))
             (nodes (treesit-agent--flatten-sparse-tree tree))
             (names nil))
        (dolist (node nodes)
          ;; Filter out non-definition nodes for Clojure
          (when (or (not (treesit-agent--clojure-parser-p))
                    (treesit-agent--is-clojure-def-node node))
            (let ((name (treesit-agent--get-defun-name node)))
              (when name
                (push name names)))))
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
          ;; Validate syntax after replacement using Emacs 30 compatible function
          (let ((root (treesit-agent--get-root)))
            (when (and root (treesit-node-check root 'has-error))
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
