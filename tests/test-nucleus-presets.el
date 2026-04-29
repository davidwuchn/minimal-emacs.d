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
(require 'nucleus-prompts)
(require 'nucleus-presets)

(defvar gptel-agent--agents)
(defvar gptel-agent-dirs)
(defvar gptel-agent-skill-dirs)
(defvar gptel-backend)
(defvar nucleus-agents-dir)
(defvar gptel-mode)
(defvar gptel--preset)
(defvar minimal-emacs-user-directory)

(ert-deftest test-nucleus-read-agent-model-from-yaml ()
  "Test reading model from YAML frontmatter."
  (cl-letf (((symbol-function 'gptel-agent-read-file)
             (lambda (file &optional _no-cache _register)
               (cond
                ((string-match-p "code_agent.md" file)
                 (list 'agent
                       :name "nucleus-gptel-agent"
                       :model "minimax-m2.7-highspeed"
                       :system "Test system prompt"))
                (t nil))))
            ((symbol-function 'file-readable-p)
              (lambda (file) (string-match-p "code_agent.md" file))))
    (let ((model (nucleus--read-agent-model "/path/to/code_agent.md")))
      (should (eq model 'minimax-m2.7-highspeed)))))

(ert-deftest test-nucleus-read-agent-model-plan ()
  "Test reading plan agent model from YAML."
  (cl-letf (((symbol-function 'gptel-agent-read-file)
             (lambda (file &optional _no-cache _register)
               (cond
                ((string-match-p "plan_agent.md" file)
                 (list 'agent
                       :name "nucleus-gptel-plan"
                       :model "minimax-m2.7-highspeed"
                       :system "Test plan prompt"))
                (t nil))))
            ((symbol-function 'file-readable-p)
              (lambda (file) (string-match-p "plan_agent.md" file))))
    (let ((model (nucleus--read-agent-model "/path/to/plan_agent.md")))
      (should (eq model 'minimax-m2.7-highspeed)))))

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
                 (list 'agent :model "minimax-m2.7-highspeed" :system "Test system")))
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

(ert-deftest test-nucleus-refresh-open-gptel-buffers-skips-stale-default-directories ()
  "Preset refresh should ignore gptel buffers whose worktree dirs were removed."
  (let* ((fresh-root (file-name-as-directory (make-temp-file "nucleus-fresh" t)))
         (stale-root (file-name-as-directory (make-temp-file "nucleus-stale" t)))
         (fresh-buf (generate-new-buffer " *nucleus-fresh*"))
         (stale-buf (generate-new-buffer " *nucleus-stale*"))
         (applied nil)
         (messages nil))
    (delete-directory stale-root t)
    (unwind-protect
        (progn
          (with-current-buffer fresh-buf
            (setq-local default-directory fresh-root)
            (setq-local gptel-mode t)
            (setq-local gptel--preset 'gptel-agent))
          (with-current-buffer stale-buf
            (setq-local default-directory stale-root)
            (setq-local gptel-mode t)
            (setq-local gptel--preset 'gptel-plan))
          (cl-letf (((symbol-function 'gptel--apply-preset)
                     (lambda (preset &optional _setter)
                       (push (list (buffer-name (current-buffer)) preset default-directory) applied)))
                    ((symbol-function 'buffer-list)
                     (lambda ()
                       (list fresh-buf stale-buf)))
                    ((symbol-function 'message)
                     (lambda (fmt &rest args)
                       (push (apply #'format fmt args) messages))))
            (nucleus--refresh-open-gptel-buffers))
          (should (= (length applied) 1))
          (should (equal (caar applied) (buffer-name fresh-buf)))
          (should (seq-some (lambda (msg)
                              (string-match-p "Skipping stale gptel buffer" msg))
                            messages)))
      (when (buffer-live-p fresh-buf)
        (kill-buffer fresh-buf))
      (when (buffer-live-p stale-buf)
        (kill-buffer stale-buf))
      (when (file-directory-p fresh-root)
        (delete-directory fresh-root t)))))

(ert-deftest test-nucleus-project-root-falls-back-from-stale-default-directory ()
  "Project root resolution should avoid deleted worktree directories."
  (let* ((live-root (file-name-as-directory (make-temp-file "nucleus-live-root" t)))
         (stale-root (file-name-as-directory (make-temp-file "nucleus-dead-root" t)))
         (default-directory stale-root)
         (user-emacs-directory "/tmp/original-root/")
         (minimal-emacs-user-directory live-root)
         (project-current-dir nil))
    (delete-directory stale-root t)
    (unwind-protect
        (cl-letf (((symbol-function 'project-current)
                   (lambda (&optional _maybe-prompt)
                     (setq project-current-dir default-directory)
                     nil)))
          (should (equal (nucleus--project-root) live-root))
          (should (equal project-current-dir live-root)))
      (when (file-directory-p live-root)
        (delete-directory live-root t)))))

(ert-deftest test-nucleus-setup-agents-prunes-stale-directories ()
  "Agent setup should drop dead worktree dirs before refreshing agent defs."
  (let* ((live-root (file-name-as-directory (make-temp-file "nucleus-live-agents" t)))
         (stale-root (file-name-as-directory (make-temp-file "nucleus-stale-agents" t)))
         (user-emacs-directory "/tmp/original-root/")
         (minimal-emacs-user-directory live-root)
         (live-agents (expand-file-name "assistant/agents/" live-root))
         (live-skills (expand-file-name "assistant/skills/" live-root))
         (stale-agents (expand-file-name "assistant/agents/" stale-root))
         (stale-skills (expand-file-name "assistant/skills/" stale-root))
         (gptel-agent-dirs (list "/tmp/keep-agents/" stale-agents stale-agents))
         (gptel-agent-skill-dirs (list "/tmp/keep-skills/" stale-skills stale-skills))
         (update-called nil))
    (make-directory live-agents t)
    (make-directory live-skills t)
    (make-directory "/tmp/keep-agents/" t)
    (make-directory "/tmp/keep-skills/" t)
    (delete-directory stale-root t)
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (eq feature 'gptel-agent)))
              ((symbol-function 'nucleus--project-root)
               (lambda ()
                 live-root))
              ((symbol-function 'gptel-agent-update)
               (lambda ()
                 (setq update-called t))))
      (nucleus-presets-setup-agents)
      (should update-called)
      (should (equal gptel-agent-dirs
                     (list "/tmp/keep-agents/" live-agents)))
      (should (equal gptel-agent-skill-dirs
                     (list "/tmp/keep-skills/" live-skills))))))

;;; Provide the test suite

(provide 'test-nucleus-presets)

;;; test-nucleus-presets.el ends here
