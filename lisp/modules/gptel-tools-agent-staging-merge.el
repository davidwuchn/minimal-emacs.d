;;; gptel-tools-agent-staging-merge.el --- Staging branch protection - merge & verify -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(require 'gptel-auto-workflow-behavioral-tests nil t)

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

(defun gptel-auto-workflow--empty-cherry-pick-state-p (&optional output allow-missing-head)
  "Return non-nil when the current worktree reflects an already-applied cherry-pick.
When ALLOW-MISSING-HEAD is non-nil, also treat a clean worktree plus localized
empty-pick OUTPUT as already applied even if `CHERRY_PICK_HEAD' is absent."
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
    (and (or (gptel-auto-workflow--non-empty-string-p cherry-pick-head)
             (and allow-missing-head
                  (stringp output)
                  (or (gptel-auto-workflow--empty-commit-output-p output)
                      (string-match-p
                       "already applied\\|previous cherry-pick is now empty\\|The previous cherry-pick is now empty"
                       output))))
         (string-empty-p unmerged-files)
         (string-empty-p worktree-status))))

(defun gptel-auto-workflow--unmerged-files ()
  "Return newline-separated unmerged files in the current git worktree."
  (string-trim
   (or (ignore-errors
         (gptel-auto-workflow--git-cmd
          "git diff --name-only --diff-filter=U 2>/dev/null"
          30))
       "")))

(defun gptel-auto-workflow--merge-to-staging (optimize-branch)
  "Merge OPTIMIZE-BRANCH to staging using cherry-pick.
Cherry-pick the tip commit of OPTIMIZE-BRANCH onto staging.
Returns t when the branch adds changes, `:already-integrated' when staging
already contains the candidate patch, and nil on failure.
Uses the staging worktree instead of switching branches in the root repo."
  (let* ((staging (gptel-auto-workflow--configured-staging-branch))
         (optimize-ref (gptel-auto-workflow--ensure-merge-source-ref optimize-branch))
         (merge-message (format "Merge %s for verification" optimize-branch))
         (commit-timeout (max 300 gptel-auto-workflow-git-timeout)))
    (if (not (gptel-auto-workflow--ensure-staging-branch-exists))
        nil
      (if (not optimize-ref)
          (progn
            (message "[auto-workflow] Missing merge source branch: %s" optimize-branch)
            nil)
        (message "[auto-workflow] Cherry-picking %s to %s" optimize-branch staging)
        (gptel-auto-workflow--with-staging-worktree
         (lambda ()
           (let ((reset-target staging)
                 (worktree gptel-auto-workflow--staging-worktree-dir))
             (if (not (and (gptel-auto-workflow--prepare-staging-merge-base reset-target)
                           (gptel-auto-workflow--ensure-staging-submodules-ready worktree)))
                 nil
               (let* ((commit-hash (string-trim
                                    (car (gptel-auto-workflow--git-result
                                          (format "git rev-parse %s"
                                                  (shell-quote-argument optimize-ref))
                                          60))))
                      (cherry-result
                       (gptel-auto-workflow--git-result
                        (format "git cherry-pick --no-commit %s"
                                (shell-quote-argument commit-hash))
                        180))
                      (cherry-output (car cherry-result)))
                 (cond
                  ((= 0 (cdr cherry-result))
                   (let ((commit-result
                          (gptel-auto-workflow--git-result
                           (format "%s git commit -m %s"
                                   gptel-auto-workflow--skip-submodule-sync-env
                                   (shell-quote-argument merge-message))
                           commit-timeout)))
                     (cond
                      ((= 0 (cdr commit-result))
                       t)
                      ((gptel-auto-workflow--empty-cherry-pick-state-p (car commit-result) t)
                       (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --skip" 60))
                       (message "[auto-workflow] Cherry-pick empty after apply (already in staging)")
                       :already-integrated)
                      (t
                       (message "[auto-workflow] Commit failed after cherry-pick: %s"
                                (my/gptel--sanitize-for-logging (car commit-result) 160))
                       nil))))
                  ((or (gptel-auto-workflow--empty-cherry-pick-state-p cherry-output t)
                       (string-match-p "already applied\\|previous cherry-pick is now empty\\|The previous cherry-pick is now empty"
                                       cherry-output))
                   (message "[auto-workflow] Cherry-pick empty (already in staging)")
                   (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
                   :already-integrated)
                  (t
                   (let ((unmerged-files (gptel-auto-workflow--unmerged-files)))
                     (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
                     (if (gptel-auto-workflow--non-empty-string-p unmerged-files)
                         (progn
                           (gptel-auto-workflow--prepare-staging-merge-base reset-target)
                           (message "[auto-workflow] Cherry-pick conflicted; refusing merge fallback. Conflicted files: %s"
                                    (my/gptel--sanitize-for-logging unmerged-files 160))
                           nil)
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
                                (merge-output (car merge-result)))
                           (cond
                            ((= 0 (cdr merge-result)) t)
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
  "Check syntax of all .el files in DIRECTORY.
Writes errors to OUTPUT-BUFFER.
Returns t if all files pass syntax check, nil otherwise."
  (if (or (null directory) (null output-buffer))
      (progn
        (message "[auto-workflow] check-el-syntax: nil argument")
        nil)
    (let ((errors nil)
          (files (ignore-errors (directory-files-recursively directory "\\.el\\'"))))
      (dolist (file files (null errors))
        (when (file-readable-p file)
          (condition-case err
              (with-temp-buffer
                (insert-file-contents file)
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
                                (file-relative-name file directory)
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
              (test-result (when (and submodule-pass test-script (file-exists-p test-script))
                             (gptel-auto-workflow--call-process-with-watchdog
                              "bash" nil output-buffer nil test-script "unit")))
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
            (setq checks-pass (not (null (car-safe baseline-check))))
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
  (if (or (null remote) (null branch)
          (string-empty-p remote) (string-empty-p branch))
      nil
    (let* ((branch-q (shell-quote-argument branch))
           (remote-result
            (gptel-auto-workflow--git-result
             (format "git ls-remote --exit-code --heads %s %s" remote branch-q)
             (or timeout 60))))
      (and (= 0 (cdr remote-result))
           (gptel-auto-workflow--parse-remote-head branch (car remote-result))))))

(defun gptel-auto-workflow--push-branch-with-lease (branch action &optional timeout)
  "Push BRANCH to the shared remote, using `--force-with-lease' when it already exists.
ACTION is a short description used in failure messages."
  (if (or (null branch) (string-empty-p branch))
      (progn
        (message "[auto-workflow] %s failed: nil or empty branch" action)
        nil)
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
       ((= 0 (cdr push-result))
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
        nil)))))

(defun gptel-auto-workflow--push-staging ()
  "Push staging branch to the shared remote after successful verification.
Unlike per-experiment optimize branches, staging is a shared integration branch,
so this push must not rewrite remote history."
  (let ((staging (gptel-auto-workflow--require-staging-branch))
        (remote (gptel-auto-workflow--shared-remote)))
    (message "[auto-workflow] Pushing staging to %s" remote)
    (when staging
      (gptel-auto-workflow--with-staging-worktree
       (lambda ()
         (setq gptel-auto-workflow--last-staging-push-output nil)
         (let* ((push-result
                 (gptel-auto-workflow--with-skipped-submodule-sync
                  (lambda ()
                    (gptel-auto-workflow--git-result
                     (format "git push %s %s"
                             remote
                             (shell-quote-argument staging))
                     180)))))
           (setq gptel-auto-workflow--last-staging-push-output (car push-result))
           (if (= 0 (cdr push-result))
               t
             (message "[auto-workflow] Push staging failed: %s"
                      (my/gptel--sanitize-for-logging (car push-result) 160))
             nil)))))))

(defvar gptel-auto-workflow--last-staging-push-output nil
  "Raw output from the most recent staging push attempt.")

(defun gptel-auto-workflow--staging-push-remote-advanced-p (output)
  "Return non-nil when OUTPUT shows the shared remote staging branch advanced."
  (string-match-p
   (rx (or "fetch first"
           "non-fast-forward"
           "failed to push some refs"
           "remote contains work that you do not have locally"))
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
    (when (gptel-auto-workflow--ensure-staging-branch-exists)
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
           (gptel-auto-workflow--make-idempotent-staging-completion completion-callback))))
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
                 "reviewer" reviewer-preset review-output)))
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
        (funcall finish nil)))
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
                   (funcall finish nil)))))))
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
        (funcall finish nil)))
     (t
      (let* ((scope-check (gptel-auto-experiment--check-scope))
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
              (funcall finish nil))
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
                   (funcall finish nil))
               (let* ((staging-base (gptel-auto-workflow--current-staging-head))
                 (merge-result
                  (gptel-auto-workflow--merge-to-staging optimize-branch))
                 (already-integrated-p (eq merge-result :already-integrated))
                 (finish-publish
                  (lambda (&optional retried)
                    (gptel-auto-workflow--delete-staging-worktree)
                    (if (not (gptel-auto-workflow--run-callback-live-p run-id))
                        (progn
                          (message "[auto-workflow] Skipping stale staging publish for %s; run %s is no longer active"
                                   optimize-branch run-id)
                          (funcall finish nil "stale-staging-publish"))
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
                        (funcall finish t))))))
            (if (not merge-result)
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
                  (funcall finish nil))
              (when already-integrated-p
                (message "[auto-workflow] Candidate changes already present in staging; verifying staged sync only"))
              (let ((worktree (or gptel-auto-workflow--staging-worktree-dir
                                  (gptel-auto-workflow--create-staging-worktree))))
                (if (not worktree)
                    (progn
                      (gptel-auto-workflow--log-staging-step-failure
                       'staging-worktree-failed optimize-branch "")
                      (gptel-auto-workflow--reset-staging-after-failure staging-base)
                      (funcall finish nil))
                  (let* ((verification (gptel-auto-workflow--verify-staging))
                         (tests-passed (car verification))
                         (output (or (cdr verification) "")))
                    (if (not tests-passed)
                        (progn
                          (gptel-auto-workflow--log-staging-step-failure
                           'staging-verification-failed optimize-branch output)
                          (gptel-auto-workflow--reset-staging-after-failure staging-base)
                          (funcall finish nil))
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
                                      (funcall finish nil)))
                                (gptel-auto-workflow--log-staging-step-failure
                                 'staging-push-failed optimize-branch push-output)
                                (gptel-auto-workflow--sync-staging-from-main)
                                (funcall finish nil))
                            (gptel-auto-workflow--log-staging-step-failure
                             'staging-push-failed optimize-branch push-output)
                            (gptel-auto-workflow--reset-staging-after-failure staging-base)
                            (funcall finish nil))))))))))))))))))


;;; Multi-Project Support

;; Auto-workflow uses .dir-locals.el for per-project configuration.
;; Place .dir-locals.el in your project root with workflow-specific settings.
;;
;; Example .dir-locals.el:
;; ((nil . ((gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
;;          (gptel-auto-experiment-max-per-target . 3)
;;          (gptel-auto-experiment-time-budget . 900)
;;          (gptel-backend . gptel--dashscope)
;;          (gptel-model . qwen3.5-plus))))

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
