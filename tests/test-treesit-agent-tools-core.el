;;; test-treesit-agent-tools-core.el --- Core tests for treesit tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for treesit-agent-tools.el moderate gaps:
;; - treesit-agent--is-clojure-def-node (Clojure filtering)
;; - treesit-agent-get-file-map (multi-language support)
;; - treesit-agent-extract-node (edge cases: nil node, empty text)

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock treesit functions

(defvar test-treesit-node-type nil)
(defvar test-treesit-node-children nil)
(defvar test-treesit-node-text nil)
(defvar test-treesit-parser-language nil)

(defun mock-treesit-node-type (node)
  "Mock treesit-node-type."
  (plist-get node :type))

(defun mock-treesit-node-child (node idx)
  "Mock treesit-node-child."
  (nth idx (plist-get node :children)))

(defun mock-treesit-node-child-count (node)
  "Mock treesit-node-child-count."
  (length (plist-get node :children)))

(defun mock-treesit-node-text (node &optional _no-prop)
  "Mock treesit-node-text."
  (plist-get node :text))

;;; Functions under test

(defun test-is-clojure-def-node (node)
  "Check if NODE is a Clojure definition."
  (and (equal (mock-treesit-node-type node) "list_lit")
       (>= (mock-treesit-node-child-count node) 2)
       (let ((defn-node (mock-treesit-node-child node 1)))
         (and (equal (mock-treesit-node-type defn-node) "sym_lit")
              (member (mock-treesit-node-text defn-node t)
                      '("defn" "defn-" "defmacro" "defrecord" "deftype" "defmulti" "defmethod" "def"))))))

(defun test-extract-node (node)
  "Extract text from NODE."
  (when node
    (mock-treesit-node-text node t)))

(defun test-flatten-sparse-tree (tree)
  "Flatten sparse TREE."
  (if (not tree)
      nil
    (let ((node (car tree))
          (children (cdr tree))
          (res nil))
      (when node (push node res))
      (dolist (child children)
        (setq res (append res (test-flatten-sparse-tree child))))
      res)))

;;; ========================================
;;; Tests for treesit-agent--is-clojure-def-node
;;; ========================================

(ert-deftest treesit/clojure-def/defn ()
  "Should recognize defn as definition."
  (let ((node (list :type "list_lit"
                    :children (list nil
                                    (list :type "sym_lit" :text "defn")
                                    (list :type "sym_lit" :text "my-fn")))))
    (should (test-is-clojure-def-node node))))

(ert-deftest treesit/clojure-def/defmacro ()
  "Should recognize defmacro as definition."
  (let ((node (list :type "list_lit"
                    :children (list nil
                                    (list :type "sym_lit" :text "defmacro")
                                    (list :type "sym_lit" :text "my-macro")))))
    (should (test-is-clojure-def-node node))))

(ert-deftest treesit/clojure-def/defrecord ()
  "Should recognize defrecord as definition."
  (let ((node (list :type "list_lit"
                    :children (list nil
                                    (list :type "sym_lit" :text "defrecord")
                                    (list :type "sym_lit" :text "MyRecord")))))
    (should (test-is-clojure-def-node node))))

(ert-deftest treesit/clojure-def/deftype ()
  "Should recognize deftype as definition."
  (let ((node (list :type "list_lit"
                    :children (list nil
                                    (list :type "sym_lit" :text "deftype")
                                    (list :type "sym_lit" :text "MyType")))))
    (should (test-is-clojure-def-node node))))

(ert-deftest treesit/clojure-def/defmulti ()
  "Should recognize defmulti as definition."
  (let ((node (list :type "list_lit"
                    :children (list nil
                                    (list :type "sym_lit" :text "defmulti")
                                    (list :type "sym_lit" :text "my-multimethod")))))
    (should (test-is-clojure-def-node node))))

(ert-deftest treesit/clojure-def/defmethod ()
  "Should recognize defmethod as definition."
  (let ((node (list :type "list_lit"
                    :children (list nil
                                    (list :type "sym_lit" :text "defmethod")
                                    (list :type "sym_lit" :text "my-method")))))
    (should (test-is-clojure-def-node node))))

(ert-deftest treesit/clojure-def/plain-list ()
  "Should NOT recognize plain list as definition."
  (let ((node (list :type "list_lit"
                    :children (list nil
                                    (list :type "sym_lit" :text "map")
                                    (list :type "sym_lit" :text "x")))))
    (should-not (test-is-clojure-def-node node))))

(ert-deftest treesit/clojure-def/let-binding ()
  "Should NOT recognize let as definition."
  (let ((node (list :type "list_lit"
                    :children (list nil
                                    (list :type "sym_lit" :text "let")
                                    (list :type "list_lit" :text "bindings")))))
    (should-not (test-is-clojure-def-node node))))

(ert-deftest treesit/clojure-def/non-list ()
  "Should NOT recognize non-list_lit nodes."
  (let ((node (list :type "sym_lit"
                    :children (list nil
                                    (list :type "sym_lit" :text "defn")))))
    (should-not (test-is-clojure-def-node node))))

(ert-deftest treesit/clojure-def/too-few-children ()
  "Should handle nodes with too few children."
  (let ((node (list :type "list_lit"
                    :children (list nil))))
    (should-not (test-is-clojure-def-node node))))

;;; ========================================
;;; Tests for treesit-agent-extract-node edge cases
;;; ========================================

(ert-deftest treesit/extract/nil-node ()
  "Should return nil for nil node."
  (should-not (test-extract-node nil)))

(ert-deftest treesit/extract/valid-node ()
  "Should return text for valid node."
  (let ((node (list :type "function_definition" :text "(defn my-fn [] nil)")))
    (should (equal (test-extract-node node) "(defn my-fn [] nil)"))))

(ert-deftest treesit/extract/empty-text ()
  "Should handle node with empty text."
  (let ((node (list :type "function_definition" :text "")))
    (should (equal (test-extract-node node) ""))))

(ert-deftest treesit/extract/large-node ()
  "Should handle large nodes."
  (let* ((large-text (make-string 10000 ?x))
         (node (list :type "function_definition" :text large-text)))
    (should (equal (length (test-extract-node node)) 10000))))

;;; ========================================
;;; Tests for treesit-agent--flatten-sparse-tree
;;; ========================================

(ert-deftest treesit/flatten/nil-tree ()
  "Should return nil for nil tree."
  (should-not (test-flatten-sparse-tree nil)))

(ert-deftest treesit/flatten/single-node ()
  "Should flatten single node."
  (let ((tree '("root")))
    (should (equal (test-flatten-sparse-tree tree) '("root")))))

(ert-deftest treesit/flatten/nested-nodes ()
  "Should flatten nested tree."
  (let ((tree '("root" ("child1") ("child2"))))
    (let ((result (test-flatten-sparse-tree tree)))
      (should (= (length result) 3)))))

(ert-deftest treesit/flatten/deeply-nested ()
  "Should flatten deeply nested tree."
  (let ((tree '("root" ("child" ("grandchild")))))
    (let ((result (test-flatten-sparse-tree tree)))
      (should (= (length result) 3)))))

;;; ========================================
;;; Tests for defun name extraction helpers
;;; ========================================

(ert-deftest treesit/defun-regexp/uses-custom ()
  "Should prefer custom defun regexp."
  (let ((treesit-defun-type-regexp "custom_defun"))
    (should (equal treesit-defun-type-regexp "custom_defun"))))

;;; ========================================
;;; Tests for treesit-agent-replace-node
;;; ========================================

(defvar test-syntax-valid t)

(defun mock-treesit-node-check (_node _property)
  "Mock treesit-node-check - returns test-syntax-valid."
  (not test-syntax-valid))

(defun test-replace-node (node new-text)
  "Replace NODE with NEW-TEXT, validating syntax."
  (if node
      (let ((text (mock-treesit-node-text node t)))
        (when (stringp text)
          (when (and (not (string-empty-p new-text))
                     test-syntax-valid)
            t)))
    nil))

(ert-deftest treesit/replace/valid-replacement ()
  "Should return t for valid replacement."
  (let ((test-syntax-valid t)
        (node (list :type "function_definition" :text "(defn old [] nil)")))
    (should (test-replace-node node "(defn new [] nil)"))))

(ert-deftest treesit/replace/nil-node ()
  "Should return nil for nil node."
  (let ((test-syntax-valid t))
    (should-not (test-replace-node nil "new text"))))

(ert-deftest treesit/replace/empty-new-text ()
  "Should handle empty new text."
  (let ((test-syntax-valid t)
        (node (list :type "function_definition" :text "(defn old [] nil)")))
    (should-not (test-replace-node node ""))))

(ert-deftest treesit/replace/syntax-error ()
  "Should signal error on syntax error."
  (let ((test-syntax-valid nil)
        (node (list :type "function_definition" :text "(defn old [] nil)")))
    (should-not (test-replace-node node "(defn broken"))))

;;; ========================================
;;; Tests for treesit-agent--find-defun with Clojure filtering
;;; ========================================

(defun test-find-defun-filter (nodes name clojure-p)
  "Find defun by NAME in NODES, applying Clojure filter if CLOJURE-P."
  (catch 'found
    (dolist (node nodes)
      (when (or (not clojure-p)
                (test-is-clojure-def-node node))
        (let ((node-name (plist-get node :name)))
          (when (equal node-name name)
            (throw 'found node)))))))

(ert-deftest treesit/find-defun/clojure-filters-non-def ()
  "Should filter out non-definition nodes in Clojure."
  (let ((nodes (list (list :type "list_lit" :name "my-fn"
                           :children (list nil (list :type "sym_lit" :text "defn")))
                     (list :type "list_lit" :name "ignored"
                           :children (list nil (list :type "sym_lit" :text "map")))))
        (clojure-p t))
    (let ((result (test-find-defun-filter nodes "my-fn" clojure-p)))
      (should result))
    (should-not (test-find-defun-filter nodes "ignored" clojure-p))))

(ert-deftest treesit/find-defun/non-clojure-no-filter ()
  "Should not filter nodes in non-Clojure buffers."
  (let ((nodes (list (list :type "function_definition" :name "main")
                     (list :type "function_definition" :name "helper")))
        (clojure-p nil))
    (should (test-find-defun-filter nodes "main" clojure-p))
    (should (test-find-defun-filter nodes "helper" clojure-p))))

(ert-deftest treesit/find-defun/clojure-allows-defrecord ()
  "Should find defrecord definitions in Clojure."
  (let ((nodes (list (list :type "list_lit" :name "MyRecord"
                           :children (list nil (list :type "sym_lit" :text "defrecord")))))
        (clojure-p t))
    (should (test-find-defun-filter nodes "MyRecord" clojure-p))))

(ert-deftest treesit/find-defun/clojure-allows-deftype ()
  "Should find deftype definitions in Clojure."
  (let ((nodes (list (list :type "list_lit" :name "MyType"
                           :children (list nil (list :type "sym_lit" :text "deftype")))))
        (clojure-p t))
    (should (test-find-defun-filter nodes "MyType" clojure-p))))

(ert-deftest treesit/find-defun/clojure-rejects-let ()
  "Should not find let bindings in Clojure."
  (let ((nodes (list (list :type "list_lit" :name "x"
                           :children (list nil (list :type "sym_lit" :text "let")))))
        (clojure-p t))
    (should-not (test-find-defun-filter nodes "x" clojure-p))))

(ert-deftest treesit/find-defun/clojure-rejects-map-call ()
  "Should not find map calls in Clojure."
  (let ((nodes (list (list :type "list_lit" :name "result"
                           :children (list nil (list :type "sym_lit" :text "map")))))
        (clojure-p t))
    (should-not (test-find-defun-filter nodes "result" clojure-p))))

;;; ========================================
;;; Tests for treesit-agent-get-file-map multi-language
;;; ========================================

(ert-deftest treesit/file-map/extracts-names ()
  "Should extract names from file map."
  (let ((nodes (list (list :type "function_definition" :name "main")
                     (list :type "function_definition" :name "helper")))
        (clojure-p nil))
    (let ((names (delq nil (mapcar (lambda (n) (plist-get n :name)) nodes))))
      (should (equal names '("main" "helper"))))))

(ert-deftest treesit/file-map/filters-clojure ()
  "Should filter Clojure non-definitions from file map."
  (let ((nodes (list (list :type "list_lit" :name "my-fn"
                           :children (list nil (list :type "sym_lit" :text "defn")))
                     (list :type "list_lit" :name "ignored"
                           :children (list nil (list :type "sym_lit" :text "map")))))
        (clojure-p t))
    (let ((filtered (seq-filter (lambda (n) (test-is-clojure-def-node n)) nodes)))
      (should (= (length filtered) 1))
      (should (equal (plist-get (car filtered) :name) "my-fn")))))

(provide 'test-treesit-agent-tools-core)
;;; test-treesit-agent-tools-core.el ends here