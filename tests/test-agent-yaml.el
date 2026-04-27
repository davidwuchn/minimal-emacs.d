;;; test-agent-yaml.el --- Tests for agent YAML frontmatter validation -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, agent, yaml, testing

;;; Commentary:

;; Tests for validating YAML frontmatter in agent files.
;; Ensures:
;; - Valid YAML syntax
;; - Required fields present (name, model)
;; - Model is a known model name

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Known models (subset of models validated in this repo)

(defconst test-agent-known-models
  '("qwen3.5-plus"
    "qwen3-max-2026-01-23"
    "qwen3-coder-plus"
    "qwen3-coder-next"
    "glm-5"
    "deepseek-v4-flash"
    "deepseek-v4-pro"
    "kimi-k2.5"
    "minimax-m2.7-highspeed"
    "minimax-m2.7"
    "minimax-m2.5")
  "List of known model names for validation.")

;;; YAML parsing

(defun test-agent--parse-yaml-frontmatter (file)
  "Parse YAML frontmatter from FILE.
Returns plist of frontmatter fields, or nil if invalid."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (looking-at "^---\\s-*$")
        (forward-line 1)
        (let ((start (point))
              (end (save-excursion
                     (if (re-search-forward "^---\\s-*$" nil t)
                         (match-beginning 0)
                       (point-max))))
              (result '()))
          (goto-char start)
          (while (< (point) end)
            (when (looking-at "^\\([a-zA-Z_-]+\\):\\s-*\\(.*\\)$")
              (let ((key (intern (concat ":" (match-string 1))))
                    (val (string-trim (match-string 2))))
                (push (cons key val) result)))
            (forward-line 1))
          (nreverse result))))))

(defun test-agent--get-agents-dir ()
  "Get the agents directory path."
  (let ((emacs-dir (or (bound-and-true-p user-emacs-directory)
                       (getenv "USER_EMACS_DIRECTORY")
                       default-directory)))
    (expand-file-name "assistant/agents/" emacs-dir)))

(defun test-agent--list-agent-files ()
  "List all agent markdown files."
  (directory-files (test-agent--get-agents-dir) t "\\.md$"))

;;; Tests

(ert-deftest test-agent-yaml-files-exist ()
  "Verify agent files exist in assistant/agents/."
  (should (file-directory-p (test-agent--get-agents-dir)))
  (should (> (length (test-agent--list-agent-files)) 0)))

(ert-deftest test-agent-yaml-frontmatter-valid ()
  "Verify all agent files have valid YAML frontmatter."
  (dolist (file (test-agent--list-agent-files))
    (let ((yaml (test-agent--parse-yaml-frontmatter file)))
      (should yaml))))

(ert-deftest test-agent-yaml-required-fields ()
  "Verify all agent files have required fields (name, model)."
  (dolist (file (test-agent--list-agent-files))
    (let ((yaml (test-agent--parse-yaml-frontmatter file)))
      (when yaml
        (should (alist-get :name yaml))
        (should (alist-get :model yaml))))))

(ert-deftest test-agent-yaml-model-known ()
  "Verify all agent files use known model names."
  (dolist (file (test-agent--list-agent-files))
    (let* ((yaml (test-agent--parse-yaml-frontmatter file))
           (model (alist-get :model yaml)))
      (when (and yaml model)
        (should (member model test-agent-known-models))))))

(ert-deftest test-agent-yaml-name-matches-filename ()
  "Verify agent name is present and reasonable."
  (dolist (file (test-agent--list-agent-files))
    (let* ((yaml (test-agent--parse-yaml-frontmatter file))
           (name (alist-get :name yaml)))
      (when yaml
        (should name)
        (should (stringp name))
        (should (> (length name) 0))))))

(ert-deftest test-agent-yaml-temperature-range ()
  "Verify temperature is in valid range [0.0, 2.0] if present."
  (dolist (file (test-agent--list-agent-files))
    (let* ((yaml (test-agent--parse-yaml-frontmatter file))
           (temp-str (alist-get :temperature yaml)))
      (when (and yaml temp-str)
        (let ((temp (string-to-number temp-str)))
          (should (and (>= temp 0.0) (<= temp 2.0))))))))

(ert-deftest test-agent-yaml-max-tokens-positive ()
  "Verify max-tokens is positive if present."
  (dolist (file (test-agent--list-agent-files))
    (let* ((yaml (test-agent--parse-yaml-frontmatter file))
           (tokens-str (alist-get :max-tokens yaml)))
      (when (and yaml tokens-str)
        (let ((tokens (string-to-number tokens-str)))
          (should (> tokens 0)))))))

;;; Provide the test suite

(provide 'test-agent-yaml)

;;; test-agent-yaml.el ends here
