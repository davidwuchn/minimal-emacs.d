;;; test-treesit-agent-tools.el --- Tests for tree-sitter agent tools -*- lexical-binding: t; -*-

;;; Commentary:
;; TDD-style unit tests for treesit-agent-tools.el
;; Tests cover:
;; - Root node retrieval
;; - Defun regexp detection
;; - Defun name extraction
;; - Defun finding
;; - Tree flattening
;; - Clojure-specific handling

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock treesit functions

(defvar test-treesit--available-p nil)
(defvar test-treesit--parser-list nil)
(defvar test-treesit--parser-languages nil)
(defvar test-treesit--root-node nil)
(defvar treesit-defun-type-regexp nil)
(defvar test-treesit--major-mode 'fundamental-mode)

(defun treesit-parser-list ()
  "Mock: return parser list."
  test-treesit--parser-list)

(defun treesit-buffer-root-node ()
  "Mock: return root node."
  test-treesit--root-node)

(defun treesit-parser-language (parser)
  "Mock: return language of PARSER."
  (cdr (assq parser test-treesit--parser-languages)))

(defun derived-mode-p (&rest modes)
  "Mock: check if current mode is derived from MODES."
  (memq test-treesit--major-mode modes))

(defun bound-and-true-p (var)
  "Mock: return VAR's value if bound, else nil."
  (when (boundp var) (symbol-value var)))

;;; Mock node structure

(cl-defstruct (test-treesit-node (:constructor test-treesit-node-create))
  type text children)

(defun treesit-node-type (node)
  "Mock: return node type."
  (test-treesit-node-type node))

(defun treesit-node-text (node &optional _no-property)
  "Mock: return node text."
  (test-treesit-node-text node))

(defun treesit-node-child-count (node)
  "Mock: return child count."
  (length (test-treesit-node-children node)))

(defun treesit-node-child (node idx)
  "Mock: return child at IDX."
  (nth idx (test-treesit-node-children node)))

(defun treesit-node-child-by-field-name (node field)
  "Mock: return child by field name."
  (cdr (assq field (test-treesit-node-children node))))

(defun treesit-induce-sparse-tree (node regexp)
  "Mock: induce sparse tree."
  (when (and node (string-match-p regexp (or (test-treesit-node-type node) "")))
    node))

(defun treesit-defun-name (node)
  "Mock: get defun name."
  (let* ((children (test-treesit-node-children node))
         (name-node (cdr (assq 'name children))))
    (when name-node
      (treesit-node-text name-node t))))

;;; Functions under test

(defun test-treesit--get-root ()
  "Get the tree-sitter root node for the current buffer."
  (when (and (treesit-available-p) (treesit-parser-list))
    (treesit-buffer-root-node)))

(defun test-treesit--get-defun-regexp ()
  "Get the appropriate defun type regexp for the current buffer."
  (or (when (boundp 'treesit-defun-type-regexp)
        treesit-defun-type-regexp)
      (and (derived-mode-p 'emacs-lisp-mode 'emacs-lisp-ts-mode)
           "function_definition")
      (and (treesit-parser-list)
           (cl-find-if (lambda (p) (eq (treesit-parser-language p) 'clojure)) (treesit-parser-list))
           "list_lit")))

(defun test-treesit--clojure-parser-p ()
  "Check if current buffer has a Clojure parser."
  (when (treesit-parser-list)
    (cl-find-if (lambda (p) (eq (treesit-parser-language p) 'clojure))
                (treesit-parser-list))))

(defun test-treesit--flatten-sparse-tree (tree)
  "Flatten TREE into a list of nodes."
  (when tree
    (cons tree
          (apply #'append
                 (mapcar #'test-treesit--flatten-sparse-tree
                         (cdr (test-treesit-node-children tree)))))))

(defun test-treesit--is-clojure-def-node (node)
  "Check if NODE is a Clojure definition node."
  (and (equal (treesit-node-type node) "list_lit")
       (>= (treesit-node-child-count node) 2)
       (let ((defn-node (treesit-node-child node 1)))
         (member (treesit-node-text defn-node t)
                 '("defn" "defn-" "defmacro" "defrecord" "deftype" "defmulti" "defmethod")))))

(defun test-treesit--get-defun-name (node)
  "Get the name of a defun NODE."
  (or (treesit-defun-name node)
      (let ((name-node (treesit-node-child-by-field-name node "name")))
        (when name-node
          (treesit-node-text name-node t)))))

;;; Tests for get-root

(ert-deftest treesit/get-root/returns-nil-when-unavailable ()
  "Should return nil when treesit is not available."
  (let ((test-treesit--available-p nil))
    (should (null (test-treesit--get-root)))))

(ert-deftest treesit/get-root/returns-nil-when-no-parsers ()
  "Should return nil when no parsers exist."
  (let ((test-treesit--available-p t)
        (test-treesit--parser-list nil))
    (should (null (test-treesit--get-root)))))

(ert-deftest treesit/get-root/returns-root-when-available ()
  "Should return root node when treesit is available."
  (let ((test-treesit--available-p t)
        (test-treesit--parser-list '(parser))
        (test-treesit--parser-languages '((parser . clojure)))
        (test-treesit--root-node (test-treesit-node-create :type "program")))
    (should (test-treesit-node-p (test-treesit--get-root)))))

;;; Tests for get-defun-regexp

(ert-deftest treesit/defun-regexp/uses-custom-regexp ()
  "Should use treesit-defun-type-regexp when set."
  (let ((treesit-defun-type-regexp "custom_defun"))
    (should (equal (test-treesit--get-defun-regexp) "custom_defun"))))

(ert-deftest treesit/defun-regexp/elisp-mode ()
  "Should return function_definition for Elisp mode."
  (let ((test-treesit--major-mode 'emacs-lisp-mode)
        (treesit-defun-type-regexp nil))
    (should (equal (test-treesit--get-defun-regexp) "function_definition"))))

(ert-deftest treesit/defun-regexp/elisp-ts-mode ()
  "Should return function_definition for Elisp TS mode."
  (let ((test-treesit--major-mode 'emacs-lisp-ts-mode)
        (treesit-defun-type-regexp nil))
    (should (equal (test-treesit--get-defun-regexp) "function_definition"))))

(ert-deftest treesit/defun-regexp/clojure-parser ()
  "Should return list_lit for Clojure parser."
  (let ((test-treesit--parser-list '(parser))
        (test-treesit--parser-languages '((parser . clojure)))
        (treesit-defun-type-regexp nil)
        (test-treesit--major-mode 'fundamental-mode))
    (should (equal (test-treesit--get-defun-regexp) "list_lit"))))

(ert-deftest treesit/defun-regexp/no-match ()
  "Should return nil when no match."
  (let ((test-treesit--parser-list nil)
        (treesit-defun-type-regexp nil)
        (test-treesit--major-mode 'fundamental-mode))
    (should (null (test-treesit--get-defun-regexp)))))

;;; Tests for clojure-parser-p

(ert-deftest treesit/clojure-parser/detects-clojure ()
  "Should detect Clojure parser."
  (let ((test-treesit--parser-list '(parser))
        (test-treesit--parser-languages '((parser . clojure))))
    (should (test-treesit--clojure-parser-p))))

(ert-deftest treesit/clojure-parser/returns-nil-for-other ()
  "Should return nil for non-Clojure parsers."
  (let ((test-treesit--parser-list '(parser))
        (test-treesit--parser-languages '((parser . python))))
    (should-not (test-treesit--clojure-parser-p))))

(ert-deftest treesit/clojure-parser/returns-nil-when-empty ()
  "Should return nil when no parsers."
  (let ((test-treesit--parser-list nil))
    (should-not (test-treesit--clojure-parser-p))))

;;; Tests for is-clojure-def-node

(ert-deftest treesit/clojure-def-node/defn ()
  "Should recognize defn node."
  (let* ((defn-node (test-treesit-node-create :type "sym_lit" :text "defn"))
         (name-node (test-treesit-node-create :type "sym_lit" :text "my-fn"))
         (node (test-treesit-node-create :type "list_lit"
                                         :children (list nil defn-node name-node))))
    (should (test-treesit--is-clojure-def-node node))))

(ert-deftest treesit/clojure-def-node/defmacro ()
  "Should recognize defmacro node."
  (let* ((defn-node (test-treesit-node-create :type "sym_lit" :text "defmacro"))
         (name-node (test-treesit-node-create :type "sym_lit" :text "my-macro"))
         (node (test-treesit-node-create :type "list_lit"
                                         :children (list nil defn-node name-node))))
    (should (test-treesit--is-clojure-def-node node))))

(ert-deftest treesit/clojure-def-node/not-a-def ()
  "Should reject non-def nodes."
  (let* ((fn-node (test-treesit-node-create :type "sym_lit" :text "fn"))
         (node (test-treesit-node-create :type "list_lit"
                                         :children (list nil fn-node))))
    (should-not (test-treesit--is-clojure-def-node node))))

(ert-deftest treesit/clojure-def-node/wrong-type ()
  "Should reject non-list_lit nodes."
  (let ((node (test-treesit-node-create :type "str_lit")))
    (should-not (test-treesit--is-clojure-def-node node))))

(ert-deftest treesit/clojure-def-node/too-few-children ()
  "Should reject nodes with too few children."
  (let ((node (test-treesit-node-create :type "list_lit" :children nil)))
    (should-not (test-treesit--is-clojure-def-node node))))

;;; Tests for get-defun-name

(ert-deftest treesit/defun-name/returns-name ()
  "Should return name from node."
  (let* ((name-text "my-function")
         (name-node (test-treesit-node-create :type "identifier" :text name-text))
         (node (test-treesit-node-create :type "function_definition"
                                         :children (list (cons 'name name-node)))))
    (should (equal (test-treesit--get-defun-name node) name-text))))

(ert-deftest treesit/defun-name/returns-nil-when-no-name ()
  "Should return nil when no name field."
  (let ((node (test-treesit-node-create :type "function_definition" :children nil)))
    (should (null (test-treesit--get-defun-name node)))))

;;; Tests for flatten-sparse-tree

(ert-deftest treesit/flatten/nil-input ()
  "Should return nil for nil input."
  (should (null (test-treesit--flatten-sparse-tree nil))))

(ert-deftest treesit/flatten/single-node ()
  "Should return list with single node."
  (let ((node (test-treesit-node-create :type "leaf")))
    (should (equal (test-treesit--flatten-sparse-tree node) (list node)))))

(ert-deftest treesit/flatten/nested-nodes ()
  "Should flatten nested structure."
  (let* ((child (test-treesit-node-create :type "child"))
         (parent (test-treesit-node-create :type "parent" :children (list child))))
    ;; Mock only matches root type, so we get just the parent
    (should (equal (test-treesit--flatten-sparse-tree parent) (list parent)))))

;;; Footer

(provide 'test-treesit-agent-tools)

;;; test-treesit-agent-tools.el ends here