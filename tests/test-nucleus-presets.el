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
(require 'nucleus-presets)

(defvar gptel-agent--agents)
(defvar gptel-backend)
(defvar nucleus-agents-dir)

(ert-deftest test-nucleus-read-agent-model-from-yaml ()
  "Test reading model from YAML frontmatter."
  (cl-letf (((symbol-function 'gptel-agent-read-file)
             (lambda (file &optional _no-cache _register)
               (cond
                ((string-match-p "code_agent.md" file)
                 (list 'agent
                       :name "nucleus-gptel-agent"
                       :model "minimax-m2.5"
                       :system "Test system prompt"))
                (t nil))))
            ((symbol-function 'file-readable-p)
              (lambda (file) (string-match-p "code_agent.md" file))))
    (let ((model (nucleus--read-agent-model "/path/to/code_agent.md")))
      (should (eq model 'minimax-m2.5)))))

(ert-deftest test-nucleus-read-agent-model-plan ()
  "Test reading plan agent model from YAML."
  (cl-letf (((symbol-function 'gptel-agent-read-file)
             (lambda (file &optional _no-cache _register)
               (cond
                ((string-match-p "plan_agent.md" file)
                 (list 'agent
                       :name "nucleus-gptel-plan"
                       :model "minimax-m2.5"
                       :system "Test plan prompt"))
                (t nil))))
            ((symbol-function 'file-readable-p)
              (lambda (file) (string-match-p "plan_agent.md" file))))
    (let ((model (nucleus--read-agent-model "/path/to/plan_agent.md")))
      (should (eq model 'minimax-m2.5)))))

(ert-deftest test-nucleus-read-agent-model-missing-file ()
  "Test that missing file returns nil."
  (let ((model (nucleus--read-agent-model "/nonexistent/file.md")))
    (should (null model))))

(ert-deftest test-nucleus-override-agent-presets-keeps-declared-tools-before-registration ()
  "Agent contracts should keep declared tool names even before registration completes."
  (let ((gptel-agent--agents '(("executor" :system "Executor system")))
        (gptel-backend 'test-backend)
        (nucleus-agents-dir "/tmp")
        (nucleus-tools-strict-validation nil))
    (cl-letf (((symbol-function 'gptel-get-preset)
               (lambda (_name)
                 '(:description "preset")))
              ((symbol-function 'gptel-make-preset)
               (lambda (&rest _) nil))
              ((symbol-function 'gptel-agent-read-file)
               (lambda (&rest _)
                 (list 'agent :model "minimax-m2.5" :system "Test system")))
              ((symbol-function 'file-readable-p)
               (lambda (_file) t))
              ((symbol-function 'nucleus--refresh-open-gptel-buffers)
               (lambda () nil))
              ((symbol-function 'gptel-get-tool)
               (lambda (name)
                 (not (member name '("TodoWrite" "Code_Map" "Grep" "Read" "Edit"))))))
      (nucleus--override-gptel-agent-presets)
      (let ((tools (plist-get (cdr (assoc "executor" gptel-agent--agents)) :tools)))
        (dolist (name '("TodoWrite" "Code_Map" "Grep" "Read" "Edit"))
          (should (member name tools)))))))

;;; Provide the test suite

(provide 'test-nucleus-presets)

;;; test-nucleus-presets.el ends here
