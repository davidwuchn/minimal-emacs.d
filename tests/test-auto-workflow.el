;;; test-auto-workflow.el --- Integration tests for auto-workflow -*- lexical-binding: t; -*-

;; Copyright (C) 2026  David Wu

;; Author: David Wu

;;; Commentary:

;; Integration tests for auto-workflow functionality.
;; Tests worktree path resolution and prompt generation.
;; Uses cl-letf for local mocking to avoid conflicts with real modules.

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock implementations (for use with cl-letf)

(defvar gptel-auto-workflow--worktree-dir nil)
(defvar gptel-auto-workflow--skills nil)
(defvar gptel-auto-experiment-time-budget 600)

(defun test-auto-workflow--project-root ()
  "Return the project root directory (git root or ~/.emacs.d).
Always returns absolute path."
  (expand-file-name
   (or (when (fboundp 'project-root)
         (when-let ((proj (project-current)))
           (project-root proj)))
       (when (boundp 'minimal-emacs-user-directory)
         minimal-emacs-user-directory)
       "~/.emacs.d/")))

(defun test-auto-workflow--build-prompt (target experiment-id max-experiments analysis baseline)
  "Build prompt for experiment EXPERIMENT-ID on TARGET.
Uses loaded skills and Eight Keys breakdown for focused improvements."
  (let* ((git-history (shell-command-to-string
                       (format "cd %s && git log --oneline -20 2>/dev/null || echo 'no history'"
                               (or gptel-auto-workflow--worktree-dir
                                   (test-auto-workflow--project-root)))))
         (patterns (when analysis (plist-get analysis :patterns)))
         (suggestions (when analysis (plist-get analysis :recommendations)))
         (skills (cdr (assoc target gptel-auto-workflow--skills)))
         (worktree-path (or gptel-auto-workflow--worktree-dir
                            (test-auto-workflow--project-root)))
         (target-full-path (expand-file-name target worktree-path)))
    (format "You are running experiment %d of %d to optimize %s.

## Working Directory
%s

## Target File (full path)
%s

## Previous Experiment Analysis
%s

## Suggestions
%s

## Git History (recent commits)
%s

## Current Baseline
Overall Eight Keys score: %.2f

## Objective
Improve the Eight Keys score for %s.
Focus on one improvement at a time.
Make minimal, targeted changes.

## Constraints
- Time budget: %d minutes
- Immutable files: early-init.el, pre-early-init.el, lisp/eca-security.el
- Must pass tests: ./scripts/verify-nucleus.sh

## Instructions
1. First, write your HYPOTHESIS: What change might improve the score? Why?
2. Read the target file using its full path
3. Implement the change minimally using Edit tool with the full path
4. Run tests to verify

Format your hypothesis at the start as:
HYPOTHESIS: [your hypothesis here]"
            experiment-id max-experiments target
            worktree-path
            target-full-path
            (or patterns "No previous experiments")
            (or suggestions "None")
            git-history
            (or baseline 0.5)
            target
            (/ gptel-auto-experiment-time-budget 60))))

;;; Unit Tests: project-root

(ert-deftest auto-workflow/project-root-returns-absolute-path ()
  "gptel-auto-workflow--project-root should return absolute path."
  (let ((root (test-auto-workflow--project-root)))
    (should (stringp root))
    (should (file-name-absolute-p root))))

(ert-deftest auto-workflow/project-root-uses-expand-file-name ()
  "Should expand ~ and relative paths to absolute."
  (let ((root (test-auto-workflow--project-root)))
    (should-not (string-match-p "^~" root))
    (should (string-match-p "^/" root))))

;;; Unit Tests: path resolution

(ert-deftest auto-workflow/worktree-path-overrides-project-root ()
  "When worktree is set, target path should use worktree."
  (let ((gptel-auto-workflow--worktree-dir "/tmp/test-worktree")
        (target "gptel-ext-retry.el"))
    (let ((full-path (expand-file-name target (or gptel-auto-workflow--worktree-dir
                                                   (test-auto-workflow--project-root)))))
      (should (string= full-path "/tmp/test-worktree/gptel-ext-retry.el")))))

(ert-deftest auto-workflow/no-worktree-uses-project-root ()
  "When worktree is nil, target path should use project root."
  (let ((gptel-auto-workflow--worktree-dir nil)
        (target "gptel-ext-retry.el"))
    (let* ((proj-root (test-auto-workflow--project-root))
           (full-path (expand-file-name target (or gptel-auto-workflow--worktree-dir
                                                    proj-root))))
      (should (file-name-absolute-p full-path))
      (should (string-match-p "/gptel-ext-retry\\.el$" full-path)))))

;;; Unit Tests: prompt content

(ert-deftest auto-workflow/prompt-with-worktree-uses-worktree-path ()
  "When worktree is set, prompt should use worktree paths."
  (let ((gptel-auto-workflow--worktree-dir "/tmp/test-worktree")
        (gptel-auto-workflow--skills nil))
    (let ((prompt (test-auto-workflow--build-prompt "test.el" 1 1 nil 0.5)))
      (should (string-match-p "/tmp/test-worktree" prompt)))))

(ert-deftest auto-workflow/prompt-without-worktree-uses-project-root ()
  "When worktree is nil, prompt should use project root paths."
  (let* ((gptel-auto-workflow--worktree-dir nil)
         (gptel-auto-workflow--skills nil)
         (proj-root (test-auto-workflow--project-root))
         (prompt (test-auto-workflow--build-prompt "test.el" 1 1 nil 0.5)))
    (should (file-name-absolute-p proj-root))
    (should (string-match-p (regexp-quote proj-root) prompt))))

(ert-deftest auto-workflow/prompt-has-required-sections ()
  "Prompt should have all required sections."
  (let* ((gptel-auto-workflow--worktree-dir nil)
         (gptel-auto-workflow--skills nil)
         (prompt (test-auto-workflow--build-prompt "test.el" 1 3 nil 0.5)))
    (should (string-match-p "## Working Directory" prompt))
    (should (string-match-p "## Target File (full path)" prompt))
    (should (string-match-p "## Previous Experiment Analysis" prompt))
    (should (string-match-p "## Suggestions" prompt))
    (should (string-match-p "## Git History" prompt))
    (should (string-match-p "## Current Baseline" prompt))
    (should (string-match-p "## Objective" prompt))
    (should (string-match-p "## Constraints" prompt))
    (should (string-match-p "## Instructions" prompt))))

(ert-deftest auto-workflow/prompt-experiment-id-included ()
  "Prompt should show current experiment number."
  (let* ((gptel-auto-workflow--worktree-dir nil)
         (gptel-auto-workflow--skills nil)
         (prompt (test-auto-workflow--build-prompt "test.el" 2 5 nil 0.5)))
    (should (string-match-p "experiment 2 of 5" prompt))))

(ert-deftest auto-workflow/prompt-target-name-included ()
  "Prompt should include target filename."
  (let* ((gptel-auto-workflow--worktree-dir nil)
         (gptel-auto-workflow--skills nil)
         (prompt (test-auto-workflow--build-prompt "gptel-ext-context.el" 1 1 nil 0.5)))
    (should (string-match-p "gptel-ext-context\\.el" prompt))))

(ert-deftest auto-workflow/prompt-instructions-use-full-path ()
  "Instructions should tell agent to use full path with Edit tool."
  (let* ((gptel-auto-workflow--worktree-dir nil)
         (gptel-auto-workflow--skills nil)
         (prompt (test-auto-workflow--build-prompt "test.el" 1 1 nil 0.5)))
    (should (string-match-p "Edit tool with the full path" prompt))
    (should (string-match-p "Read the target file using its full path" prompt))))

;;; Path Format Tests

(ert-deftest auto-workflow/working-directory-is-absolute ()
  "Working directory in prompt must be absolute path."
  (let* ((gptel-auto-workflow--worktree-dir nil)
         (gptel-auto-workflow--skills nil)
         (prompt (test-auto-workflow--build-prompt "test.el" 1 1 nil 0.5)))
    (with-temp-buffer
      (insert prompt)
      (goto-char (point-min))
      (should (re-search-forward "## Working Directory\n\\([^\n]+\\)" nil t))
      (let ((workdir (match-string 1)))
        (should (file-name-absolute-p workdir))
        (should-not (string-match-p "^~" workdir))))))

(ert-deftest auto-workflow/target-path-is-absolute ()
  "Target file path in prompt must be absolute."
  (let* ((gptel-auto-workflow--worktree-dir nil)
         (gptel-auto-workflow--skills nil)
         (prompt (test-auto-workflow--build-prompt "test.el" 1 1 nil 0.5)))
    (with-temp-buffer
      (insert prompt)
      (goto-char (point-min))
      (should (re-search-forward "## Target File (full path)\n\\([^\n]+\\)" nil t))
      (let ((target-path (match-string 1)))
        (should (file-name-absolute-p target-path))
        (should-not (string-match-p "^~" target-path))))))

(ert-deftest auto-workflow/paths-contain-no-tilde ()
  "Paths should not contain unexpanded ~."
  (let* ((gptel-auto-workflow--worktree-dir nil)
         (gptel-auto-workflow--skills nil)
         (prompt (test-auto-workflow--build-prompt "test.el" 1 1 nil 0.5)))
    (should-not (string-match-p "^~" prompt))
    (should-not (string-match-p "
~" prompt))))

(provide 'test-auto-workflow)
;;; test-auto-workflow.el ends here
