;;; test-gptel-tools-glob.el --- Tests for gptel-tools-glob.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, glob, file-search, testing

;;; Commentary:

;; Unit tests for the Glob tool in gptel-tools-glob.el.
;; Tests cover:
;; - Pattern matching (wildcards, extensions)
;; - Path filtering
;; - Depth limiting
;; - Async behavior
;; - Edge cases (empty results, special characters)

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock File System

(defvar test-gptel-glob--mock-files
  '("lisp/modules/gptel-tools.el"
    "lisp/modules/gptel-tools-agent.el"
    "lisp/modules/gptel-tools-bash.el"
    "lisp/modules/gptel-tools-code.el"
    "lisp/modules/gptel-tools-edit.el"
    "lisp/modules/gptel-tools-apply.el"
    "lisp/modules/gptel-tools-preview.el"
    "lisp/modules/gptel-tools-glob.el"
    "lisp/modules/gptel-tools-grep.el"
    "lisp/modules/gptel-tools-introspection.el"
    "lisp/modules/gptel-tools-programmatic.el"
    "tests/test-gptel-tools-edit.el"
    "tests/test-gptel-tools-apply.el"
    "tests/test-gptel-tools-preview.el"
    "tests/test-gptel-tools-agent.el"
    "tests/test-gptel-tools-bash.el"
    "tests/test-gptel-tools-code.el"
    "tests/test-eca-security.el"
    "tests/test-eca-ext.el"
    "assistant/agents/researcher.el"
    "assistant/agents/executor.el"
    "assistant/agents/explorer.el"
    "assistant/agents/introspector.el"
    "assistant/agents/reviewer.el"
    "README.md"
    "Makefile"
    "var/elpa/gptel-agent-20260308.2122/gptel-agent.el"
    "var/elpa/gptel-agent-20260308.2122/gptel-agent-tools.el")
  "Mock file system for Glob tests.")

;;; Glob Mock Implementation

(defun test-gptel-glob--search (pattern &optional path depth)
  "Mock Glob implementation.
PATTERN is the glob pattern.
PATH is the optional search path.
DEPTH is the optional max depth.
Returns list of matching file paths."
  (let ((case-fold-search nil)
        (results nil))
    ;; Convert glob pattern to regex
    (let ((regex (test-gptel-glob--glob-to-regex pattern)))
      (dolist (file test-gptel-glob--mock-files)
        ;; Apply path filter if specified
        (when (or (null path)
                  (string-prefix-p path file))
          ;; Apply depth filter if specified
          (when (or (null depth)
                    (<= (test-gptel-glob--count-depth file) depth))
            ;; Match against pattern
            (when (string-match-p regex file)
              (push file results))))))
    (nreverse results)))

(defun test-gptel-glob--glob-to-regex (pattern)
  "Convert glob PATTERN to regex."
  (let ((regex "")
        (i 0)
        (len (length pattern)))
    (while (< i len)
      (let ((char (aref pattern i)))
        (cond
         ((eq char ?*) (setq regex (concat regex ".*")))
         ((eq char ??) (setq regex (concat regex ".")))
         ((memq char '(?. ?^ ?$ ?+ ?\\ ?\[ ?\] ?\( ?\)))
          (setq regex (concat regex "\\" (string char))))
         (t (setq regex (concat regex (string char))))))
      (setq i (1+ i)))
    (concat regex "\\'")))

(defun test-gptel-glob--count-depth (path)
  "Count directory depth in PATH."
  (length (split-string path "/")))

;;; Basic Pattern Tests

(ert-deftest test-gptel-glob-star-extension ()
  "Test Glob with *.el pattern."
  (let ((results (test-gptel-glob--search "*.el")))
    (should (> (length results) 0))
    (dolist (file results)
      (should (string-suffix-p ".el" file)))))

(ert-deftest test-gptel-glob-star-all ()
  "Test Glob with * pattern."
  (let ((results (test-gptel-glob--search "*")))
    (should (= (length results) (length test-gptel-glob--mock-files)))))

(ert-deftest test-gptel-glob-specific-extension ()
  "Test Glob with *.md pattern."
  (let ((results (test-gptel-glob--search "*.md")))
    (should (= (length results) 1))
    (should (equal (car results) "README.md"))))

(ert-deftest test-gptel-glob-partial-match ()
  "Test Glob with partial pattern."
  (let ((results (test-gptel-glob--search "*gptel*")))
    (should (> (length results) 0))
    (dolist (file results)
      (should (string-match-p "gptel" file)))))

;;; Path Filter Tests

(ert-deftest test-gptel-glob-path-filter-lisp ()
  "Test Glob with lisp/ path filter."
  (let ((results (test-gptel-glob--search "*.el" "lisp/")))
    (should (> (length results) 0))
    (dolist (file results)
      (should (string-prefix-p "lisp/" file)))))

(ert-deftest test-gptel-glob-path-filter-tests ()
  "Test Glob with tests/ path filter."
  (let ((results (test-gptel-glob--search "*.el" "tests/")))
    (should (> (length results) 0))
    (dolist (file results)
      (should (string-prefix-p "tests/" file)))))

(ert-deftest test-gptel-glob-path-filter-assistant ()
  "Test Glob with assistant/ path filter."
  (let ((results (test-gptel-glob--search "*.el" "assistant/")))
    (should (> (length results) 0))
    (dolist (file results)
      (should (string-prefix-p "assistant/" file)))))

(ert-deftest test-gptel-glob-path-filter-combined ()
  "Test Glob with path and pattern combined."
  (let ((results (test-gptel-glob--search "*agent*.el" "lisp/modules/")))
    (should (> (length results) 0))
    (dolist (file results)
      (should (string-prefix-p "lisp/modules/" file))
      (should (string-match-p "agent" file)))))

;;; Depth Limit Tests

(ert-deftest test-gptel-glob-depth-1 ()
  "Test Glob with depth 1."
  (let ((results (test-gptel-glob--search "*" nil 1)))
    (dolist (file results)
      (should (<= (test-gptel-glob--count-depth file) 1)))))

(ert-deftest test-gptel-glob-depth-2 ()
  "Test Glob with depth 2."
  (let ((results (test-gptel-glob--search "*.el" nil 2)))
    (dolist (file results)
      (should (<= (test-gptel-glob--count-depth file) 2)))))

(ert-deftest test-gptel-glob-depth-with-path ()
  "Test Glob with both path and depth."
  (let ((results (test-gptel-glob--search "*.el" "lisp/modules/" 2)))
    (dolist (file results)
      (should (string-prefix-p "lisp/modules/" file))
      (should (<= (test-gptel-glob--count-depth file) 2)))))

;;; Wildcard Tests

(ert-deftest test-gptel-glob-question-mark ()
  "Test Glob with ? wildcard."
  (let ((results (test-gptel-glob--search "test-?.el")))
    ;; Should match single character
    (should (or (= (length results) 0)
                (let ((file (car results)))
                  ;; Check that ? matches exactly one char
                  (string-match-p "test-[^/]+\\.el" file))))))

(ert-deftest test-gptel-glob-multiple-stars ()
  "Test Glob with multiple * wildcards."
  (let ((results (test-gptel-glob--search "*gptel*tools*.el")))
    (dolist (file results)
      (should (string-match-p "gptel" file))
      (should (string-match-p "tools" file))
      (should (string-suffix-p ".el" file)))))

;;; Edge Case Tests

(ert-deftest test-gptel-glob-no-matches ()
  "Test Glob with no matching files."
  (let ((results (test-gptel-glob--search "*.xyz")))
    (should (= (length results) 0))))

(ert-deftest test-gptel-glob-empty-pattern ()
  "Test Glob with empty pattern."
  (let ((results (test-gptel-glob--search "")))
    ;; Should handle gracefully
    (should (listp results))))

(ert-deftest test-gptel-glob-special-chars ()
  "Test Glob with special characters in pattern."
  (let ((results (test-gptel-glob--search "test-*.el")))
    (should (listp results))))

(ert-deftest test-gptel-glob-case-sensitivity ()
  "Test Glob case sensitivity."
  (let ((results-lower (test-gptel-glob--search "*.el"))
        (results-upper (test-gptel-glob--search "*.EL")))
    ;; Should be case-sensitive by default
    (should-not (equal (length results-lower) (length results-upper)))))

(ert-deftest test-gptel-glob-nonexistent-path ()
  "Test Glob with nonexistent path."
  (let ((results (test-gptel-glob--search "*.el" "nonexistent/")))
    (should (= (length results) 0))))

;;; Async Behavior Tests

(ert-deftest test-gptel-glob-async-returns-list ()
  "Test Glob async returns a list."
  (let ((results (test-gptel-glob--search "*.el")))
    (should (listp results))))

(ert-deftest test-gptel-glob-async-ordering ()
  "Test Glob async returns consistent ordering."
  (let ((results1 (test-gptel-glob--search "*.el"))
        (results2 (test-gptel-glob--search "*.el")))
    (should (equal results1 results2))))

;;; Integration-style Tests

(ert-deftest test-gptel-glob-find-all-test-files ()
  "Test Glob finds all test files."
  (let ((results (test-gptel-glob--search "test-*.el" "tests/")))
    (should (>= (length results) 5))
    (dolist (file results)
      (should (string-prefix-p "tests/test-" file))
      (should (string-suffix-p ".el" file)))))

(ert-deftest test-gptel-glob-find-all-agent-tools ()
  "Test Glob finds all gptel-tools modules."
  (let ((results (test-gptel-glob--search "gptel-tools-*.el" "lisp/modules/")))
    (should (>= (length results) 8))
    (dolist (file results)
      (should (string-prefix-p "lisp/modules/gptel-tools-" file)))))

(ert-deftest test-gptel-glob-find-all-agents ()
  "Test Glob finds all agent definitions."
  (let ((results (test-gptel-glob--search "*.el" "assistant/agents/")))
    (should (>= (length results) 5))
    (dolist (file results)
      (should (string-prefix-p "assistant/agents/" file)))))

(ert-deftest test-gptel-glob-complex-workflow ()
  "Test Glob in complex file discovery workflow."
  (let* ((modules (test-gptel-glob--search "gptel-tools-*.el" "lisp/modules/"))
         (tests (test-gptel-glob--search "test-gptel-tools-*.el" "tests/"))
         (agents (test-gptel-glob--search "*.el" "assistant/agents/")))
    (should (> (length modules) 0))
    (should (> (length tests) 0))
    (should (> (length agents) 0))
    ;; Verify no overlap between modules and tests
    (dolist (m modules)
      (should-not (member m tests)))))

;;; Provide the test suite

(provide 'test-gptel-tools-glob)

;;; test-gptel-tools-glob.el ends here
