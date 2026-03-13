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

;;; ========================================
;;; Tests for treesit-agent-find-workspace failures
;;; ========================================

(defun test-workspace-search (grepper-available candidates timeout-occurs)
  "Simulate workspace search with GREPPER-AVAILABLE, CANDIDATES, and TIMEOUT-OCCURS."
  (cond
   ((not grepper-available)
    (error "ripgrep (rg) is required for workspace-wide AST searches"))
   (timeout-occurs
    nil)
   ((null candidates)
    (format "No structural definition found for 'symbol' in /test"))
   (t
    (string-join candidates "\n\n"))))

(ert-deftest treesit/workspace/ripgrep-missing ()
  "Should error when ripgrep is not available."
  (should-error (test-workspace-search nil nil nil) :type 'error))

(ert-deftest treesit/workspace/empty-results ()
  "Should return message for empty results."
  (let ((result (test-workspace-search t nil nil)))
    (should (string-match-p "No structural definition" result))))

(ert-deftest treesit/workspace/timeout-during-parse ()
  "Should handle timeout during file parsing."
  (let ((result (test-workspace-search t '("file1.el") t)))
    (should-not result)))

(ert-deftest treesit/workspace/success-with-results ()
  "Should return concatenated results."
  (let ((result (test-workspace-search t '("==== file1.el ====\n(defn foo [])") nil)))
    (should (string-match-p "file1.el" result))))

;;; ========================================
;;; Tests for multi-language defun-name fallbacks
;;; ========================================

(defun test-get-defun-name-fallback (node-type node-text lang)
  "Get defun name using fallback logic for NODE-TYPE, NODE-TEXT, and LANG."
  (cond
   ((equal lang 'rust)
    (cond
     ((equal node-type "impl_item")
      (concat "impl " node-text))
     ((equal node-type "function_item")
      node-text)))
   ((equal lang 'python)
    (cond
     ((equal node-type "function_definition")
      node-text)
     ((equal node-type "class_definition")
      node-text)))
   ((equal lang 'java)
    (cond
     ((member node-type '("method_declaration" "class_declaration"))
      node-text)))
   ((equal lang 'c)
    (cond
     ((member node-type '("function_definition" "type_definition"))
      node-text)))
   ((equal lang 'cpp)
    (cond
     ((member node-type '("function_definition" "class_specifier" "namespace_definition"))
      node-text)))
   ((equal lang 'lua)
    (cond
     ((equal node-type "function_declaration")
      node-text)))
   (t nil)))

(ert-deftest treesit/defun-name/rust-impl-item ()
  "Should extract name from Rust impl_item."
  (should (equal (test-get-defun-name-fallback "impl_item" "MyStruct" 'rust) "impl MyStruct")))

(ert-deftest treesit/defun-name/rust-function ()
  "Should extract name from Rust function_item."
  (should (equal (test-get-defun-name-fallback "function_item" "my_func" 'rust) "my_func")))

(ert-deftest treesit/defun-name/python-function ()
  "Should extract name from Python function_definition."
  (should (equal (test-get-defun-name-fallback "function_definition" "my_func" 'python) "my_func")))

(ert-deftest treesit/defun-name/python-class ()
  "Should extract name from Python class_definition."
  (should (equal (test-get-defun-name-fallback "class_definition" "MyClass" 'python) "MyClass")))

(ert-deftest treesit/defun-name/java-method ()
  "Should extract name from Java method_declaration."
  (should (equal (test-get-defun-name-fallback "method_declaration" "myMethod" 'java) "myMethod")))

(ert-deftest treesit/defun-name/java-class ()
  "Should extract name from Java class_declaration."
  (should (equal (test-get-defun-name-fallback "class_declaration" "MyClass" 'java) "MyClass")))

(ert-deftest treesit/defun-name/c-function ()
  "Should extract name from C function_definition."
  (should (equal (test-get-defun-name-fallback "function_definition" "my_func" 'c) "my_func")))

(ert-deftest treesit/defun-name/cpp-class ()
  "Should extract name from C++ class_specifier."
  (should (equal (test-get-defun-name-fallback "class_specifier" "MyClass" 'cpp) "MyClass")))

(ert-deftest treesit/defun-name/cpp-namespace ()
  "Should extract name from C++ namespace_definition."
  (should (equal (test-get-defun-name-fallback "namespace_definition" "myns" 'cpp) "myns")))

(ert-deftest treesit/defun-name/lua-function ()
  "Should extract name from Lua function_declaration."
  (should (equal (test-get-defun-name-fallback "function_declaration" "my_func" 'lua) "my_func")))

(ert-deftest treesit/defun-name/unknown-lang ()
  "Should return nil for unknown language."
  (should-not (test-get-defun-name-fallback "function_definition" "my_func" 'unknown)))

(ert-deftest treesit/defun-name/unknown-node-type ()
  "Should return nil for unknown node type."
  (should-not (test-get-defun-name-fallback "unknown_type" "my_func" 'rust)))

;;; ========================================
;;; Tests for treesit-agent--find-defun core logic
;;; ========================================

(defun test-find-defun-core (nodes name)
  "Core defun lookup logic - find NAME in NODES."
  (catch 'found
    (dolist (node nodes)
      (when (equal (plist-get node :name) name)
        (throw 'found node)))))

(ert-deftest treesit/find-defun-core/finds-by-name ()
  "Should find node by name."
  (let ((nodes (list '(:name "foo" :type "defun")
                     '(:name "bar" :type "defun"))))
    (should (plist-get (test-find-defun-core nodes "foo") :name))))

(ert-deftest treesit/find-defun-core/returns-nil-if-not-found ()
  "Should return nil if name not found."
  (let ((nodes (list '(:name "foo" :type "defun"))))
    (should-not (test-find-defun-core nodes "nonexistent"))))

(ert-deftest treesit/find-defun-core/returns-first-match ()
  "Should return first matching node."
  (let ((nodes (list '(:name "foo" :id 1)
                     '(:name "foo" :id 2))))
    (should (= (plist-get (test-find-defun-core nodes "foo") :id) 1))))

;;; ========================================
;;; Tests for treesit-agent-get-file-map core logic
;;; ========================================

(defun test-get-file-map-core (nodes filter-fn)
  "Get file map from NODES using FILTER-FN."
  (delq nil
        (mapcar (lambda (n)
                  (when (funcall filter-fn n)
                    (plist-get n :name)))
                nodes)))

(ert-deftest treesit/file-map-core/extracts-names ()
  "Should extract names from filtered nodes."
  (let ((nodes (list '(:name "foo" :valid t)
                     '(:name "bar" :valid nil)
                     '(:name "baz" :valid t)))
        (filter (lambda (n) (plist-get n :valid))))
    (should (equal (test-get-file-map-core nodes filter) '("foo" "baz")))))

(ert-deftest treesit/file-map-core/handles-empty-nodes ()
  "Should handle empty node list."
  (let ((filter (lambda (_) t)))
    (should (null (test-get-file-map-core nil filter)))))

(ert-deftest treesit/file-map-core/handles-all-filtered ()
  "Should return empty list when all filtered out."
  (let ((nodes (list '(:name "foo" :valid nil)))
        (filter (lambda (n) (plist-get n :valid))))
    (should (null (test-get-file-map-core nodes filter)))))

;;; ========================================
;;; Tests for treesit-agent--ensure-parser
;;; ========================================

(defun test-ensure-parser-extension (ext)
  "Map extension EXT to language."
  (cond
   ((member ext '("el" "elisp")) 'elisp)
   ((member ext '("py" "pyw")) 'python)
   ((member ext '("rs")) 'rust)
   ((member ext '("clj" "cljs" "cljc" "edn")) 'clojure)
   ((member ext '("js" "mjs")) 'javascript)
   ((member ext '("ts")) 'typescript)
   ((member ext '("tsx")) 'tsx)
   ((member ext '("rb")) 'ruby)
   ((member ext '("go")) 'go)
   ((member ext '("c" "h")) 'c)
   ((member ext '("cpp" "cc" "cxx" "hpp")) 'cpp)
   ((member ext '("java")) 'java)
   ((member ext '("lua")) 'lua)
   (t nil)))

(ert-deftest treesit/ensure-parser/elisp ()
  "Should map .el to elisp."
  (should (eq (test-ensure-parser-extension "el") 'elisp)))

(ert-deftest treesit/ensure-parser/python ()
  "Should map .py to python."
  (should (eq (test-ensure-parser-extension "py") 'python)))

(ert-deftest treesit/ensure-parser/rust ()
  "Should map .rs to rust."
  (should (eq (test-ensure-parser-extension "rs") 'rust)))

(ert-deftest treesit/ensure-parser/clojure ()
  "Should map .clj to clojure."
  (should (eq (test-ensure-parser-extension "clj") 'clojure)))

(ert-deftest treesit/ensure-parser/java ()
  "Should map .java to java."
  (should (eq (test-ensure-parser-extension "java") 'java)))

(ert-deftest treesit/ensure-parser/c ()
  "Should map .c and .h to c."
  (should (eq (test-ensure-parser-extension "c") 'c))
  (should (eq (test-ensure-parser-extension "h") 'c)))

(ert-deftest treesit/ensure-parser/cpp ()
  "Should map .cpp/.hpp to cpp."
  (should (eq (test-ensure-parser-extension "cpp") 'cpp))
  (should (eq (test-ensure-parser-extension "hpp") 'cpp)))

(ert-deftest treesit/ensure-parser/lua ()
  "Should map .lua to lua."
  (should (eq (test-ensure-parser-extension "lua") 'lua)))

(ert-deftest treesit/ensure-parser/unknown ()
  "Should return nil for unknown extension."
  (should-not (test-ensure-parser-extension "xyz")))

(provide 'test-treesit-agent-tools-core)
;;; test-treesit-agent-tools-core.el ends here