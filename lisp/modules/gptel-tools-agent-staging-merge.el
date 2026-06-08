;;; gptel-tools-agent-staging-merge.el --- Staging branch protection - merge & verify -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(require 'cl-lib)
(require 'subr-x)
(require 'gptel-auto-workflow-behavioral-tests nil t)
(defvar gptel-auto-workflow--recovering-stale-staging)
(declare-function magit-get-current-branch "magit-git" ())
(declare-function gptel-auto-workflow--current-run-id "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--make-idempotent-callback "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--non-empty-string-p "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--optimize-branch-integrated-p "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--run-callback-live-p "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--run-behavioral-tests "gptel-auto-workflow-behavioral-tests" (changed-files))
(declare-function gptel-auto-experiment--check-scope "gptel-tools-agent-benchmark")
(declare-function gptel-auto-workflow--check-protected-configs "gptel-tools-agent-benchmark")
(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--categorize-error "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--should-blacklist-provider-p "gptel-tools-agent-error")
(declare-function gptel-auto-workflow--activate-provider-failover "gptel-tools-agent-error")
(declare-function gptel-auto-workflow--current-head-hash "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--empty-commit-output-p "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--git-cmd "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--git-result "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--with-skipped-submodule-sync "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--with-staging-worktree "gptel-tools-agent-experiment-loop")
(declare-function my/gptel--sanitize-for-logging "gptel-tools-agent-git")
(declare-function gptel-auto-workflow--call-process-with-watchdog "gptel-tools-agent-main")
(declare-function gptel-auto-experiment-log-tsv "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--agent-base-preset "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--invoke-staging-completion "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--make-idempotent-staging-completion "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--ensure-merge-source-ref "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--ensure-staging-branch-exists "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--ensure-staging-submodules-ready "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--fix-output-indicates-already-fixed-p "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--fix-review-issues "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--hydrate-staging-submodules "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--prepare-staging-merge-base "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--review-changes "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--review-disproven-undefined-function-blocker-p "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--review-retryable-error-p "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--staging-tests-match-main-baseline-p "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--summarize-staging-verification-output "gptel-tools-agent-staging-baseline")
(declare-function my/gptel--invoke-callback-safely "gptel-tools-agent-subagent")
(declare-function gptel-auto-workflow--assert-main-untouched "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--configured-staging-branch "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--create-staging-worktree "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--delete-staging-worktree "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--require-staging-branch "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--shared-remote "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--sync-staging-from-main "gptel-tools-agent-worktree")

;; Forward declarations for dynamic variables
(defvar gptel-auto-experiment-max-changed-files)
(defvar gptel-auto-experiment-retry-delay)
(defvar gptel-auto-workflow-git-timeout)
(defvar gptel-auto-workflow--auto-promote-staging t
  "Non-nil to automatically promote verified staging to main.")
(defvar gptel-auto-workflow--last-staging-push-output)
(defvar gptel-auto-workflow--review-error-retry-count)
(defvar gptel-auto-workflow--review-max-retries)
(defvar gptel-auto-workflow--review-retry-count)
(defvar gptel-auto-workflow--running)
(defvar gptel-auto-workflow--skip-submodule-sync-env)
(defvar gptel-auto-workflow--staging-push-max-retries)
(defvar gptel-auto-workflow--staging-worktree-dir)

(defconst gptel-auto-workflow--empty-cherry-pick-pattern
  "already applied\\|previous cherry-pick is now empty\\|The previous cherry-pick is now empty"
  "Regex pattern matching git output indicating cherry-pick is already applied.")

(defun gptel-auto-workflow--staging-changed-files ()
  "Return list of changed files in current staging worktree.
Returns nil if not in a staging worktree or if no changes."
  (when-let ((worktree gptel-auto-workflow--staging-worktree-dir))
    (let ((default-directory worktree))
      (let ((output (ignore-errors
                      (gptel-auto-workflow--git-cmd
                       "git diff --name-only HEAD~1 HEAD 2>/dev/null"
                       30))))
        (when (gptel-auto-workflow--non-empty-string-p output)
          (split-string output "\n" t))))))

(defun gptel-auto-workflow--cached-cherry-pick-state ()
  "Return cached git state for cherry-pick detection.
Returns a plist with :cherry-pick-head, :unmerged-files, :worktree-status.
This fetches all state in one batch to avoid repeated git subprocess calls."
  (let ((cherry-pick-head
         (ignore-errors
           (gptel-auto-workflow--git-cmd
            "git rev-parse -q --verify CHERRY_PICK_HEAD 2>/dev/null"
            30)))
        (unmerged-files
         (or (ignore-errors
               (gptel-auto-workflow--git-cmd
                "git diff --name-only --diff-filter=U 2>/dev/null"
                30))
             ""))
        (worktree-status
         (or (ignore-errors
               (gptel-auto-workflow--git-cmd
                "git status --porcelain 2>/dev/null"
                30))
             "")))
    (list :cherry-pick-head cherry-pick-head
          :unmerged-files unmerged-files
          :worktree-status worktree-status)))

(defun gptel-auto-workflow--empty-cherry-pick-state-p (&optional output allow-missing-head cached-state)
  "Return non-nil when worktree reflects an already-applied cherry-pick.
When ALLOW-MISSING-HEAD is non-nil, also treat a clean worktree plus localized
  empty-pick OUTPUT as already applied even if `CHERRY_PICK_HEAD'
  is absent.
When CACHED-STATE is provided, uses it instead of querying git again."
  (let ((cherry-pick-head
         (if (plist-member cached-state :cherry-pick-head)
             (plist-get cached-state :cherry-pick-head)
           (ignore-errors
             (gptel-auto-workflow--git-cmd
              "git rev-parse -q --verify CHERRY_PICK_HEAD 2>/dev/null"
              30))))
        (unmerged-files
         (if (plist-member cached-state :unmerged-files)
             (plist-get cached-state :unmerged-files)
           (or (ignore-errors
                 (gptel-auto-workflow--git-cmd
                  "git diff --name-only --diff-filter=U 2>/dev/null"
                  30))
               "")))
        (worktree-status
         (if (plist-member cached-state :worktree-status)
             (plist-get cached-state :worktree-status)
           (or (ignore-errors
                 (gptel-auto-workflow--git-cmd
                  "git status --porcelain 2>/dev/null"
                  30))
               ""))))
    (and (or (gptel-auto-workflow--non-empty-string-p cherry-pick-head)
             (and allow-missing-head
                  (stringp output)
                  (or (gptel-auto-workflow--empty-commit-output-p output)
                      (string-match-p
                       gptel-auto-workflow--empty-cherry-pick-pattern
                       output))))
         (string-empty-p unmerged-files)
         (string-empty-p worktree-status))))

(defun gptel-auto-workflow--cached-unmerged-files (cached-state)
  "Return unmerged files from CACHED-STATE or query git if not cached."
  (if (plist-member cached-state :unmerged-files)
      (plist-get cached-state :unmerged-files)
    (gptel-auto-workflow--unmerged-files)))

(defun gptel-auto-workflow--unmerged-files ()
  "Return newline-separated unmerged files in the current git worktree."
  (string-trim
   (or (ignore-errors
         (gptel-auto-workflow--git-cmd
          "git diff --name-only --diff-filter=U 2>/dev/null"
          30))
       "")))

(defun gptel-auto-workflow--staging-has-conflict-markers-p ()
  "Return non-nil if any staged file contains unresolved conflict markers."
  (let* ((result (gptel-auto-workflow--git-result "git diff --cached" 30))
         (diff (and result (= 0 (cdr result)) (car result))))
    (and diff (string-match-p "^\\+<<<<<<< " diff))))

(defun gptel-auto-workflow--try-autoresolve-conflicts (unmerged-files optimize-branch merge-message commit-timeout)
  "Try to auto-resolve cherry-pick conflicts in UNMERGED-FILES.
For SAFE file types (.md docs, knowledge pages), use --theirs (the
optimize branch's version is the source of truth for synthesized content).
For .el source code files, require manual review (do not auto-resolve).
Aborts the cherry-pick first, then for SAFE files runs git checkout
--theirs + git add. If all conflicts are SAFE, commits the result.
Returns cons cell (auto-resolved-count . manual-required-count):
  - car = count of files auto-resolved
  - cdr = count of files requiring manual review
Returns nil if the cherry-pick is not aborted cleanly."
  (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
  (let ((auto-resolved-files '())
        (manual-required-files '()))
    (dolist (file (split-string unmerged-files "\n" t))
      (cond
       ((string-match-p "\\.md$" file)
        ;; Knowledge pages / docs: optimize is source of truth
        (gptel-auto-workflow--git-cmd
         (format "git checkout --theirs %s"
                 (shell-quote-argument file)) 30)
        (gptel-auto-workflow--git-cmd "git add" 30)
        (push file auto-resolved-files))
       (t
        ;; Source code: require human review (safe default)
        (push file manual-required-files))))
    (if (and auto-resolved-files (null manual-required-files))
        (let* ((commit-result
                (gptel-auto-workflow--git-result
                 (format "%s git commit -m %s"
                         gptel-auto-workflow--skip-submodule-sync-env
                         (shell-quote-argument
                          (concat merge-message " (auto-resolved .md conflicts)")))
                 commit-timeout)))
          (if (= 0 (cdr commit-result))
              (progn
                (message "[auto-workflow] Auto-resolved %d .md conflict(s) for %s: %s"
                         (length auto-resolved-files)
                         optimize-branch
                         (mapconcat #'identity auto-resolved-files ", "))
                (cons (length auto-resolved-files) 0))
            (progn
              (message "[auto-workflow] Auto-resolve commit failed: %s"
                       (my/gptel--sanitize-for-logging (car commit-result) 160))
              (cons 0 (length manual-required-files)))))
      (cons (length auto-resolved-files) (length manual-required-files)))))

(defun gptel-auto-workflow--merge-to-staging (optimize-branch)
  "Merge OPTIMIZE-BRANCH to staging using cherry-pick.
Cherry-pick the tip commit of OPTIMIZE-BRANCH onto staging.
Returns t when the branch adds changes, `:already-integrated' when staging
already contains the candidate patch, and nil on failure.
Uses the staging worktree instead of switching branches in the root repo."
  (let* ((staging (gptel-auto-workflow--configured-staging-branch))
         (optimize-ref (gptel-auto-workflow--ensure-merge-source-ref optimize-branch))
         (merge-message (format "Merge %s for verification" optimize-branch))
         (commit-timeout (max 300 (or gptel-auto-workflow-git-timeout 300))))
    (if (not (gptel-auto-workflow--ensure-staging-branch-exists))
        nil
      (if (not optimize-ref)
          (progn
            (message "[auto-workflow] Missing merge source branch: %s" optimize-branch)
            nil)
         ;; Sync staging with main first so test fixes are included
         ;; Must run from repo root — daemon's default-directory may be a worktree
         (let* ((default-directory (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                                            (gptel-auto-workflow--worktree-base-root))
                                       default-directory))
                (sync-result (gptel-auto-workflow--git-result
                              (format "git merge %s/main --no-ff -m %s" "origin" (shell-quote-argument "Sync staging with main before experiment"))
                              180)))
           (if (= 0 (cdr sync-result))
               (message "[auto-workflow] Synced staging with main before cherry-pick")
             (message "[auto-workflow] Staging sync with main skipped: %s"
                      (my/gptel--sanitize-for-logging (car sync-result) 160))))
         (message "[auto-workflow] Cherry-picking %s to %s" optimize-branch staging)
         (gptel-auto-workflow--with-staging-worktree
          (lambda ()
            (let ((reset-target staging)
                  (worktree gptel-auto-workflow--staging-worktree-dir)
                  (git-state nil))
              (if (not (and (gptel-auto-workflow--prepare-staging-merge-base reset-target)
                            (gptel-auto-workflow--ensure-staging-submodules-ready worktree)))
                  nil
               (let* ((commit-hash-raw (car-safe
                                        (gptel-auto-workflow--git-result
                                         (format "git rev-parse %s"
                                                 (shell-quote-argument optimize-ref))
                                         60)))
                      (commit-hash (and (stringp commit-hash-raw)
                                        (string-match-p
                                         (rx (repeat 40 (any "0-9a-f")))
                                         commit-hash-raw)
                                        (string-trim commit-hash-raw)))
                       (is-merge-commit
                        (when commit-hash
                          (= 0 (cdr (gptel-auto-workflow--git-result
                                     (format "git rev-parse --verify %s^2" (shell-quote-argument commit-hash))
                                     60)))))
                       (cherry-result
                        (when commit-hash
                          (gptel-auto-workflow--git-result
                           (format "git cherry-pick --no-commit %s %s"
                                   (if is-merge-commit "-m 1" "")
                                   (shell-quote-argument commit-hash))
                           180)))
                      (cherry-output (or (car-safe cherry-result) "")))
                 (cond
                  ((null cherry-result)
                   (message "[auto-workflow] Failed to resolve commit hash for %s"
                            optimize-branch)
                   nil)
                   ((= 0 (cdr cherry-result))
                    (let ((commit-result
                           (gptel-auto-workflow--git-result
                            (format "%s git commit -m %s"
                                    gptel-auto-workflow--skip-submodule-sync-env
                                    (shell-quote-argument merge-message))
                            commit-timeout)))
                      (when (gptel-auto-workflow--staging-has-conflict-markers-p)
                        (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
                        (message "[auto-workflow] Cherry-pick produced conflict markers; refusing commit")
                        (setq commit-result (cons "Conflict markers detected" 1)))
                      (cond
                      ((= 0 (cdr commit-result))
                       t)
                      ((progn
                         (unless git-state
                           (setq git-state (gptel-auto-workflow--cached-cherry-pick-state)))
                         (gptel-auto-workflow--empty-cherry-pick-state-p (car commit-result) t git-state))
                       (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --skip" 60))
                       (message "[auto-workflow] Cherry-pick empty after apply (already in staging)")
                       :already-integrated)
                      (t
                       (message "[auto-workflow] Commit failed after cherry-pick: %s"
                                (my/gptel--sanitize-for-logging (car commit-result) 160))
                       nil))))
                  ((or (progn
                         (unless git-state
                           (setq git-state (gptel-auto-workflow--cached-cherry-pick-state)))
                         (gptel-auto-workflow--empty-cherry-pick-state-p cherry-output t git-state))
                       (string-match-p gptel-auto-workflow--empty-cherry-pick-pattern
                                       cherry-output))
                   (message "[auto-workflow] Cherry-pick empty (already in staging)")
                   (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
                   :already-integrated)
                   (t
                    (let ((unmerged-files
                           (progn
                             (unless git-state
                               (setq git-state (gptel-auto-workflow--cached-cherry-pick-state)))
                             (gptel-auto-workflow--cached-unmerged-files git-state))))
                      (if (gptel-auto-workflow--non-empty-string-p unmerged-files)
                          (let ((auto-resolved (gptel-auto-workflow--try-autoresolve-conflicts
                                                unmerged-files optimize-branch
                                                merge-message commit-timeout)))
                            (if (and (car-safe auto-resolved) (null (cdr-safe auto-resolved)))
                                t
                              (if (cdr-safe auto-resolved)
                                  (progn
                                    (message "[auto-workflow] Cherry-pick conflicted; %d auto-resolved, %d need manual review: %s"
                                             (car auto-resolved) (cdr auto-resolved)
                                             (my/gptel--sanitize-for-logging unmerged-files 160))
                                    (gptel-auto-workflow--prepare-staging-merge-base reset-target)
                                    nil)
                                (progn
                                  (message "[auto-workflow] Cherry-pick conflicted; refusing merge fallback. Conflicted files: %s"
                                           (my/gptel--sanitize-for-logging unmerged-files 160))
                                  (gptel-auto-workflow--prepare-staging-merge-base reset-target)
                                  nil))))
                        (message "[auto-workflow] Cherry-pick failed, falling back to merge: %s"
                                 (my/gptel--sanitize-for-logging cherry-output 160))
                        (if (not (and (gptel-auto-workflow--prepare-staging-merge-base reset-target)
                                      (gptel-auto-workflow--ensure-staging-submodules-ready worktree)))
                            nil
                         (let* ((merge-result
                                 (gptel-auto-workflow--git-result
                                  (format "git merge -X theirs %s --no-ff -m %s"
                                          (shell-quote-argument optimize-ref)
                                          (shell-quote-argument merge-message))
                                  180))
                                (merge-output (or (car-safe merge-result) "")))
                           (cond
                            ((= 0 (cdr merge-result))
                             (not (gptel-auto-workflow--staging-has-conflict-markers-p)))
                            ((string-match-p "Already up[ -]to[- ]date" merge-output)
                             :already-integrated)
                             (t
                              (ignore-errors (gptel-auto-workflow--git-cmd "git merge --abort" 60))
                              (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
                              (gptel-auto-workflow--prepare-staging-merge-base reset-target)
                              (message "[auto-workflow] Merge also failed: %s"
                                       (my/gptel--sanitize-for-logging merge-output 160))
                             nil)))))))))))))))))



(defun gptel-auto-workflow--check-el-syntax (directory output-buffer)
  "Check syntax of changed .el files in DIRECTORY.
Only validates files modified vs HEAD to avoid failing on pre-existing
issues in untouched files. Writes errors to OUTPUT-BUFFER.
Returns t if all changed files pass syntax check, nil otherwise."
  (if (or (null directory) (null output-buffer))
      (progn
        (message "[auto-workflow] check-el-syntax: nil argument")
        nil)
    (let* ((default-directory directory)
           (errors nil)
           (changed-files (ignore-errors
                            (split-string
                             (shell-command-to-string
                              "git diff --name-only HEAD~1 HEAD 2>/dev/null")
                             "\n" t)))
           (files (seq-filter (lambda (f)
                                (and (string-suffix-p ".el" f)
                                     (not (string-suffix-p "-autoloads.el" f))
                                     (file-readable-p (expand-file-name f directory))))
                              changed-files)))
      (when (null changed-files)
        ;; No changed files detected — skip syntax check (nothing to verify)
        (message "[auto-workflow] check-el-syntax: no changed files detected, skipping"))
      (dolist (file files (null errors))
        (let ((full-path (expand-file-name file directory)))
          (condition-case err
              (with-temp-buffer
                (insert-file-contents full-path)
                ;; Parse with `emacs-lisp-mode' so syntax-propertize handles
                ;; reader forms correctly, but suppress mode hooks so staging
                ;; verification cannot trip unrelated editor setup.
                (delay-mode-hooks
                  (emacs-lisp-mode))
                (goto-char (point-min))
                (while (not (eobp))
                  (forward-sexp)))
            (error
             (let ((msg (format "SYNTAX ERROR: %s: %s"
                                file
                                (error-message-string err))))
               (push msg errors)
               (when (buffer-live-p output-buffer)
                 (with-current-buffer output-buffer
                   (insert msg "\n")))))))))))

(defun gptel-auto-workflow--verify-staging ()
  "Run verification in the staging worktree.
Returns (success-p . output)."
  (let* ((worktree gptel-auto-workflow--staging-worktree-dir)
         (test-script (and worktree (expand-file-name "scripts/run-tests.sh" worktree)))
         (verify-script (and worktree (expand-file-name "scripts/verify-nucleus.sh" worktree)))
         (output-buffer (generate-new-buffer "*staging-verify*"))
         result)
     (if (not (and worktree (file-exists-p worktree)))
         (progn
           (message "[auto-workflow] Staging worktree not found")
           (cons nil "Staging worktree not found"))
       ;; Merge latest main so staging tests include recent fixes
       (message "[auto-workflow] About to merge main into staging worktree...")
       (let ((default-directory worktree))
         (let ((main-merge (gptel-auto-workflow--git-result
                            (format "git merge -X theirs %s --no-ff -m %s"
                                    (shell-quote-argument "main")
                                    (shell-quote-argument "Sync main into staging for verification"))
                            180)))
           (if (= 0 (cdr main-merge))
               (message "[auto-workflow] Merged main into staging worktree SUCCESS")
             (message "[auto-workflow] Main merge into staging failed (non-fatal)")
             (ignore-errors (gptel-auto-workflow--git-cmd "git merge --abort" 60)))))
        (message "[auto-workflow] Verifying staging...")
        (let* ((default-directory worktree)
              (syntax-pass (gptel-auto-workflow--check-el-syntax worktree output-buffer))
              (submodules (when syntax-pass (gptel-auto-workflow--hydrate-staging-submodules worktree)))
              (submodule-pass (and syntax-pass (= 0 (cdr submodules))))
              (submodule-note
               (and syntax-pass
                    (not submodule-pass)
                    (let ((note (car-safe submodules)))
                      (if (gptel-auto-workflow--non-empty-string-p note)
                          note
                        "Staging submodule hydration failed"))))
              (_ (when submodule-note
                   (with-current-buffer output-buffer
                     (insert submodule-note "\n"))))
              (_ (when submodule-pass
                   (message "[auto-workflow] Running unit tests in staging (may block ~60s)...")))
               (test-result (when (and submodule-pass test-script (file-exists-p test-script))
                              (gptel-auto-workflow--call-process-with-watchdog
                               "bash" nil output-buffer nil test-script "unit")))
               (_ (when test-result
                    (message "[auto-workflow] Unit tests completed (exit=%d)" test-result)))
               (verify-result (when (and submodule-pass verify-script (file-exists-p verify-script))
                               (let ((process-environment
                                      (cons "VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1"
                                            process-environment)))
                                 (gptel-auto-workflow--call-process-with-watchdog
                                  "bash" nil output-buffer nil verify-script))))
              ;; Run behavioral smoke tests for changed files
              (behavioral-result (when submodule-pass
                                   (let ((changed-files (gptel-auto-workflow--staging-changed-files)))
                                     (when (and changed-files
                                                (featurep 'gptel-auto-workflow-behavioral-tests))
                                       (gptel-auto-workflow--run-behavioral-tests changed-files)))))
              (behavioral-pass (or (null behavioral-result)
                                   (car behavioral-result)))
              (_ (when behavioral-result
                   (with-current-buffer output-buffer
                     (goto-char (point-max))
                     (unless (bolp) (insert "\n"))
                     (insert (cdr behavioral-result) "\n"))))
              (test-pass (and submodule-pass
                              (or (not (and test-script (file-exists-p test-script)))
                                  (eq test-result 0))))
              (verify-pass (and submodule-pass
                                (or (not (and verify-script (file-exists-p verify-script)))
                                    (eq verify-result 0))))
              (checks-pass (and test-pass verify-pass behavioral-pass))
             (output (with-current-buffer output-buffer (buffer-string))))
        (when (and submodule-pass
                   (not checks-pass))
          (let ((baseline-check
                 (gptel-auto-workflow--staging-tests-match-main-baseline-p output)))
            (setq checks-pass (car-safe baseline-check))
            (with-current-buffer output-buffer
              (goto-char (point-max))
              (unless (bolp)
                (insert "\n"))
              (insert "\n"
                      (let ((note (cdr-safe baseline-check)))
                        (if (gptel-auto-workflow--non-empty-string-p note)
                            note
                          "Staging verification failed against main baseline"))
                      "\n"))
            (setq output (with-current-buffer output-buffer (buffer-string)))))
        (kill-buffer output-buffer)
        (setq result (and syntax-pass submodule-pass checks-pass))
        (message "[auto-workflow] Staging verification: %s"
                 (if result
                     "PASS"
                   (format "FAIL (%s)"
                           (gptel-auto-workflow--summarize-staging-verification-output
                            output))))
        (cons result output)))))



(defun gptel-auto-workflow--parse-remote-head (branch output)
  "Return BRANCH head parsed from git ls-remote OUTPUT, ignoring SSH noise."
  (let ((pattern (format "^\\([0-9a-f]\\{40\\}\\)\trefs/heads/%s$"
                         (regexp-quote branch)))
        head)
    (dolist (line (split-string (or output "") "\n" t) head)
      (when (and (null head)
                 (string-match pattern line))
        (setq head (match-string 1 line))))))

(defun gptel-auto-workflow--remote-branch-head (remote branch &optional timeout)
  "Return BRANCH head on REMOTE, or nil when the branch is absent."
  (let* ((branch-q (shell-quote-argument branch))
         (remote-result
          (gptel-auto-workflow--git-result
           (format "git ls-remote --exit-code --heads %s %s" remote branch-q)
           (or timeout 60))))
    (and (consp remote-result)
         (= 0 (cdr-safe remote-result))
         (gptel-auto-workflow--parse-remote-head branch (car-safe remote-result)))))

(defun gptel-auto-workflow--push-branch-with-lease (branch action &optional timeout)
  "Push BRANCH to the shared remote.
Use `--force-with-lease' when branch already exists.
ACTION is a short description used in failure messages."
  (let* ((remote (gptel-auto-workflow--shared-remote))
         (branch-q (shell-quote-argument branch))
         (push-timeout (or timeout 180))
         (remote-head
          (gptel-auto-workflow--remote-branch-head remote branch 60))
         (local-head
          (gptel-auto-workflow--current-head-hash))
         (push-command
          (if remote-head
              (format "git push %s %s %s"
                      (shell-quote-argument
                       (format "--force-with-lease=%s:%s"
                               branch
                               remote-head))
                      remote
                      branch-q)
            (format "git push %s %s" remote branch-q)))
         (push-result
          (gptel-auto-workflow--with-skipped-submodule-sync
           (lambda ()
             (gptel-auto-workflow--git-result
              push-command
              push-timeout))))
         (push-output (car push-result)))
    (cond
     ((and push-result (= 0 (cdr push-result)))
      t)
     ((and local-head
           (equal local-head
                  (gptel-auto-workflow--remote-branch-head remote branch 60)))
      (message "[auto-workflow] %s reached %s despite the initial push error"
               action remote)
      t)
     ((and (< push-timeout 360)
           (stringp push-output)
           (string-match-p "Command timed out after" push-output))
      (message "[auto-workflow] %s timed out after %ds; retrying once with %ds"
               action push-timeout 360)
      (gptel-auto-workflow--push-branch-with-lease branch action 360))
     (t
      (message "[auto-workflow] %s failed: %s"
               action
               (my/gptel--sanitize-for-logging push-output 160))
       nil))))
 
(defun gptel-auto-workflow--promote-staging-to-main ()
  "Merge staging into main and push main to origin.
Returns t on success, nil on failure.  Only runs when
`gptel-auto-workflow--auto-promote-staging' is non-nil.

SAFETY: Never force-pushes main.  First fast-forwards local main to
origin/main to integrate any external (e.g. human-pushed) commits,
then merges staging, then does a regular fast-forward push.  If
origin/main advanced since the daemon last synced, the external
commits are preserved."
  (when gptel-auto-workflow--auto-promote-staging
    (let* ((staging (gptel-auto-workflow--require-staging-branch))
           (remote (gptel-auto-workflow--shared-remote))
           (default-directory (or (gptel-auto-workflow--project-root)
                                  default-directory)))
      ;; Self-heal: clear stale git state before any operation
      (gptel-auto-workflow--git-result
       "git merge --abort 2>/dev/null; git checkout HEAD -- mementum/ assistant/ 2>/dev/null; true" 30)
      (message "[auto-workflow] Auto-promoting staging to main...")
      (condition-case err
          (progn
            ;; Fetch latest to get any external commits on main
            (gptel-auto-workflow--git-result
             (format "git fetch %s main" remote) 180)
            ;; Fast-forward local main to origin/main first, so external
            ;; (e.g. human-pushed) commits are never dropped.
             (let ((ff-remote-result
                    (gptel-auto-workflow--git-result
                     (format "git merge --ff-only %s/main" remote) 60)))
               (unless (= 0 (cdr ff-remote-result))
                 ;; Fast-forward failed — local may have diverged from origin.
                 ;; Try rebase to reconcile before failing permanently.
                 (message "[auto-workflow] Cannot ff to origin/main: %s — attempting rebase"
                          (car ff-remote-result))
                 (let ((rebase-result
                        (gptel-auto-workflow--git-result
                         (format "git pull --rebase %s main" remote) 120)))
                   (if (= 0 (cdr rebase-result))
                       (message "[auto-workflow] Rebased onto origin/main, continuing auto-promote")
                     (message "[auto-workflow] ✗ Auto-promote error: Auto-promote blocked: %s"
                              (car rebase-result))
                     (error "Auto-promote blocked: local main must match origin/main before merging staging")))))
            ;; Merge staging into main (main is now at origin/main).
            ;; Daemon-generated artifacts (DIRECTIVE.md, comparison reports, etc.)
            ;; can dirty the worktree and block git merge.  Stash them first.
            (gptel-auto-workflow--git-result
             "git stash push -m 'auto-promote: dirty artifacts' -- assistant/ mementum/ 2>/dev/null || true"
             30)
            (let ((merge-result
                   (gptel-auto-workflow--git-result
                    (format "git merge --ff-only %s" (shell-quote-argument staging))
                    60)))
              (if (/= 0 (cdr merge-result))
                  (let ((no-ff-result
                         (gptel-auto-workflow--git-result
                          (format "git merge --no-edit %s" (shell-quote-argument staging))
                          60)))
                    (if (/= 0 (cdr no-ff-result))
                        (progn
                          (message "[auto-workflow] ✗ Auto-promote merge failed: %s"
                                   (car no-ff-result))
                          nil)
                      t))
                t))
            ;; Restore daemon-generated artifacts after merge
            (gptel-auto-workflow--git-result
             "git stash pop 2>/dev/null || (git checkout -- assistant/ mementum/ 2>/dev/null; true)" 30)
            ;; Push main to origin — regular push, never force.
            ;; Because we fast-forwarded to origin/main above, this is
            ;; always a clean fast-forward.
            (let ((push-result (gptel-auto-workflow--git-result
                                (format "git push %s main" remote) 180)))
              (if (and push-result (= 0 (cdr push-result)))
                  (progn
                    (message "[auto-workflow] ✓ Staging promoted to main")
                    t)
                (message "[auto-workflow] ✗ Push failed: %s" (car push-result))
                nil)))
        (error
         (message "[auto-workflow] ✗ Auto-promote error: %s" (error-message-string err))
         nil)))))

(defun gptel-auto-workflow--push-staging ()
   "Push staging branch to the shared remote after successful verification.
Unlike per-experiment optimize branches, staging is a shared integration branch,
so this push must not rewrite remote history. Use --force-with-lease so that
concurrent pipeline pushes to staging don't cause non-fast-forward rejection."
  (let ((staging (gptel-auto-workflow--require-staging-branch))
        (remote (gptel-auto-workflow--shared-remote)))
    (message "[auto-workflow] Pushing staging to %s" remote)
    (when staging
      (gptel-auto-workflow--with-staging-worktree
       (lambda ()
         (setq gptel-auto-workflow--last-staging-push-output nil)
          ;; Fetch remote staging first, then push. Retry logic handles races.
          (gptel-auto-workflow--git-result
           (format "git fetch %s %s" remote (shell-quote-argument staging)) 30)
          (let* ((push-result
                  (gptel-auto-workflow--with-skipped-submodule-sync
                   (lambda ()
                     (gptel-auto-workflow--git-result
                      (format "git push %s %s"
                              remote
                              (shell-quote-argument staging))
                      180)))))
           (setq gptel-auto-workflow--last-staging-push-output (car push-result))
           (if (and push-result (= 0 (cdr push-result)))
               t
             (message "[auto-workflow] Push staging failed: %s"
                       (my/gptel--sanitize-for-logging (car push-result) 300))
             nil)))))))

(defvar gptel-auto-workflow--last-staging-push-output nil
  "Raw output from the most recent staging push attempt.")

(defun gptel-auto-workflow--staging-push-remote-advanced-p (output)
  "Return non-nil when OUTPUT shows the shared remote staging branch advanced."
  (string-match-p
   (rx (or "fetch first"
           "non-fast-forward"
           "failed to push some refs"
           "remote contains work that you do not have locally"
           "stale"           ; --force-with-lease rejection: stale reference
           "[rejected]"))     ; generic push rejection
   (or output "")))

(defun gptel-auto-workflow--retry-staging-publish-after-remote-advance (optimize-branch &optional retries-remaining)
  "Refresh shared staging and retry publishing OPTIMIZE-BRANCH.
RETRIES-REMAINING counts remaining refresh-and-retry attempts after an
initial remote-advance rejection. Returns a plist with keys `:success',
`:reason', and `:output'."
  (let* ((remote (gptel-auto-workflow--shared-remote))
         (remaining (or retries-remaining
                        gptel-auto-workflow--staging-push-max-retries))
         (max-retries (max 1 gptel-auto-workflow--staging-push-max-retries))
         (attempt (1+ (- max-retries remaining))))
    (message "[auto-workflow] %s/%s advanced; refreshing staging and retrying publish (%d/%d)"
             remote
             (gptel-auto-workflow--require-staging-branch)
             attempt max-retries)
    (setq gptel-auto-workflow--last-staging-push-output nil)
    (cond
     ((not (gptel-auto-workflow--sync-staging-from-main))
      (if (> remaining 1)
          (progn
            (message "[auto-workflow] Failed to sync refreshed staging; retrying publish refresh (%d/%d)"
                     attempt max-retries)
            (gptel-auto-workflow--retry-staging-publish-after-remote-advance
             optimize-branch
             (1- remaining)))
        (list :success nil
              :reason 'staging-sync-failed
              :output (format "Failed to sync staging from updated %s/%s"
                              remote
                              (gptel-auto-workflow--require-staging-branch)))))
     ((not (gptel-auto-workflow--merge-to-staging optimize-branch))
      (list :success nil
            :reason 'staging-merge-failed
            :output (format "Failed to merge %s onto refreshed staging" optimize-branch)))
     (t
      (let ((worktree (or gptel-auto-workflow--staging-worktree-dir
                          (gptel-auto-workflow--create-staging-worktree))))
        (cond
         ((not worktree)
          (list :success nil
                :reason 'staging-worktree-failed
                :output "Failed to create staging worktree"))
         (t
          (let* ((verification (gptel-auto-workflow--verify-staging))
                 (tests-passed (car verification))
                 (output (or (cdr verification) "")))
            (if (not tests-passed)
                (list :success nil
                      :reason 'staging-verification-failed
                      :output output)
              (if (gptel-auto-workflow--push-staging)
                  (list :success t :output output)
                (let ((push-output
                       (or gptel-auto-workflow--last-staging-push-output
                           output
                           "")))
                  (if (and (> remaining 1)
                           (gptel-auto-workflow--staging-push-remote-advanced-p
                            push-output))
                      (gptel-auto-workflow--retry-staging-publish-after-remote-advance
                       optimize-branch
                       (1- remaining))
                    (list :success nil
                          :reason 'staging-push-failed
                          :output push-output)))))))))))))

(defun gptel-auto-workflow--log-staging-step-failure (reason optimize-branch output)
  "Log staging step failure REASON for OPTIMIZE-BRANCH with OUTPUT."
  (pcase reason
    ('staging-worktree-failed
     (message "[auto-workflow] ✗ Failed to create staging worktree")
     (gptel-auto-experiment-log-tsv
      (gptel-auto-workflow--current-run-id)
      (list :target "staging-worktree"
            :id 0
            :hypothesis "Staging worktree"
            :score-before 0
            :score-after 0
            :kept nil
            :duration 0
            :grader-quality 0
            :grader-reason "staging-worktree-failed"
            :comparator-reason "Failed to create staging worktree"
            :analyzer-patterns ""
            :agent-output "")))
    ('staging-verification-failed
     (message "[auto-workflow] ✗ Staging verification FAILED: %s"
              (gptel-auto-workflow--summarize-staging-verification-output output))
     (gptel-auto-experiment-log-tsv
      (gptel-auto-workflow--current-run-id)
      (list :target "staging-verification"
            :id 0
            :hypothesis "Staging verification"
            :score-before 0
            :score-after 0
            :kept nil
            :duration 0
            :grader-quality 0
            :grader-reason "staging-verification-failed"
            :comparator-reason (truncate-string-to-width (or output "") 200)
            :analyzer-patterns ""
            :agent-output (or output ""))))
    ('staging-merge-failed
     (message "[auto-workflow] ✗ Merge to staging failed, aborting")
     (gptel-auto-experiment-log-tsv
      (gptel-auto-workflow--current-run-id)
      (list :target "staging-merge"
            :id 0
            :hypothesis "Staging merge"
            :score-before 0
            :score-after 0
            :kept nil
            :duration 0
            :grader-quality 0
            :grader-reason "staging-merge-failed"
            :comparator-reason
            (or output (format "Failed to merge %s to staging" optimize-branch))
            :analyzer-patterns ""
            :agent-output "")))
    ((or 'staging-push-failed 'staging-sync-failed)
     (message "[auto-workflow] ✗ Staging push FAILED")
     (gptel-auto-experiment-log-tsv
      (gptel-auto-workflow--current-run-id)
      (list :target "staging-push"
            :id 0
            :hypothesis "Staging push"
            :score-before 0
            :score-after 0
            :kept nil
            :duration 0
            :grader-quality 0
            :grader-reason
            (pcase reason
              ('staging-sync-failed "staging-sync-failed")
              (_ "staging-push-failed"))
            :comparator-reason
            (if (string-empty-p (string-trim (or output "")))
                "Failed to push staging"
              (truncate-string-to-width output 200))
            :analyzer-patterns ""
            :agent-output (or output ""))))))


(defun gptel-auto-workflow--current-staging-head ()
  "Return the current commit at the staging branch head, or nil if unavailable."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root))
    (when (and proj-root (gptel-auto-workflow--ensure-staging-branch-exists))
      (let* ((staging-q (shell-quote-argument
                         (gptel-auto-workflow--configured-staging-branch)))
             (head-result
              (gptel-auto-workflow--git-result
               (format "git rev-parse --verify %s" staging-q)
               60)))
        (when (= 0 (cdr head-result))
          (string-trim (car head-result)))))))

(defun gptel-auto-workflow--restore-staging-ref (base-ref)
  "Restore the staging branch and worktree to BASE-REF.
Returns non-nil on success."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (base-q (shell-quote-argument base-ref)))
    (when (and base-ref (gptel-auto-workflow--ensure-staging-branch-exists))
      (let ((staging (gptel-auto-workflow--configured-staging-branch)))
        (gptel-auto-workflow--delete-staging-worktree)
        (let ((worktree (gptel-auto-workflow--create-staging-worktree)))
          (when worktree
            (let ((default-directory worktree))
              (let* ((staging-q (shell-quote-argument staging))
                     (results (list
                               (gptel-auto-workflow--git-result
                                (format "git checkout %s" staging-q)
                                60)
                               (gptel-auto-workflow--git-result
                                (format "git reset --hard %s" base-q)
                                180)))
                     (failed (cl-find-if (lambda (item) (/= 0 (cdr item))) results)))
                (if failed
                    (progn
                      (message "[auto-workflow] Failed to restore staging baseline: %s"
                               (my/gptel--sanitize-for-logging (car failed) 160))
                      nil)
                  t)))))))))

(defun gptel-auto-workflow--reset-staging-after-failure (&optional base-ref)
  "Restore staging after a failed staging step.
When BASE-REF is non-nil, prefer restoring the last known-good staging state.
Falls back to rebuilding staging from the workflow base if BASE-REF cannot be
restored."
  (cond
   ((and base-ref
         (gptel-auto-workflow--restore-staging-ref base-ref))
    (message "[auto-workflow] Restored staging to last good baseline after failure")
    t)
   ((gptel-auto-workflow--sync-staging-from-main)
    (if base-ref
        (message "[auto-workflow] Fell back to workflow base after staging restore failure")
      (message "[auto-workflow] Reset staging to workflow base after failure"))
    t)
   (t
    (message "[auto-workflow] Failed to reset staging after failure")
    nil)))

(defun gptel-auto-workflow--staging-flow (optimize-branch &optional completion-callback)
  "Run staging verification flow for OPTIMIZE-BRANCH.

Flow:
1. Review changes (if gptel-auto-workflow-require-review)
2. If review blocked: try to fix (up to N retries)
3. Merge OPTIMIZE-BRANCH to staging
4. Create staging worktree (never touches project root)
5. Run tests on staging
6. If pass: push staging to the shared remote (human reviews later)
7. If fail: log failure to TSV, then restore staging to the last good baseline

ASSUMPTION: OPTIMIZE-BRANCH has been pushed to the shared remote.
BEHAVIOR: Never modifies project root - all verification in worktree.
EDGE CASE: Handles merge conflicts with auto-resolution (theirs).
TEST: Verify main is never touched by auto-workflow.
SAFETY: Asserts main branch is not current before any operation.

NOTE: Human must manually merge staging to main after review."
  (let ((completion-callback
         (when completion-callback
           (gptel-auto-workflow--make-idempotent-staging-completion completion-callback)))
         ;; Auto-detect: staging flow is safe on main because it only
         ;; cherry-picks experiment branches to staging.  Setting this
         ;; flag bypasses assert-main-untouched, which would otherwise
         ;; block ALL experiments when running from the main worktree.
         (gptel-auto-workflow--recovering-stale-staging
          (or gptel-auto-workflow--recovering-stale-staging
              (string= (ignore-errors (magit-get-current-branch)) "main"))))
    (gptel-auto-workflow--assert-main-untouched)
    (setq gptel-auto-workflow--review-retry-count 0)
    (setq gptel-auto-workflow--review-error-retry-count 0)
    (message "[auto-workflow] Starting staging flow for %s" optimize-branch)
    (let ((skip-review (gptel-auto-workflow--optimize-branch-integrated-p optimize-branch)))
      (if skip-review
          (condition-case err
              (progn
                (message "[auto-workflow] Candidate already present in staging or main; skipping review for %s"
                         optimize-branch)
                (gptel-auto-workflow--staging-flow-after-review
                 optimize-branch
                 '(t . "Review skipped: branch already integrated")
                 completion-callback))
            (error
             (message "[auto-workflow] Staging flow callback failed for %s: %s"
                      optimize-branch
                      (my/gptel--sanitize-for-logging
                       (error-message-string err) 200))
             (ignore-errors (gptel-auto-workflow--delete-staging-worktree))
             (when completion-callback
               (my/gptel--invoke-callback-safely completion-callback nil))))
        (gptel-auto-workflow--review-changes
         optimize-branch
         (lambda (review-result)
           (condition-case err
               (gptel-auto-workflow--staging-flow-after-review
                optimize-branch
                review-result
                completion-callback)
             (error
              (message "[auto-workflow] Staging flow callback failed for %s: %s"
                       optimize-branch
                       (my/gptel--sanitize-for-logging
                        (error-message-string err) 200))
              (ignore-errors (gptel-auto-workflow--delete-staging-worktree))
              (when completion-callback
                (my/gptel--invoke-callback-safely completion-callback nil))))))))))


(defun gptel-auto-workflow--staging-flow-after-review (optimize-branch review-result &optional completion-callback)
  "Continue staging flow after review for OPTIMIZE-BRANCH.
REVIEW-RESULT is (approved-p . review-output).
When COMPLETION-CALLBACK is non-nil, call it with non-nil on success."
  (unless (consp review-result)
    (message "[auto-workflow] Invalid review result type %S for %s, treating as blocked"
             (type-of review-result) optimize-branch)
    (setq review-result (cons nil (format "Invalid review result: %S" review-result))))
  (let* ((raw-approved (car review-result))
         (review-output (cdr review-result))
         (disproven-undefined-blocker
          (and (not raw-approved)
               (gptel-auto-workflow--review-disproven-undefined-function-blocker-p
                optimize-branch review-output)))
         (approved (or raw-approved disproven-undefined-blocker))
         (review-error-category
          (and (not approved)
               (stringp review-output)
               (car-safe
                (gptel-auto-experiment--categorize-error review-output))))
         (review-error (and (not approved)
                            (gptel-auto-workflow--review-retryable-error-p review-output)))
         (run-id (and (or gptel-auto-workflow--running
                          (bound-and-true-p gptel-auto-workflow--cron-job-running))
                      (boundp 'gptel-auto-workflow--run-id)
                      gptel-auto-workflow--run-id))
         (finish (gptel-auto-workflow--make-idempotent-callback
                  (lambda (success &optional reason)
                    (gptel-auto-workflow--invoke-staging-completion
                     completion-callback success reason)))))
    (when disproven-undefined-blocker
      (message "[auto-workflow] Reviewer undefined-function blocker disproven locally for %s; continuing"
               disproven-undefined-blocker))
    (cond
     (review-error
      (if (< gptel-auto-workflow--review-error-retry-count
             gptel-auto-workflow--review-max-retries)
             (progn
              (when (memq review-error-category '(:api-rate-limit :api-error :timeout))
                (when-let ((reviewer-preset
                            (gptel-auto-workflow--agent-base-preset "reviewer")))
                  (gptel-auto-workflow--activate-provider-failover
                   "reviewer" reviewer-preset review-output
                   (not (gptel-auto-experiment--should-blacklist-provider-p review-output)))))
            (cl-incf gptel-auto-workflow--review-error-retry-count)
            (message "[auto-workflow] Review failed transiently, retrying review (%d/%d)..."
                     gptel-auto-workflow--review-error-retry-count
                     gptel-auto-workflow--review-max-retries)
            (run-with-timer
             gptel-auto-experiment-retry-delay nil
             (lambda ()
               (if (gptel-auto-workflow--run-callback-live-p run-id)
                   (gptel-auto-workflow--review-changes
                    optimize-branch
                    (lambda (retry-review-result)
                      (gptel-auto-workflow--staging-flow-after-review
                       optimize-branch
                       retry-review-result
                       completion-callback)))
                 (message "[auto-workflow] Skipping stale review retry for %s; run %s is no longer active"
                          optimize-branch run-id)))))
        (message "[auto-workflow] ✗ Review failed (max retries): %s"
                 (my/gptel--sanitize-for-logging review-output 200))
        (gptel-auto-experiment-log-tsv
         (gptel-auto-workflow--current-run-id)
         (list :target "staging-review"
               :id 0
               :hypothesis "Staging review"
               :score-before 0
               :score-after 0
               :kept nil
               :duration 0
               :grader-quality 0
               :grader-reason "review-failed-max-retries"
               :comparator-reason (truncate-string-to-width review-output 200)
               :analyzer-patterns ""
                :agent-output review-output))
         (funcall finish nil "review-failed-max-retries")))
      ((not approved)
      (if (< gptel-auto-workflow--review-retry-count
             gptel-auto-workflow--review-max-retries)
          (progn
            (cl-incf gptel-auto-workflow--review-retry-count)
            (message "[auto-workflow] Review blocked, attempting fix...")
            (gptel-auto-workflow--fix-review-issues
             optimize-branch
             review-output
             (lambda (fix-result)
               (let* ((fix-success (car fix-result))
                      (fix-output (cdr fix-result))
                      (already-fixed
                       (and (not fix-success)
                            (gptel-auto-workflow--fix-output-indicates-already-fixed-p
                             fix-output))))
                 (cond
                  (fix-success
                   (message "[auto-workflow] Fix applied, re-reviewing...")
                   (gptel-auto-workflow--review-changes
                    optimize-branch
                    (lambda (re-review-result)
                      (gptel-auto-workflow--staging-flow-after-review
                       optimize-branch
                       re-review-result
                       completion-callback))))
                  (already-fixed
                   (message "[auto-workflow] Fixer reports issue already resolved; re-reviewing current branch...")
                   (gptel-auto-workflow--review-changes
                    optimize-branch
                    (lambda (re-review-result)
                      (gptel-auto-workflow--staging-flow-after-review
                       optimize-branch
                       re-review-result
                       completion-callback))))
                  (t
                   (message "[auto-workflow] Fix failed: %s"
                            (my/gptel--sanitize-for-logging fix-output 200))
                   (gptel-auto-experiment-log-tsv
                    (gptel-auto-workflow--current-run-id)
                    (list :target "staging-review"
                          :id 0
                          :hypothesis "Staging review fix"
                          :score-before 0
                          :score-after 0
                          :kept nil
                          :duration 0
                          :grader-quality 0
                          :grader-reason "fix-failed"
                          :comparator-reason (truncate-string-to-width fix-output 200)
                          :analyzer-patterns ""
                           :agent-output review-output))
                    (funcall finish nil "fix-failed")))))))
        (message "[auto-workflow] ✗ Review BLOCKED (max retries): %s"
                 (my/gptel--sanitize-for-logging review-output 200))
        (gptel-auto-experiment-log-tsv
         (gptel-auto-workflow--current-run-id)
         (list :target "staging-review"
               :id 0
               :hypothesis "Staging review"
               :score-before 0
               :score-after 0
               :kept nil
               :duration 0
               :grader-quality 0
               :grader-reason "review-blocked-max-retries"
               :comparator-reason (truncate-string-to-width review-output 200)
               :analyzer-patterns ""
                :agent-output review-output))
         (funcall finish nil "review-blocked-max-retries")))
      (t
      (let* ((scope-check (gptel-auto-experiment--check-scope optimize-branch))
             (scope-ok (car scope-check))
             (changed-files (cdr scope-check)))
        (if (not scope-ok)
            (progn
              (message "[auto-workflow] ✗ Scope creep BLOCKED merge: %d files (max: %d)"
                       (length changed-files) gptel-auto-experiment-max-changed-files)
              (gptel-auto-experiment-log-tsv
               (gptel-auto-workflow--current-run-id)
               (list :target "staging-scope"
                     :id 0
                     :hypothesis "Staging scope check"
                     :score-before 0
                     :score-after 0
                     :kept nil
                     :duration 0
                     :grader-quality 0
                     :grader-reason "scope-creep-blocked"
                     :comparator-reason
                     (format "Too many files: %s" (mapconcat #'identity changed-files ", "))
                     :analyzer-patterns ""
                      :agent-output ""))
               (funcall finish nil "scope-creep-blocked"))
            (let* ((config-check (gptel-auto-workflow--check-protected-configs optimize-branch))
                  (config-ok (car config-check))
                  (config-reason (cdr config-check)))
             (if (not config-ok)
                 (progn
                   (message "[auto-workflow] ✗ Protected config regression BLOCKED merge: %s"
                            config-reason)
                   (gptel-auto-experiment-log-tsv
                    (gptel-auto-workflow--current-run-id)
                    (list :target "staging-config"
                          :id 0
                          :hypothesis "Protected config check"
                          :score-before 0
                          :score-after 0
                          :kept nil
                          :duration 0
                          :grader-quality 0
                          :grader-reason "protected-config-regression"
                          :comparator-reason config-reason
                          :analyzer-patterns ""
                           :agent-output ""))
                    (funcall finish nil "protected-config-regression"))
                 (let* ((staging-base (gptel-auto-workflow--current-staging-head))
                  (merge-result
                   (progn
                     (gptel-auto-workflow--git-result
                      "git merge --abort 2>/dev/null; git checkout HEAD -- mementum/ assistant/ 2>/dev/null; true" 30)
                     (gptel-auto-workflow--merge-to-staging optimize-branch)))
                 (already-integrated-p (eq merge-result :already-integrated))
                 (finish-publish
                  (lambda (&optional retried)
                    (gptel-auto-workflow--delete-staging-worktree)
                    ;; Staging completion should always execute, even if the
                    ;; workflow run has already finished.  The experiment
                    ;; passed grading; it deserves to be either kept or
                    ;; explicitly downgraded, not silently lost because the
                    ;; run ended before async staging completed.
                    (progn
                      (when (not (gptel-auto-workflow--run-callback-live-p run-id))
                        (message "[auto-workflow] Staging publish for %s completing after run %s finished"
                                 optimize-branch run-id))
                      (if already-integrated-p
                          (progn
                            (message
                             (if retried
                                 "[auto-workflow] Candidate already present in staging after refresh; published staging sync only."
                               "[auto-workflow] Candidate already present in staging; published staging sync only."))
                            (funcall finish nil "already-in-staging"))
                        (message
                         (if retried
                             "[auto-workflow] ✓ Staging pushed after refreshing remote advance."
                           "[auto-workflow] ✓ Staging pushed. Human must merge to main."))
                         (if (gptel-auto-workflow--promote-staging-to-main)
                             (funcall finish t)
                            (message "[auto-workflow] ⚠ Auto-promote to main failed; staging pushed but not merged")
                            (funcall finish nil "auto-promote-failed")))))))
            (if (null merge-result)
                (progn
                  (message "[auto-workflow] ✗ Merge to staging failed, aborting")
                  (gptel-auto-experiment-log-tsv
                   (gptel-auto-workflow--current-run-id)
                   (list :target "staging-merge"
                         :id 0
                         :hypothesis "Staging merge"
                         :score-before 0
                         :score-after 0
                         :kept nil
                         :duration 0
                         :grader-quality 0
                         :grader-reason "staging-merge-failed"
                         :comparator-reason
                         (format "Failed to merge %s to staging" optimize-branch)
                         :analyzer-patterns ""
                          :agent-output ""))
                   (funcall finish nil "staging-merge-failed"))
               (when already-integrated-p
                (message "[auto-workflow] Candidate changes already present in staging; verifying staged sync only"))
              (let ((worktree (or gptel-auto-workflow--staging-worktree-dir
                                  (gptel-auto-workflow--create-staging-worktree))))
                (if (not worktree)
                    (progn
                       (gptel-auto-workflow--log-staging-step-failure
                        'staging-worktree-failed optimize-branch "")
                       (gptel-auto-workflow--reset-staging-after-failure staging-base)
                       (funcall finish nil "staging-worktree-failed"))
                  (let* ((verification (gptel-auto-workflow--verify-staging))
                         (tests-passed (car verification))
                         (output (or (cdr verification) "")))
                    (if (not tests-passed)
                        (progn
                           (gptel-auto-workflow--log-staging-step-failure
                            'staging-verification-failed optimize-branch output)
                           (gptel-auto-workflow--reset-staging-after-failure staging-base)
                           (funcall finish nil "staging-verification-failed"))
                      (message "[auto-workflow] ✓ Staging verification PASSED")
                      (if (gptel-auto-workflow--push-staging)
                          (funcall finish-publish nil)
                        (let* ((push-output gptel-auto-workflow--last-staging-push-output)
                               (remote-advanced-p
                                (gptel-auto-workflow--staging-push-remote-advanced-p
                                 push-output)))
                          (if remote-advanced-p
                              (if (> gptel-auto-workflow--staging-push-max-retries 0)
                                  (let* ((retry-result
                                          (gptel-auto-workflow--retry-staging-publish-after-remote-advance
                                           optimize-branch))
                                         (retry-success (plist-get retry-result :success))
                                         (retry-reason (plist-get retry-result :reason))
                                         (retry-output (plist-get retry-result :output)))
                                    (if retry-success
                                        (funcall finish-publish t)
                                      (gptel-auto-workflow--log-staging-step-failure
                                       retry-reason optimize-branch retry-output)
                                       (gptel-auto-workflow--sync-staging-from-main)
                                       (funcall finish nil "staging-push-failed")))
                                 (gptel-auto-workflow--log-staging-step-failure
                                  'staging-push-failed optimize-branch push-output)
                                 (gptel-auto-workflow--sync-staging-from-main)
                                 (funcall finish nil "staging-push-failed"))
                             (gptel-auto-workflow--log-staging-step-failure
                              'staging-push-failed optimize-branch push-output)
                             (gptel-auto-workflow--reset-staging-after-failure staging-base)
                             (funcall finish nil "staging-push-failed"))))))))))))))))))


;;; Multi-Project Support

;; Auto-workflow uses .dir-locals.el for per-project configuration.
;; Place .dir-locals.el in your project root with workflow-specific settings.
;;
;; Example .dir-locals.el:
;; ((nil . ((gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
;;          (gptel-auto-experiment-max-per-target . 3)
;;          (gptel-auto-experiment-time-budget . 900)
;;          (gptel-backend . gptel--dashscope)
;;          (gptel-model . qwen3.7-plus))))

(defvar gptel-auto-workflow--project-root-override nil
  "Override for project root when running from non-git directory.
Set via .dir-locals.el or M-x gptel-auto-workflow-set-project-root")

(defun gptel-auto-workflow-set-project-root (root)
  "Set the project ROOT for current session.
Useful when working on projects without git or with complex layouts.
ROOT should be an absolute path to the project directory."
  (interactive "DProject root: ")
  (setq gptel-auto-workflow--project-root-override (expand-file-name root))
  (message "[auto-workflow] Project root set to: %s" 
           gptel-auto-workflow--project-root-override))

(provide 'gptel-tools-agent-staging-merge)
;;; gptel-tools-agent-staging-merge.el ends here
