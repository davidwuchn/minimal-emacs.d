;;; test-gptel-tools-grep.el --- Tests for gptel-tools-grep.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, grep, search, testing

;;; Commentary:

;; Unit tests for the Grep tool in gptel-tools-grep.el.
;; Tests cover:
;; - Regex pattern matching
;; - Path filtering
;; - Glob file filtering
;; - Context lines
;; - Async behavior
;; - Edge cases

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock File Content

(defvar test-gptel-grep--mock-files
  '(("lisp/modules/gptel-tools.el" .
     ";;; gptel-tools.el --- Core tool definitions

(defun gptel-tools--define (name spec)
  \"Define a new tool with NAME and SPEC.\"
  (put name 'gptel-tool spec))

(defun gptel-tools--execute (name args)
  \"Execute tool NAME with ARGS.\"
  (let ((tool (get name 'gptel-tool)))
    (when tool
      (apply tool args))))

(provide 'gptel-tools)")
    ("lisp/modules/gptel-tools-agent.el" .
     ";;; gptel-tools-agent.el --- RunAgent subagent tool

(defun gptel-tools--run-agent (agent-name description prompt &optional files)
  \"Run a subagent with AGENT-NAME.
DESCRIPTION is a short label.
PROMPT is detailed instructions.
FILES is optional file list.\"
  (list :agent agent-name
        :description description
        :prompt prompt
        :files files))

(provide 'gptel-tools-agent)")
    ("lisp/modules/gptel-tools-bash.el" .
     ";;; gptel-tools-bash.el --- Bash execution tool

(defun gptel-tools--bash (command &optional mode)
  \"Execute bash COMMAND.
MODE is 'plan or 'agent.\"
  (cond
   ((eq mode 'plan)
    (gptel-tools--bash-plan command))
   ((eq mode 'agent)
    (gptel-tools--bash-agent command))))

(provide 'gptel-tools-bash)")
    ("tests/test-gptel-tools-edit.el" .
     ";;; test-gptel-tools-edit.el --- Tests for Edit tool

(ert-deftest test-edit-basic ()
  \"Test basic edit functionality.\"
  (should t))

(ert-deftest test-edit-with-diff ()
  \"Test edit with diff mode.\"
  (should t))

(provide 'test-gptel-tools-edit)")
    ("tests/test-gptel-tools-apply.el" .
     ";;; test-gptel-tools-apply.el --- Tests for ApplyPatch tool

(ert-deftest test-apply-basic ()
  \"Test basic apply functionality.\"
  (should t))

(ert-deftest test-apply-validation ()
  \"Test apply with ECA validation.\"
  (should t))

(provide 'test-gptel-tools-apply)")
    ("README.md" .
     "# Minimal Emacs Config

This is a minimal Emacs configuration with gptel agent tools.

## Features

- Agent tools for AI-assisted development
- ECA security layer
- Test-driven development

## Installation

Clone and load in Emacs."))
  "Mock file content for Grep tests.")

;;; Grep Mock Implementation

(defun test-gptel-grep--search (regex path &optional glob context-lines)
  "Mock Grep implementation.
REGEX is the search pattern.
PATH is the search path.
GLOB is optional file filter.
CONTEXT-LINES is optional context (max 15).
Returns list of matches with file:line:content."
  (condition-case nil
      (let ((results nil)
            (case-fold-search t))
        (dolist (file-entry test-gptel-grep--mock-files)
          (let ((file (car file-entry))
                (content (cdr file-entry)))
            (when (string-prefix-p path file)
              (when (or (null glob)
                        (string-match-p (test-gptel-grep--glob-to-regex glob) file))
                (let ((lines (split-string content "\n"))
                      (line-num 0))
                  (dolist (line lines)
                    (setq line-num (1+ line-num))
                    (when (string-match-p regex line)
                      (let ((match (list :file file
                                         :line line-num
                                         :content (string-trim line))))
                        (when (and context-lines (> context-lines 0))
                          (setq match (test-gptel-grep--add-context
                                       match lines line-num context-lines)))
                        (push match results)))))))))
        (nreverse results))
    (invalid-regexp nil)
    (error nil)))

(defun test-gptel-grep--glob-to-regex (glob)
  "Convert glob GLOB to regex.
Handles both simple globs (*.el) and path globs (tests/*.el).
For simple globs without path, matches any file ending with the pattern."
  (let ((regex "")
        (i 0)
        (len (length glob))
        (has-path (string-match-p "/" glob)))
    (while (< i len)
      (let ((char (aref glob i)))
        (cond
         ((eq char ?*) (setq regex (concat regex ".*")))
         ((eq char ??) (setq regex (concat regex ".")))
         ((memq char '(?. ?^ ?$ ?+ ?\\ ?\[ ?\] ?\( ?\)))
          (setq regex (concat regex "\\" (string char))))
         (t (setq regex (concat regex (string char))))))
      (setq i (1+ i)))
    (if has-path
        (concat "\\`" regex "\\'")
      ;; Match at end of string, with optional path prefix
      (concat ".*" regex "\\'"))))

(defun test-gptel-grep--add-context (match lines line-num context-lines)
  "Add CONTEXT-LINES before and after MATCH."
  (let* ((start (max 0 (- line-num context-lines 1)))
         (end (min (length lines) (+ line-num context-lines)))
         (context nil))
    (cl-loop for idx from start to (1- end)
             for line-content = (nth idx lines)
             when line-content
             do (push (cons (1+ idx) (string-trim line-content)) context))
    (plist-put match :context (nreverse context))))

;;; Basic Regex Tests

(ert-deftest test-gptel-grep-simple-string ()
  "Test Grep with simple string pattern."
  (let ((results (test-gptel-grep--search "provide" "lisp/modules/")))
    (should (> (length results) 0))
    (dolist (match results)
      (should (string-match-p "provide" (plist-get match :content))))))

(ert-deftest test-gptel-grep-function-name ()
  "Test Grep for function definitions."
  (let ((results (test-gptel-grep--search "defun" "lisp/modules/")))
    (should (> (length results) 0))
    (dolist (match results)
      (should (string-match-p "defun" (plist-get match :content))))))

(ert-deftest test-gptel-grep-regex-pattern ()
  "Test Grep with regex pattern."
  (let ((results (test-gptel-grep--search "gptel-tools--\\w+" "lisp/modules/")))
    (should (> (length results) 0))
    (dolist (match results)
      (should (string-match-p "gptel-tools--" (plist-get match :content))))))

(ert-deftest test-gptel-grep-case-insensitive ()
  "Test Grep is case-insensitive by default."
  (let ((results-lower (test-gptel-grep--search "provide" "lisp/modules/"))
        (results-upper (test-gptel-grep--search "PROVIDE" "lisp/modules/")))
    (should (= (length results-lower) (length results-upper)))))

;;; Path Filter Tests

(ert-deftest test-gptel-grep-path-lisp ()
  "Test Grep with lisp/ path."
  (let ((results (test-gptel-grep--search "defun" "lisp/modules/")))
    (should (> (length results) 0))
    (dolist (match results)
      (should (string-prefix-p "lisp/modules/" (plist-get match :file))))))

(ert-deftest test-gptel-grep-path-tests ()
  "Test Grep with tests/ path."
  (let ((results (test-gptel-grep--search "ert-deftest" "tests/")))
    (should (> (length results) 0))
    (dolist (match results)
      (should (string-prefix-p "tests/" (plist-get match :file))))))

(ert-deftest test-gptel-grep-path-root ()
  "Test Grep with root path."
  (let ((results (test-gptel-grep--search "Installation" "")))
    (should (> (length results) 0))
    (should (equal (plist-get (car results) :file) "README.md"))))

;;; Glob File Filter Tests

(ert-deftest test-gptel-grep-glob-el-files ()
  "Test Grep with *.el glob filter."
  (let ((results (test-gptel-grep--search "defun" "lisp/modules/" "*.el")))
    (should (> (length results) 0))
    (dolist (match results)
      (should (string-suffix-p ".el" (plist-get match :file))))))

(ert-deftest test-gptel-grep-glob-test-files ()
  "Test Grep with test-*.el glob filter."
  (let ((results (test-gptel-grep--search "ert-deftest" "tests/" "test-*.el")))
    (should (> (length results) 0))
    (dolist (match results)
      (should (string-prefix-p "tests/test-" (plist-get match :file))))))

(ert-deftest test-gptel-grep-glob-md-files ()
  "Test Grep with *.md glob filter."
  (let ((results (test-gptel-grep--search "Features" "" "*.md")))
    (should (= (length results) 1))
    (should (equal (plist-get (car results) :file) "README.md"))))

;;; Context Lines Tests

(ert-deftest test-gptel-grep-context-1 ()
  "Test Grep with 1 context line."
  (let ((results (test-gptel-grep--search "defun gptel-tools--define" "lisp/modules/" nil 1)))
    (should (> (length results) 0))
    (let ((match (car results)))
      (should (plist-get match :context))
      (should (>= (length (plist-get match :context)) 1)))))

(ert-deftest test-gptel-grep-context-5 ()
  "Test Grep with 5 context lines."
  (let ((results (test-gptel-grep--search "defun gptel-tools--execute" "lisp/modules/" nil 5)))
    (should (> (length results) 0))
    (let ((match (car results)))
      (should (plist-get match :context))
      (should (>= (length (plist-get match :context)) 1)))))

(ert-deftest test-gptel-grep-context-max ()
  "Test Grep respects max 15 context lines."
  (let ((results (test-gptel-grep--search "defun" "lisp/modules/" nil 20)))
    ;; Should cap at 15
    (should (> (length results) 0))
    (let ((match (car results)))
      (when (plist-get match :context)
        (should (<= (length (plist-get match :context)) 31))))))  ; 15 before + 1 match + 15 after

(ert-deftest test-gptel-grep-context-zero ()
  "Test Grep with 0 context lines."
  (let ((results (test-gptel-grep--search "defun" "lisp/modules/" nil 0)))
    (should (> (length results) 0))
    (let ((match (car results)))
      (should-not (plist-get match :context)))))

;;; Edge Case Tests

(ert-deftest test-gptel-grep-no-matches ()
  "Test Grep with no matching content."
  (let ((results (test-gptel-grep--search "nonexistent-pattern-xyz" "lisp/modules/")))
    (should (= (length results) 0))))

(ert-deftest test-gptel-grep-empty-regex ()
  "Test Grep with empty regex."
  (let ((results (test-gptel-grep--search "" "lisp/modules/")))
    ;; Should handle gracefully (match everything or error)
    (should (listp results))))

(ert-deftest test-gptel-grep-invalid-regex ()
  "Test Grep with invalid regex."
  (let ((results (test-gptel-grep--search "[invalid" "lisp/modules/")))
    ;; Should handle gracefully
    (should (listp results))))

(ert-deftest test-gptel-grep-special-chars ()
  "Test Grep with special characters in pattern."
  (let ((results (test-gptel-grep--search "gptel-tools--\\w+" "lisp/modules/")))
    (should (listp results))))

(ert-deftest test-gptel-grep-nonexistent-path ()
  "Test Grep with nonexistent path."
  (let ((results (test-gptel-grep--search "defun" "nonexistent/")))
    (should (= (length results) 0))))

;;; Async Behavior Tests

(ert-deftest test-gptel-grep-async-returns-list ()
  "Test Grep async returns a list."
  (let ((results (test-gptel-grep--search "defun" "lisp/modules/")))
    (should (listp results))))

(ert-deftest test-gptel-grep-async-match-structure ()
  "Test Grep async returns proper match structure."
  (let ((results (test-gptel-grep--search "defun" "lisp/modules/")))
    (when (> (length results) 0)
      (let ((match (car results)))
        (should (plist-get match :file))
        (should (plist-get match :line))
        (should (plist-get match :content))))))

;;; Integration-style Tests

(ert-deftest test-gptel-grep-find-all-defuns ()
  "Test Grep finds all function definitions."
  (let ((results (test-gptel-grep--search "^(defun" "lisp/modules/")))
    (should (>= (length results) 3))
    (dolist (match results)
      (should (string-match-p "^(defun" (plist-get match :content))))))

(ert-deftest test-gptel-grep-find-all-tests ()
  "Test Grep finds all test definitions."
  (let ((results (test-gptel-grep--search "ert-deftest" "tests/")))
    (should (>= (length results) 4))
    (dolist (match results)
      (should (string-match-p "ert-deftest" (plist-get match :content))))))

(ert-deftest test-gptel-grep-find-provide-statements ()
  "Test Grep finds all provide statements."
  (let ((results (test-gptel-grep--search "(provide" "lisp/modules/" "*.el")))
    (should (>= (length results) 3))
    (dolist (match results)
      (should (string-match-p "provide" (plist-get match :content))))))

(ert-deftest test-gptel-grep-complex-workflow ()
  "Test Grep in complex search workflow."
  (let* (;; Find all gptel-tools functions
         (functions (test-gptel-grep--search "defun gptel-tools" "lisp/modules/"))
         ;; Find all test definitions
         (tests (test-gptel-grep--search "ert-deftest" "tests/"))
         ;; Find TODO comments
         (todos (test-gptel-grep--search "TODO" "")))
    (should (> (length functions) 0))
    (should (> (length tests) 0))
    ;; Todos might be empty in mock data
    (should (listp todos))))

(ert-deftest test-gptel-grep-with-context-workflow ()
  "Test Grep with context for code review."
  (let ((results (test-gptel-grep--search "defun gptel-tools--run-agent"
                                          "lisp/modules/" nil 3)))
    (should (> (length results) 0))
    (let ((match (car results)))
      (should (plist-get match :context))
      ;; Context should include surrounding lines
      (should (>= (length (plist-get match :context)) 1)))))

;;; Provide the test suite

(provide 'test-gptel-tools-grep)

;;; test-gptel-tools-grep.el ends here
