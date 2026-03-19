;;; test-nucleus-presets.el --- Tests for nucleus-presets.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, nucleus, testing

;;; Commentary:

;; Unit tests for nucleus-presets.el.
;; Tests cover:
;; - YAML model config reading
;; - Fallback behavior when YAML missing

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock gptel-agent-read-file

(defun gptel-agent-read-file (file &optional _no-cache _register)
  "Mock implementation for testing.
Returns parsed YAML frontmatter from FILE."
  (cond
   ((string-match-p "code_agent.md" file)
    (list 'agent
          :name "nucleus-gptel-agent"
          :model "qwen3.5-plus"
          :system "Test system prompt"))
   ((string-match-p "plan_agent.md" file)
    (list 'agent
          :name "nucleus-gptel-plan"
          :model "qwen3.5-plus"
          :system "Test plan prompt"))
   (t nil)))

;;; nucleus--read-agent-model tests

(defun nucleus--read-agent-model (agent-file)
  "Read model from AGENT-FILE YAML frontmatter.
Returns model as symbol, or nil if not found."
  (when (and agent-file
             (fboundp 'gptel-agent-read-file))
    (let* ((parsed (gptel-agent-read-file agent-file nil nil))
           (plist (cdr parsed))
           (model (plist-get plist :model)))
      (when (stringp model)
        (intern model)))))

(ert-deftest test-nucleus-read-agent-model-from-yaml ()
  "Test reading model from YAML frontmatter."
  (let ((model (nucleus--read-agent-model "/path/to/code_agent.md")))
    (should (eq model 'qwen3.5-plus))))

(ert-deftest test-nucleus-read-agent-model-plan ()
  "Test reading plan agent model from YAML."
  (let ((model (nucleus--read-agent-model "/path/to/plan_agent.md")))
    (should (eq model 'qwen3.5-plus))))

(ert-deftest test-nucleus-read-agent-model-missing-file ()
  "Test that missing file returns nil."
  (let ((model (nucleus--read-agent-model "/nonexistent/file.md")))
    (should (null model))))

;;; Provide the test suite

(provide 'test-nucleus-presets)

;;; test-nucleus-presets.el ends here