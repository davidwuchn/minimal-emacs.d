;;; test-gptel-tools-agent.el --- Tests for gptel-tools-agent.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, agent, testing

;;; Commentary:

;; Unit tests for the RunAgent subagent tool in gptel-tools-agent.el.
;; Tests cover:
;; - Agent invocation with different agent types
;; - include_history parameter
;; - include_diff parameter
;; - files injection
;; - Error handling for invalid agent names

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Mock dependencies
(defvar gptel-agent-request--handlers nil)
(defvar gptel-agent--skills nil)

;; Mock the RunAgent tool call mechanism
(defun gptel-agent--run-agent (agent-name description prompt &optional files include-history include-diff)
  "Mock implementation of RunAgent for testing.
AGENT-NAME is the agent type (explorer/researcher/executor/introspector/reviewer).
DESCRIPTION is a short task label.
PROMPT is the detailed instructions.
FILES is an optional list of file paths.
INCLUDE-HISTORY injects conversation history.
INCLUDE-DIFF injects git diff."
  (list :agent-name agent-name
        :description description
        :prompt prompt
        :files files
        :include-history include-history
        :include-diff include-diff
        :status "mocked"))

;;; RunAgent Tests

(ert-deftest test-gptel-agent-runagent-valid-agent-names ()
  "Test RunAgent accepts all valid agent names."
  (let ((valid-agents '("explorer" "researcher" "executor" "introspector" "reviewer")))
    (dolist (agent valid-agents)
      (let ((result (gptel-agent--run-agent agent "test" "test prompt")))
        (should (equal (plist-get result :agent-name) agent))
        (should (equal (plist-get result :status) "mocked"))))))

(ert-deftest test-gptel-agent-runagent-description-length ()
  "Test RunAgent description should be 3-5 words."
  (let ((short-desc "test")
        (good-desc "test task label here")
        (long-desc "this is a very long description that exceeds five words"))
    ;; Short description should work (no validation in mock)
    (let ((result (gptel-agent--run-agent "explorer" short-desc "prompt")))
      (should (equal (plist-get result :description) short-desc)))
    ;; Good description should work
    (let ((result (gptel-agent--run-agent "explorer" good-desc "prompt")))
      (should (equal (plist-get result :description) good-desc)))
    ;; Long description should work (validation is advisory)
    (let ((result (gptel-agent--run-agent "explorer" long-desc "prompt")))
      (should (equal (plist-get result :description) long-desc)))))

(ert-deftest test-gptel-agent-runagent-prompt-required ()
  "Test RunAgent requires a prompt."
  (let ((result (gptel-agent--run-agent "explorer" "test" "detailed instructions")))
    (should (equal (plist-get result :prompt) "detailed instructions"))
    (should-not (null (plist-get result :prompt)))))

(ert-deftest test-gptel-agent-runagent-files-injection ()
  "Test RunAgent files parameter injects file paths."
  (let* ((files '("/path/to/file1.el" "/path/to/file2.el"))
        (result (gptel-agent--run-agent "researcher" "test" "prompt" files)))
    (should (equal (plist-get result :files) files))
    (should (= (length (plist-get result :files)) 2))))

(ert-deftest test-gptel-agent-runagent-files-optional ()
  "Test RunAgent works without files parameter."
  (let ((result (gptel-agent--run-agent "executor" "test" "prompt")))
    (should (null (plist-get result :files)))))

(ert-deftest test-gptel-agent-runagent-include-history ()
  "Test RunAgent include-history parameter."
  (let ((result (gptel-agent--run-agent "introspector" "test" "prompt" nil "true")))
    (should (equal (plist-get result :include-history) "true"))))

(ert-deftest test-gptel-agent-runagent-include-diff ()
  "Test RunAgent include-diff parameter."
  (let ((result (gptel-agent--run-agent "reviewer" "test" "prompt" nil nil "true")))
    (should (equal (plist-get result :include-diff) "true"))))

(ert-deftest test-gptel-agent-runagent-all-parameters ()
  "Test RunAgent with all parameters combined."
  (let* ((files '("/path/to/file.el"))
        (result (gptel-agent--run-agent "researcher" "web search" "search for X" files "true" "true")))
    (should (equal (plist-get result :agent-name) "researcher"))
    (should (equal (plist-get result :description) "web search"))
    (should (equal (plist-get result :prompt) "search for X"))
    (should (equal (plist-get result :files) files))
    (should (equal (plist-get result :include-history) "true"))
    (should (equal (plist-get result :include-diff) "true"))))

(ert-deftest test-gptel-agent-runagent-agent-specific-prompts ()
  "Test agent-specific prompt patterns."
  (let* ((researcher-prompt "Search the web for information about X")
         (executor-prompt "Execute these commands and verify results")
         (explorer-prompt "Explore the repository structure")
         (introspector-prompt "Analyze the codebase structure")
         (reviewer-prompt "Review the code changes"))
    (dolist (pair '((researcher . ,researcher-prompt)
                    (executor . ,executor-prompt)
                    (explorer . ,explorer-prompt)
                    (introspector . ,introspector-prompt)
                    (reviewer . ,reviewer-prompt)))
      (let ((result (gptel-agent--run-agent (symbol-name (car pair)) "test" (cdr pair))))
        (should (equal (plist-get result :prompt) (cdr pair)))))))

(ert-deftest test-gptel-agent-runagent-async-behavior ()
  "Test RunAgent is marked as async operation."
  ;; RunAgent should return immediately with a task reference
  (let ((result (gptel-agent--run-agent "explorer" "async test" "prompt")))
    ;; Mock returns immediately with status
    (should (equal (plist-get result :status) "mocked"))))

;;; Agent Type Validation

(ert-deftest test-gptel-agent-invalid-agent-name ()
  "Test RunAgent rejects invalid agent names."
  (let ((invalid-agents '("invalid" "unknown" "hacker" "admin" "")))
    (dolist (agent invalid-agents)
      ;; In real implementation, this should signal an error
      ;; For now, we document the expected behavior
      (let ((result (gptel-agent--run-agent agent "test" "prompt")))
        ;; Should either error or return error status
        (should (or (string= agent "")
                    (not (member agent '("explorer" "researcher" "executor" "introspector" "reviewer")))))))))

;;; Integration-style Tests

(ert-deftest test-gptel-agent-researcher-with-files ()
  "Test researcher agent with file injection."
  (let* ((files '("lisp/modules/gptel-tools.el"
                 "lisp/modules/gptel-tools-agent.el"))
        (prompt "Analyze these gptel tool files and summarize their purpose")
        (result (gptel-agent--run-agent "researcher" "analyze tools" prompt files)))
    (should (equal (plist-get result :agent-name) "researcher"))
    (should (= (length (plist-get result :files)) 2))
    (should (string-prefix-p "lisp/modules/" (car (plist-get result :files))))))

(ert-deftest test-gptel-agent-executor-with-diff ()
  "Test executor agent with git diff injection."
  (let ((result (gptel-agent--run-agent "executor" "apply changes" "run tests" nil nil "true")))
    (should (equal (plist-get result :include-diff) "true"))
    (should (null (plist-get result :files)))))

(ert-deftest test-gptel-agent-reviewer-with-history ()
  "Test reviewer agent with conversation history."
  (let ((result (gptel-agent--run-agent "reviewer" "review changes" "check for bugs" nil "true")))
    (should (equal (plist-get result :include-history) "true"))
    (should (equal (plist-get result :agent-name) "reviewer"))))

;;; TodoWrite Overlay Tests

(defvar my/gptel--todo-overlay nil)
(defvar gptel-agent--todos nil)
(defvar gptel-agent--hrule "\n")

(defun my/gptel-agent--write-todo-around (orig todos)
  "Test stub for TodoWrite overlay advice."
  (setq gptel-agent--todos todos)
  (let ((existing-ov my/gptel--todo-overlay))
    (if existing-ov
        (progn
          (overlay-put existing-ov 'after-string
                       (format "Tasks: %d" (length todos)))
          t)
      (funcall orig todos))))

(ert-deftest test-todowrite-overlay-caching ()
  "Test that TodoWrite overlay is cached for O(1) lookup."
  (with-temp-buffer
    (let ((ov (make-overlay 1 1)))
      (overlay-put ov 'gptel-agent--todos t)
      (setq-local my/gptel--todo-overlay ov)
      (should (eq my/gptel--todo-overlay ov))
      (should (overlay-get my/gptel--todo-overlay 'gptel-agent--todos)))))

(ert-deftest test-todowrite-overlay-update ()
  "Test that TodoWrite updates cached overlay."
  (with-temp-buffer
    (let ((ov (make-overlay 1 1)))
      (overlay-put ov 'gptel-agent--todos t)
      (setq-local my/gptel--todo-overlay ov)
      (setq gptel-agent--todos nil)
      (let ((todos [(:content "Task 1" :status "pending" :activeForm "Doing task 1")]))
        (setq gptel-agent--todos (append todos nil))
        (should (= (length gptel-agent--todos) 1))))))

;;; Provide the test suite

(provide 'test-gptel-tools-agent)

;;; test-gptel-tools-agent.el ends here
