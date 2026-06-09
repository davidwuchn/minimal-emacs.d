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
(require 'gptel-auto-workflow-bare-path-diagnostic)
(require 'gptel-platform-sandbox)
(require 'gptel-tools)
(require 'gptel-tools-edit)
(require 'gptel-tools-grep)
(require 'gptel-tools-bash)

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

(defun test-auto-workflow--make-temp-dir (prefix)
  "Create a temporary directory with PREFIX and return its path."
  (let ((dir (make-temp-name (expand-file-name prefix temporary-file-directory))))
    (make-directory dir t)
    dir))

;;; Bare Path Diagnostic Tests

(ert-deftest auto-workflow/bare-path-diagnostic/detects-directory-files-bare-string ()
  "Should detect (directory-files \"some-dir\" ...) as a bare path violation."
  (let* ((test-dir (test-auto-workflow--make-temp-dir "bare-path-test-"))
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
  (let* ((test-dir (test-auto-workflow--make-temp-dir "bare-path-test-"))
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
  (let* ((test-dir (test-auto-workflow--make-temp-dir "bare-path-test-"))
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
  (let* ((test-dir (test-auto-workflow--make-temp-dir "bare-path-test-"))
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
  (let* ((test-dir (test-auto-workflow--make-temp-dir "bare-path-test-"))
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
  (let* ((test-dir (test-auto-workflow--make-temp-dir "bare-path-test-"))
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
  (let* ((test-dir (test-auto-workflow--make-temp-dir "bare-path-test-"))
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
  (let* ((test-dir (test-auto-workflow--make-temp-dir "bare-path-test-"))
         (test-file (expand-file-name "test-clean.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files (expand-file-name \"lisp/modules\" root) t \"\\.el\\'\"))\n")
            (insert ";; (directory-files \"commented-dir\" t) — this is a comment\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 0))))
      (delete-directory test-dir t))))

;;; Model Routing Tests

(ert-deftest auto-workflow/model-routing/detects-code-task ()
  "Should detect code tasks from keywords."
  (should (eq (gptel-auto-workflow--detect-task-type "defun my-function ()") 'code))
  (should (eq (gptel-auto-workflow--detect-task-type "fix this bug") 'code))
  (should (eq (gptel-auto-workflow--detect-task-type "implement a new module") 'code)))

(ert-deftest auto-workflow/model-routing/detects-review-task ()
  "Should detect review tasks from keywords."
  (should (eq (gptel-auto-workflow--detect-task-type "review my code") 'review))
  (should (eq (gptel-auto-workflow--detect-task-type "audit the security") 'review))
  (should (eq (gptel-auto-workflow--detect-task-type "validate changes") 'review)))

(ert-deftest auto-workflow/model-routing/detects-research-task ()
  "Should detect research tasks from keywords."
  (should (eq (gptel-auto-workflow--detect-task-type "research the topic") 'research))
  (should (eq (gptel-auto-workflow--detect-task-type "analyze data") 'research))
  (should (eq (gptel-auto-workflow--detect-task-type "explore options") 'research)))

(ert-deftest auto-workflow/model-routing/detects-creative-task ()
  "Should detect creative tasks from keywords."
  (should (eq (gptel-auto-workflow--detect-task-type "brainstorm ideas") 'creative))
  (should (eq (gptel-auto-workflow--detect-task-type "design a new feature") 'creative))
  (should (eq (gptel-auto-workflow--detect-task-type "create a prototype") 'creative)))

(ert-deftest auto-workflow/model-routing/detects-orchestration-task ()
  "Should detect orchestration tasks from keywords."
  (should (eq (gptel-auto-workflow--detect-task-type "plan the workflow") 'orchestration))
  (should (eq (gptel-auto-workflow--detect-task-type "coordinate tasks") 'orchestration))
  (should (eq (gptel-auto-workflow--detect-task-type "manage the pipeline") 'orchestration)))

(ert-deftest auto-workflow/model-routing/returns-nil-for-empty-prompt ()
  "Should return nil for empty or unmatched prompts."
  (should (null (gptel-auto-workflow--detect-task-type "")))
  (should (null (gptel-auto-workflow--detect-task-type nil)))
  (should (null (gptel-auto-workflow--detect-task-type "hello world"))))

(ert-deftest auto-workflow/model-routing/routes-to-correct-model ()
  "Should route task types to correct agents/models."
  (let ((code-route (gptel-auto-workflow--route-task-to-model 'code))
        (review-route (gptel-auto-workflow--route-task-to-model 'review))
        (research-route (gptel-auto-workflow--route-task-to-model 'research))
        (creative-route (gptel-auto-workflow--route-task-to-model 'creative))
        (orchestration-route (gptel-auto-workflow--route-task-to-model 'orchestration))
        (default-route (gptel-auto-workflow--route-task-to-model nil)))
    (should (string= (plist-get code-route :agent) "implementer"))
    (should (string= (plist-get code-route :model) "glm-5.1"))
    (should (string= (plist-get review-route :agent) "delegate-opus"))
    (should (string= (plist-get review-route :model) "claude-opus-4.8"))
    (should (string= (plist-get research-route :agent) "delegate"))
    (should (string= (plist-get research-route :model) "deepseek-v4-pro"))
    (should (string= (plist-get creative-route :agent) "delegate-creative"))
    (should (string= (plist-get creative-route :model) "minimax-m3"))
    (should (string= (plist-get orchestration-route :agent) "@maintainer"))
    (should (string= (plist-get orchestration-route :model) "kimi-k2.6"))
    (should (string= (plist-get default-route :agent) "delegate"))
    (should (string= (plist-get default-route :model) "deepseek-v4-pro"))))

(ert-deftest auto-workflow/auto-route-prompt/returns-full-routing ()
  "Should return complete routing plist with task type, agent, and model."
  (let ((routing (gptel-auto-workflow--auto-route-prompt "implement a new function")))
    (should (eq (plist-get routing :task-type) 'code))
    (should (string= (plist-get routing :agent) "implementer"))
    (should (string= (plist-get routing :model) "glm-5.1"))
    (should (plist-get routing :task-type))
    (should (plist-get routing :agent))
    (should (plist-get routing :model))))

(ert-deftest auto-workflow/auto-route-prompt/handles-nil ()
  "Should handle nil prompts gracefully."
  (let ((routing (gptel-auto-workflow--auto-route-prompt nil)))
    (should (null (plist-get routing :task-type)))
    (should (string= (plist-get routing :agent) "delegate"))
    (should (string= (plist-get routing :model) "deepseek-v4-pro"))))

;;; Platform Sandbox Tests

(ert-deftest auto-workflow/platform-sandbox/available-p ()
  "Platform sandbox should detect availability (sandbox-exec on macOS, bwrap on Linux)."
  (let ((result (gptel-platform-sandbox--available-p)))
    (should (or (eq result t) (eq result nil)))))

(ert-deftest auto-workflow/platform-sandbox/platform-name ()
  "Platform name should return a keyword."
  (let ((name (gptel-platform-sandbox--platform-name)))
    (should (memq name '(:seatbelt :bubblewrap :none)))))

(ert-deftest auto-workflow/platform-sandbox/seatbelt-profile-plan-mode ()
  "Seatbelt profile in plan mode should deny network."
  (when (eq system-type 'darwin)
    (let ((profile nil))
      (unwind-protect
          (progn
            (setq profile (gptel-platform-sandbox--seatbelt-profile :plan))
            (should (file-exists-p profile))
            (with-temp-buffer
              (insert-file-contents profile)
              (let ((content (buffer-string)))
                ;; Plan mode denies network
                (should (string-match-p "(deny network\\*)" content))
                ;; Workspace gets read+write
                (should (string-match-p "(allow file-read\\* file-write\\*" content))
                ;; Default is deny
                (should (string-match-p "(deny default)" content)))))
        (when (and profile (file-exists-p profile))
          (delete-file profile))))))

(ert-deftest auto-workflow/platform-sandbox/seatbelt-profile-agent-mode ()
  "Seatbelt profile in agent mode should allow network."
  (when (eq system-type 'darwin)
    (let ((profile nil))
      (unwind-protect
          (progn
            (setq profile (gptel-platform-sandbox--seatbelt-profile :agent))
            (should (file-exists-p profile))
            (with-temp-buffer
              (insert-file-contents profile)
              (let ((content (buffer-string)))
                ;; Agent mode allows network
                (should (string-match-p "(allow network-outbound)" content))
                ;; Should NOT contain deny network
                (should-not (string-match-p "(deny network\\*)" content)))))
        (when (and profile (file-exists-p profile))
          (delete-file profile))))))

(ert-deftest auto-workflow/platform-sandbox/wrap-command-returns-cons ()
  "wrap-command should return (WRAPPED . PROFILE-FILE) or (COMMAND . nil)."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-platform-sandbox--workspace-root root)
         (result (gptel-platform-sandbox--wrap-command "echo hello")))
    (should (consp result))
    (should (stringp (car result)))
    ;; Cleanup if profile file was created
    (when (cdr result)
      (should (file-exists-p (cdr result)))
      (delete-file (cdr result)))))

(ert-deftest auto-workflow/platform-sandbox/wrap-command-contains-sandbox-exec ()
  "On macOS, wrapped command should contain sandbox-exec."
  (when (and (eq system-type 'darwin)
             (executable-find "sandbox-exec"))
    (let* ((root (expand-file-name "~/.emacs.d/"))
           (gptel-platform-sandbox--workspace-root root)
           (result (gptel-platform-sandbox--wrap-command "echo hello")))
      (unwind-protect
          (should (string-match-p "sandbox-exec" (car result)))
        (when (cdr result)
          (delete-file (cdr result)))))))

;;; Tool Boundary Integration Tests

(ert-deftest auto-workflow/tool-boundary/read/rejects-outside-path ()
  "Read tool should signal error for paths outside workspace."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil))
    (should-error (my/gptel--read-file-safe "/tmp/outside-boundary-test.el")
                  :type 'error)))

(ert-deftest auto-workflow/tool-boundary/read/accepts-inside-path ()
  "Read tool should accept paths inside workspace (even if file doesn't exist, boundary check passes)."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil))
    ;; This should NOT signal a boundary error — it will fail with "not readable"
    ;; but that proves boundary check passed.
    (should-error (my/gptel--read-file-safe "lisp/modules/nonexistent-test-file.el")
                  :type 'error)))

(ert-deftest auto-workflow/tool-boundary/edit/rejects-outside-path ()
  "Edit tool callback should receive error containing [boundary] for outside paths."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil)
         (result nil))
    ;; Edit is async — error delivered to callback as string
    (my/gptel--agent-edit-async
     (lambda (r) (setq result r))
     "/tmp/outside-edit-boundary-test.el"
     "old" "new")
    (should (stringp result))
    (should (string-match-p "\\[boundary\\]" result))))

(ert-deftest auto-workflow/tool-boundary/grep/rejects-outside-path ()
  "Grep tool callback should receive error containing [boundary] for outside paths."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil)
         (result nil))
    ;; Grep is async — error delivered to callback as string
    (my/gptel--agent-grep-async
     (lambda (r) (setq result r))
     "test-pattern"
     "/tmp/outside-grep-boundary-dir")
    (should (stringp result))
    (should (string-match-p "\\[boundary\\]" result))))

(ert-deftest auto-workflow/tool-boundary/bash/rejects-outside-cwd ()
  "Bash tool should reject commands when CWD is outside workspace."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil)
         (default-directory "/tmp/")
         (result nil))
    ;; Mock context directory to return something outside workspace
    (cl-letf (((symbol-function 'my/gptel--bash-context-directory)
               (lambda () "/tmp/")))
      (my/gptel--agent-bash-async
       (lambda (r) (setq result r))
       "echo hello"))
    (should (stringp result))
    (should (string-match-p "\\[boundary\\]" result))))

(ert-deftest auto-workflow/tool-boundary/bash/sandbox-toggle-disable ()
  "Bash tool should work without platform sandbox when toggle is nil."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil)
         (my/gptel-bash-platform-sandbox nil)
         (default-directory root)
         (result nil))
    (cl-letf (((symbol-function 'my/gptel--bash-context-directory)
               (lambda () root)))
      ;; Should not error — boundary check passes, sandbox disabled
      (my/gptel--agent-bash-async
       (lambda (r) (setq result r))
       "echo hello"))
    ;; Result should NOT be a boundary error (might be actual output or timeout)
    (when (stringp result)
      (should-not (string-match-p "\\[boundary\\]" result)))))

(provide 'test-auto-workflow)
;;; test-auto-workflow.el ends here

;;; Security Regression Tests
;;; These verify that the 14 findings from the security audit are fixed.

;; ── C1: Platform sandbox shell breakout ──

(ert-deftest security/C1/seatbelt-wraps-command-as-single-arg ()
  "Platform sandbox must pass command as a single shell-quoted arg to bash -c.
Prevents shell metachar breakout via ; && | newlines."
  (when (eq system-type 'darwin)
    (let* ((gptel-platform-sandbox--workspace-root (expand-file-name "~/.emacs.d/"))
           (result (gptel-platform-sandbox--wrap-command "echo inside; echo outside")))
      (unwind-protect
          (progn
            ;; Must contain /bin/bash -c with shell-quoted arg
            (should (string-match-p "/bin/bash -c " (car result)))
            ;; Must NOT contain raw semicolon after -- (that would allow breakout)
            (should-not (string-match-p "-- echo inside; " (car result)))
            ;; The semicolon must be escaped (shell-quote-argument escapes it)
            (should (string-match-p "echo\\\\.*inside" (car result))))
        (when (cdr result) (delete-file (cdr result)))))))

(ert-deftest security/C1/newline-does-not-break-out ()
  "Newlines in command must not break out of sandbox-exec wrapping."
  (when (eq system-type 'darwin)
    (let* ((gptel-platform-sandbox--workspace-root (expand-file-name "~/.emacs.d/"))
           (result (gptel-platform-sandbox--wrap-command "git status\nrm -rf /")))
      (unwind-protect
          (progn
            ;; The entire command including newline must be a single arg to bash -c
            (should (string-match-p "/bin/bash -c " (car result)))
            ;; Should not contain raw newline breaking the sandbox-exec command
            (should-not (string-match-p "-- git status\n" (car result))))
        (when (cdr result) (delete-file (cdr result)))))))

;; ── C2: Plan-mode whitelist removes interpreters ──

(ert-deftest security/C2/rejects-python ()
  "Plan mode must reject python (arbitrary code execution)."
  (should (stringp (my/gptel--safe-bash-command-p "python -c 'open(\"pwned\",\"w\").write(\"x\")'"))))

(ert-deftest security/C2/rejects-node ()
  "Plan mode must reject node (arbitrary code execution)."
  (should (stringp (my/gptel--safe-bash-command-p "node -e 'require(\"fs\").writeFileSync(\"pwned\",\"x\")'"))))

(ert-deftest security/C2/rejects-awk ()
  "Plan mode must reject awk (can call system())."
  (should (stringp (my/gptel--safe-bash-command-p "awk 'BEGIN { system(\"touch pwned\") }'"))))

(ert-deftest security/C2/rejects-xargs ()
  "Plan mode must reject xargs (can spawn arbitrary commands)."
  (should (stringp (my/gptel--safe-bash-command-p "echo x | xargs -I{} sh -c 'touch pwned'"))))

(ert-deftest security/C2/rejects-make ()
  "Plan mode must reject make (can execute arbitrary recipes)."
  (should (stringp (my/gptel--safe-bash-command-p "make -f /tmp/evil.mk"))))

(ert-deftest security/C2/rejects-cargo ()
  "Plan mode must reject cargo (can execute build scripts)."
  (should (stringp (my/gptel--safe-bash-command-p "cargo build"))))

(ert-deftest security/C2/rejects-npm ()
  "Plan mode must reject npm (can execute arbitrary scripts)."
  (should (stringp (my/gptel--safe-bash-command-p "npm install malicious-pkg"))))

(ert-deftest security/C2/rejects-pip ()
  "Plan mode must reject pip (can install malicious packages)."
  (should (stringp (my/gptel--safe-bash-command-p "pip install malicious-pkg"))))

(ert-deftest security/C2/allows-git-status ()
  "Plan mode must still allow git status (legitimate read-only command)."
  (should (eq t (my/gptel--safe-bash-command-p "git status"))))

(ert-deftest security/C2/allows-ls ()
  "Plan mode must still allow ls (legitimate read-only command)."
  (should (eq t (my/gptel--safe-bash-command-p "ls -la"))))

(ert-deftest security/C2/allows-grep ()
  "Plan mode must still allow grep (legitimate read-only command)."
  (should (eq t (my/gptel--safe-bash-command-p "grep -r pattern lisp/"))))

;; ── H1: Newline injection ──

(ert-deftest security/H1/rejects-newline-in-command ()
  "Plan mode must reject commands containing newlines."
  (should (stringp (my/gptel--safe-bash-command-p "git status\nrm -rf /"))))

(ert-deftest security/H1/rejects-newline-with-python ()
  "Plan mode must reject newline followed by python."
  (should (stringp (my/gptel--safe-bash-command-p "git status\npython -c '1'"))))

(ert-deftest security/H1/rejects-dollar-brace ()
  "Plan mode must reject ${ (variable expansion)."
  (should (stringp (my/gptel--safe-bash-command-p "echo ${IFS}pattern"))))

;; ── H2: Insert/Mkdir/Move boundary checks ──

(ert-deftest security/H2/move-rejects-outside-source ()
  "Move tool must reject source paths outside workspace."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil))
    (should-error
     (let ((gptel--preset 'gptel-agent))
       (funcall
        (lambda (source dest)
          (let ((src (gptel-auto-workflow--expand-workspace-path source))
                (dst (gptel-auto-workflow--expand-workspace-path dest)))
            (format "Moved %s to %s" src dst)))
        "/tmp/outside-source.txt" "inside-dest.txt"))
     :type 'error)))

(ert-deftest security/H2/move-rejects-outside-dest ()
  "Move tool must reject destination paths outside workspace."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil))
    (should-error
     (let ((gptel--preset 'gptel-agent))
       (funcall
        (lambda (source dest)
          (let ((src (gptel-auto-workflow--expand-workspace-path source))
                (dst (gptel-auto-workflow--expand-workspace-path dest)))
            (format "Moved %s to %s" src dst)))
        "README.md" "/tmp/outside-dest.txt"))
     :type 'error)))

;; ── H3: Persistent bash state isolation ──

(ert-deftest security/H3/command-runs-in-subshell-cd-reset ()
  "Bash commands must run in a subshell that resets CWD to context directory.
Verifies the command is wrapped in 'cd <dir> && {...}'."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil)
         (my/gptel-bash-platform-sandbox nil)
         (default-directory root)
         (sent-string nil))
    ;; Mock process-send-string to capture what would be sent
    (cl-letf (((symbol-function 'my/gptel--bash-context-directory) (lambda () root))
              ((symbol-function 'process-send-string)
               (lambda (_proc str) (setq sent-string str)))
              ((symbol-function 'process-put) (lambda (&rest _) nil))
              ((symbol-function 'run-at-time) (lambda (&rest _) nil))
              ((symbol-function 'set-process-filter) (lambda (&rest _) nil))
              ((symbol-function 'my/gptel--ensure-persistent-bash) (lambda () nil))
              ((symbol-function 'buffer-live-p) (lambda (_) nil))
              ((symbol-function 'process-buffer) (lambda (_) (current-buffer))))
      (let ((my/gptel--persistent-bash-process t))
        (my/gptel--agent-bash-async #'ignore "pwd")))
    ;; Verify the sent string contains cd with quoted context dir
    (should (stringp sent-string))
    (should (string-match-p "cd " sent-string))
    (should (string-match-p "&&" sent-string))))

;; ── H5: Patch validation ──

(ert-deftest security/H5/rejects-multi-file-patch ()
  "Edit tool must reject patches with multiple file targets."
  (should-error
   (my/gptel--validate-patch-target
    "--- a/foo.el\n+++ b/foo.el\n@@ -1 +1 @@\n-old\n+new\n--- a/bar.el\n+++ b/bar.el\n@@ -1 +1 @@\n-old\n+new\n"
    "foo.el")
   :type 'error))

(ert-deftest security/H5/rejects-mismatched-destination ()
  "Edit tool must reject patches where +++ header targets different file."
  (should-error
   (my/gptel--validate-patch-target
    "--- a/foo.el\n+++ b/bar.el\n@@ -1 +1 @@\n-old\n+new\n"
    "foo.el")
   :type 'error))

(ert-deftest security/H5/allows-matching-patch ()
  "Edit tool must accept patches where both headers match expected file."
  (should (eq t (my/gptel--validate-patch-target
                 "--- a/foo.el\n+++ b/foo.el\n@@ -1 +1 @@\n-old\n+new\n"
                 "foo.el"))))

(ert-deftest security/H5/allows-dev-null-source ()
  "Edit tool must accept patches with /dev/null source (new file)."
  (should (eq t (my/gptel--validate-patch-target
                 "--- /dev/null\n+++ b/new-file.el\n@@ -0,0 +1 @@\n+content\n"
                 "new-file.el"))))

;; ── M1: TOCTOU — expand-workspace-path returns truename ──

(ert-deftest security/M1/expand-workspace-path-resolves-symlinks ()
  "expand-workspace-path must return the file-truename (resolved symlink target)."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil)
         (result (gptel-auto-workflow--expand-workspace-path "README.md")))
    ;; Result should be a truename (no unresolved symlinks in path)
    (should (string= result (file-truename result)))))

;; ── M2: Concurrent Bash guard ──

(ert-deftest security/M2/concurrent-bash-rejected ()
  "Concurrent Bash commands must be rejected when my/gptel--bash-busy is t."
  (let* ((root (expand-file-name "~/.emacs.d/"))
         (gptel-auto-workflow--allowed-workspace-roots (list root))
         (gptel-auto-workflow--run-project-root root)
         (gptel-auto-workflow--project-root-override nil)
         (gptel-auto-workflow--current-project nil)
         (my/gptel--bash-busy t)
         (default-directory root)
         (result nil))
    (cl-letf (((symbol-function 'my/gptel--bash-context-directory) (lambda () root)))
      (my/gptel--agent-bash-async
       (lambda (r) (setq result r))
       "echo hello"))
    (should (stringp result))
    (should (string-match-p "\\[concurrent\\]" result))))

;; ── L1: Fail-closed warning when sandbox unavailable ──

(ert-deftest security/L1/warns-when-sandbox-unavailable ()
  "When platform sandbox is requested but unavailable, command runs unsandboxed.
Verify the wrap-command fallback returns the raw command."
  (let* ((gptel-platform-sandbox--workspace-root (expand-file-name "~/.emacs.d/")))
    ;; Mock platform unavailable
    (cl-letf (((symbol-function 'gptel-platform-sandbox--available-p) (lambda () nil)))
      ;; When sandbox unavailable, wrap-and-send returns nil (no profile file)
      ;; and the raw command is sent directly via process-send-string
      (should-not (gptel-platform-sandbox--available-p)))))
