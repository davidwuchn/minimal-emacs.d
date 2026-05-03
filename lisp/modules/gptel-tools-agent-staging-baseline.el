;;; gptel-tools-agent-staging-baseline.el --- Staging branch protection - baseline & review -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defun gptel-auto-workflow--with-temporary-worktree (slug ref fn)
  "Create a detached temporary worktree for REF, call FN with its path, then clean up."
  (let* ((proj-root (gptel-auto-workflow--default-dir))
         (default-directory proj-root)
         (worktree-dir (gptel-auto-workflow--temporary-worktree-path slug))
         (worktree-q (shell-quote-argument worktree-dir))
         (ref-q (shell-quote-argument ref)))
    (gptel-auto-workflow--with-error-handling
     (format "create %s worktree" slug)
     (lambda ()
       (when (or (file-exists-p worktree-dir)
                 (string-match-p (regexp-quote worktree-dir)
                                 (gptel-auto-workflow--git-cmd "git worktree list" 60)))
         (gptel-auto-workflow--cleanup-staging-submodule-worktrees worktree-dir)
         (ignore-errors
           (gptel-auto-workflow--git-cmd
            (format "git worktree remove --force %s" worktree-q)
            180))
         (ignore-errors (delete-directory worktree-dir t)))
       (make-directory (file-name-directory worktree-dir) t)
       (let ((add-result
              (gptel-auto-workflow--git-result
               (format "git worktree add --force --detach %s %s" worktree-q ref-q)
               180)))
         (unless (= 0 (cdr add-result))
           (error "git worktree add failed: %s" (car add-result))))
       (gptel-auto-workflow--seed-worktree-runtime-var worktree-dir)
       (unwind-protect
           (funcall fn worktree-dir)
         (gptel-auto-workflow--cleanup-staging-submodule-worktrees worktree-dir)
         (ignore-errors
           (gptel-auto-workflow--git-cmd
            (format "git worktree remove --force %s" worktree-q)
            180))
         (when (file-exists-p worktree-dir)
           (ignore-errors (delete-directory worktree-dir t))))))))

(defun gptel-auto-workflow--main-baseline-test-results ()
  "Return plist describing verification failures for the current staging baseline ref."
  (let ((main-ref (gptel-auto-workflow--staging-main-ref)))
    (cond
     ((not main-ref)
      (list :error "Missing main ref for baseline comparison"))
     (t
      (or
       (gptel-auto-workflow--with-temporary-worktree
        "main-baseline"
        main-ref
        (lambda (worktree)
          (let* ((test-script (expand-file-name "scripts/run-tests.sh" worktree))
                 (verify-script (expand-file-name "scripts/verify-nucleus.sh" worktree))
                 (hydrate (gptel-auto-workflow--hydrate-staging-submodules worktree)))
            (cond
             ((/= 0 (cdr hydrate))
              (list :ref main-ref
                    :error (format "Failed to hydrate %s baseline: %s"
                                   main-ref
                                   (car hydrate))))
             ((not (file-exists-p test-script))
              (list :ref main-ref
                    :error (format "Missing test script in %s baseline worktree" main-ref)))
             (t
              (let* ((buffer (generate-new-buffer "*main-baseline-verify*"))
                     exit-code
                     verify-exit-code
                     output
                     failed-tests)
                (unwind-protect
                    (let ((default-directory worktree))
                      (setq exit-code
                            (if (file-exists-p test-script)
                                (gptel-auto-workflow--call-process-with-watchdog
                                 "bash" nil buffer nil test-script "unit")
                              0))
                      (setq verify-exit-code
                            (if (file-exists-p verify-script)
                                (let ((process-environment
                                       (cons "VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1"
                                             process-environment)))
                                  (gptel-auto-workflow--call-process-with-watchdog
                                   "bash" nil buffer nil verify-script))
                              0))
                      (setq output (with-current-buffer buffer (buffer-string)))
                      (setq failed-tests (gptel-auto-workflow--extract-failed-tests output))
                      (cond
                       ((and (eq exit-code 0) (eq verify-exit-code 0))
                        (list :ref main-ref
                              :exit-code 0
                              :failed-tests nil
                              :output output))
                       (failed-tests
                        (list :ref main-ref
                              :exit-code (or (and (/= exit-code 0) exit-code)
                                             (and (/= verify-exit-code 0) verify-exit-code)
                                             1)
                              :failed-tests failed-tests
                              :output output))
                       (t
                        (list :ref main-ref
                              :exit-code (or (and (/= exit-code 0) exit-code)
                                             (and (/= verify-exit-code 0) verify-exit-code)
                                             1)
                              :error (format "Failed to parse %s baseline test failures"
                                             main-ref)
                              :output output))))
                  (when (buffer-live-p buffer)
                    (kill-buffer buffer)))))))))
       (list :ref main-ref
             :error (format "Failed to create %s baseline worktree" main-ref)))))))

(defun gptel-auto-workflow--staging-tests-match-main-baseline-p (staging-output)
  "Return (PASS-P . NOTE) comparing STAGING-OUTPUT verification failures against main baseline."
  (let ((staging-failures (gptel-auto-workflow--extract-failed-tests staging-output)))
    (cond
     ((null staging-failures)
      (cons t "Staging tests passed: no failures detected"))
     (t
      (let* ((baseline (gptel-auto-workflow--main-baseline-test-results))
             (baseline-error (plist-get baseline :error))
             (baseline-ref (or (plist-get baseline :ref) "main"))
             (baseline-failures (plist-get baseline :failed-tests))
             (new-failures (cl-set-difference staging-failures baseline-failures
                                              :test #'string=)))
        (cond
         (baseline-error
          (cons nil (format "Failed to determine %s baseline: %s"
                            baseline-ref baseline-error)))
         (new-failures
          (cons nil (format "New staging verification failures vs %s: %s"
                            baseline-ref
                            (mapconcat #'identity new-failures ", "))))
         (t
          (cons t (format "No new staging verification failures vs %s baseline%s"
                          baseline-ref
                          (if baseline-failures
                              (format " (%s)"
                                      (mapconcat #'identity baseline-failures ", "))
                            ""))))))))))

(defun gptel-auto-workflow--summarize-staging-verification-output (output)
  "Return a concise failure summary extracted from staging verification OUTPUT."
  (let ((failed-tests (gptel-auto-workflow--extract-failed-tests output)))
    (cond
     (failed-tests
      (format "failing tests: %s"
              (mapconcat #'identity failed-tests ", ")))
     ((gptel-auto-workflow--non-empty-string-p output)
      (my/gptel--sanitize-for-logging output 200))
     (t
      "no verification output captured"))))

(defun gptel-auto-workflow--hydrate-staging-submodules (&optional worktree)
  "Materialize top-level submodules in WORKTREE from shared module repos.
This avoids broken linked-worktree submodule metadata under `.git/worktrees/.../modules'."
  (let* ((root (or worktree gptel-auto-workflow--staging-worktree-dir))
         (paths (gptel-auto-workflow--staging-submodule-paths root))
         (hydrated nil)
         failure)
    (if (not (and root (file-directory-p root)))
        (cons "Staging worktree not found" 1)
      (dolist (path paths nil)
        (unless failure
          (let* ((commit (gptel-auto-workflow--staging-submodule-gitlink-revision root path))
                 (shared-git-dir (gptel-auto-workflow--shared-submodule-git-dir path commit))
                 (target (expand-file-name path root))
                 add-result)
            (cond
             ((not commit)
              (setq failure (format "Missing gitlink revision for submodule %s" path)))
             ((not (and shared-git-dir
                        (file-directory-p shared-git-dir)))
              (setq failure
                    (format "Missing shared submodule repo for %s: %s"
                            path shared-git-dir)))
             (t
              (let ((cleanup-error
                     (gptel-auto-workflow--cleanup-staging-submodule-worktree root path)))
                (if cleanup-error
                    (setq failure cleanup-error)
                  (make-directory (file-name-directory target) t)
                  (gptel-auto-workflow--normalize-shared-submodule-core-worktree
                   path shared-git-dir)
                  (setq add-result
                        (unwind-protect
                            (gptel-auto-workflow--git-result
                             (format "git --git-dir=%s worktree add --detach --force %s %s"
                                     (shell-quote-argument shared-git-dir)
                                     (shell-quote-argument target)
                                     (shell-quote-argument commit))
                             180)
                          (gptel-auto-workflow--normalize-shared-submodule-core-worktree
                           path shared-git-dir)))
                  (if (= 0 (cdr add-result))
                      (push (format "%s=%s" path (gptel-auto-workflow--truncate-hash commit))
                            hydrated)
                    (setq failure
                          (format "Failed to hydrate %s: %s" path (car add-result)))))))))))
      (if failure
          (cons failure 1)
        (cons (if hydrated
                  (format "Hydrated submodules: %s"
                          (mapconcat #'identity (nreverse hydrated) ", "))
                "")
              0)))))

(defun gptel-auto-workflow--ensure-staging-submodules-ready (&optional worktree)
  "Hydrate staging submodules in WORKTREE before hook-driven git commits run.
This is a no-op when WORKTREE is nil or missing, which keeps unit tests that
stub away linked worktrees lightweight."
  (if (not (and (stringp worktree)
                (file-directory-p worktree)))
      t
    (let ((hydrate (gptel-auto-workflow--hydrate-staging-submodules worktree)))
      (if (= 0 (cdr hydrate))
          t
        (message "[auto-workflow] Failed to hydrate staging submodules: %s"
                 (my/gptel--sanitize-for-logging (car hydrate) 200))
        nil))))

(defun gptel-auto-workflow--staging-submodule-conflict-commits (path)
  "Return conflicted gitlink revisions for submodule PATH in the current worktree."
  (let* ((conflict-result
          (gptel-auto-workflow--git-result
           (format "git ls-files -u -- %s" (shell-quote-argument path))
           60))
         (output (car conflict-result))
         commits)
    (when (= 0 (cdr conflict-result))
      (dolist (line (split-string (or output "") "\n" t))
        (when (string-match
               (format "^160000 \\([0-9a-f]\\{40\\}\\) \\([123]\\)\t%s$"
                       (regexp-quote path))
               line)
          (setq commits
                (plist-put commits
                           (pcase (match-string 2 line)
                             ("1" :base)
                             ("2" :ours)
                             ("3" :theirs))
                           (match-string 1 line))))))
    commits))

(defun gptel-auto-workflow--submodule-commit-ancestor-p (git-dir ancestor descendant)
  "Return non-nil when ANCESTOR is contained in DESCENDANT within GIT-DIR."
  (and (stringp git-dir)
       (file-directory-p git-dir)
       (gptel-auto-workflow--non-empty-string-p ancestor)
       (gptel-auto-workflow--non-empty-string-p descendant)
       (= 0
          (cdr (gptel-auto-workflow--git-result
                (format "git --git-dir=%s merge-base --is-ancestor %s %s"
                        (shell-quote-argument git-dir)
                        (shell-quote-argument ancestor)
                        (shell-quote-argument descendant))
                60)))))

(defun gptel-auto-workflow--resolve-ancestor-submodule-merge-conflicts (&optional worktree)
  "Resolve unmerged top-level submodule conflicts in WORKTREE when ancestry is clear.
If every unmerged path is a declared top-level submodule and one side's gitlink is
an ancestor of the other, record the descendant gitlink in the index and return
non-nil. Otherwise leave the merge unresolved and return nil."
  (let* ((root (or worktree default-directory))
         (default-directory root)
         (submodule-paths (gptel-auto-workflow--staging-submodule-paths root))
         (unmerged-result
          (gptel-auto-workflow--git-result
           "git diff --name-only --diff-filter=U"
           30))
         (unmerged-paths
          (when (= 0 (cdr unmerged-result))
            (split-string (string-trim (car unmerged-result)) "\n" t)))
         (resolved nil)
         (all-resolved t))
    (when (and unmerged-paths
               (cl-every (lambda (path) (member path submodule-paths)) unmerged-paths))
      (dolist (path unmerged-paths)
        (let* ((conflict (gptel-auto-workflow--staging-submodule-conflict-commits path))
               (ours (plist-get conflict :ours))
               (theirs (plist-get conflict :theirs))
               (git-dir (or (gptel-auto-workflow--shared-submodule-git-dir path ours)
                            (gptel-auto-workflow--shared-submodule-git-dir path theirs)))
               (chosen
                (cond
                 ((gptel-auto-workflow--submodule-commit-ancestor-p git-dir ours theirs)
                  theirs)
                 ((gptel-auto-workflow--submodule-commit-ancestor-p git-dir theirs ours)
                  ours)
                 ((gptel-auto-workflow--non-empty-string-p ours)
                  ours)
                 ((gptel-auto-workflow--non-empty-string-p theirs)
                  theirs)
                 (t nil))))
          (if (not chosen)
              (setq all-resolved nil)
            (let ((update-result
                   (gptel-auto-workflow--git-result
                    (format "git update-index --cacheinfo 160000 %s %s"
                            (shell-quote-argument chosen)
                            (shell-quote-argument path))
                    60)))
              (if (= 0 (cdr update-result))
                  (push (format "%s=%s" path (gptel-auto-workflow--truncate-hash chosen))
                        resolved)
                (setq all-resolved nil))))))
      (when (and all-resolved resolved)
        (message "[auto-workflow] Resolved submodule merge conflicts: %s"
                 (mapconcat #'identity (nreverse resolved) ", "))
        t))))


(defun gptel-auto-workflow--review-diff-content (optimize-branch)
  "Return review diff content for OPTIMIZE-BRANCH.

The review surface must match the exact tip commit that staging merge will
cherry-pick, not the full branch delta against staging."
  (let* ((optimize-ref (gptel-auto-workflow--ensure-merge-source-ref optimize-branch)))
    (cond
     ((not optimize-ref)
      (format "Error resolving review branch: %s" optimize-branch))
     (t
      (let* ((rev-result
              (gptel-auto-workflow--git-result
               (format "git rev-parse %s"
                       (shell-quote-argument optimize-ref))
               60))
             (commit-hash (string-trim (car rev-result))))
        (cond
         ((not (= 0 (cdr rev-result)))
          (format "Error resolving review commit: %s" (car rev-result)))
         ((not (string-match-p "^[a-f0-9]\\{7,40\\}$" commit-hash))
          (format "Error resolving review commit: %s" commit-hash))
         (t
          (let* ((diff-result
                  (gptel-auto-workflow--git-result
                   (format "git diff --find-renames %s^ %s"
                           (shell-quote-argument commit-hash)
                           (shell-quote-argument commit-hash))
                   60))
                 (diff-output (car diff-result)))
            (cond
             ((string-empty-p diff-output)
              "No changes detected in review commit.")
             ((not (= 0 (cdr diff-result)))
              (format "Error generating diff: %s" diff-output))
             (t
              diff-output))))))))))

(defun gptel-auto-workflow--review-attachment-files (worktree changed-files)
  "Return reviewer file attachments for CHANGED-FILES in WORKTREE.

The returned plist contains:
- `:files' absolute file paths safe to attach
- `:skipped' relative file paths omitted due to reviewer context limits
- `:bytes' cumulative bytes attached"
  (let ((files nil)
        (skipped nil)
        (total-bytes 0))
    (dolist (relative-file changed-files
                           (list :files (nreverse files)
                                 :skipped (nreverse skipped)
                                 :bytes total-bytes))
      (let* ((absolute-file (expand-file-name relative-file worktree))
             (attrs (and (file-readable-p absolute-file)
                         (file-attributes absolute-file)))
             (size (and attrs (file-attribute-size attrs))))
        (if (or (not (integerp size))
                (> size gptel-auto-workflow-review-file-context-max-bytes)
                (> (+ total-bytes size)
                   gptel-auto-workflow-review-file-context-max-total-bytes))
            (push relative-file skipped)
          (push absolute-file files)
          (cl-incf total-bytes size))))))

(defun gptel-auto-workflow--review-changes (optimize-branch callback)
  "Review changes in OPTIMIZE-BRANCH before merging to staging.
Calls CALLBACK with (approved-p . review-output).
Reviewer checks for Blocker/Critical issues."
  (if (not gptel-auto-workflow-require-review)
      (funcall callback (cons t "Review disabled by config"))
    (let* ((proj-root (gptel-auto-workflow--project-root))
           (worktree (car (gptel-auto-workflow--branch-worktree-paths
                           optimize-branch proj-root)))
           (changed-files (and worktree
                               (gptel-auto-workflow--worktree-tip-changed-elisp-files
                                worktree)))
           (review-file-info (and worktree
                                  changed-files
                                  (gptel-auto-workflow--review-attachment-files
                                   worktree changed-files)))
           (review-files (plist-get review-file-info :files))
           (skipped-review-files (plist-get review-file-info :skipped))
           (default-directory proj-root)
           (review-timeout (max my/gptel-agent-task-timeout
                                gptel-auto-workflow-review-time-budget))
           (diff-content (gptel-auto-workflow--review-diff-content optimize-branch))
           (attachment-note
            (if skipped-review-files
                (format "ATTACHED FILE CONTEXT:\n- Attached changed files: %d\n- Omitted oversized files: %s\n- Use repo tools to inspect omitted files when needed.\n\n"
                        (length review-files)
                        (mapconcat #'identity skipped-review-files ", "))
              ""))
           (review-prompt (format "Review the following changes for blockers, critical bugs, and security issues.

CHANGES (diff):
%s

REVIEW CRITERIA:
- Blocker: Runtime error, state corruption, data loss, security hole
- Critical: Proven correctness bug in current code
- Security: eval of untrusted input, shell injection, nil without guard

REVIEW METHOD:
- If the diff introduces a call to an existing helper/function, inspect that helper's
  current definition before blocking on unknown behavior.
- Do not block solely because a referenced helper is outside the diff when you can
  verify it from the current file/repo.
- When attached changed file contents are present, use them before claiming a file
  cannot be located.

%s

OUTPUT: First line must be exactly 'APPROVED' or 'BLOCKED: [reason]'.
You may include structured markdown after that verdict line.

Maximum response: 1000 characters."
                                  (truncate-string-to-width diff-content 3000 nil nil "...")
                                  attachment-note)))
      (message "[auto-workflow] Reviewing changes in %s..." optimize-branch)
      (when skipped-review-files
        (message "[auto-workflow] Reviewer attachments omitted oversized files: %s"
                 (mapconcat #'identity skipped-review-files ", ")))
      (if (and gptel-auto-experiment-use-subagents
               (fboundp 'gptel-benchmark-call-subagent))
          (let ((gptel-benchmark--subagent-files review-files))
            (gptel-benchmark-call-subagent
             'reviewer
             "Review changes before merge"
             review-prompt
             (lambda (result)
               (let* ((response (if (stringp result) result (format "%S" result)))
                      (approved (gptel-auto-workflow--review-approved-p response)))
                 (message "[auto-workflow] Review %s: %s"
                          (if approved "PASSED" "BLOCKED")
                          (my/gptel--sanitize-for-logging response 100))
                 (my/gptel--invoke-callback-safely
                  callback
                  (cons approved response))))
             review-timeout))
        (funcall callback (cons t "No reviewer agent available, auto-approving"))))))

(defun gptel-auto-workflow--review-approved-p (response)
  "Return non-nil when RESPONSE approves a staging review.

Accept explicit APPROVED/BLOCKED markers, blocker-free reviewer markdown,
and analysis-only reviewer summaries that cite current lines without
surfacing blocking markers or issue details."
  (when (stringp response)
    (let* ((normalized (replace-regexp-in-string "|" "\n" response))
           (case-fold-search t)
           (approved (string-match
                      (rx (or line-start "\n")
                          (* blank)
                          (* (any "#*>`*_"))
                          (* blank)
                          "APPROVED" word-end)
                      normalized))
           (blocked (string-match
                     (rx (or line-start "\n")
                         (* blank)
                         (* (any "#*>`*_"))
                         (* blank)
                         "BLOCKED" word-end)
                     normalized))
           (no-blockers (string-match-p
                         (rx (or line-start "\n")
                             (* blank)
                             (? (+ "#") (* blank))
                             "No blockers"
                             (* nonl))
                         normalized))
           (non-blocking-section (string-match-p
                                  (rx (or line-start "\n")
                                      (* blank)
                                      (+ "#") (+ blank)
                                      (or "No Issue"
                                          "Praise"
                                          "Defensive Hardening"
                                          "Style-Only Suggestions")
                                      word-end)
                                  normalized))
           (bug-section (string-match-p
                         (rx (or line-start "\n")
                             (* blank)
                             (+ "#") (+ blank)
                             "Proven Correctness Bugs"
                             word-end)
                         normalized))
           (analysis-summary (string-match-p
                              (rx (or "Based on my analysis"
                                      "Overall assessment"
                                      "After reviewing"
                                      "After examining"
                                      "I reviewed"
                                      "I examined"))
                              normalized))
           (analysis-line-reference (string-match-p
                                     (rx (or (seq ".el:" (+ digit))
                                             (seq "line " (+ digit))))
                                     normalized))
           (issue-label (string-match-p
                         (rx (or line-start "\n")
                             (* blank)
                             (? "-")
                             (* blank)
                             "Issue:"
                             (+ blank))
                         normalized))
           (action-items (string-match-p
                          (rx (or line-start "\n")
                              (* blank)
                              "- [ ]")
                          normalized))
           (unverified (string-match-p
                        (rx (or line-start "\n")
                            (* blank)
                            "UNVERIFIED")
                        normalized))
           (blocking-summary (string-match-p
                              (rx (or "introduces a correctness bug"
                                      "introduces a runtime error"
                                      "introduces a security"
                                      "can signal"
                                      "can crash"
                                      "can fail"
                                      "will signal"
                                      "will crash"
                                      "will fail"
                                      "logic failure"
                                      "state corruption"))
                              normalized)))
      (cond
       ((and blocked
             (or (not approved)
                 (< blocked approved)))
        nil)
       (approved t)
       ((and (or no-blockers non-blocking-section)
             (not bug-section)
             (not issue-label)
             (not action-items)
             (not unverified))
        t)
       ((and analysis-summary
             analysis-line-reference
             (not bug-section)
             (not issue-label)
             (not action-items)
             (not unverified)
             (not blocking-summary))
        t)
       (t nil)))))

(defun gptel-auto-workflow--review-undefined-function-symbol (review-output)
  "Return the undefined function symbol named in REVIEW-OUTPUT, or nil.
Used to catch reviewer false positives before they enter the fix loop."
  (when (stringp review-output)
    (let ((case-fold-search t))
      (when (string-match
             "undefined function[[:space:]]+[`'\"“”‘’]?\\([^`'\"“”‘’[:space:])]+\\)[`'\"“”‘’]?"
             review-output)
        (match-string 1 review-output)))))

(defun gptel-auto-workflow--worktree-tip-changed-elisp-files (worktree)
  "Return Elisp files changed by the tip commit in WORKTREE."
  (when (and (stringp worktree) (file-directory-p worktree))
    (let* ((default-directory worktree)
           (result (gptel-auto-workflow--git-result
                    "git diff --name-only --diff-filter=ACMR HEAD~1 HEAD -- '*.el'"
                    60)))
      (when (= 0 (cdr result))
        (split-string (car result) "\n" t)))))

(defun gptel-auto-workflow--file-defines-function-p (filepath function-name)
  "Return non-nil when FILEPATH defines FUNCTION-NAME in a defun-like form."
  (when-let ((content (gptel-auto-workflow--read-file-contents filepath)))
    (let ((case-fold-search nil))
      (or (string-match-p
           (format
            "^[[:space:]]*(\\(?:cl-\\)?def\\(?:un\\|macro\\|subst\\)\\_>\\s-+%s\\_>"
            (regexp-quote function-name))
           content)
          (string-match-p
           (format
            "^[[:space:]]*(defalias\\_>\\s-+'%s\\_>"
            (regexp-quote function-name))
           content)))))

(defun gptel-auto-workflow--review-disproven-undefined-function-blocker-p (optimize-branch review-output)
  "Return blocker symbol when REVIEW-OUTPUT makes a disproven undefined-function claim.
The blocker is treated as disproven only when the review output cites a single
undefined-function claim and a changed Elisp file in OPTIMIZE-BRANCH defines
that function locally."
  (when-let* ((function-name
               (gptel-auto-workflow--review-undefined-function-symbol review-output))
              ((stringp review-output))
              ((not (string-match-p
                     (rx (or "Proven Correctness Bugs"
                             "Action Items"
                             "Issue:"
                             "security"
                             "logic failure"
                             "state corruption"))
                     review-output)))
              (worktree (car (gptel-auto-workflow--branch-worktree-paths optimize-branch)))
              (changed-files (and worktree
                                  (gptel-auto-workflow--worktree-tip-changed-elisp-files
                                   worktree))))
    (when (cl-some
           (lambda (relative-file)
             (gptel-auto-workflow--file-defines-function-p
              (expand-file-name relative-file worktree)
              function-name))
           changed-files)
      function-name)))

(defun gptel-auto-workflow--fix-review-issues (optimize-branch review-output callback)
  "Try to fix issues found in review for OPTIMIZE-BRANCH.
REVIEW-OUTPUT contains the blocker/critical issues.
Calls CALLBACK with (success-p . fix-output).
If `gptel-auto-workflow-research-before-fix' is nil, executor handles directly."
  (if (not (stringp review-output))
      (funcall callback
               (cons nil
                     (format "Error: Invalid review output type %s for %s"
                             (type-of review-output)
                             optimize-branch)))
    (let* ((proj-root (gptel-auto-workflow--project-root))
           (worktree (car (gptel-auto-workflow--branch-worktree-paths optimize-branch proj-root)))
           (default-directory (or worktree proj-root)))
      (message "[auto-workflow] Fixing review issues (retry %d/%d)..."
               gptel-auto-workflow--review-retry-count gptel-auto-workflow--review-max-retries)
      (if (not (and (stringp worktree) (file-directory-p worktree)))
          (funcall callback
                   (cons nil
                         (format "Error: Missing review fix worktree for %s"
                                 optimize-branch)))
        (if (not gptel-auto-workflow-research-before-fix)
            (gptel-auto-workflow--fix-directly review-output callback worktree)
          (gptel-auto-workflow--research-then-fix review-output callback worktree))))))

(defun gptel-auto-workflow--review-retryable-error-p (review-output)
  "Return non-nil when REVIEW-OUTPUT reflects a reviewer failure worth retrying.

This covers transient transport/provider failures plus contract failures where
the reviewer admits it could not verify the diff or locate the relevant file."
  (when (and (stringp review-output)
             (not (gptel-auto-workflow--review-approved-p review-output)))
    (let ((case-fold-search t))
      (or (memq (car (gptel-auto-experiment--categorize-error review-output))
                '(:api-rate-limit :api-error :timeout))
          (string-match-p
           (rx (or line-start "\n")
               (* blank)
               "UNVERIFIED")
           review-output)
          (string-match-p "did not meet verification contract" review-output)
          (string-match-p "cannot access the file directly" review-output)
          (string-match-p "cannot locate the file" review-output)))))

(defun gptel-auto-workflow--fix-output-indicates-already-fixed-p (fix-output)
  "Return non-nil when FIX-OUTPUT says the worktree already contains the fix."
  (when (stringp fix-output)
    (let ((case-fold-search t))
      (or (string-match-p "already been fixed" fix-output)
          (string-match-p "already fixed" fix-output)
          (string-match-p "already present in the worktree" fix-output)
          (string-match-p "fix already present in worktree" fix-output)))))

(defun gptel-auto-workflow--worktree-dirty-p ()
  "Return non-nil when `default-directory' has uncommitted changes."
  (let ((status (string-trim (or (ignore-errors
                                   (gptel-auto-workflow--git-cmd
                                    "git status --porcelain 2>/dev/null"
                                    30))
                                 ""))))
    (gptel-auto-workflow--non-empty-string-p status)))

(defun gptel-auto-workflow--finalize-review-fix-result (response pre-fix-head)
  "Return (success-p . RESPONSE) after verifying a review-fix attempt.
PRE-FIX-HEAD is the current HEAD hash before the fixer runs."
  (let ((success (not (string-match-p "^Error:" response)))
        (fix-captured nil))
    (when success
      (when (gptel-auto-workflow--worktree-dirty-p)
        (setq fix-captured
              (and (gptel-auto-workflow--stage-worktree-changes
                    "Stage review fix"
                    60)
                   (gptel-auto-workflow--commit-step-success-p
                    (format "%s git commit -m %s"
                            gptel-auto-workflow--skip-submodule-sync-env
                            (shell-quote-argument "fix: address review issues"))
                    "Commit review fix"
                    gptel-auto-workflow-git-timeout))))
      (let ((post-fix-head (gptel-auto-workflow--current-head-hash)))
        (setq fix-captured
              (or fix-captured
                  (and pre-fix-head
                       post-fix-head
                       (not (equal pre-fix-head post-fix-head))))))
      (unless fix-captured
        (message "[auto-workflow] Review fix returned without code changes or commit")))
    (cons (and success fix-captured) response)))

(defun gptel-auto-workflow--fix-directly (review-output callback &optional worktree)
  "Let executor fix REVIEW-OUTPUT issues directly (faster).
When WORKTREE is non-nil, run the fixer and git capture there."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (fix-root
          (or (and (fboundp 'gptel-auto-workflow--normalize-worktree-dir)
                   (gptel-auto-workflow--normalize-worktree-dir
                    (or worktree proj-root)
                    proj-root))
              (file-name-as-directory
               (expand-file-name (or worktree proj-root)))))
         (fix-buffer
          (or (and (fboundp 'gptel-auto-workflow--get-worktree-buffer)
                   (ignore-errors
                     (gptel-auto-workflow--get-worktree-buffer fix-root)))
              (get-buffer-create
               (format " *aw-review-fix:%s*"
                       (file-name-nondirectory
                        (directory-file-name fix-root))))))
         (default-directory fix-root)
         (pre-fix-head (gptel-auto-workflow--current-head-hash))
         (fix-prompt
          (format "Fix the following issues in the code.

ISSUES FROM REVIEW:
%s

INSTRUCTIONS:
1. Read the affected files to understand context
2. Make minimal fixes to address each issue
3. Do NOT make unrelated changes
4. Do NOT create git commits yourself; leave file changes in the worktree
5. Do not reply with only a plan or explanation; actually modify the relevant files
6. If you cannot apply a real code change, reply with 'Error: no fix applied'

Focus only on the issues mentioned. Do not refactor or add features."
                  (truncate-string-to-width review-output 1500 nil nil "..."))))
    (when (buffer-live-p fix-buffer)
      (with-current-buffer fix-buffer
        (setq default-directory fix-root)))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (gptel-auto-experiment--call-in-context
         fix-buffer fix-root
         (lambda ()
           (gptel-benchmark-call-subagent
            'executor
            "Fix review issues"
            fix-prompt
            (lambda (result)
              (let ((default-directory fix-root)
                    (response (if (stringp result) result (format "%S" result))))
                (funcall callback
                         (gptel-auto-workflow--finalize-review-fix-result
                          response
                          pre-fix-head)))))))
      (funcall callback (cons nil "No executor agent available")))))

(defun gptel-auto-workflow--research-then-fix (review-output callback &optional worktree)
  "Use researcher to find approach, then executor to fix REVIEW-OUTPUT.
When WORKTREE is non-nil, run both phases and git capture there."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (fix-root
          (or (and (fboundp 'gptel-auto-workflow--normalize-worktree-dir)
                   (gptel-auto-workflow--normalize-worktree-dir
                    (or worktree proj-root)
                    proj-root))
              (file-name-as-directory
               (expand-file-name (or worktree proj-root)))))
         (fix-buffer
          (or (and (fboundp 'gptel-auto-workflow--get-worktree-buffer)
                   (ignore-errors
                     (gptel-auto-workflow--get-worktree-buffer fix-root)))
              (get-buffer-create
               (format " *aw-review-fix:%s*"
                       (file-name-nondirectory
                        (directory-file-name fix-root))))))
         (default-directory fix-root)
         (pre-fix-head (gptel-auto-workflow--current-head-hash))
         (research-prompt
          (format "Research the best approach to fix these issues:

ISSUES FROM REVIEW:
%s

TASK:
1. Find relevant code patterns in the codebase
2. Check for similar fixes already implemented
3. Identify the minimal, correct fix approach
4. Return a concise fix plan (file:line, change description)

Do NOT make changes. Only research and report findings."
                  (truncate-string-to-width review-output 1000 nil nil "..."))))
    (when (buffer-live-p fix-buffer)
      (with-current-buffer fix-buffer
        (setq default-directory fix-root)))
    (message "[auto-workflow] Researching fix approach...")
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (gptel-auto-experiment--call-in-context
         fix-buffer fix-root
         (lambda ()
           (gptel-benchmark-call-subagent
            'researcher
            "Research fix approach"
            research-prompt
            (lambda (research-result)
              (let* ((default-directory fix-root)
                     (research-response
                      (if (stringp research-result)
                          research-result
                        (format "%S" research-result)))
                     (fix-prompt
                      (format "Apply fixes based on this research:

RESEARCH FINDINGS:
%s

ORIGINAL ISSUES:
%s

INSTRUCTIONS:
1. Apply the minimal fixes identified in research
2. Do NOT make unrelated changes
3. Do NOT create git commits yourself; leave file changes in the worktree
4. Do not reply with only an explanation; actually modify the files
5. If you cannot apply a real code change, reply with 'Error: no fix applied'"
                              (truncate-string-to-width research-response 1000 nil nil "...")
                              (truncate-string-to-width review-output 500 nil nil "..."))))
                (gptel-auto-experiment--call-in-context
                 fix-buffer fix-root
                 (lambda ()
                   (gptel-benchmark-call-subagent
                    'executor
                    "Apply researched fixes"
                    fix-prompt
                    (lambda (result)
                      (let ((default-directory fix-root)
                            (response (if (stringp result)
                                          result
                                        (format "%S" result))))
                        (funcall callback
                                 (gptel-auto-workflow--finalize-review-fix-result
                                  response
                                  pre-fix-head))))))))))))
      (funcall callback (cons nil "No subagent available")))))

(defun gptel-auto-workflow--ensure-on-main-branch ()
  "Ensure main repo is on main branch.
Returns t on success, nil if unable to switch.
This prevents 'branch already used by worktree' errors."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (current-branch (string-trim 
                          (or (gptel-auto-workflow--git-cmd 
                               "git rev-parse --abbrev-ref HEAD 2>/dev/null") 
                              "main"))))
    (if (string= current-branch "main")
        t
      (message "[auto-workflow] Switching from %s to main branch" current-branch)
      (gptel-auto-workflow--with-error-handling
       "switch to main branch"
       (lambda ()
         (gptel-auto-workflow--git-cmd "git checkout main")
         t)))))

;;;###autoload
;;;###autoload

(defun gptel-auto-workflow--ensure-staging-branch-exists ()
  "Ensure the staging branch exists locally.
If it is missing locally, recover it from the shared remote staging branch or
create it from the preferred main ref. Remote pushes are deferred until
verification passes."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging (gptel-auto-workflow--require-staging-branch))
         (remote (gptel-auto-workflow--shared-remote)))
    (gptel-auto-workflow--with-error-handling
     "ensure staging branch exists"
     (lambda ()
       (when staging
         (let* ((staging-q (shell-quote-argument staging))
                (remote-staging (gptel-auto-workflow--shared-remote-ref staging))
                (remote-staging-q (shell-quote-argument remote-staging))
                (remote-staging-refspec
                 (gptel-auto-workflow--shared-remote-refspec staging))
                (remote-staging-refspec-q (shell-quote-argument remote-staging-refspec))
                (local-exists
                 (= 0 (cdr (gptel-auto-workflow--git-result
                            (format "git rev-parse --verify %s" staging-q)
                            60)))))
           (cond
            (local-exists
             (message "[auto-workflow] %s branch exists locally" staging)
             t)
            ((= 0 (cdr (gptel-auto-workflow--git-result
                        (format "git ls-remote --exit-code --heads %s %s"
                                remote
                                staging-q)
                        60)))
             (message "[auto-workflow] Creating local %s from %s/%s" staging remote staging)
             (and (= 0 (cdr (gptel-auto-workflow--git-result
                             (format "git fetch %s %s" remote remote-staging-refspec-q)
                             180)))
                  (= 0 (cdr (gptel-auto-workflow--git-result
                             (format "git branch %s %s" staging-q remote-staging-q)
                             180)))))
            (t
             (let ((main-ref (gptel-auto-workflow--staging-main-ref)))
               (if (not main-ref)
                   nil
                 (message "[auto-workflow] Creating %s branch from %s" staging main-ref)
                 (let ((create-result
                        (gptel-auto-workflow--git-result
                         (format "git branch %s %s"
                                 staging-q
                                 (shell-quote-argument main-ref))
                         180)))
                   (= 0 (cdr create-result)))))))))))))

(defun gptel-auto-workflow--ensure-merge-source-ref (branch)
  "Return a mergeable ref for BRANCH, fetching it narrowly if needed.
Prefers the local branch when present so workflows keep working in repos that
do not fetch every shared-remote head into local tracking refs."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (branch-q (shell-quote-argument branch))
         (remote (gptel-auto-workflow--shared-remote))
         (remote-ref (gptel-auto-workflow--shared-remote-ref branch))
         (remote-ref-q (shell-quote-argument remote-ref))
         (remote-refspec (gptel-auto-workflow--shared-remote-refspec branch))
         (remote-refspec-q (shell-quote-argument remote-refspec)))
    (cond
     ((= 0 (cdr (gptel-auto-workflow--git-result
                 (format "git rev-parse --verify %s" branch-q)
                 60)))
      branch)
     ((= 0 (cdr (gptel-auto-workflow--git-result
                 (format "git rev-parse --verify %s" remote-ref-q)
                 60)))
      remote-ref)
     ((and (= 0 (cdr (gptel-auto-workflow--git-result
                      (format "git ls-remote --exit-code --heads %s %s" remote branch-q)
                      60)))
           (= 0 (cdr (gptel-auto-workflow--git-result
                      (format "git fetch %s %s" remote remote-refspec-q)
                      180))))
      remote-ref)
     (t nil))))


;;;###autoload


(defun gptel-auto-workflow--prepare-staging-merge-base (reset-target)
  "Reset the staging worktree to RESET-TARGET.
Returns non-nil on success, nil on failure."
  (let* ((staging (gptel-auto-workflow--require-staging-branch))
         (reset-q (shell-quote-argument reset-target)))
    (when staging
      (let* ((staging-q (shell-quote-argument staging))
             (current-branch-result
              (gptel-auto-workflow--git-result "git branch --show-current" 30))
             (current-branch
              (and (= 0 (cdr current-branch-result))
                   (string-trim (car current-branch-result))))
             (setup-results
              (append
               (unless (equal current-branch staging)
                 (list (gptel-auto-workflow--git-result
                        (format "git checkout %s" staging-q)
                        60)))
               (list (gptel-auto-workflow--git-result
                      (format "git reset --hard %s" reset-q)
                      180))))
             (failed-setup (cl-find-if (lambda (item) (/= 0 (cdr item)))
                                       setup-results)))
        (if failed-setup
            (progn
              (message "[auto-workflow] Failed to prepare staging merge: %s"
                       (my/gptel--sanitize-for-logging (car failed-setup) 160))
              nil)
          t)))))

(provide 'gptel-tools-agent-staging-baseline)
;;; gptel-tools-agent-staging-baseline.el ends here
