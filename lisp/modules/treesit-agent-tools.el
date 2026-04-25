;;; treesit-agent-tools.el --- Tree-sitter tools for AI agents -*- no-byte-compile: t; lexical-binding: t; -*-

(require 'treesit)

(require 'imenu)

(defun treesit-agent--get-root ()
  "Get the tree-sitter root node for the current buffer."
  (when (and (treesit-available-p) (treesit-parser-list))
    (treesit-buffer-root-node)))

(defun treesit-agent--has-parser-language-p (lang)
  "Check if current buffer has a tree-sitter parser for LANG."
  (and (treesit-parser-list)
       (cl-find-if (lambda (p) (eq (treesit-parser-language p) lang)) (treesit-parser-list))))

(defun treesit-agent--get-defun-regexp ()
  "Get the appropriate defun type regexp for the current buffer.
Provides fallback regexps for languages that don't set treesit-defun-type-regexp."
  (or (bound-and-true-p treesit-defun-type-regexp)
      ;; Fallback for Elisp (regexp matches node type string, not a query)
      (and (derived-mode-p 'emacs-lisp-mode 'emacs-lisp-ts-mode)
           "function_definition")
      ;; Fallback for Clojure family (check parser language since mode might not be set)
      (and (treesit-agent--has-parser-language-p 'clojure)
           "list_lit")
      ;; Fallback for Rust (function, struct, enum, impl, trait, mod)
      (and (treesit-agent--has-parser-language-p 'rust)
           "\\(?:function\\|struct\\|enum\\|impl\\|trait\\|mod\\)_item")
      ;; Fallback for Python (class, function — matches inside decorated_definition too)
      (and (treesit-agent--has-parser-language-p 'python)
           "\\(?:class\\|function\\)_definition")
      ;; Fallback for Java (class, method, constructor, enum, interface, record)
      (and (treesit-agent--has-parser-language-p 'java)
           "\\(?:class\\|method\\|constructor\\|enum\\|interface\\|record\\)_declaration")
      ;; Fallback for C (function, struct, enum, union, type_definition)
      (and (treesit-agent--has-parser-language-p 'c)
           "\\(?:function_definition\\|struct_specifier\\|enum_specifier\\|union_specifier\\|type_definition\\)")
      ;; Fallback for C++ (adds class_specifier and namespace_definition)
      (and (treesit-agent--has-parser-language-p 'cpp)
           "\\(?:function_definition\\|class_specifier\\|struct_specifier\\|enum_specifier\\|union_specifier\\|namespace_definition\\|type_definition\\)")
      ;; Fallback for Lua (function_declaration only — name field handles extraction)
      (and (treesit-agent--has-parser-language-p 'lua)
           "function_declaration")))

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
               (treesit-node-text name-node t))))
      ;; Fallback for Rust impl_item: "impl Type" or "impl Trait for Type"
      (and (equal (treesit-node-type node) "impl_item")
           (let ((trait-node (treesit-node-child-by-field-name node "trait"))
                 (type-node (treesit-node-child-by-field-name node "type")))
             (cond
              ((and trait-node type-node)
               (concat (treesit-node-text trait-node t) " for " (treesit-node-text type-node t)))
              (type-node
               (treesit-node-text type-node t)))))
      ;; Fallback for C/C++ function_definition: declarator.declarator gives just the name
      (and (equal (treesit-node-type node) "function_definition")
           (let* ((decl (treesit-node-child-by-field-name node "declarator"))
                  (inner (and decl (treesit-node-child-by-field-name decl "declarator"))))
             (when inner (treesit-node-text inner t))))
      ;; Fallback for C/C++ type_definition: declarator field is the typedef name
      (and (equal (treesit-node-type node) "type_definition")
           (let ((decl (treesit-node-child-by-field-name node "declarator")))
             (when decl (treesit-node-text decl t))))))

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
  (treesit-agent--has-parser-language-p 'clojure))

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

(provide 'treesit-agent-tools)
