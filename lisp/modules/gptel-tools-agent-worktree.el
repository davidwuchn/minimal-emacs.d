;;; gptel-tools-agent-worktree.el --- Worktree management, staging setup -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defun gptel-auto-workflow--remote-optimize-branches (&optional proj-root)
  "Return remote optimize branches within PROJ-ROOT.

Each entry is a plist with `:branch' and `:head'. SSH noise is ignored."
  (let* ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
         (remote (gptel-auto-workflow--shared-remote))
         (entries nil))
    (if (not (and (file-directory-p default-directory)
                  (gptel-auto-workflow--non-empty-string-p remote)))
        nil
      (let ((result
             (gptel-auto-workflow--git-result
              (format "git ls-remote --heads %s %s"
                      remote
                      (shell-quote-argument "refs/heads/optimize/*"))
              180)))
        (when (= 0 (cdr result))
          (dolist (line (split-string (or (car result) "") "\n" t))
            (when (string-match
                   "^\\([0-9a-f]\\{40\\}\\)\trefs/heads/\\(optimize/.+\\)$"
                   line)
              (push (list :branch (match-string 2 line)
                          :head (match-string 1 line))
                    entries))))
        (nreverse entries)))))

(defun gptel-auto-workflow--discard-worktree-buffers (worktree-dir)
  "Abort, kill, and unregister live gptel buffers rooted at WORKTREE-DIR."
  (when (and (stringp worktree-dir)
             (> (length worktree-dir) 0))
    (let* ((root (file-name-as-directory (expand-file-name worktree-dir)))
           (root-parent (file-name-directory (directory-file-name root)))
           (safe-default-directory
            (or (my/gptel--first-existing-directory
                 root-parent
                 user-emacs-directory
                 temporary-file-directory)
                temporary-file-directory))
           (tracked
            (delete-dups
             (list (gptel-auto-workflow--hash-get-bound 'gptel-auto-workflow--worktree-buffers root)
                   (gptel-auto-workflow--hash-get-bound 'gptel-auto-workflow--project-buffers root))))
           (killed 0))
      (cl-labels
          ((defer-kill (buf attempts-left)
             (run-at-time
              1 nil
              (lambda ()
                (when (buffer-live-p buf)
                  (let ((proc (ignore-errors (get-buffer-process buf))))
                    (cond
                     ((and (processp proc)
                           (process-live-p proc)
                           (> attempts-left 0))
                      (defer-kill buf (1- attempts-left)))
                     (t
                      (let ((kill-buffer-query-functions nil))
                        (kill-buffer buf)))))))))
           (retire-buffer (buf)
             (setq-local default-directory safe-default-directory)
             (when (fboundp 'gptel-abort)
               (ignore-errors (gptel-abort buf)))
             (let ((proc (ignore-errors (get-buffer-process buf))))
               (if (and (processp proc) (process-live-p proc))
                   (defer-kill buf 30)
                 (let ((kill-buffer-query-functions nil))
                   (kill-buffer buf))))))
        (dolist (buf (delete-dups (append tracked (buffer-list))))
          (when (buffer-live-p buf)
            (with-current-buffer buf
              (let ((buf-dir
                     (and (stringp default-directory)
                          (file-name-as-directory
                           (expand-file-name default-directory)))))
                (when (and buf-dir
                           (string-prefix-p root buf-dir)
                           (or (memq buf tracked)
                               (string-prefix-p "*gptel-agent:" (buffer-name buf))))
                  (retire-buffer buf)
                  (cl-incf killed)))))))
      (when (and (boundp 'gptel-auto-workflow--worktree-buffers)
                 (hash-table-p gptel-auto-workflow--worktree-buffers))
        (remhash root gptel-auto-workflow--worktree-buffers))
      (when (and (boundp 'gptel-auto-workflow--project-buffers)
                 (hash-table-p gptel-auto-workflow--project-buffers))
        (remhash root gptel-auto-workflow--project-buffers))
      killed)))

(defun gptel-auto-workflow--discard-missing-worktree-buffers ()
  "Discard tracked workflow buffers rooted at deleted worktrees."
  (let (roots)
    (dolist (table-symbol '(gptel-auto-workflow--worktree-buffers
                            gptel-auto-workflow--project-buffers))
      (when-let ((table (and (boundp table-symbol)
                             (symbol-value table-symbol))))
        (when (hash-table-p table)
          (maphash (lambda (root _buf)
                     (when (and (stringp root)
                                (> (length root) 0)
                                (not (file-directory-p root)))
                       (push root roots)))
                   table))))
    (let ((discarded 0))
      (dolist (root (delete-dups roots))
        (setq discarded (+ discarded
                           (or (gptel-auto-workflow--discard-worktree-buffers root) 0))))
      discarded)))

(defun gptel-auto-workflow--resolve-worktree-base-dir ()
  "Return the configured worktree base directory or the default fallback."
  (or (and (boundp 'gptel-auto-workflow-worktree-base)
           gptel-auto-workflow-worktree-base)
      "var/tmp/experiments"))

(defun gptel-auto-workflow-create-worktree (target &optional experiment-id)
  "Create worktree for TARGET. EXPERIMENT-ID creates numbered branch.
Stores worktree-dir, current-branch in hash table keyed by TARGET.
Uses git CLI directly to avoid magit-worktree-branch hangs.
If branch exists locally, deletes it first to avoid conflicts."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (branch (gptel-auto-workflow--branch-name target experiment-id))
         (base-ref nil)
         (worktree-base-dir (gptel-auto-workflow--resolve-worktree-base-dir))
         (worktree-dir (expand-file-name
                        (format "%s/%s" worktree-base-dir branch)
                        proj-root))
         (stderr-buffer (generate-new-buffer "*git-stderr*")))
    (condition-case err
        (progn
          (make-directory (file-name-directory worktree-dir) t)
          (let ((default-directory proj-root))
            (setq base-ref (or (gptel-auto-workflow--current-staging-head)
                               (gptel-auto-workflow--staging-main-ref)))
            (unless base-ref
              (error "missing base ref for experiment worktree (staging or main)"))
            (gptel-auto-workflow--discard-worktree-buffers worktree-dir)
            (call-process "git" nil stderr-buffer nil "worktree" "prune")
            (dolist (existing-worktree
                     (gptel-auto-workflow--branch-worktree-paths branch proj-root))
              (gptel-auto-workflow--discard-worktree-buffers existing-worktree)
              (message "[auto-workflow] Removing stale worktree for %s: %s"
                       branch existing-worktree)
              (call-process "git" nil stderr-buffer nil
                            "worktree" "remove" "-f" existing-worktree)
              (when (file-exists-p existing-worktree)
                (delete-directory existing-worktree t)))
            ;; Remove existing worktree if present (stale from previous run)
            (when (file-exists-p worktree-dir)
              (gptel-auto-workflow--discard-worktree-buffers worktree-dir)
              (call-process "git" nil stderr-buffer nil "worktree" "remove" "-f" worktree-dir)
              ;; Stale nested bug fallout can leave a plain directory here even
              ;; when Git no longer considers it an attached worktree.
              (when (file-exists-p worktree-dir)
                (delete-directory worktree-dir t)))
            ;; Delete branch if it exists locally (stale from previous run)
            (call-process "git" nil stderr-buffer nil "branch" "-D" branch)
            (when (buffer-live-p stderr-buffer)
              (with-current-buffer stderr-buffer
                (erase-buffer)))
            ;; Create worktree with new branch
            (let* ((exit-code (call-process "git" nil stderr-buffer nil
                                            "worktree" "add" "-b" branch
                                            worktree-dir base-ref))
                   (stderr-output (when (buffer-live-p stderr-buffer)
                                    (with-current-buffer stderr-buffer
                                      (buffer-string))))
                   (stderr-preview (my/gptel--sanitize-for-logging stderr-output 200)))
              (unless (eq exit-code 0)
                (when stderr-output
                  (message "[auto-workflow] Git stderr: %s" stderr-preview))
                (error "git worktree add failed with exit code %s: %s"
                       exit-code (or stderr-preview "no output")))
              (gptel-auto-workflow--seed-worktree-runtime-var worktree-dir)
              (when (gptel-auto-workflow--worktree-needs-submodule-hydration-p worktree-dir)
                (unless (gptel-auto-workflow--ensure-staging-submodules-ready worktree-dir)
                  (error "failed to hydrate experiment submodules in %s" worktree-dir))))
            (kill-buffer stderr-buffer)
            (message "[auto-workflow] Created: %s" branch)
            (puthash target (list :worktree-dir worktree-dir :current-branch branch)
                     gptel-auto-workflow--worktree-state)
            worktree-dir))
      (error
       (when (buffer-live-p stderr-buffer)
         (kill-buffer stderr-buffer))
       (message "[auto-workflow] Failed to create worktree: %s" err)
       (gptel-auto-workflow--clear-worktree-state target)
       nil))))

(defun gptel-auto-workflow-delete-worktree (target)
  "Delete worktree for TARGET from hash table.
Also deletes the associated branch.
Uses git CLI directly to avoid magit issues."
  (let* ((state (or (gethash target gptel-auto-workflow--worktree-state)
                    (list)))
         (worktree-dir (plist-get state :worktree-dir))
         (branch (plist-get state :current-branch)))
    (when worktree-dir
      (gptel-auto-workflow--discard-worktree-buffers worktree-dir)
      (when (file-exists-p worktree-dir)
        (let ((proj-root (gptel-auto-workflow--worktree-base-root)))
          (condition-case err
              (let ((default-directory proj-root))
                ;; Remove worktree
                (let ((exit-code (call-process "git" nil nil nil
                                               "worktree" "remove" worktree-dir)))
                  (unless (eq exit-code 0)
                    (error "git worktree remove failed with exit code %s" exit-code)))
                ;; Delete the branch
                (when branch
                  (call-process "git" nil nil nil "branch" "-D" branch)))
            (error
             (message "[auto-workflow] Failed to delete worktree: %s" err))))))
    (gptel-auto-workflow--clear-worktree-state target)))

;;; Staging Branch Protection

;; ═══════════════════════════════════════════════════════════════════════════
;; CRITICAL INVARIANT: Auto-workflow NEVER touches main branch.
;;
;; What we DO:
;;   - Read from main (to create worktrees, sync staging)
;;   - Write to optimize/* (experiment branches)
;;   - Write to staging (integration branch)
;;
;; What we NEVER do:
;;   - checkout main
;;   - merge to main
;;   - push to main
;;   - reset main
;;
;; Human responsibility:
;;   - Review staging
;;   - Merge staging → main manually
;; ═══════════════════════════════════════════════════════════════════════════

(defun gptel-auto-workflow--assert-main-untouched ()
  "Assert that current branch is NOT main.
Call this before any git operation that might modify branches."
  (let ((current (magit-get-current-branch)))
    (when (string= current "main")
      (error "[SAFETY] Auto-workflow attempted to operate on main branch!"))))

(defun gptel-auto-workflow--configured-staging-branch ()
  "Return the configured staging branch when it is a non-empty string."
  (let ((branch gptel-auto-workflow-staging-branch))
    (and (gptel-auto-workflow--non-empty-string-p branch)
         branch)))

(defun gptel-auto-workflow--require-staging-branch ()
  "Return the configured staging branch, logging when it is invalid."
  (or (gptel-auto-workflow--configured-staging-branch)
      (message "[auto-workflow] Missing staging branch configuration")
      nil))

(defun gptel-auto-workflow--shared-remote ()
  "Return the canonical remote used for auto-workflow shared refs."
  (let* ((default-directory (or (gptel-auto-workflow--project-root)
                                (gptel-auto-workflow--default-dir)
                                default-directory))
         (configured
          (and (gptel-auto-workflow--non-empty-string-p
                gptel-auto-workflow-shared-remote)
               gptel-auto-workflow-shared-remote))
         (tracked
          (let ((remote (ignore-errors (magit-get "branch" "main" "remote"))))
            (and (gptel-auto-workflow--non-empty-string-p remote) remote))))
    (cond
     ((gptel-auto-workflow--non-empty-string-p configured) configured)
     ((gptel-auto-workflow--non-empty-string-p tracked) tracked)
     (t "origin"))))

(defun gptel-auto-workflow--shared-remote-branch (branch)
  "Return BRANCH under the shared auto-workflow remote."
  (when (gptel-auto-workflow--non-empty-string-p branch)
    (format "%s/%s" (gptel-auto-workflow--shared-remote) branch)))

(defun gptel-auto-workflow--shared-remote-ref (branch)
  "Return the full remote-tracking ref for BRANCH on the shared remote."
  (when (gptel-auto-workflow--non-empty-string-p branch)
    (format "refs/remotes/%s/%s"
            (gptel-auto-workflow--shared-remote)
            branch)))

(defun gptel-auto-workflow--shared-remote-refspec (branch)
  "Return a targeted fetch refspec for BRANCH on the shared remote."
  (let ((remote-ref (gptel-auto-workflow--shared-remote-ref branch)))
    (when remote-ref
      (format "+refs/heads/%s:%s" branch remote-ref))))

(defun gptel-auto-workflow--staging-branch-exists-p ()
  "Check if staging branch exists locally or remotely."
  (let* ((branch (gptel-auto-workflow--configured-staging-branch))
         (remote-branch (and branch
                             (gptel-auto-workflow--shared-remote-branch branch))))
    (and branch
         (or (member branch (magit-list-local-branch-names))
             (member remote-branch
                     (magit-list-remote-branch-names))))))

(defun gptel-auto-workflow--autonomous-maintenance-commit-subject-p (subject)
  "Return non-nil when SUBJECT is an autonomous maintenance commit."
  (and (stringp subject)
       (or (string-match-p "\\`💡 synthesis: .+ (AI-generated)\\'" subject)
           (string-match-p
            "\\`instincts evolution: weekly batch update"
            subject))))

(defun gptel-auto-workflow--staging-main-ref ()
  "Return the safe main ref staging and experiments should mirror.
Prefer local `main' when it either matches the shared remote's `main' branch or
is a clean ahead-only tip. Otherwise use the shared remote's `main' so dirty or
diverged local state does not leak into workflow branches."
  (let ((default-directory (gptel-auto-workflow--default-dir)))
    (let* ((remote-main (gptel-auto-workflow--shared-remote-branch "main"))
           (main-result (gptel-auto-workflow--git-result
                         "git rev-parse --verify main"
                         60))
           (remote-result (and remote-main
                               (gptel-auto-workflow--git-result
                                (format "git rev-parse --verify %s" remote-main)
                                60)))
           (have-main (= 0 (cdr main-result)))
           (have-remote (and remote-main
                             (= 0 (cdr remote-result))))
           (main-hash (and have-main (string-trim (car main-result))))
           (remote-hash (and have-remote (string-trim (car remote-result)))))
      (cond
       ((and have-main have-remote)
        (if (string= main-hash remote-hash)
            "main"
          (let* ((status-result (gptel-auto-workflow--git-result
                                 "git status --porcelain"
                                 60))
                 (clean-main (and (= 0 (cdr status-result))
                                  (string-empty-p (string-trim (car status-result)))))
                 (ahead-result (and clean-main
                                    (gptel-auto-workflow--git-result
                                     (format "git rev-list --left-right --count %s...main"
                                             remote-main)
                                     60)))
                 (ahead-counts (and ahead-result
                                    (= 0 (cdr ahead-result))
                                    (split-string (string-trim (car ahead-result))
                                                  "[[:space:]]+" t)))
                 (behind-count (and (= (length ahead-counts) 2)
                                    (string-to-number (nth 0 ahead-counts))))
                 (ahead-count (and (= (length ahead-counts) 2)
                                   (string-to-number (nth 1 ahead-counts))))
                 (ahead-only-main (and clean-main
                                       (numberp behind-count)
                                       (numberp ahead-count)
                                       (= behind-count 0)
                                       (> ahead-count 0)))
                 (subject-result (and ahead-only-main
                                      (gptel-auto-workflow--git-result
                                       (format "git log --format=%%s %s..main" remote-main)
                                       60)))
                 (ahead-subjects (and subject-result
                                      (= 0 (cdr subject-result))
                                      (split-string (string-trim-right (car subject-result))
                                                    "\n"
                                                    t))))
            (if ahead-only-main
                (if (and (consp ahead-subjects)
                         (cl-every
                          #'gptel-auto-workflow--autonomous-maintenance-commit-subject-p
                          ahead-subjects))
                    (progn
                      (message "[auto-workflow] Local main only contains autonomous maintenance commits; using %s as workflow base"
                               remote-main)
                      remote-main)
                  (message "[auto-workflow] Local main is clean and ahead of %s; using main as workflow base"
                           remote-main)
                  "main")
              (message "[auto-workflow] Local main differs from %s; using %s as workflow base"
                       remote-main remote-main)
              remote-main))))
       (have-remote
        remote-main)
       (have-main
        "main")
       (t
        (message "[auto-workflow] Missing main ref for staging sync")
        nil)))))

(defun gptel-auto-workflow--staging-sync-ref ()
  "Return the ref staging should sync from at workflow start.
Prefer the shared remote staging branch when it exists so concurrent hosts
append to the shared integration branch instead of rebuilding it from `main'.
Callers may still need to refresh that base with
`gptel-auto-workflow--staging-main-ref' when remote staging lags behind the
selected main ref. Fall back to `gptel-auto-workflow--staging-main-ref' only
when the remote staging branch is absent."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging (gptel-auto-workflow--require-staging-branch))
         (remote (gptel-auto-workflow--shared-remote)))
    (when staging
      (let* ((staging-q (shell-quote-argument staging))
             (remote-staging (gptel-auto-workflow--shared-remote-ref staging))
             (remote-staging-refspec
              (gptel-auto-workflow--shared-remote-refspec staging))
             (remote-probe
              (gptel-auto-workflow--git-result
               (format "git ls-remote --exit-code --heads %s %s" remote staging-q)
               60)))
        (cond
         ((= 0 (cdr remote-probe))
          (let ((fetch-result
                 (gptel-auto-workflow--git-result
                  (format "git fetch %s %s"
                          remote
                          (shell-quote-argument remote-staging-refspec))
                  180)))
            (if (= 0 (cdr fetch-result))
                remote-staging
              (message "[auto-workflow] Failed to fetch %s/%s for staging sync: %s"
                       remote
                       staging
                       (my/gptel--sanitize-for-logging (car fetch-result) 160))
              nil)))
         ((= 2 (cdr remote-probe))
          (gptel-auto-workflow--staging-main-ref))
         (t
          (message "[auto-workflow] Failed to probe %s/%s for staging sync: %s"
                   remote
                   staging
                   (my/gptel--sanitize-for-logging (car remote-probe) 160))
          nil))))))

(defun gptel-auto-workflow--ref-ancestor-p (ancestor descendant)
  "Return non-nil when ANCESTOR is already contained in DESCENDANT."
  (and (gptel-auto-workflow--non-empty-string-p ancestor)
       (gptel-auto-workflow--non-empty-string-p descendant)
       (= 0
          (cdr (gptel-auto-workflow--git-result
                (format "git merge-base --is-ancestor %s %s"
                        (shell-quote-argument ancestor)
                        (shell-quote-argument descendant))
                60)))))

(defun gptel-auto-workflow--refresh-staging-base-with-main (main-ref)
  "Bring the current staging worktree up to MAIN-REF without dropping staging commits.
Do not require the pre-merge staging checkout to hydrate cleanly: MAIN-REF may
be the source of truth that repairs stale submodule gitlinks from the shared
remote staging branch."
  (let ((worktree default-directory))
    (let* ((main-q (shell-quote-argument main-ref))
           (ff-result
            (gptel-auto-workflow--git-result
             (format "git merge --ff-only %s" main-q)
             180))
           (ff-output (car ff-result)))
      (cond
       ((= 0 (cdr ff-result))
        (gptel-auto-workflow--finalize-refreshed-staging-submodules worktree main-ref))
       ((string-match-p "Already up[ -]to[- ]date" ff-output)
        (gptel-auto-workflow--finalize-refreshed-staging-submodules worktree main-ref))
       (t
        (let* ((merge-result
                (gptel-auto-workflow--git-result
                 (format "git merge -X theirs %s --no-ff -m %s"
                         main-q
                         (shell-quote-argument
                          (format "Sync staging with %s" main-ref)))
                 180))
               (merge-output (car merge-result)))
          (cond
           ((= 0 (cdr merge-result))
            (gptel-auto-workflow--finalize-refreshed-staging-submodules worktree main-ref))
           ((string-match-p "Already up[ -]to[- ]date" merge-output)
            (gptel-auto-workflow--finalize-refreshed-staging-submodules worktree main-ref))
           ((gptel-auto-workflow--resolve-ancestor-submodule-merge-conflicts worktree)
            (if (not (gptel-auto-workflow--ensure-staging-submodules-ready worktree))
                (progn
                  (ignore-errors
                    (gptel-auto-workflow--git-cmd "git merge --abort" 60))
                  nil)
              (let ((commit-result
                     (gptel-auto-workflow--git-result
                      (format "%s git commit --no-edit"
                              gptel-auto-workflow--skip-submodule-sync-env)
                      180)))
                (if (= 0 (cdr commit-result))
                    t
                  (ignore-errors
                    (gptel-auto-workflow--git-cmd "git merge --abort" 60))
                  (message "[auto-workflow] Failed to finalize staging refresh with %s: %s"
                           main-ref
                           (my/gptel--sanitize-for-logging (car commit-result) 160))
                  nil))))
           (t
            (ignore-errors
              (gptel-auto-workflow--git-cmd "git merge --abort" 60))
            (message "[auto-workflow] Failed to refresh staging with %s: %s"
                     main-ref
                     (my/gptel--sanitize-for-logging merge-output 160))
            nil))))))))


(defun gptel-auto-workflow--sync-staging-from-main ()
  "Sync staging from current upstream state at workflow start.
Prefer the shared remote staging branch when available so shared staging keeps
remote results.
Otherwise reset staging to the selected main ref. When remote staging exists
but lags behind the selected main ref, merge the selected main ref into the
local staging base before verification. Never checks out staging in the root
repo."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (main-ref nil)
         (sync-ref nil))
    (message "[auto-workflow] Syncing staging")
    (cond
     ((not (gptel-auto-workflow--ensure-staging-branch-exists))
      nil)
     ((progn
        (setq sync-ref (gptel-auto-workflow--staging-sync-ref))
        (setq main-ref (gptel-auto-workflow--staging-main-ref))
        (not sync-ref))
      nil)
     (t
      (let ((worktree (gptel-auto-workflow--create-staging-worktree)))
        (if (not worktree)
            nil
          (let* ((staging (gptel-auto-workflow--configured-staging-branch))
                 (remote-staging (gptel-auto-workflow--shared-remote-ref staging))
                 (default-directory worktree))
            (let* ((results (list
                             (gptel-auto-workflow--git-result
                              (format "git checkout %s" (shell-quote-argument staging))
                              60)
                             (gptel-auto-workflow--git-result
                              (format "git reset --hard %s"
                                      (shell-quote-argument sync-ref))
                              180)))
                   (failed (cl-find-if (lambda (item) (/= 0 (cdr item))) results)))
              (cond
               (failed
                (message "[auto-workflow] Failed to sync staging: %s"
                         (my/gptel--sanitize-for-logging (car failed) 160))
                nil)
               ((and (equal sync-ref remote-staging)
                     (gptel-auto-workflow--non-empty-string-p main-ref)
                     (not (gptel-auto-workflow--ref-ancestor-p main-ref sync-ref)))
                (when (gptel-auto-workflow--refresh-staging-base-with-main main-ref)
                  (message "[auto-workflow] ✓ Staging synced from %s plus %s"
                           sync-ref main-ref)
                  t))
               ((and (equal sync-ref remote-staging)
                     (gptel-auto-workflow--non-empty-string-p main-ref))
                (when (gptel-auto-workflow--finalize-refreshed-staging-submodules worktree main-ref)
                  (message "[auto-workflow] ✓ Staging synced from %s" sync-ref)
                  t))
               (t
                (message "[auto-workflow] ✓ Staging synced from %s" sync-ref)
                t))))))))))



(defun gptel-auto-workflow--create-staging-worktree ()
  "Create isolated worktree for staging verification.
Never touches project root - all verification happens in the worktree.
Returns worktree path or nil on failure."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (default-directory proj-root)
         (worktree-base-dir (gptel-auto-workflow--resolve-worktree-base-dir))
         (worktree-dir (expand-file-name
                        (format "%s/staging-verify" worktree-base-dir)
                        proj-root))
         (worktree-q (shell-quote-argument worktree-dir)))
    (gptel-auto-workflow--with-error-handling
     "create staging worktree"
     (lambda ()
       (when (gptel-auto-workflow--ensure-staging-branch-exists)
         (let* ((branch (gptel-auto-workflow--configured-staging-branch))
                (branch-q (shell-quote-argument branch)))
           (gptel-auto-workflow--discard-worktree-buffers worktree-dir)
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
                   (format "git worktree add --force %s %s" worktree-q branch-q)
                   180)))
             (unless (= 0 (cdr add-result))
               (error "git worktree add failed: %s" (car add-result))))
           (gptel-auto-workflow--seed-worktree-runtime-var worktree-dir)
           (setq gptel-auto-workflow--staging-worktree-dir worktree-dir)
           (message "[auto-workflow] Created staging worktree: %s" worktree-dir)
           worktree-dir))))))



(defun gptel-auto-workflow--delete-staging-worktree ()
  "Delete staging verification worktree.
NOTE: Staging branch is never deleted, only the worktree."
  (when gptel-auto-workflow--staging-worktree-dir
    (let* ((proj-root (gptel-auto-workflow--project-root))
           (default-directory proj-root)
           (worktree gptel-auto-workflow--staging-worktree-dir))
      (gptel-auto-workflow--with-error-handling
       "delete staging worktree"
       (lambda ()
         (gptel-auto-workflow--discard-worktree-buffers worktree)
         (gptel-auto-workflow--cleanup-staging-submodule-worktrees worktree)
         (ignore-errors
           (gptel-auto-workflow--git-cmd
            (format "git worktree remove --force %s"
                    (shell-quote-argument worktree))
            180))
         (when (file-exists-p worktree)
           (ignore-errors (delete-directory worktree t))))))
    (setq gptel-auto-workflow--staging-worktree-dir nil)))

(defun gptel-auto-workflow--staging-submodule-paths (&optional worktree)
  "Return top-level submodule paths declared in WORKTREE."
  (let* ((root (or worktree gptel-auto-workflow--staging-worktree-dir))
         (gitmodules (and root (expand-file-name ".gitmodules" root)))
         paths)
    (when (and gitmodules (file-readable-p gitmodules))
      (with-temp-buffer
        (insert-file-contents gitmodules)
        (goto-char (point-min))
        (while (re-search-forward "^[[:space:]]*path = \\(.+\\)$" nil t)
          (push (string-trim (match-string 1)) paths))))
    (nreverse paths)))

(defun gptel-auto-workflow--worktree-needs-submodule-hydration-p (&optional worktree)
  "Return non-nil when WORKTREE declares missing or empty top-level submodules."
  (let ((root (or worktree gptel-auto-workflow--staging-worktree-dir)))
    (and (stringp root)
         (file-directory-p root)
         (cl-some
          (lambda (path)
            (let ((target (expand-file-name path root)))
              (or (not (file-directory-p target))
                  (null (directory-files target nil directory-files-no-dot-files-regexp t)))))
          (gptel-auto-workflow--staging-submodule-paths root)))))

(defun gptel-auto-workflow--staging-submodule-gitlink-revision (worktree path)
  "Return the gitlink revision for PATH in WORKTREE, or nil."
  (when (and (file-directory-p worktree)
             (gptel-auto-workflow--non-empty-string-p path))
    (let* ((default-directory worktree)
           (result (gptel-auto-workflow--git-result
                    (format "git ls-tree HEAD -- %s" (shell-quote-argument path))
                    60)))
      (when (and result
                 (= 0 (cdr result))
                 (string-match "160000 commit \\([0-9a-f]\\{40\\}\\)\t" (car result)))
        (match-string 1 (car result))))))

(defun gptel-auto-workflow--staging-submodule-gitlink-revision-at-ref (worktree ref path)
  "Return the gitlink revision for PATH at REF in WORKTREE, or nil."
  (when (and (file-directory-p worktree)
             (gptel-auto-workflow--non-empty-string-p ref)
             (gptel-auto-workflow--non-empty-string-p path))
    (let* ((default-directory worktree)
           (result (gptel-auto-workflow--git-result
                    (format "git ls-tree %s -- %s"
                            (shell-quote-argument ref)
                            (shell-quote-argument path))
                    60)))
      (when (and result
                 (= 0 (cdr result))
                 (string-match "160000 commit \\([0-9a-f]\\{40\\}\\)\t" (car result)))
        (match-string 1 (car result))))))

(defun gptel-auto-workflow--worktree-base-repo-root ()
  "Return the canonical superproject root for the stable workflow root."
  (let* ((git-common-dir (gptel-auto-workflow--worktree-base-git-common-dir))
         (repo-root (and git-common-dir
                         (string-match "\\(.+/\\.git\\)\\(?:/worktrees/[^/]+\\)?\\'"
                                       (directory-file-name git-common-dir))
                         (file-name-directory (match-string 1
                                                            (directory-file-name git-common-dir))))))
    (or repo-root
        (gptel-auto-workflow--worktree-base-root))))

(defun gptel-auto-workflow--checkout-git-common-dir-from-marker (checkout)
  "Return CHECKOUT's git-common-dir by reading its `.git' marker directly."
  (let ((git-marker (expand-file-name ".git" checkout)))
    (cond
     ((file-directory-p git-marker)
      git-marker)
     ((file-regular-p git-marker)
      (let ((git-dir
             (with-temp-buffer
               (insert-file-contents git-marker)
               (goto-char (point-min))
               (when (re-search-forward "^gitdir: \\(.+\\)$" nil t)
                 (expand-file-name (string-trim (match-string 1)) checkout)))))
        (when git-dir
          (let ((commondir-file (expand-file-name "commondir" git-dir)))
            (if (file-regular-p commondir-file)
                (with-temp-buffer
                  (insert-file-contents commondir-file)
                  (expand-file-name (string-trim (buffer-string)) git-dir))
              git-dir)))))
     (t nil))))

(defun gptel-auto-workflow--submodule-checkout-git-dir-at-root (root path)
  "Return the absolute git-common-dir for submodule PATH checked out under ROOT."
  (let ((checkout (and root (expand-file-name path root))))
    (when (file-directory-p checkout)
      (or (gptel-auto-workflow--checkout-git-common-dir-from-marker checkout)
          (let* ((git-common-result
                  (gptel-auto-workflow--git-result
                   (format "git -C %s rev-parse --git-common-dir"
                           (shell-quote-argument checkout))
                   60))
                 (git-common (and git-common-result
                                  (string-trim (car git-common-result)))))
            (when (and git-common-result
                       (= 0 (cdr git-common-result))
                       (not (string-empty-p git-common)))
              (expand-file-name git-common checkout)))))))

(defun gptel-auto-workflow--submodule-checkout-git-dirs (path)
  "Return candidate checked-out git dirs for submodule PATH.

Search both the stable workflow worktree root and the canonical main checkout
root, since one may have a fresher submodule checkout than the other."
  (let* ((roots (cl-remove-duplicates
                 (delq nil
                       (list (gptel-auto-workflow--worktree-base-root)
                             (gptel-auto-workflow--worktree-base-repo-root)))
                 :test #'string=))
         (git-dirs
          (mapcar (lambda (root)
                    (gptel-auto-workflow--submodule-checkout-git-dir-at-root root path))
                  roots)))
    (cl-remove-duplicates (delq nil git-dirs) :test #'string=)))

(defun gptel-auto-workflow--normalize-shared-submodule-core-worktree (path git-dir)
  "Re-anchor shared submodule GIT-DIR for PATH to the canonical checkout."
  (let* ((repo-root (or (gptel-auto-workflow--worktree-base-repo-root)
                        (gptel-auto-workflow--worktree-base-root)))
         (checkout (and repo-root (expand-file-name path repo-root)))
         (canonical-git-dir
          (and (stringp checkout)
               (file-directory-p checkout)
               (gptel-auto-workflow--checkout-git-common-dir-from-marker checkout))))
    (when (and (stringp git-dir)
               (file-directory-p git-dir)
               (stringp checkout)
               (file-directory-p checkout)
               (stringp canonical-git-dir)
               (file-directory-p canonical-git-dir)
               (string=
                (directory-file-name (expand-file-name git-dir))
                (directory-file-name (expand-file-name canonical-git-dir))))
      (pcase-let ((`(,output . ,exit-code)
                   (gptel-auto-workflow--git-result
                    (format "git config --file %s core.worktree %s"
                            (shell-quote-argument (expand-file-name "config" git-dir))
                            (shell-quote-argument (directory-file-name checkout)))
                    60)))
        (unless (= exit-code 0)
          (message "[auto-workflow] Failed to normalize shared submodule worktree for %s: %s"
                   path
                   (my/gptel--sanitize-for-logging output 200)))))
    git-dir))

(defun gptel-auto-workflow--worktree-base-git-common-dir ()
  "Return the git-common-dir for the stable workflow root."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (git-common-result
          (and proj-root
               (gptel-auto-workflow--git-result
                (format "git -C %s rev-parse --git-common-dir"
                        (shell-quote-argument proj-root))
                60)))
         (git-common (and git-common-result
                          (string-trim (car git-common-result)))))
    (when (and git-common-result
               (= 0 (cdr git-common-result))
               (not (string-empty-p git-common)))
      (expand-file-name git-common proj-root))))

(defun gptel-auto-workflow--git-dir-has-commit-p (git-dir commit)
  "Return non-nil when GIT-DIR contains COMMIT.
When COMMIT is nil, only check that GIT-DIR exists."
  (and (file-directory-p git-dir)
       (or (not commit)
           (= 0 (cdr (gptel-auto-workflow--git-result
                      (format "git --git-dir=%s cat-file -e %s^{commit}"
                              (shell-quote-argument git-dir)
                              (shell-quote-argument commit))
                      60))))))

(defun gptel-auto-workflow--shared-submodule-git-dir (path &optional commit)
  "Return a local git dir for submodule PATH that can materialize COMMIT.
Prefer the current checkout when it is a standalone repo, then fall back to the
superproject-managed `.git/modules/...` store."
  (when (gptel-auto-workflow--non-empty-string-p path)
    (let* ((checkout-git-dirs (gptel-auto-workflow--submodule-checkout-git-dirs path))
           (repo-git-dir (gptel-auto-workflow--worktree-base-git-common-dir))
           (module-git-dir (and repo-git-dir
                                (expand-file-name (format "modules/%s" path) repo-git-dir)))
           (candidates (cl-remove-duplicates
                        (append checkout-git-dirs (and module-git-dir (list module-git-dir)))
                        :test #'string=)))
      (car (cl-mapcan
            (lambda (git-dir)
              (when (and (stringp git-dir)
                         (gptel-auto-workflow--git-dir-has-commit-p
                          (gptel-auto-workflow--normalize-shared-submodule-core-worktree
                           path git-dir)
                          commit))
                (list git-dir)))
            candidates)))))

(defun gptel-auto-workflow--finalize-refreshed-staging-submodules (worktree main-ref)
  "Ensure refreshed staging WORKTREE uses materializable top-level submodule gitlinks.
If refreshed staging cannot hydrate a top-level submodule gitlink locally, try to
repair just that gitlink from MAIN-REF, then rehydrate and commit the repair."
  (let* ((default-directory worktree)
         (starting-head (string-trim
                         (gptel-auto-workflow--git-cmd "git rev-parse HEAD" 60)))
         (hydrate-result (gptel-auto-workflow--hydrate-staging-submodules worktree)))
    (if (= 0 (cdr hydrate-result))
        t
      (let ((repaired nil)
            (failure nil))
        (dolist (path (gptel-auto-workflow--staging-submodule-paths worktree))
          (unless failure
            (let* ((current-commit
                    (gptel-auto-workflow--staging-submodule-gitlink-revision worktree path))
                   (current-git-dir
                    (and current-commit
                         (gptel-auto-workflow--shared-submodule-git-dir path current-commit))))
              (when (and current-commit (not current-git-dir))
                (let* ((main-commit
                        (and (gptel-auto-workflow--non-empty-string-p main-ref)
                             (gptel-auto-workflow--staging-submodule-gitlink-revision-at-ref
                              worktree main-ref path)))
                       (main-git-dir
                        (and main-commit
                             (gptel-auto-workflow--shared-submodule-git-dir path main-commit))))
                  (cond
                   ((and main-commit
                         main-git-dir
                         (not (equal current-commit main-commit)))
                    (pcase-let ((`(,output . ,exit-code)
                                 (gptel-auto-workflow--git-result
                                  (format "git update-index --cacheinfo 160000 %s %s"
                                          (shell-quote-argument main-commit)
                                          (shell-quote-argument path))
                                  60)))
                      (if (= exit-code 0)
                          (push (format "%s=%s"
                                        path
                                        (gptel-auto-workflow--truncate-hash main-commit))
                                repaired)
                        (setq failure
                              (format "Failed to repair %s from %s: %s"
                                      path
                                      main-ref
                                      output)))))
                   (t
                    (setq failure
                          (format "Missing materializable fallback for %s (current=%s, main=%s)"
                                  path
                                  (or current-commit "nil")
                                  (or main-commit "nil"))))))))))
        (cond
         (failure
          (ignore-errors
            (let ((default-directory worktree))
              (gptel-auto-workflow--git-cmd "git reset --hard HEAD" 60)))
          (message "[auto-workflow] Failed to repair refreshed staging submodules from %s: %s"
                   main-ref
                   (my/gptel--sanitize-for-logging failure 200))
          nil)
         ((null repaired)
          (message "[auto-workflow] Failed to hydrate refreshed staging submodules: %s"
                   (my/gptel--sanitize-for-logging (car hydrate-result) 200))
          nil)
         (t
          (let* ((repair-message
                  (format "Repair staging submodule gitlinks from %s" main-ref))
                 (commit-command
                  (format "%s git commit -m %s"
                          gptel-auto-workflow--skip-submodule-sync-env
                          (shell-quote-argument repair-message))))
            (if (not (gptel-auto-workflow--commit-step-success-p
                      commit-command
                      "Repair staging submodule gitlinks"
                      180))
                (progn
                  (ignore-errors
                    (gptel-auto-workflow--git-cmd "git reset --hard HEAD" 60))
                  nil)
              (setq hydrate-result
                    (gptel-auto-workflow--hydrate-staging-submodules worktree))
              (if (/= 0 (cdr hydrate-result))
                  (progn
                    (when (gptel-auto-workflow--non-empty-string-p starting-head)
                      (ignore-errors
                        (gptel-auto-workflow--git-cmd
                         (format "git reset --hard %s"
                                 (shell-quote-argument starting-head))
                         60)))
                    (message "[auto-workflow] Failed to hydrate repaired staging submodules from %s: %s"
                             main-ref
                             (my/gptel--sanitize-for-logging (car hydrate-result) 200))
                    nil)
                (message "[auto-workflow] Repaired stale staging submodule gitlinks from %s: %s"
                         main-ref
                         (mapconcat #'identity (nreverse repaired) ", "))
                t)))))))))

(defun gptel-auto-workflow--cleanup-staging-submodule-worktree (worktree path)
  "Remove any staged submodule worktree for PATH under WORKTREE.
Return nil on success, or an error string if the stale path could not be removed."
  (let* ((shared-git-dir (gptel-auto-workflow--shared-submodule-git-dir path))
         (target (expand-file-name path worktree)))
    (when (file-directory-p shared-git-dir)
      (gptel-auto-workflow--normalize-shared-submodule-core-worktree path shared-git-dir)
      (unwind-protect
          (progn
            (ignore-errors
              (gptel-auto-workflow--git-result
               (format "git --git-dir=%s worktree prune --expire now"
                       (shell-quote-argument shared-git-dir))
               60))
            (ignore-errors
              (gptel-auto-workflow--git-result
               (format "git --git-dir=%s worktree remove --force %s"
                       (shell-quote-argument shared-git-dir)
                       (shell-quote-argument target))
               60)))
        (gptel-auto-workflow--normalize-shared-submodule-core-worktree path shared-git-dir)))
    (let ((delete-by-moving-to-trash nil))
      (cond
       ((file-symlink-p target)
        (ignore-errors (delete-file target)))
       ((file-directory-p target)
        (ignore-errors (delete-directory target t)))
       ((file-exists-p target)
        (ignore-errors (delete-file target)))))
    (when (file-exists-p target)
      (format "Failed to remove stale submodule path %s" path))))

(defun gptel-auto-workflow--cleanup-staging-submodule-worktrees (&optional worktree)
  "Remove staged top-level submodule worktrees from WORKTREE."
  (let ((root (or worktree gptel-auto-workflow--staging-worktree-dir)))
    (when (and root (file-exists-p root))
      (dolist (path (gptel-auto-workflow--staging-submodule-paths root))
        (gptel-auto-workflow--cleanup-staging-submodule-worktree root path)))))

(defun gptel-auto-workflow--strip-ansi-escapes (text)
  "Return TEXT with ANSI color escape sequences removed."
  (if (not (stringp text))
      ""
    (replace-regexp-in-string "\x1b\\[[0-9;]*[[:alpha:]]" "" text t t)))

(defun gptel-auto-workflow--extract-failed-tests (output)
  "Return unique verification failure signatures parsed from OUTPUT."
  (let (failed)
    (when (stringp output)
      (with-temp-buffer
        (insert (gptel-auto-workflow--strip-ansi-escapes output))
        (goto-char (point-min))
        (while (re-search-forward
                "^   FAILED[[:space:]]+[0-9]+/[0-9]+[[:space:]]+\\([^[:space:]\n]+\\)"
                nil t)
          (push (match-string 1) failed))
        (goto-char (point-min))
        (while (re-search-forward
                "^[[:space:]]*✗[[:space:]]+\\(.+\\)$"
                nil t)
          (push (format "summary:%s" (string-trim (match-string 1))) failed))
        (goto-char (point-min))
        (while (re-search-forward
                "^ERROR:[[:space:]]+\\(.+\\)$"
                nil t)
          (push (format "error:%s" (string-trim (match-string 1))) failed))))
    (nreverse (cl-remove-duplicates failed :test #'string=))))

(defun gptel-auto-workflow--temporary-worktree-path (slug)
  "Return a temporary worktree path for SLUG under the workflow worktree base."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (worktree-base-dir (gptel-auto-workflow--resolve-worktree-base-dir)))
    (expand-file-name (format "%s/%s-%d" worktree-base-dir slug (emacs-pid))
                      proj-root)))

(provide 'gptel-tools-agent-worktree)
;;; gptel-tools-agent-worktree.el ends here
