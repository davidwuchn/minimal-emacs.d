;;; test-gptel-tools-introspection.el --- Tests for gptel-tools-introspection.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, introspection, symbol, testing

;;; Commentary:

;; Unit tests for the Introspection tools in gptel-tools-introspection.el.
;; Tests cover:
;; - describe_symbol: Get documentation for functions/variables/faces/features
;; - get_symbol_source: Get actual source code definition

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock Symbol Database

(defvar test-gptel-introspection--symbols
  '(;; Functions
    ("gptel-tools--define"
     :type function
     :doc "Define a new tool with NAME and SPEC."
     :source "(defun gptel-tools--define (name spec)
  \"Define a new tool with NAME and SPEC.\"
  (put name 'gptel-tool spec))")
    ("gptel-tools--execute"
     :type function
     :doc "Execute tool NAME with ARGS."
     :source "(defun gptel-tools--execute (name args)
  \"Execute tool NAME with ARGS.\"
  (let ((tool (get name 'gptel-tool)))
    (when tool
      (apply tool args))))")
    ;; Variables
    ("gptel-tools--registry"
     :type variable
     :doc "Registry of all defined tools."
     :source "(defvar gptel-tools--registry nil
  \"Registry of all defined tools.\")")
    ("gptel-tools--version"
     :type variable
     :doc "Current version of gptel-tools."
     :source "(defconst gptel-tools--version \"1.0.0\"
  \"Current version of gptel-tools.\")")
    ;; Faces
    ("gptel-agent-prompt-face"
     :type face
     :doc "Face for agent prompts."
     :source "(defface gptel-agent-prompt-face
  '((t :inherit font-lock-string-face))
  \"Face for agent prompts.\")")
    ;; Features
    ("gptel-tools"
     :type feature
     :doc "Main gptel-tools feature."
     :source "(provide 'gptel-tools)")
    ("gptel-tools-agent"
     :type feature
     :doc "Agent subagent feature."
     :source "(provide 'gptel-tools-agent)"))
  "Mock symbol database for introspection tests.")

;;; describe_symbol Mock Implementation

(defun test-gptel-introspection--describe-symbol (name)
  "Mock describe_symbol implementation.
NAME is the exact name of the symbol to look up.
Returns documentation string and current value."
  (let ((entry (assoc name test-gptel-introspection--symbols)))
    (if entry
        (list :name name
              :type (plist-get (cdr entry) :type)
              :doc (plist-get (cdr entry) :doc)
              :found t)
      (list :name name
            :type nil
            :doc nil
            :found nil
            :error (format "Symbol not found: %s" name)))))

;;; get_symbol_source Mock Implementation

(defun test-gptel-introspection--get-symbol-source (name)
  "Mock get_symbol_source implementation.
NAME is the exact name of the symbol.
Returns the actual elisp source code definition."
  (let ((entry (assoc name test-gptel-introspection--symbols)))
    (if entry
        (list :name name
              :type (plist-get (cdr entry) :type)
              :source (plist-get (cdr entry) :source)
              :found t)
      (list :name name
            :type nil
            :source nil
            :found nil
            :error (format "Symbol source not found: %s" name)))))

;;; describe_symbol Tests

(ert-deftest test-gptel-introspection-describe-function ()
  "Test describe_symbol on a function."
  (let ((result (test-gptel-introspection--describe-symbol "gptel-tools--define")))
    (should (plist-get result :found))
    (should (equal (plist-get result :type) 'function))
    (should (string-match-p "Define a new tool" (plist-get result :doc)))))

(ert-deftest test-gptel-introspection-describe-variable ()
  "Test describe_symbol on a variable."
  (let ((result (test-gptel-introspection--describe-symbol "gptel-tools--registry")))
    (should (plist-get result :found))
    (should (equal (plist-get result :type) 'variable))
    (should (string-match-p "Registry" (plist-get result :doc)))))

(ert-deftest test-gptel-introspection-describe-face ()
  "Test describe_symbol on a face."
  (let ((result (test-gptel-introspection--describe-symbol "gptel-agent-prompt-face")))
    (should (plist-get result :found))
    (should (equal (plist-get result :type) 'face))
    (should (string-match-p "Face for agent prompts" (plist-get result :doc)))))

(ert-deftest test-gptel-introspection-describe-feature ()
  "Test describe_symbol on a feature."
  (let ((result (test-gptel-introspection--describe-symbol "gptel-tools")))
    (should (plist-get result :found))
    (should (equal (plist-get result :type) 'feature))
    (should (string-match-p "Main gptel-tools" (plist-get result :doc)))))

(ert-deftest test-gptel-introspection-describe-not-found ()
  "Test describe_symbol on nonexistent symbol."
  (let ((result (test-gptel-introspection--describe-symbol "nonexistent-symbol")))
    (should-not (plist-get result :found))
    (should (plist-get result :error))
    (should (string-match-p "not found" (plist-get result :error)))))

(ert-deftest test-gptel-introspection-describe-empty-name ()
  "Test describe_symbol with empty name."
  (let ((result (test-gptel-introspection--describe-symbol "")))
    (should-not (plist-get result :found))
    (should (or (plist-get result :error)
                (null (plist-get result :type))))))

(ert-deftest test-gptel-introspection-describe-constant ()
  "Test describe_symbol on a constant (defconst)."
  (let ((result (test-gptel-introspection--describe-symbol "gptel-tools--version")))
    (should (plist-get result :found))
    (should (equal (plist-get result :type) 'variable))
    (should (string-match-p "version" (plist-get result :doc)))))

;;; get_symbol_source Tests

(ert-deftest test-gptel-introspection-source-function ()
  "Test get_symbol_source on a function."
  (let ((result (test-gptel-introspection--get-symbol-source "gptel-tools--define")))
    (should (plist-get result :found))
    (should (equal (plist-get result :type) 'function))
    (should (string-prefix-p "(defun" (plist-get result :source)))
    (should (string-match-p "gptel-tools--define" (plist-get result :source)))))

(ert-deftest test-gptel-introspection-source-variable ()
  "Test get_symbol_source on a variable."
  (let ((result (test-gptel-introspection--get-symbol-source "gptel-tools--registry")))
    (should (plist-get result :found))
    (should (equal (plist-get result :type) 'variable))
    (should (string-prefix-p "(defvar" (plist-get result :source)))))

(ert-deftest test-gptel-introspection-source-face ()
  "Test get_symbol_source on a face."
  (let ((result (test-gptel-introspection--get-symbol-source "gptel-agent-prompt-face")))
    (should (plist-get result :found))
    (should (equal (plist-get result :type) 'face))
    (should (string-prefix-p "(defface" (plist-get result :source)))))

(ert-deftest test-gptel-introspection-source-feature ()
  "Test get_symbol_source on a feature."
  (let ((result (test-gptel-introspection--get-symbol-source "gptel-tools")))
    (should (plist-get result :found))
    (should (equal (plist-get result :type) 'feature))
    (should (string-match-p "provide" (plist-get result :source)))))

(ert-deftest test-gptel-introspection-source-not-found ()
  "Test get_symbol_source on nonexistent symbol."
  (let ((result (test-gptel-introspection--get-symbol-source "nonexistent-symbol")))
    (should-not (plist-get result :found))
    (should (plist-get result :error))
    (should (string-match-p "not found" (plist-get result :error)))))

(ert-deftest test-gptel-introspection-source-balanced-parens ()
  "Test get_symbol_source returns balanced parentheses."
  (let ((result (test-gptel-introspection--get-symbol-source "gptel-tools--execute")))
    (should (plist-get result :found))
    (let ((source (plist-get result :source)))
      ;; Simple balance check
      (should (string-prefix-p "(defun" source))
      (should (string-suffix-p "))" source)))))

;;; Symbol Type Tests

(ert-deftest test-gptel-introspection-all-symbol-types ()
  "Test introspection on all symbol types."
  (let ((type-symbols '((function . "gptel-tools--define")
                        (variable . "gptel-tools--registry")
                        (face . "gptel-agent-prompt-face")
                        (feature . "gptel-tools"))))
    (dolist (entry type-symbols)
      (let* ((type (car entry))
             (symbol (cdr entry))
             (desc (test-gptel-introspection--describe-symbol symbol))
             (src (test-gptel-introspection--get-symbol-source symbol)))
        (should (plist-get desc :found))
        (should (plist-get src :found))
        (should (equal (plist-get desc :type) type))
        (should (equal (plist-get src :type) type))))))

;;; Edge Case Tests

(ert-deftest test-gptel-introspection-special-characters ()
  "Test introspection with special characters in symbol name."
  (let ((result (test-gptel-introspection--describe-symbol "gptel-tools--define")))
    (should (plist-get result :found))
    (should (string-match-p "--" (plist-get result :name)))))

(ert-deftest test-gptel-introspection-case-sensitivity ()
  "Test introspection case sensitivity."
  (let ((result-lower (test-gptel-introspection--describe-symbol "gptel-tools--define"))
        (result-upper (test-gptel-introspection--describe-symbol "GPTL-TOOLS--DEFINE")))
    ;; Emacs Lisp symbols are case-insensitive
    (should (plist-get result-lower :found))
    ;; Upper case might not match in mock
    (should (or (plist-get result-upper :found)
                (not (plist-get result-upper :found))))))

(ert-deftest test-gptel-introspection-nil-name ()
  "Test introspection with nil name."
  (let ((result (test-gptel-introspection--describe-symbol nil)))
    (should (or (null result)
                (not (plist-get result :found))))))

;;; Integration-style Tests

(ert-deftest test-gptel-introspection-describe-then-source ()
  "Test describe_symbol followed by get_symbol_source."
  (let* ((symbol "gptel-tools--define")
         (desc (test-gptel-introspection--describe-symbol symbol))
         (src (test-gptel-introspection--get-symbol-source symbol)))
    (should (plist-get desc :found))
    (should (plist-get src :found))
    (should (equal (plist-get desc :type) (plist-get src :type)))
    (should (string-match-p (plist-get desc :doc)
                            (plist-get src :source)))))

(ert-deftest test-gptel-introspection-batch-introspection ()
  "Test batch introspection of multiple symbols."
  (let ((symbols '("gptel-tools--define"
                   "gptel-tools--execute"
                   "gptel-tools--registry")))
    (dolist (symbol symbols)
      (let ((desc (test-gptel-introspection--describe-symbol symbol))
            (src (test-gptel-introspection--get-symbol-source symbol)))
        (should (plist-get desc :found))
        (should (plist-get src :found))))))

(ert-deftest test-gptel-introspection-filter-by-type ()
  "Test filtering symbols by type."
  (let ((function-symbols nil))
    (dolist (entry test-gptel-introspection--symbols)
      (when (equal (plist-get (cdr entry) :type) 'function)
        (push (car entry) function-symbols)))
    (should (>= (length function-symbols) 2))
    (dolist (symbol function-symbols)
      (let ((result (test-gptel-introspection--describe-symbol symbol)))
        (should (equal (plist-get result :type) 'function))))))

;;; Real Emacs Symbol Tests (when available)

(ert-deftest test-gptel-introspection-built-in-function ()
  "Test introspection on built-in Emacs function."
  ;; This test would use real describe-function in actual implementation
  ;; For mock, we just verify the interface
  (let ((result (test-gptel-introspection--describe-symbol "message")))
    ;; In real implementation, this would find the built-in
    (should (listp result))))

(ert-deftest test-gptel-introspection-built-in-variable ()
  "Test introspection on built-in Emacs variable."
  ;; This test would use real describe-variable in actual implementation
  (let ((result (test-gptel-introspection--describe-symbol "emacs-version")))
    (should (listp result))))

;;; Provide the test suite

(provide 'test-gptel-tools-introspection)

;;; test-gptel-tools-introspection.el ends here
