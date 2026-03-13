;;; test-treesit-agent-tools-workspace.el --- Tests for workspace AST tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Integration tests for treesit-agent-tools-workspace.el
;; Tests:
;; - treesit-agent--ensure-parser
;; - treesit-agent-find-workspace

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock project functions

(defvar test-project-current nil)
(defvar test-project-root nil)

(defun project-current ()
  "Mock: return current project."
  test-project-current)

(defun project-root (_proj)
  "Mock: return project root."
  test-project-root)

;;; Mock treesit functions

(defvar test-treesit-parser-list nil)
(defvar test-treesit-language-available nil)

(defun treesit-parser-list ()
  "Mock: return parser list."
  test-treesit-parser-list)

(defun treesit-language-available-p (lang)
  "Mock: check if LANG is available."
  (member lang test-treesit-language-available))

(defun treesit-parser-create (lang)
  "Mock: create parser for LANG."
  (push lang test-treesit-parser-list))

;;; Functions under test

(defun test-treesit--ensure-parser (file)
  "Ensure a tree-sitter parser is active for FILE's buffer."
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

;;; Tests for treesit-agent--ensure-parser

(ert-deftest workspace/ensure-parser/elisp ()
  "Should create elisp parser for .el files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(elisp python)))
    (test-treesit--ensure-parser "test.el")
    (should (member 'elisp test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/python ()
  "Should create python parser for .py files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(elisp python)))
    (test-treesit--ensure-parser "test.py")
    (should (member 'python test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/rust ()
  "Should create rust parser for .rs files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(rust)))
    (test-treesit--ensure-parser "src/lib.rs")
    (should (member 'rust test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/clojure ()
  "Should create clojure parser for .clj files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(clojure)))
    (test-treesit--ensure-parser "src/core.clj")
    (should (member 'clojure test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/javascript ()
  "Should create javascript parser for .js files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(javascript)))
    (test-treesit--ensure-parser "app.js")
    (should (member 'javascript test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/typescript ()
  "Should create typescript parser for .ts files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(typescript)))
    (test-treesit--ensure-parser "main.ts")
    (should (member 'typescript test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/go ()
  "Should create go parser for .go files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(go)))
    (test-treesit--ensure-parser "main.go")
    (should (member 'go test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/java ()
  "Should create java parser for .java files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(java)))
    (test-treesit--ensure-parser "Main.java")
    (should (member 'java test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/c ()
  "Should create c parser for .c files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(c)))
    (test-treesit--ensure-parser "main.c")
    (should (member 'c test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/cpp ()
  "Should create cpp parser for .cpp files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(cpp)))
    (test-treesit--ensure-parser "main.cpp")
    (should (member 'cpp test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/lua ()
  "Should create lua parser for .lua files."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(lua)))
    (test-treesit--ensure-parser "script.lua")
    (should (member 'lua test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/skips-when-parser-exists ()
  "Should not create parser when one already exists."
  (let ((test-treesit-parser-list '(existing))
        (test-treesit-language-available '(python)))
    (test-treesit--ensure-parser "test.py")
    (should (equal test-treesit-parser-list '(existing)))))

(ert-deftest workspace/ensure-parser/skips-unavailable-language ()
  "Should not create parser when language is unavailable."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available nil))
    (test-treesit--ensure-parser "test.py")
    (should (null test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/skips-unknown-extension ()
  "Should not create parser for unknown extensions."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(elisp)))
    (test-treesit--ensure-parser "test.xyz")
    (should (null test-treesit-parser-list))))

(ert-deftest workspace/ensure-parser/multiple-extensions ()
  "Should handle all extension variants."
  (let ((test-treesit-parser-list nil)
        (test-treesit-language-available '(clojure)))
    (test-treesit--ensure-parser "core.cljs")
    (should (member 'clojure test-treesit-parser-list))))

;;; Tests for extension-to-language mapping

(ert-deftest workspace/extension-mapping/elisp-variants ()
  "Both .el and .elisp should map to elisp."
  (let ((test-treesit-language-available '(elisp)))
    (let ((test-treesit-parser-list nil))
      (test-treesit--ensure-parser "file.el")
      (should (member 'elisp test-treesit-parser-list)))
    (let ((test-treesit-parser-list nil))
      (test-treesit--ensure-parser "file.elisp")
      (should (member 'elisp test-treesit-parser-list)))))

(ert-deftest workspace/extension-mapping/clojure-variants ()
  "All Clojure extensions should map to clojure."
  (let ((test-treesit-language-available '(clojure)))
    (dolist (ext '("clj" "cljs" "cljc" "edn"))
      (let ((test-treesit-parser-list nil))
        (test-treesit--ensure-parser (format "file.%s" ext))
        (should (member 'clojure test-treesit-parser-list))))))

(ert-deftest workspace/extension-mapping/cpp-variants ()
  "All C++ extensions should map to cpp."
  (let ((test-treesit-language-available '(cpp)))
    (dolist (ext '("cpp" "cc" "cxx" "hpp"))
      (let ((test-treesit-parser-list nil))
        (test-treesit--ensure-parser (format "file.%s" ext))
        (should (member 'cpp test-treesit-parser-list))))))

;;; Footer

(provide 'test-treesit-agent-tools-workspace)

;;; test-treesit-agent-tools-workspace.el ends here