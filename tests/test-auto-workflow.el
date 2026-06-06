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
(require 'gptel-tools-agent-base)
(require 'gptel-auto-workflow-evolution)

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
2. Use Code_Map or Grep to find the relevant function/section in the target file first
3. Read only focused line ranges from the target file using its full path; avoid reading the entire file unless absolutely necessary
4. Implement the change minimally using Edit tool with the full path
5. Run tests to verify

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

;;; Unit Tests: workspace boundary validator

(ert-deftest auto-workflow/workspace-boundary/path-within-workspace-p-inside ()
  "Path inside ~/.emacs.d/ should return t."
  (let ((gptel-auto-workflow--allowed-workspace-roots
         (list (expand-file-name "~/.emacs.d/")))
        (path (expand-file-name "lisp/modules/gptel-tools-agent-base.el" "~/.emacs.d/")))
    (should (gptel-auto-workflow--path-within-workspace-p path))))

(ert-deftest auto-workflow/workspace-boundary/path-within-workspace-p-outside ()
  "Path outside all roots should return nil."
  (let ((gptel-auto-workflow--allowed-workspace-roots
         (list (expand-file-name "~/.emacs.d/")))
        (path "/tmp/outside-workspace-test-dir/"))
    (should-not (gptel-auto-workflow--path-within-workspace-p path))))

(ert-deftest auto-workflow/workspace-boundary/path-within-workspace-p-nil ()
  "nil path should return nil."
  (let ((gptel-auto-workflow--allowed-workspace-roots
         (list (expand-file-name "~/.emacs.d/"))))
    (should-not (gptel-auto-workflow--path-within-workspace-p nil))))

(ert-deftest auto-workflow/workspace-boundary/path-within-workspace-p-exact-root ()
  "Path exactly equal to a root directory should return t."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root)))
    (should (gptel-auto-workflow--path-within-workspace-p root))))

(ert-deftest auto-workflow/workspace-boundary/path-within-workspace-p-relative ()
  "Relative path inside workspace should return t when default-directory is inside a root."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (default-directory root))
    (should (gptel-auto-workflow--path-within-workspace-p "lisp/modules/test.el"))))

(ert-deftest auto-workflow/workspace-boundary/path-within-workspace-p-dotdot-escape ()
  "Path with .. escaping workspace should return nil."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (default-directory root))
    (should-not (gptel-auto-workflow--path-within-workspace-p "../../../outside-escape.el"))))

(ert-deftest auto-workflow/workspace-boundary/path-within-workspace-p-multiple-roots ()
  "Path inside second root should return t when first root doesn't match."
  (let* ((root1 (expand-file-name "~/.emacs.d/"))
         (root2 (expand-file-name "/tmp/aw-boundary-test-root/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root1 root2))
         (path (expand-file-name "some-file.el" root2)))
    (unwind-protect
        (progn
          (make-directory root2 t)
          (should (gptel-auto-workflow--path-within-workspace-p path)))
      (when (file-directory-p root2)
        (delete-directory root2 t)))))

(ert-deftest auto-workflow/workspace-boundary/expand-workspace-path-valid ()
  "Valid path within workspace should return expanded absolute path."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil)
         (result (gptel-auto-workflow--expand-workspace-path "lisp/modules/test.el")))
    (should (stringp result))
    (should (file-name-absolute-p result))
    (should (string-prefix-p (file-name-as-directory root) result))))

(ert-deftest auto-workflow/workspace-boundary/expand-workspace-path-invalid ()
  "Path outside workspace should signal an error."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil))
    (should-error (gptel-auto-workflow--expand-workspace-path "/tmp/outside-path.el"))))

(ert-deftest auto-workflow/workspace-boundary/expand-workspace-path-nil ()
  "nil path should signal an error."
  (let ((gptel-auto-workflow--allowed-workspace-roots
         (list (expand-file-name "~/.emacs.d/"))))
    (should-error (gptel-auto-workflow--expand-workspace-path nil))))

(ert-deftest auto-workflow/workspace-boundary/expand-workspace-path-with-root ()
  "Path expanded relative to explicit root argument."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (result (gptel-auto-workflow--expand-workspace-path "lisp/modules/test.el" root)))
    (should (stringp result))
    (should (string-prefix-p (file-name-as-directory root) result))))

(ert-deftest auto-workflow/workspace-boundary/macro-inside-workspace ()
  "with-workspace-boundary should execute body when path is inside workspace."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil)
         (executed nil))
    (with-workspace-boundary (f "lisp/modules/test.el")
      (setq executed t))
    (should executed)))

(ert-deftest auto-workflow/workspace-boundary/macro-outside-workspace ()
  "with-workspace-boundary should signal error when path is outside workspace."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil))
    (should-error
     (with-workspace-boundary (f "/tmp/outside-path.el")
       f))))

(ert-deftest auto-workflow/workspace-boundary/macro-binds-path-var ()
  "with-workspace-boundary should bind path-var to the expanded absolute path."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil)
         (bound-value nil))
    (with-workspace-boundary (f "lisp/modules/test.el")
      (setq bound-value f))
    (should (stringp bound-value))
    (should (file-name-absolute-p bound-value))
    (should (string-prefix-p (file-name-as-directory root) bound-value))))

(ert-deftest auto-workflow/workspace-boundary/macro-with-explicit-root ()
  "with-workspace-boundary should accept optional root argument."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (bound-value nil))
    (with-workspace-boundary (f "lisp/modules/test.el" root)
      (setq bound-value f))
    (should (stringp bound-value))
    (should (string-prefix-p (file-name-as-directory root) bound-value))))

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
    (should (string-match-p "Use Code_Map or Grep to find the relevant function/section" prompt))
    (should (string-match-p "Read only focused line ranges from the target file using its full path" prompt))))

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

(defun make-temp-file (prefix)
  "Create a temporary directory with PREFIX and return its path."
  (let ((dir (make-temp-name (expand-file-name prefix temporary-file-directory))))
    (make-directory dir t)
    dir))

;;; Bare Path Diagnostic Tests

(ert-deftest auto-workflow/bare-path-diagnostic/detects-directory-files-bare-string ()
  "Should detect (directory-files \"some-dir\" ...) as a bare path violation."
  (let* ((test-dir (make-temp-file "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files \"relative-dir\" t \"\\.el\\'\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 1))
            (should (string= (plist-get (car violations) :function) "directory-files"))
            (should (string= (plist-get (car violations) :raw-path) "relative-dir"))))
      (delete-directory test-dir t))))

(ert-deftest auto-workflow/bare-path-diagnostic/detects-with-temp-file-bare-string ()
  "Should detect (with-temp-file \"output.txt\" ...) as a bare path violation."
  (let* ((test-dir (make-temp-file "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (with-temp-file \"output.txt\"\n    (insert \"data\")))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 1))
            (should (string= (plist-get (car violations) :function) "with-temp-file"))
            (should (string= (plist-get (car violations) :raw-path) "output.txt"))))
      (delete-directory test-dir t))))

(ert-deftest auto-workflow/bare-path-diagnostic/detects-find-file-bare-string ()
  "Should detect (find-file \"config.el\") as a bare path violation."
  (let* ((test-dir (make-temp-file "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (find-file \"config.el\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 1))
            (should (string= (plist-get (car violations) :function) "find-file"))
            (should (string= (plist-get (car violations) :raw-path) "config.el"))))
      (delete-directory test-dir t))))

(ert-deftest auto-workflow/bare-path-diagnostic/skips-absolute-paths ()
  "Should NOT flag absolute paths (/tmp/... or ~/...)."
  (let* ((test-dir (make-temp-file "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files \"/tmp/absolute-dir\" t \"\\.el\\'\"))\n")
            (insert "(defun test-fn2 ()\n  (find-file \"~/config.el\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 0))))
      (delete-directory test-dir t))))

(ert-deftest auto-workflow/bare-path-diagnostic/skips-expand-file-name-with-root ()
  "Should NOT flag paths wrapped in expand-file-name with a root."
  (let* ((test-dir (make-temp-file "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files (expand-file-name \"relative-dir\" some-root) t \"\\.el\\'\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 0))))
      (delete-directory test-dir t))))

(ert-deftest auto-workflow/bare-path-diagnostic/skips-workspace-expand-paths ()
  "Should NOT flag paths wrapped in gptel-auto-workflow--expand-workspace-path."
  (let* ((test-dir (make-temp-file "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files (gptel-auto-workflow--expand-workspace-path \"lisp/modules\") t \"\\.el\\'\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 0))))
      (delete-directory test-dir t))))

(ert-deftest auto-workflow/bare-path-diagnostic/suggested-fix-is-expand-workspace-path ()
  "Suggested fix should wrap the bare path in gptel-auto-workflow--expand-workspace-path."
  (let* ((test-dir (make-temp-file "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (insert-file-contents \"data/input.tsv\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 1))
            (should (string= (plist-get (car violations) :suggested-fix)
                             "(gptel-auto-workflow--expand-workspace-path \"data/input.tsv\")"))))
      (delete-directory test-dir t))))

(ert-deftest auto-workflow/bare-path-diagnostic/no-violations-clean-file ()
  "Should return empty list when file has no bare path violations."
  (let* ((test-dir (make-temp-file "bare-path-test-"))
         (test-file (expand-file-name "test-clean.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files (expand-file-name \"lisp/modules\" root) t \"\\.el\\'\"))\n")
            (insert ";; (directory-files \"commented-dir\" t) — this is a comment\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 0))))
      (delete-directory test-dir t))))

(provide 'test-auto-workflow)
;;; test-auto-workflow.el ends here
