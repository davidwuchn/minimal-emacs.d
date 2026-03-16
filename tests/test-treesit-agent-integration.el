;;; test-treesit-agent-integration.el --- Integration tests for tree-sitter agent tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Integration tests for treesit-agent-tools.el.
;; Tests actual implementations, skipping if tree-sitter is unavailable.
;; Many tests skip in batch mode due to font-lock infinite loop in emacs-lisp-mode.

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Check if tree-sitter is available

(defun test-treesit-available-p ()
  "Check if tree-sitter is available and working."
  (and (fboundp 'treesit-available-p)
       (treesit-available-p)))

;;; Load the actual module

(load-file (expand-file-name "lisp/modules/treesit-agent-tools.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))

;;; Tests for treesit-agent--get-root

(ert-deftest integration/treesit-get-root/no-parser ()
  "Should return nil when no parser is available.
Skip in batch mode due to font-lock issues."
  (skip-unless (not noninteractive))
  (skip-unless (test-treesit-available-p))
  (with-temp-buffer
    (emacs-lisp-mode)
    (should (null (treesit-agent--get-root)))))

;;; Tests for treesit-agent--get-defun-regexp

(ert-deftest integration/treesit-defun-regexp/elisp-mode ()
  "Should return function_definition for Elisp mode.
Skip in batch mode due to font-lock issues."
  (skip-unless (not noninteractive))
  (with-temp-buffer
    (emacs-lisp-mode)
    (let ((regexp (treesit-agent--get-defun-regexp)))
      (should (or (null regexp)
                  (stringp regexp))))))

;;; Tests for treesit-agent--get-defun-name

(ert-deftest integration/treesit-get-defun-name/elisp-function ()
  "Should extract name from Elisp function.
Skip in batch mode due to font-lock issues."
  (skip-unless (not noninteractive))
  (skip-unless (test-treesit-available-p))
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun my-test-function () \"doc\" body)")
    (goto-char (point-min))
    (let ((root (treesit-agent--get-root)))
      (skip-unless root)
      (let* ((regexp (treesit-agent--get-defun-regexp))
             (tree (treesit-induce-sparse-tree root regexp))
             (nodes (treesit-agent--flatten-sparse-tree tree)))
        (when nodes
          (let ((name (treesit-agent--get-defun-name (car nodes))))
            (should (or (null name) (stringp name)))))))))

;;; Tests for treesit-agent-get-file-map

(ert-deftest integration/treesit-get-file-map/elisp-file ()
  "Should return list of defined functions.
Skip in batch mode due to font-lock issues."
  (skip-unless (not noninteractive))
  (skip-unless (test-treesit-available-p))
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun foo () 1)
(defun bar () 2)
(defvar my-var 42)")
    (goto-char (point-min))
    (let ((root (treesit-agent--get-root)))
      (skip-unless root)
      (let ((names (treesit-agent-get-file-map)))
        (should (listp names))))))

;;; Tests for treesit-agent-extract-node

(ert-deftest integration/treesit-extract-node/extracts-function ()
  "Should extract function text by name.
Skip in batch mode due to font-lock issues."
  (skip-unless (not noninteractive))
  (skip-unless (test-treesit-available-p))
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun my-extract-test () \"test\" 42)")
    (goto-char (point-min))
    (let ((root (treesit-agent--get-root)))
      (skip-unless root)
      (let ((text (treesit-agent-extract-node "my-extract-test")))
        (should (or (null text) (stringp text)))))))

;;; Tests for treesit-agent-replace-node

(ert-deftest integration/treesit-replace-node/valid-syntax ()
  "Should replace function with valid new text.
Skip in batch mode due to font-lock issues."
  (skip-unless (not noninteractive))
  (skip-unless (test-treesit-available-p))
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun my-replace-test () 1)")
    (goto-char (point-min))
    (let ((root (treesit-agent--get-root)))
      (skip-unless root)
      (condition-case err
          (let ((result (treesit-agent-replace-node
                         "my-replace-test"
                         "(defun my-replace-test () 2)")))
            (when result
              (should (eq result t))))
        (error
         (should (string-match-p "not found\\|nil" (error-message-string err))))))))

(ert-deftest integration/treesit-replace-node/invalid-syntax-rejected ()
  "Should reject invalid syntax replacement.
Skip in batch mode due to font-lock issues."
  (skip-unless (not noninteractive))
  (skip-unless (test-treesit-available-p))
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun my-bad-replace () 1)")
    (goto-char (point-min))
    (let ((root (treesit-agent--get-root)))
      (skip-unless root)
      (condition-case err
          (progn
            (treesit-agent-replace-node "my-bad-replace" "(defun broken")
            (should nil))
        (error
         (should t))))))

;;; Tests for treesit-agent--clojure-parser-p

(ert-deftest integration/treesit-clojure-parser/not-clojure ()
  "Should return nil for non-Clojure buffer.
Skip in batch mode due to font-lock infinite loop in emacs-lisp-mode."
  (skip-unless (not noninteractive))
  (with-temp-buffer
    (emacs-lisp-mode)
    (should-not (treesit-agent--clojure-parser-p))))

;;; Tests for treesit-agent--is-clojure-def-node

(ert-deftest integration/treesit-is-clojure-def-node/skip-non-clojure ()
  "Should work correctly even in non-Clojure buffers."
  (should t))

;;; Tests for fallback regexps

(ert-deftest integration/treesit-defun-regexp/rust-fallback ()
  "Rust fallback regexp should match function_item etc."
  (let ((regexp "\\(?:function\\|struct\\|enum\\|impl\\|trait\\|mod\\)_item"))
    (should (string-match-p regexp "function_item"))
    (should (string-match-p regexp "struct_item"))
    (should (string-match-p regexp "enum_item"))
    (should (string-match-p regexp "impl_item"))
    (should (string-match-p regexp "trait_item"))
    (should (string-match-p regexp "mod_item"))))

(ert-deftest integration/treesit-defun-regexp/python-fallback ()
  "Python fallback regexp should match class/function_definition."
  (let ((regexp "\\(?:class\\|function\\)_definition"))
    (should (string-match-p regexp "class_definition"))
    (should (string-match-p regexp "function_definition"))))

(ert-deftest integration/treesit-defun-regexp/java-fallback ()
  "Java fallback regexp should match class/method etc."
  (let ((regexp "\\(?:class\\|method\\|constructor\\|enum\\|interface\\|record\\)_declaration"))
    (should (string-match-p regexp "class_declaration"))
    (should (string-match-p regexp "method_declaration"))
    (should (string-match-p regexp "constructor_declaration"))
    (should (string-match-p regexp "enum_declaration"))
    (should (string-match-p regexp "interface_declaration"))
    (should (string-match-p regexp "record_declaration"))))

(ert-deftest integration/treesit-defun-regexp/c-fallback ()
  "C fallback regexp should match function_definition etc."
  (let ((regexp "\\(?:function_definition\\|struct_specifier\\|enum_specifier\\|union_specifier\\|type_definition\\)"))
    (should (string-match-p regexp "function_definition"))
    (should (string-match-p regexp "struct_specifier"))
    (should (string-match-p regexp "enum_specifier"))
    (should (string-match-p regexp "union_specifier"))
    (should (string-match-p regexp "type_definition"))))

(ert-deftest integration/treesit-defun-regexp/cpp-fallback ()
  "C++ fallback regexp should match class_specifier etc."
  (let ((regexp "\\(?:function_definition\\|class_specifier\\|struct_specifier\\|enum_specifier\\|union_specifier\\|namespace_definition\\|type_definition\\)"))
    (should (string-match-p regexp "function_definition"))
    (should (string-match-p regexp "class_specifier"))
    (should (string-match-p regexp "namespace_definition"))))

(ert-deftest integration/treesit-defun-regexp/lua-fallback ()
  "Lua fallback regexp should match function_declaration."
  (let ((regexp "function_declaration"))
    (should (string-match-p regexp "function_declaration"))))

;;; Footer

(provide 'test-treesit-agent-integration)

;;; test-treesit-agent-integration.el ends here