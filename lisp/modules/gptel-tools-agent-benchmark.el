;;; gptel-tools-agent-benchmark.el --- Benchmark, evaluation, scoring -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(require 'cl-lib)
(declare-function magit-git-success "magit-git")
(declare-function gptel-auto-experiment--validate-code "gptel-tools-agent-validation")
(declare-function gptel-backend-registry-default-model "gptel-ext-backend-registry" (backend))
(declare-function project-root "project")
(declare-function gptel-auto-workflow--call-in-run-context "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--non-empty-string-p "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--plist-get "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--state-active-p "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--worktree-or-project-dir "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--aborted-agent-output-p "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--categorize-error "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--is-retryable-error-p "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--provider-pressure-error-p "gptel-tools-agent-error")
(declare-function gptel-auto-workflow--activate-provider-failover "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--agent-error-p "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--extract-hypothesis "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--git-result "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--isolated-state-environment "gptel-tools-agent-experiment-loop")
(declare-function my/gptel--sanitize-for-logging "gptel-tools-agent-git")
(declare-function gptel-auto-workflow--call-process-with-watchdog "gptel-tools-agent-main")
(declare-function gptel-auto-experiment--tsv-decision-label "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-experiment--tsv-escape "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--hydrate-staging-submodules "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--staging-tests-match-main-baseline-p "gptel-tools-agent-staging-baseline")
(declare-function gptel-auto-workflow--get-worktree-dir "gptel-tools-agent-subagent")
(declare-function my/gptel--invoke-callback-safely "gptel-tools-agent-subagent")
(declare-function gptel-auto-workflow--worktree-needs-submodule-hydration-p "gptel-tools-agent-worktree")
(defvar gptel-auto-experiment-max-aux-subagent-retries)
(defvar gptel-auto-experiment-max-per-provider-attempts)
(defvar gptel-auto-experiment-min-quality-gain-on-score-tie)
(defvar gptel-auto-experiment-use-subagents)
(defvar gptel-auto-workflow--current-target)
(defvar gptel-auto-workflow--project-root-override)
(defvar gptel-auto-workflow-use-staging)

(defun gptel-auto-workflow--project-root ()
  "Return the MAIN project root directory.
When in a worktree, returns the main repo root (parent of .git/worktrees).
Priority:
1. gptel-auto-workflow--project-root-override (if set via .dir-locals.el)
2. Git common dir (handles worktrees correctly)
3. project.el detection (project-current + project-root)
4. Git worktree root (git rev-parse --show-toplevel)
5. ~/.emacs.d/ (fallback)
Always returns absolute path."
  (cond
   ;; 1. Explicit override (from .dir-locals.el)
   (gptel-auto-workflow--project-root-override
    gptel-auto-workflow--project-root-override)

   ;; 2. Stable workflow run root (captured before entering worktrees)
   ((and (boundp 'gptel-auto-workflow--run-project-root)
         gptel-auto-workflow--run-project-root)
    (expand-file-name gptel-auto-workflow--run-project-root))
   
   ;; 3. Git common dir - returns main repo even from worktrees
   ((let* ((git-common (string-trim
                        (shell-command-to-string
                         "git rev-parse --git-common-dir 2>/dev/null || echo ''")))
           (git-dir (when (and (not (string-empty-p git-common))
                               (file-directory-p (expand-file-name git-common)))
                      (expand-file-name git-common))))
      (when git-dir
        (if (string-match-p "/.git/worktrees/" git-dir)
            ;; Worktree: go up to find main repo root
            (expand-file-name "../../.." git-dir)
          ;; Main repo: use parent of .git
          (file-name-directory (directory-file-name git-dir))))))
   
   ;; 4. project.el detection (preferred method)
   ((let ((proj (and (fboundp 'project-current)
                     (fboundp 'project-root)
                     (project-current nil))))
      (when proj
        (expand-file-name (project-root proj)))))
   
   ;; 5. Git toplevel (fallback)
   ((let ((git-root (string-trim
                     (shell-command-to-string
                      "git rev-parse --show-toplevel 2>/dev/null || echo ''"))))
      (and (not (string-empty-p git-root))
           (file-directory-p git-root)
           git-root)))
   
   ;; 6. Fallback
   (t (expand-file-name
       (or (when (boundp 'minimal-emacs-user-directory)
             minimal-emacs-user-directory)
           "~/.emacs.d/")))))

;;; Benchmark & Evaluation

(defun gptel-auto-experiment-run-tests ()
  "Run ERT tests and return (passed . output).
Tests run in worktree if set, otherwise project root.
Returns cons cell: (t . output) if all pass, (nil . output) if any fail."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (worktree (or (gptel-auto-workflow--get-worktree-dir gptel-auto-workflow--current-target)
                       proj-root))
         (hydrate-submodules-p
          (and worktree
               (or (and proj-root
                        (not (file-equal-p proj-root worktree)))
                   (gptel-auto-workflow--worktree-needs-submodule-hydration-p worktree))))
         (default-directory worktree)
         (process-environment
          (gptel-auto-workflow--isolated-state-environment
           "ov5-auto-workflow-test-"
           (list "VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1")))
         (isolated-status-file (getenv "AUTO_WORKFLOW_STATUS_FILE"))
         (test-script (expand-file-name "scripts/run-tests.sh" worktree))
         (output-buffer (generate-new-buffer "*test-output*"))
         result)
    (unwind-protect
        (if (not (file-directory-p worktree))
            (progn
              (message "[auto-experiment] Worktree deleted, skipping tests: %s" worktree)
              (cons t "Worktree deleted - skipping tests"))
          (if (not (file-executable-p test-script))
              (progn
                (message "[auto-experiment] Test script not found or not executable: %s" test-script)
                (cons t "No test script - skipping"))
          (let* (;; Linked worktrees need the same shared-repo hydration that
                 ;; staging uses, and fresh project-root worktrees can also
                 ;; arrive with gitlink directories that exist but are empty.
                 (hydrate-result (when hydrate-submodules-p
                                   (gptel-auto-workflow--hydrate-staging-submodules worktree)))
                 (hydrate-pass (or (not hydrate-submodules-p)
                                   (= 0 (cdr hydrate-result)))))
            (if (not hydrate-pass)
                (progn
                  (with-current-buffer output-buffer
                    (insert (car hydrate-result) "\n"))
                  (message "[auto-experiment] ✗ Submodule hydration failed: %s"
                           (my/gptel--sanitize-for-logging (car hydrate-result) 200))
                  (cons nil (with-current-buffer output-buffer (buffer-string))))
              (cl-labels
                  ((run-tests-once (attempt)
                     (message "[auto-experiment] Running tests%s..."
                              (if (> attempt 1)
                                  (format " (attempt %d)" attempt)
                                ""))
                     (with-current-buffer output-buffer
                       (erase-buffer))
                     (let ((exit-code
                            (gptel-auto-workflow--call-process-with-watchdog
                             test-script nil output-buffer nil "unit")))
                       (with-current-buffer output-buffer
                         (cons (zerop exit-code) (buffer-string))))))
                (setq result (run-tests-once 1))
                (unless (car result)
                  (let ((first-output (cdr result)))
                    (message "[auto-experiment] Retrying tests after failure")
                    (sleep-for 1)
                    (let ((retry-result (run-tests-once 2)))
                      (setq result
                            (if (car retry-result)
                                retry-result
                              (cons nil
                                    (format "Initial test run failed:\n%s\n\nRetry failed:\n%s"
                                            first-output
                                            (cdr retry-result))))))))
                (when (car result)
                  (message "[auto-experiment] ✓ Tests passed"))
                result)))))
      (when (buffer-live-p output-buffer)
        (kill-buffer output-buffer))
      (when (file-exists-p isolated-status-file)
        (delete-file isolated-status-file)))))

(defcustom gptel-auto-experiment-require-tests t
  "When non-nil, require tests to pass before merging experiment to staging.
This catches bugs that the grader might miss (e.g., CL idioms that don't
work in ELisp).  Set to nil to disable (only for emergency situations)."
  :type 'boolean
  :group 'gptel-auto-workflow)

(defun gptel-auto-experiment--defer-tests-to-staging-p (skip-tests)
  "Return non-nil when benchmark tests should be deferred to staging.
This only applies to headless auto-workflow runs that already verify candidates
through the staging gate."
  (and skip-tests
       gptel-auto-experiment-require-tests
       gptel-auto-workflow-use-staging
       (bound-and-true-p gptel-auto-workflow--headless)))

(defcustom gptel-auto-experiment-max-changed-files 10
  "Maximum number of files an experiment can change.
Prevents scope creep where executor touches many unrelated files.
Set to 0 to disable the check."
  :type 'integer
  :group 'gptel-auto-workflow)
(defcustom gptel-auto-workflow-protected-configs
  `(("assistant/agents/code_agent.md" . ,(symbol-name (gptel-backend-registry-default-model 'MiniMax)))
    ("assistant/agents/plan_agent.md" . ,(symbol-name (gptel-backend-registry-default-model 'MiniMax)))
    ("assistant/agents/comparator.md" . ,(symbol-name (gptel-backend-registry-default-model 'MiniMax)))
    ("assistant/agents/explorer_agent.md" . ,(symbol-name (gptel-backend-registry-default-model 'MiniMax)))
    ("assistant/agents/introspector.md" . ,(symbol-name (gptel-backend-registry-default-model 'MiniMax))))
  "Protected configuration files and their expected values.
AUTO-GENERATED from `gptel-backend-registry' — edit defaults there.
Each element is (FILE . EXPECTED-VALUE).  If an experiment changes
FILE so that it no longer contains EXPECTED-VALUE, the merge is blocked.
Prevents regressions like model downgrades."
  :type '(alist :key-type string :value-type string)
  :group 'gptel-auto-workflow)

(defun gptel-auto-workflow--check-protected-configs (optimize-branch)
  "Check that OPTIMIZE-BRANCH does not regress protected configs.
Returns (ok-p . reason) where REASON is nil if safe, or a description
of the regression if blocked."
  (let ((regressions nil))
    (dolist (protected gptel-auto-workflow-protected-configs)
      (let* ((file (car protected))
             (expected (cdr protected))
             (proj-root (gptel-auto-workflow--project-root))
             (default-directory proj-root)
             (staging-content
              (gptel-auto-workflow--git-result
               (format "git show staging:%s" (shell-quote-argument file))
               30))
             (experiment-content
              (gptel-auto-workflow--git-result
               (format "git show %s:%s"
                       (shell-quote-argument optimize-branch)
                       (shell-quote-argument file))
               30)))
        (when (and (stringp expected)
                   (consp staging-content) (= 0 (cdr staging-content))
                   (consp experiment-content) (= 0 (cdr experiment-content)))
          (let* ((staging-str (car staging-content))
                 (experiment-str (car experiment-content))
                 (staging-has-it (and (stringp staging-str)
                                      (string-match-p (regexp-quote expected) staging-str)))
                 (experiment-has-it (and (stringp experiment-str)
                                         (string-match-p (regexp-quote expected) experiment-str))))
            (when (and staging-has-it (not experiment-has-it))
              (push (format "%s: lost %s" file expected) regressions))))))
    (if regressions
        (progn
          (message "[auto-workflow] ⚠ Protected config regression detected: %s"
                   (mapconcat #'identity regressions "; "))
          (cons nil (mapconcat #'identity regressions "; ")))
      (cons t nil))))


(defun gptel-auto-experiment--check-scope (&optional optimize-branch)
  "Return (ok-p . changed-files) for current experiment.
When OPTIMIZE-BRANCH is given, compare OPTIMIZE-BRANCH against main
using a three-dot diff (main...OPTIMIZE-BRANCH) from the project root.
This avoids false scope-creep when `gptel-auto-workflow--current-target'
has been rebound by a later experiment during async staging flow.

Excludes auto-generated paths (mementum/, assistant/skills/, _template/)
from the count — those are produced by the evolution cycle, not by
experiments, and would otherwise trigger false positives.

Checks that the number of remaining changed files is within limits."
  (let* ((project-root (gptel-auto-workflow--project-root))
         (changed-files
          (if optimize-branch
              (shell-command-to-string
               (format "cd %s && git diff main...%s --name-only --diff-filter=ACMR 2>/dev/null"
                       (shell-quote-argument project-root)
                       (shell-quote-argument optimize-branch)))
            (let ((worktree (gptel-auto-workflow--worktree-or-project-dir)))
              (shell-command-to-string
               (format "cd %s && git diff --name-only HEAD~1 2>/dev/null"
                       (shell-quote-argument worktree))))))
         (all-files (split-string changed-files "\n" t))
         ;; Exclude auto-generated paths that evolve independently
         (files (seq-remove
                 (lambda (f)
                   (string-match-p
                    (rx (or (seq bol "mementum/")
                            (seq bol "assistant/skills/")
                            (seq bol "_template/")))
                    f))
                 all-files))
         (count (length files)))
    (if (and (> gptel-auto-experiment-max-changed-files 0)
             (> count gptel-auto-experiment-max-changed-files))
        (progn
          (message "[auto-exp] ⚠ Scope creep detected: %d files changed (max: %d)"
                   count gptel-auto-experiment-max-changed-files)
          (when (> (length all-files) count)
            (message "[auto-exp]   (excluded %d auto-generated files)"
                     (- (length all-files) count)))
          (cons nil files))
      (cons t files))))

(defun gptel-auto-experiment-benchmark (&optional skip-tests hypothesis)
  "Run syntax validation + Eight Keys scoring.
If SKIP-TESTS is non-nil, skip test execution (tests run in staging flow).
HYPOTHESIS is the experiment hypothesis string, used for task-type-aware
scoring.  Returns plist with :passed, :tests-passed, :eight-keys, etc.

NOTE: Nucleus script validation is skipped for experiments because:
1. verify-nucleus.sh uses script location ($DIR), not worktree context
2. Executor already runs verification in worktree context
3. Full validation happens in staging flow

IMPORTANT: When `gptel-auto-experiment-require-tests' is non-nil (default),
tests still run before the experiment is considered passed, even if
SKIP-TESTS is t.  The exception is the normal headless staging workflow,
where benchmark tests are deferred to the staging gate to keep the worker
daemon alive."
  (let* ((start (float-time))
         (default-directory (gptel-auto-workflow--worktree-or-project-dir))
         (target-file (when gptel-auto-workflow--current-target
                        (expand-file-name gptel-auto-workflow--current-target default-directory)))
         (validation-error (when target-file
                             (gptel-auto-experiment--validate-code target-file))))
    (if validation-error
        (progn
          (message "[auto-exp] ✗ Validation failed: %s"
                   (my/gptel--sanitize-for-logging validation-error 200))
          (list :passed nil
                :validation-error validation-error
                :time (- (float-time) start)))
      (let* ((defer-tests-to-staging
              (gptel-auto-experiment--defer-tests-to-staging-p skip-tests))
             (should-run-tests
              (or (not skip-tests)
                  (and gptel-auto-experiment-require-tests
                       (not defer-tests-to-staging))))
             (tests-result (when should-run-tests
                             (gptel-auto-experiment-run-tests)))
             (raw-tests-passed (and tests-result (car tests-result)))
             (tests-output (when tests-result (cdr tests-result)))
             ;; Allow test failures that match main baseline
             (baseline-check (when (and should-run-tests (not raw-tests-passed))
                               (gptel-auto-workflow--staging-tests-match-main-baseline-p tests-output)))
              (tests-passed (or (not should-run-tests)
                                (and skip-tests (not gptel-auto-experiment-require-tests))
                                raw-tests-passed
                                (and baseline-check (car baseline-check))))
              (debug-info (format "DEBUG: skip=%s defer=%s should-run=%s raw-passed=%s baseline=%s tests-passed=%s"
                                  skip-tests defer-tests-to-staging should-run-tests raw-tests-passed baseline-check tests-passed))
             (final-tests-output (or (and baseline-check (cdr baseline-check))
                                     tests-output))
             (scores (gptel-auto-experiment--eight-keys-scores hypothesis)))
        (when defer-tests-to-staging
          (message "[auto-exp] Deferring tests to staging flow for %s"
                   (or gptel-auto-workflow--current-target default-directory)))
        (when (and skip-tests gptel-auto-experiment-require-tests)
          (message "[auto-exp] Tests required before staging merge: %s"
                   (if tests-passed "PASS" "FAIL")))
          (list :passed tests-passed
                :debug-info debug-info
                :nucleus-passed t
                :nucleus-skipped t
                :tests-passed tests-passed
               :tests-output final-tests-output
               :tests-skipped (not should-run-tests)
               :time (- (float-time) start)
               :eight-keys (when scores (alist-get 'overall scores))
               :eight-keys-scores scores)))))

(defun gptel-auto-experiment--eight-keys-scores (&optional hypothesis)
  "Get full Eight Keys scores alist from current codebase.
Scores based on commit message + code diff (not just stat).
If HYPOTHESIS is provided, use task-type-aware scoring.
Loads gptel-benchmark-principles if not already available."
  (unless (fboundp 'gptel-benchmark-eight-keys-score)
    (message "[auto-exp] Eight Keys scorer not loaded — requiring gptel-benchmark-principles")
    (condition-case err
        (require 'gptel-benchmark-principles nil t)
      (error (message "[auto-exp] Failed to load Eight Keys scorer: %S" err))))
  (when (fboundp 'gptel-benchmark-eight-keys-score)
    (let* ((worktree (gptel-auto-workflow--worktree-or-project-dir))
           ;; SECURITY: Use shell-quote-argument to prevent shell injection
           (worktree-quoted (shell-quote-argument worktree))
           (commit-msg (shell-command-to-string
                        (format "cd %s && git log -1 --format='%%B' 2>/dev/null || echo ''"
                                worktree-quoted)))
           (code-diff (shell-command-to-string
                       (format "cd %s && git diff HEAD~1 --unified=2 2>/dev/null | head -200"
                               worktree-quoted)))
           (output (concat commit-msg "\n\n" code-diff)))
      (if hypothesis
          (condition-case err
              (gptel-benchmark-eight-keys-score output hypothesis)
            (wrong-number-of-arguments
             ;; Long-lived workflow daemons may have a stale one-argument scorer
             ;; loaded while the auto-workflow module has already hot-reloaded.
             (message "[auto-exp] Eight Keys scorer lacks hypothesis arity; falling back to legacy scoring: %S"
                      err)
             (gptel-benchmark-eight-keys-score output)))
        (gptel-benchmark-eight-keys-score output)))))

(defun gptel-auto-experiment--eight-keys-score ()
  "Get Eight Keys overall score from current codebase."
  (let ((scores (gptel-auto-experiment--eight-keys-scores)))
    (when scores (alist-get 'overall scores))))

(defun gptel-auto-experiment--code-quality-score ()
  "Get code quality score from current changes."
  (when (fboundp 'gptel-benchmark--code-quality-score)
    (let* ((worktree (gptel-auto-workflow--worktree-or-project-dir)))
      (when (and worktree (file-directory-p worktree))
        (let* ((worktree-quoted (shell-quote-argument worktree))
               (changed-files (shell-command-to-string
                               (format "cd %s && git diff --name-only HEAD~1 2>/dev/null | grep '\\.el$'"
                                       worktree-quoted))))
          (when (string-match-p "\\.el$" (string-trim-right changed-files))
            (let ((total-score 0.0)
                  (file-count 0))
              (dolist (file (split-string changed-files "\n" t))
                (when (and (stringp file)
                           (not (string-empty-p (string-trim file))))
                  (let* ((filepath (expand-file-name (string-trim file) worktree))
                         (content (gptel-auto-workflow--read-file-contents filepath)))
                    (when content
                      (let ((score (gptel-benchmark--code-quality-score content)))
                        (when (numberp score)
                          (setq total-score (+ total-score score))
                          (setq file-count (1+ file-count))))))))
              (if (> file-count 0)
                  (/ total-score file-count)
                0.5))))))))

;;; Subagent Integrations

(defun gptel-auto-experiment--call-in-context (buffer directory fn &optional run-root &rest _ignored)
  "Call FN in BUFFER with DIRECTORY bound as `default-directory'.
When RUN-ROOT is non-nil, preserve that workflow root for async callbacks that
resume from buffers outside the original project context.
Accepts extra IGNORED args passed by byte-compiled closure callers."
  (gptel-auto-workflow--call-in-run-context
   run-root fn buffer directory))

(defmacro gptel-auto-experiment--with-context (buffer directory &rest body)
  "Run BODY in BUFFER with DIRECTORY bound as `default-directory'."
  (declare (indent 2) (debug t))
  `(gptel-auto-experiment--call-in-context
    ,buffer ,directory
    (lambda ()
      ,@body)))

(defmacro gptel-auto-experiment--with-run-context (buffer directory run-root &rest body)
  "Run BODY in BUFFER with DIRECTORY and RUN-ROOT rebound for workflow callbacks."
  (declare (indent 3) (debug t))
  `(gptel-auto-experiment--call-in-context
    ,buffer ,directory
    (lambda ()
      ,@body)
    ,run-root))

(defun gptel-auto-experiment--analysis-value-present-p (value)
  "Return non-nil when VALUE contains usable analyzer content."
  (cond
   ((null value) nil)
   ((stringp value) (not (string-empty-p (string-trim value))))
   ((vectorp value) (> (length value) 0))
   ((proper-list-p value) (not (null value)))
   (t t)))

(defun gptel-auto-experiment--analysis-list (value)
  "Return VALUE as a list for analyzer prompt composition."
  (cond
   ((null value) nil)
   ((vectorp value) (append value nil))
   ((proper-list-p value) value)
   (t (list value))))

(defun gptel-auto-experiment--summarize-previous-results (previous-results)
  "Return a prompt-friendly summary string for PREVIOUS-RESULTS."
  (when previous-results
    (mapconcat
     (lambda (result)
       (when (and (proper-list-p result) (plist-get result :hypothesis))
         (let* ((experiment-id (gptel-auto-workflow--plist-get result :id "?"))
                (decision (gptel-auto-experiment--tsv-decision-label result))
              (hypothesis
               (truncate-string-to-width
                (gptel-auto-experiment--tsv-escape
                 (gptel-auto-workflow--plist-get result :hypothesis "unknown"))
                220 nil nil "...")))
          (format "- Experiment %s: %s - %s"
                  experiment-id decision hypothesis))))
     previous-results
     "\n")))

(defun gptel-auto-experiment--fallback-analysis (previous-results)
  "Return deterministic analysis plist derived from PREVIOUS-RESULTS."
  (when previous-results
    (let ((recommendations '()))
      (push "Do not repeat a previous hypothesis verbatim. Choose a materially different change or explain why it avoids the earlier outcome."
            recommendations)
      (when (cl-some
             (lambda (result)
               (and (proper-list-p result)
                    (string= (gptel-auto-experiment--tsv-decision-label result)
                             "discarded")))
             previous-results)
        (push "At least one prior attempt was discarded as no improvement; pivot to a different function, defect, or improvement type."
              recommendations))
      (when (cl-some
             (lambda (result)
               (and (proper-list-p result)
                    (member (gptel-auto-experiment--tsv-decision-label result)
                            '("tests-failed"
                              "validation-failed"
                              "inspection-thrash"
                              "repeated-focus-symbol"
                              "retry-grade-failed"))))
             previous-results)
        (push "At least one prior attempt failed validation/tests; avoid editing the same code path again unless the new change directly fixes that failure."
              recommendations))
      (list :patterns nil
            :issues nil
            :recommendations (nreverse (delete-dups recommendations))
            :previous-summary (gptel-auto-experiment--summarize-previous-results
                                previous-results)))))

(defun gptel-auto-experiment--merge-analysis (analysis previous-results)
  "Merge ANALYSIS with deterministic history from PREVIOUS-RESULTS."
  (let* ((fallback (gptel-auto-experiment--fallback-analysis previous-results))
         (valid-analysis (and (proper-list-p analysis) analysis))
         (patterns (if (gptel-auto-experiment--analysis-value-present-p
                        (gptel-auto-workflow--plist-get valid-analysis :patterns nil))
                       (gptel-auto-workflow--plist-get valid-analysis :patterns nil)
                     (gptel-auto-workflow--plist-get fallback :patterns nil)))
         (issues (if (gptel-auto-experiment--analysis-value-present-p
                      (gptel-auto-workflow--plist-get valid-analysis :issues nil))
                     (gptel-auto-workflow--plist-get valid-analysis :issues nil)
                   (gptel-auto-workflow--plist-get fallback :issues nil)))
         (recommendations
          (delete-dups
           (append (gptel-auto-experiment--analysis-list
                    (gptel-auto-workflow--plist-get valid-analysis :recommendations nil))
                   (gptel-auto-experiment--analysis-list
                    (gptel-auto-workflow--plist-get fallback :recommendations nil))))))
    (when (or (gptel-auto-experiment--analysis-value-present-p patterns)
              (gptel-auto-experiment--analysis-value-present-p issues)
              recommendations
              (gptel-auto-workflow--plist-get fallback :previous-summary nil))
      (list :patterns patterns
            :issues issues
            :recommendations recommendations
            :previous-summary (gptel-auto-workflow--plist-get fallback :previous-summary nil)))))

(defcustom gptel-auto-experiment-repeat-focus-threshold 3
  "Prior non-kept attempts on the same changed symbol before
short-circuiting repeats."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-experiment--extract-focus-symbols (output)
  "Return deduplicated function-like symbols mentioned in OUTPUT."
  (let (symbols)
    (when (stringp output)
      (with-temp-buffer
        (insert output)
        (goto-char (point-min))
        (while (re-search-forward "`\\([^`\n]+\\)`" nil t)
          (let ((candidate (match-string 1)))
            (when (and candidate
                       (< (length candidate) 200)
                       (string-match-p "--\\|::" candidate))
              (push candidate symbols))))))
    (nreverse (cl-remove-duplicates symbols :test #'string=))))

(defun gptel-auto-experiment--repeated-focus-match (output previous-results &optional target-file)
  "Return plist when OUTPUT repeats a changed symbol in PREVIOUS-RESULTS.
Only counts prior non-kept results and triggers once a symbol appears in at
least `gptel-auto-experiment-repeat-focus-threshold' previous attempts.
When TARGET-FILE is non-nil, also counts per-target-file discards so
repeatedly failing files get deprioritized across symbol changes."
  ;; BOUNDARY: guard against malformed previous-results
  (when (proper-list-p previous-results)
    (let ((current-symbols (gptel-auto-experiment--extract-focus-symbols output)))
      (when target-file
        (push target-file current-symbols))
      (when current-symbols
        (let ((counts (make-hash-table :test 'equal))
              matches)
          (dolist (result previous-results)
            (when (and (proper-list-p result) (not (gptel-auto-workflow--plist-get result :kept nil)))
              (let ((prev-symbols (gptel-auto-experiment--extract-focus-symbols
                                   (gptel-auto-workflow--plist-get result :agent-output ""))))
                (when (and (stringp target-file)
                           (equal target-file (gptel-auto-workflow--plist-get result :target "")))
                  (push target-file prev-symbols))
                (dolist (symbol prev-symbols)
                  (puthash symbol (1+ (gethash symbol counts 0)) counts)))))
          (dolist (symbol current-symbols)
            (let ((count (gethash symbol counts 0)))
              (when (>= count gptel-auto-experiment-repeat-focus-threshold)
                (push (cons symbol count) matches))))
          (when matches
            (let* ((sorted (sort matches (lambda (a b) (> (cdr a) (cdr b)))))
                   (best (car sorted)))
              (list :symbol (car best)
                    :count (cdr best)
                    :matches (nreverse sorted)))))))))

(defun gptel-auto-experiment--subagent-raw-result (result)
  "Return raw transient error text from RESULT, or nil when unavailable."
  (cond
   ((stringp result) result)
   ((and (proper-list-p result)
         (stringp (plist-get result :raw)))
    (plist-get result :raw))
   (t nil)))

(defun gptel-auto-experiment--subagent-error-output-p (raw)
  "Return non-nil when RAW looks like a real subagent failure payload.
Successful analyzer/comparator text can mention prior timeouts or failures in
its narrative.  Those references must not be treated as retryable transport
errors."
  (and (stringp raw)
       (or (string-match-p "\\`Error:" raw)
           (string-match-p "\\`Warning:.*not available" raw)
           (gptel-auto-experiment--aborted-agent-output-p raw))))

(defun gptel-auto-experiment--retryable-aux-subagent-category (result)
  "Return retryable transient error category for RESULT, or nil."
  (when-let* ((raw (gptel-auto-experiment--subagent-raw-result result))
              ((gptel-auto-experiment--subagent-error-output-p raw))
              (category (car (gptel-auto-experiment--categorize-error raw))))
    (when (or (memq category '(:timeout :api-rate-limit))
              (and (eq category :api-error)
                   (gptel-auto-experiment--is-retryable-error-p raw)))
      category)))

(defun gptel-auto-experiment--current-subagent-preset (agent-type)
  "Return the effective preset for AGENT-TYPE in the current run."
  (when-let* ((base-preset
               (and (fboundp 'gptel-auto-workflow--agent-base-preset)
                    (gptel-auto-workflow--agent-base-preset agent-type))))
    (if (fboundp 'gptel-auto-workflow--maybe-override-subagent-provider)
        (gptel-auto-workflow--maybe-override-subagent-provider agent-type base-preset)
      base-preset)))

(defun gptel-auto-experiment--call-aux-subagent-with-retry
    (agent-type invoke callback &optional retries provider-attempts)
  "Invoke AGENT-TYPE via INVOKE, retrying transient failures before CALLBACK.

INVOKE is called with a single callback argument and must start the actual
subagent request. Retries on same provider up to
`gptel-auto-experiment-max-per-provider-attempts' before advancing to
the next fallback provider. PROVIDER-ATTEMPTS tracks consecutive retries
on the current provider."
  (funcall
   invoke
   (lambda (result)
      (let* ((attempt (or retries 0))
             (prov-attempts (or provider-attempts 0))
             (category
              (gptel-auto-experiment--retryable-aux-subagent-category result))
             (raw (gptel-auto-experiment--subagent-raw-result result))
             (is-pressure (gptel-auto-experiment--provider-pressure-error-p raw))
             ;; Advance provider only after N consecutive failures on same one
             (should-advance (and is-pressure
                                  (>= (1+ prov-attempts)
                                      gptel-auto-experiment-max-per-provider-attempts)))
             ;; verbum determinism: lambda-healthy backends have 0.0 drift.
             ;; Skip retries for non-network errors — computation is
             ;; deterministic. Only retry on quota/network pressure.
             (lambda-available (fboundp 'gptel-auto-workflow--backend-health-level)))
        (if (and category
                 (not (bound-and-true-p gptel-auto-experiment--quota-exhausted))
                 (< attempt gptel-auto-experiment-max-aux-subagent-retries)
                 (or is-pressure (not lambda-available)))
           (progn
             (when should-advance
               (when-let ((preset
                           (gptel-auto-experiment--current-subagent-preset
                            agent-type)))
                 (gptel-auto-workflow--activate-provider-failover
                  agent-type preset raw)))
             (message "[auto-exp] %s failed transiently (%s), retrying (%d/%d)%s"
                      agent-type category
                      (1+ attempt) gptel-auto-experiment-max-aux-subagent-retries
                      (if should-advance " [advanced provider]" ""))
             (let ((at agent-type)
                   (inv invoke)
                   (cb callback)
                   (next-att (1+ attempt))
                   (next-prov (if should-advance 0 (1+ prov-attempts))))
               (if noninteractive
                    (gptel-auto-experiment--call-aux-subagent-with-retry
                     at inv cb next-att next-prov)
                  (run-with-timer 0 nil
                                  (lambda ()
                                    (gptel-auto-experiment--call-aux-subagent-with-retry
                                     at inv cb next-att next-prov))))))
         (funcall callback result))))))

(defun gptel-auto-experiment-analyze (previous-results callback)
  "Analyze patterns from PREVIOUS-RESULTS. Call CALLBACK with analysis.
The analyzer subagent overlay will appear in the current buffer at time of call."
  ;; Capture the current buffer to ensure analyzer overlay appears in right place
  (let ((analyze-buffer (current-buffer))
        (finalize
         (lambda (analysis)
           (funcall callback
                    (gptel-auto-experiment--merge-analysis
                     analysis previous-results)))))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-analyze)
             previous-results)
        (with-current-buffer analyze-buffer
          (gptel-auto-experiment--call-aux-subagent-with-retry
           "analyzer"
           (lambda (cb)
             (gptel-benchmark-analyze
              previous-results
              "Experiment patterns"
              cb))
           finalize))
      (funcall finalize nil))))

(defvar gptel-auto-experiment--grade-state (make-hash-table :test 'eql)
  "Hash table for per-grade state. Keyed by grade-id.
Values are plist: (:done :timer).")

(defvar gptel-auto-experiment--grade-counter 0
  "Counter for generating unique grade IDs.")

(defvar gptel-auto-experiment--grading-target nil
  "Dynamically bound target file for the current grade request.")

(defvar gptel-auto-experiment--grading-worktree nil
  "Dynamically bound experiment worktree for the current grade request.")

(defvar gptel-auto-experiment-grade-timeout 900
  "Timeout in seconds for grading subagent.
Matches gptel-auto-experiment-time-budget (900s in headless mode).
Previously 450s caused grader to timeout before experiment finished,
destroying all experiments with score=0. Now grader lives as long as
the experiment itself.")

(defun gptel-auto-experiment--reset-grade-state ()
  "Cancel and clear all pending grade callbacks."
  (maphash
   (lambda (_grade-id state)
     (when (timerp (plist-get state :timer))
       (cancel-timer (plist-get state :timer))))
    gptel-auto-experiment--grade-state)
  (clrhash gptel-auto-experiment--grade-state))

(defun gptel-auto-experiment--normalize-grade-result (result)
  "Return RESULT as a grade plist with numeric score fields."
  (cl-labels ((number-string-p
               (value)
               (and (stringp value)
                    (string-match-p
                     "\\`[[:space:]]*[+-]?[0-9]+\\(?:\\.[0-9]+\\)?[[:space:]]*\\'"
                     value)))
              (number-or-default
               (value default)
               (cond
                ((numberp value) value)
                ((number-string-p value) (string-to-number value))
                (t default))))
    (let* ((plist-result-p (proper-list-p result))
           (grade (if plist-result-p
                      (copy-sequence result)
                    (list :details (format "Error: malformed grader result: %S" result)
                          :grader-only-failure t)))
           (raw-score (plist-get grade :score))
           (raw-total (plist-get grade :total))
           (score (number-or-default raw-score 0))
           (total (max 1 (number-or-default raw-total (max 1 score))))
           (malformed (or (not plist-result-p)
                          (and raw-score (not (numberp raw-score))
                               (not (number-string-p raw-score)))
                          (and raw-total (not (numberp raw-total))
                               (not (number-string-p raw-total)))))
           (percentage
            (number-or-default (plist-get grade :percentage)
                               (* 100.0 (/ (float score) total))))
           (details (plist-get grade :details)))
      (setq grade (plist-put grade :score score))
      (setq grade (plist-put grade :total total))
      (setq grade (plist-put grade :percentage percentage))
      (setq grade (plist-put grade :passed (and (not malformed)
                                                (eq (plist-get grade :passed) t))))
      (unless (stringp details)
        (setq grade (plist-put grade :details
                               (format "Error: malformed grader result: %S" result))))
      (when malformed
        (setq grade (plist-put grade :grader-only-failure t))
        (unless (plist-get grade :error-source)
          (setq grade
                (plist-put grade :error-source
                           (format "Error: malformed grader result: score=%S total=%S"
                                   raw-score raw-total)))))
      grade)))

(defun gptel-auto-experiment--finish-grade (grade-id callback result
                                                      &optional cancel-timer)
  "Finalize GRADE-ID with RESULT, always cleaning grade state.
CALLBACK receives RESULT.  When CANCEL-TIMER is non-nil, cancel the
stored timeout timer before invoking CALLBACK."
  (let ((state (gethash grade-id gptel-auto-experiment--grade-state)))
    (when (gptel-auto-workflow--state-active-p state)
      (puthash grade-id (plist-put state :done t)
               gptel-auto-experiment--grade-state)
      (when (and cancel-timer
                 (timerp (plist-get state :timer)))
        (cancel-timer (plist-get state :timer)))
      (let ((result (gptel-auto-experiment--normalize-grade-result result)))
        (unwind-protect
            (my/gptel--invoke-callback-safely callback result)
          (remhash grade-id gptel-auto-experiment--grade-state)))
      t)))

(defun gptel-auto-experiment--build-grading-output (output &optional target worktree)
  "Augment OUTPUT with concrete worktree evidence for grading.
When TARGET and WORKTREE are available, include git status and a diff excerpt
so the grader can inspect the actual edit instead of relying only on the
executor's prose summary."
  (let* ((base-output (if (stringp output) output (format "%s" output)))
         (resolved-target (or target gptel-auto-experiment--grading-target))
         (resolved-worktree (or worktree gptel-auto-experiment--grading-worktree))
         (reasoning-evidence (gptel-auto-experiment--extract-verify-evidence base-output)))
    (if (or (not (gptel-auto-workflow--non-empty-string-p resolved-target))
            (not (gptel-auto-workflow--non-empty-string-p resolved-worktree))
            (not (file-directory-p resolved-worktree)))
        (if reasoning-evidence
            (format "%s\n\nVERIFICATION EVIDENCE FROM <think>:\n%s"
                    base-output reasoning-evidence)
          base-output)
      (let* ((default-directory resolved-worktree)
             (target-q (shell-quote-argument resolved-target))
             (status-result
              (gptel-auto-workflow--git-result
               (format "git status --short -- %s" target-q) 30))
             (diff-result
              (gptel-auto-workflow--git-result
               (format "git diff --unified=2 -- %s" target-q) 30))
             (status-output (string-trim (car status-result)))
             (diff-output (string-trim (car diff-result)))
             (status-text
              (if (and (= (cdr status-result) 0)
                       (not (string-empty-p status-output)))
                  status-output
                "No pending git status for target"))
              (compile-output (when (and (gptel-auto-workflow--non-empty-string-p resolved-target)
                                        (string-suffix-p ".el" resolved-target))
                               (let* ((target-path (expand-file-name resolved-target))
                                      (cmd (format "emacs -batch -Q -L . -L lisp/modules -f batch-byte-compile %s 2>&1"
                                                  (shell-quote-argument target-path)))
                                      (r (gptel-auto-workflow--git-result cmd 10)))
                                 (if (= (cdr r) 0)
                                     "Byte-compile: clean"
                                   (format "Byte-compile: %s" (string-trim (or (car r) "failed")))))))
              (diff-text
              (cond
               ((/= (cdr diff-result) 0)
                (format "git diff failed: %s"
                        (my/gptel--sanitize-for-logging (car diff-result) 200)))
               ((string-empty-p diff-output)
                "No diff captured for target")
               ((> (length diff-output) 3000)
                (concat (substring diff-output 0 3000) "\n...[truncated]"))
               (t diff-output))))
        (format "%s\n\nWORKTREE EVIDENCE:\n- Target: %s\n- Byte-compile: %s\n- Git status:\n%s\n- Diff excerpt:\n%s%s"
                base-output
                resolved-target
                (or compile-output "skipped")
                status-text
                diff-text
                (if reasoning-evidence
                    (format "\n\nVERIFICATION EVIDENCE FROM <think>:\n%s" reasoning-evidence)
                  ""))))))

(defun gptel-auto-experiment--extract-verify-evidence (output)
  "Extract verification command evidence from OUTPUT's <think> blocks.
Searches for mentions of byte-compile, syntax check, load test, nucleus,
or test commands in reasoning sections.  Returns a formatted string or nil."
  (when (and (stringp output) (string-match-p "<think>" output))
    (let ((evidence-lines nil)
          (verify-keywords
           '("byte-compile" "syntax" "load test" "check-parens"
             "nucleus" "run-tests" "verify" "emacs -Q" "batch" "ert"))
          (in-think nil))
      (with-temp-buffer
        (insert output)
        (goto-char (point-min))
        (while (not (eobp))
          (let* ((line (buffer-substring-no-properties
                        (line-beginning-position) (line-end-position)))
                 (starts-think (string-match-p "<think>" line))
                 (ends-think (string-match-p "</think>" line))
                 (has-evidence
                  (let ((case-fold-search t))
                    (catch 'match
                      (dolist (kw verify-keywords)
                        (when (string-match-p kw line)
                          (throw 'match t)))
                      nil))))
            (when (and has-evidence
                       (or in-think starts-think))
              (push (string-trim line) evidence-lines))
            (when starts-think (setq in-think t))
            (when ends-think (setq in-think nil)))
          (forward-line 1)))
      (when evidence-lines
        (let ((lines (nreverse evidence-lines)))
          (while (> (length lines) 15)
            (setq lines (butlast lines)))
          (mapconcat #'identity lines "\n"))))))

(defun gptel-auto-experiment--target-pending-changes-p (target &optional worktree)
  "Return non-nil when TARGET has pending git changes in WORKTREE."
  (let ((resolved-target target)
        (resolved-worktree worktree))
    (and (gptel-auto-workflow--non-empty-string-p resolved-target)
         (gptel-auto-workflow--non-empty-string-p resolved-worktree)
         (file-directory-p resolved-worktree)
         (let* ((default-directory resolved-worktree)
                (status-result
                 (gptel-auto-workflow--git-result
                  (format "git status --short -- %s"
                          (shell-quote-argument resolved-target))
                  30))
                (status-output (string-trim (car status-result))))
           (and (= (cdr status-result) 0)
                (not (string-empty-p status-output)))))))

(defun gptel-auto-experiment--executor-timeout-p (error-output)
  "Return non-nil when ERROR-OUTPUT reports an explicit executor timeout."
  (and (stringp error-output)
       (string-match-p
        "timed out after [0-9]+s\\(?: idle timeout ([-0-9.]+s total runtime)\\| total runtime\\)?\\.?"
        error-output)))

(defun gptel-auto-experiment--timeout-salvage-output (output prompt target &optional worktree)
  "Return synthetic executor output when timed-out error OUTPUT left real
valid target edits.  PROMPT is the original executor prompt.  TARGET and
WORKTREE identify the actual edited file.
Returns nil (no salvage) when pending changes are syntactically broken,
avoiding wasted retry cycles on corrupted files."
  (when (and (gptel-auto-experiment--agent-error-p output)
             (gptel-auto-experiment--executor-timeout-p output)
             (gptel-auto-experiment--target-pending-changes-p target worktree))
    ;; Validate pending changes before salvaging — broken parens or syntax
    ;; errors from a timed-out executor are not worth salvaging.
    (let* ((target-file (expand-file-name target (or worktree default-directory)))
           (validation-error (when (file-exists-p target-file)
                               (gptel-auto-experiment--validate-code target-file))))
      (if validation-error
          (progn
            (message "[auto-exp] ⏱ Timed-out executor left BROKEN changes in %s (%s); reverting instead of salvaging"
                     target validation-error)
            (when worktree
              (let ((default-directory worktree))
                (magit-git-success "checkout" "--" ".")))
            nil)
        ;; Pending changes are valid — salvage them
        (let* ((raw-hypothesis (gptel-auto-experiment--extract-hypothesis prompt))
               (hypothesis
                (if (or (not (gptel-auto-workflow--non-empty-string-p raw-hypothesis))
                        (member raw-hypothesis '("Agent error" "No hypothesis stated")))
                    (format "Timed-out executor left partial changes in %s for workflow evaluation"
                            target)
                  raw-hypothesis)))
          (format
           (concat
            "HYPOTHESIS: %s\n"
            "CHANGED:\n"
            "- Executor timed out before returning a final response, but the worktree contains pending changes for %s.\n"
            "EVIDENCE:\n"
            "- Treat the concrete worktree diff below as the source of truth for this partial attempt.\n"
            "- Original timeout: %s\n"
            "VERIFY:\n"
            "- Run the normal benchmark and required tests against the changed worktree.\n"
            "COMMIT:\n"
            "- No commit was created before timeout; only keep the change if benchmark and review gates pass.\n"
            "Task completed with partial work ready for workflow evaluation.")
           hypothesis
           target
           (my/gptel--sanitize-for-logging output 200)))))))

(defun gptel-auto-experiment-grade (output callback &optional target worktree)
  "Grade experiment OUTPUT. LLM decides quality threshold.
Timeout fails the grade (conservative).
If OUTPUT is an error message, fails immediately with error details.
Uses hash table keyed by grade-id to support parallel execution.
The grader subagent overlay will appear in the current buffer at time of call.
TARGET and WORKTREE let the grader inspect concrete git evidence."
  (let ((grade-id (setq gptel-auto-experiment--grade-counter (1+ gptel-auto-experiment--grade-counter)))
        (grade-buffer (current-buffer)))
    (cl-block gptel-auto-experiment-grade
      ;; Blind mode: grader is broken, auto-pass without API call
      (when (and (boundp 'gptel-auto-workflow--blind-mode)
                 gptel-auto-workflow--blind-mode)
        (message "[auto-exp] BLIND MODE: skipping grader, auto-pass")
        (my/gptel--invoke-callback-safely
         callback (list :score 4 :total 5 :percentage 80.0 :passed t
                        :details "blind-mode-auto-pass"
                        :grader-only-failure t))
        (cl-return-from gptel-auto-experiment-grade))
      ;; Nil or empty output: fail immediately, don't waste an API call
      (when (or (null output)
                (and (stringp output) (string-empty-p (string-trim output))))
        (message "[auto-exp] Skipping grader: nil or empty executor output")
        (my/gptel--invoke-callback-safely
         callback (list :score 0 :total 1 :percentage 0.0 :passed nil
                        :details "no-executor-output"
                        :grader-only-failure t))
        (cl-return-from gptel-auto-experiment-grade))
      (when (gptel-auto-experiment--agent-error-p output)
        (let* ((error-snippet (if (stringp output)
                                  (my/gptel--sanitize-for-logging output 200)
                                "Unknown error"))
               (error-category (car (gptel-auto-experiment--categorize-error output))))
          (message "[auto-exp] Executor error detected: %s" error-snippet)
          (my/gptel--invoke-callback-safely
           callback (list :score 0 :total 1 :percentage 0.0 :passed nil
                           :details (format "Agent error: %s" error-snippet)
                           :error-category error-category))
          (cl-return-from gptel-auto-experiment-grade)))
      ;; Quota exhausted: skip grading, no backend can respond
      (when (bound-and-true-p gptel-auto-experiment--quota-exhausted)
        (message "[auto-exp] Quota exhausted, skipping grader")
        (my/gptel--invoke-callback-safely
          callback (list :score 0 :total 1 :percentage 0.0 :passed nil
                         :details "quota-exhausted"
                         :quota-exhausted t))
        (cl-return-from gptel-auto-experiment-grade))
      (puthash grade-id (list :done nil :timer nil)
               gptel-auto-experiment--grade-state)
      (let ((timeout-timer
             (run-with-timer
              gptel-auto-experiment-grade-timeout nil
              (lambda ()
                (let ((state (gethash grade-id
                                      gptel-auto-experiment--grade-state)))
                  (when (gptel-auto-workflow--state-active-p state)
                    (message "[auto-exp] Grading timeout after %ds — AUTO-PASS to prevent destruction"
                             gptel-auto-experiment-grade-timeout)
                    ;; CRITICAL FIX: timeout means grader couldn't evaluate,
                    ;; NOT that code is bad. Auto-pass prevents 0%% keep rate.
                    (gptel-auto-experiment--finish-grade
                     grade-id callback
                     (list :score 4 :total 5 :percentage 80.0 :passed t
                           :details "Grader timeout — auto-pass to prevent experiment destruction"
                           :grader-only-failure t))))))))
        (puthash grade-id (list :done nil :timer timeout-timer)
                 gptel-auto-experiment--grade-state))
      (if (and gptel-auto-experiment-use-subagents
               (fboundp 'gptel-benchmark-grade))
          ;; Ensure grader dispatch cannot strand the experiment without a
          ;; result when routing/prompt construction fails synchronously.
          (condition-case err
              (with-current-buffer grade-buffer
                (gptel-benchmark-grade
                 (gptel-auto-experiment--build-grading-output output target worktree)
                 '("change clearly described"
                   "change is minimal and focused"
                   "improves code: fixes bug, improves performance, addresses TODO/FIXME, or enhances clarity/testability"
                   "verification attempted (byte-compile, syntax, load-test, nucleus, or tests — also check VERIFICATION EVIDENCE FROM <think> section and <think> reasoning blocks)")
                 '("large refactor unrelated to stated improvement"
                   "changed security files without review"
                   "no description or unclear purpose"
                   "style-only change without functional impact"
                   "replaces working code without clear improvement")
                 (lambda (result)
                   (gptel-auto-experiment--finish-grade
                    grade-id callback result t))
                 gptel-auto-experiment-grade-timeout))
            (error
             (message "[auto-exp] Grader dispatch failed: %s"
                      (my/gptel--sanitize-for-logging
                       (error-message-string err) 200))
             (gptel-auto-experiment--finish-grade
              grade-id callback
              (list :score 0 :total 1 :percentage 0.0 :passed nil
                    :details (format "Error: grader dispatch failed: %s"
                                     (error-message-string err))
                    :error-source (format "Error: grader dispatch failed: %s"
                                          (error-message-string err))
                    :grader-only-failure t)
              t)))
        (gptel-auto-experiment--finish-grade
         grade-id callback (list :score 100 :passed t) t)))))

(defun gptel-auto-experiment--parse-comparator-winner (response)
  "Return comparator winner token parsed from RESPONSE, or nil."
  (when (stringp response)
    (let ((case-fold-search t))
      (cond
       ((string-match "^\\s-*A\\b" response) "A")
       ((string-match "^\\s-*B\\b" response) "B")
       ((string-match "^\\s-*tie\\b" response) "tie")))))

(defun gptel-auto-experiment--expected-comparator-winner (combined-before combined-after &optional threshold)
  "Return the winner implied by COMBINED-BEFORE vs COMBINED-AFTER.
THRESHOLD defaults to 0.005 and matches the comparator prompt rules."
  (unless (and (numberp combined-before) (numberp combined-after))
    (setq combined-before (or (and (numberp combined-before) combined-before) 0))
    (setq combined-after (or (and (numberp combined-after) combined-after) 0)))
  (let* ((decision-threshold (or threshold 0.005))
         (combined-delta (- combined-after combined-before)))
    (cond
     ((>= combined-delta decision-threshold) "B")
     ((<= combined-delta (- decision-threshold)) "A")
     (t "tie"))))

(defun gptel-auto-experiment--coerce-number (value default)
  "Return VALUE as a number, or DEFAULT if conversion fails.
Handles strings by converting via `string-to-number', returning DEFAULT
for empty strings or non-numeric strings."
  (cond
   ((numberp value) value)
   ((stringp value)
    (let ((num (string-to-number value)))
      (if (= num 0)
          (if (string-match-p "\\`[[:space:]]*0\\(?:[.,]0*\\)?[[:space:]]*\\'" value)
              num
            (or default 0))
        num)))
   (t (or default 0))))

(defun gptel-auto-experiment--decision-gate
    (winner score-before score-after quality-before quality-after combined-before combined-after
            &optional threshold)
  "Return gated comparator decision metadata for WINNER.

The gate rejects changes whose combined score (60% eight-keys + 40% code
quality) regresses.  A small eight-keys score dip is tolerated when code
quality improves enough to lift the combined score above threshold.

For high-baseline targets (quality >= 0.85), the quality gain requirement
is reduced because well-written code is harder to improve measurably."
  (let* ((score-before (gptel-auto-experiment--coerce-number score-before 0))
         (score-after (gptel-auto-experiment--coerce-number score-after 0))
         (quality-before (gptel-auto-experiment--coerce-number quality-before 0.5))
         (quality-after (gptel-auto-experiment--coerce-number quality-after 0.5))
         (combined-before (gptel-auto-experiment--coerce-number combined-before 0))
         (combined-after (gptel-auto-experiment--coerce-number combined-after 0))
         (decision-threshold (or threshold 0.005))
         (score-delta (- score-after score-before))
         (quality-delta (- quality-after quality-before))
         (combined-delta (- combined-after combined-before))
         ;; Adjust quality gain threshold based on baseline quality
         (quality-gain-threshold
          (cond
           ;; Very high baseline: accept any non-negative quality change
           ((>= quality-before 0.90) 0.0)
           ;; High baseline: require minimal gain
           ((>= quality-before 0.85) 0.001)
           ;; Normal baseline: standard threshold
           (t gptel-auto-experiment-min-quality-gain-on-score-tie))))
    (cond
     ;; Combined score regression: reject outright regardless of individual deltas
     ((<= combined-delta (- decision-threshold))
      (list :winner "A"
            :note "Rejected: combined score regressed"))
     ;; Score regressed but combined score improves: quality gain compensates
     ((< score-delta (- decision-threshold))
      (if (> combined-delta decision-threshold)
          (list :winner "B"
                :note (format "Kept: quality gain (%.2f) compensates for score regression (%.3f)"
                              quality-delta score-delta))
        (list :winner "A"
              :note "Rejected: score regressed without sufficient combined improvement")))
     ;; Score tie (within decision threshold)
     ((< (abs score-delta) decision-threshold)
      (if (and (> combined-delta 0)
               (>= quality-delta quality-gain-threshold))
          (list :winner "B"
                :note (format "Kept: score tie with >= %.3f quality gain (baseline %.2f)"
                              quality-gain-threshold quality-before))
        (list :winner "A"
              :note (if (<= combined-delta 0)
                        "Rejected: score tie without positive combined improvement"
                      (format "Rejected: score tie without >= %.3f quality gain (baseline %.2f, got %.3f)"
                              quality-gain-threshold quality-before quality-delta)))))
     ;; Score improved: accept
     (t
      (list :winner (if (string= winner "tie") "B" winner)
            :note (and (string= winner "tie")
                       "Kept: score improved despite combined tie"))))))

;; ─── Think-Block Intelligence ───

(require 'subr-x)  ; for string-trim

(defun gptel-auto-experiment--extract-think-blocks (output)
  "Extract all <think>...</think> blocks from OUTPUT.
Returns list of strings, each a single think block's content."
  (when (stringp output)
    (let ((result nil)
          (start 0))
      (while (string-match "<think>" output start)
        (let ((block-start (match-end 0))
              (block-end (when (string-match "</think>" output (match-end 0))
                           (match-beginning 0))))
          (when block-end
            (push (string-trim (substring output block-start block-end)) result)
            (setq start (match-end 0)))
          (unless block-end
            (push (string-trim (substring output block-start)) result)
            (setq start (length output)))))
      (nreverse result))))

(defun gptel-auto-experiment--classify-think-blocks (blocks)
  "Classify each think BLOCK into a reasoning category.
Returns plist: (:categories LIST :dominant SYMBOL :score FLOAT :verdict STRING)."
  (let ((categories nil)
        (scores nil)
        (patterns
         '(;; Category: planning — agent is strategizing
           (planning . ("let me plan" "i need to" "first.*then" "step[s]?"
                        "approach" "strategy" "before.*implement"
                        "create a plan" "what.*need to do"))
           ;; Category: exploring — agent is reading/investigating
           (exploring . ("let me (read|look|check|find|search|see|examine|understand)"
                         "let.s (read|look|check|find|search|see|examine|understand)"
                         "i don.t see" "what does" "how does"
                         "let me.*open" "let me.*file"
                         "reading.*file" "to understand"))
           ;; Category: acting — agent is making changes
           (acting . ("i.ll (edit|write|change|modify|fix|add|remove|replace|update|refactor)"
                      "let me.*(edit|write|change|modify|fix|add)"
                      "making.*change" "apply.*patch"
                      "i.(ve| have) (made|changed|fixed|added)"))
           ;; Category: verifying — agent is testing
           (verifying . ("byte.compile" "check.parens" "run.*(test|verify)"
                         "syntax.*(check|ok)" "compile.*(pass|fail|error)"
                         "verify.*(works|pass)" "tests.*pass"))
           ;; Category: confused — agent doesn't know what to do
           (confused . ("i.m not sure" "i don.t (know|understand)" "this is (unclear|confusing)"
                        "what (should|am i)" "need more (context|information)"
                        "i think.*but" "not sure what"))
           ;; Category: self-correcting — agent realizes mistake
           (self-correcting . ("actually" "wait" "on second thought" "let me (rethink|reconsider|redo)"
                               "that.s wrong" "i made a mistake" "that didn.t work"
                               "let me try (again|differently)")))))
    (dolist (block blocks)
      (let ((lower (downcase block))
            (best-category 'exploring)
            (best-score 0))
        (dolist (entry patterns)
          (let ((cat (car entry))
                (kws (cdr entry)))
            (dolist (kw kws)
              (when (string-match-p kw lower)
                (let ((hits (length (split-string lower kw t))))
                  (when (> (1- hits) best-score)
                    (setq best-category cat
                          best-score (1- hits))))))))
        (push best-category categories)
        (push best-score scores)))
    (let* ((counts (make-hash-table))
           (total-score 0))
      (dolist (cat categories)
        (puthash cat (1+ (gethash cat counts 0)) counts))
      (dolist (s scores)
        (setq total-score (+ total-score s)))
      (let* ((dominant
              (let ((best (car categories))
                    (best-n 0))
                (maphash (lambda (cat n) (when (> n best-n) (setq best cat best-n n))) counts)
                best))
             (act-count (or (gethash 'acting counts) 0))
             (explore-count (or (gethash 'exploring counts) 0))
             (confused-count (or (gethash 'confused counts) 0))
             (plan-count (or (gethash 'planning counts) 0))
             (n-blocks (length blocks))
             (reasoning-score
              ;; Higher score = more likely to succeed
              (/ (+ (* act-count 3.0)   ; acting is best
                    (* (- n-blocks plan-count explore-count confused-count) 1.0)
                    ;; Penalize no action
                    (if (and (> n-blocks 3) (= act-count 0)) -3.0 0.0)
                    ;; Penalize confusion
                    (* confused-count -2.0))
                 (max n-blocks 1)))
             (verdict
              (cond
               ((= act-count 0)
                (cond
                 ((> confused-count 2) "STUCK-CONFUSED: agent does not understand task")
                 ((> explore-count 2) "STUCK-EXPLORING: agent reads but never edits")
                 ((> plan-count 2) "STUCK-PLANNING: agent plans but never acts")
                 (t "STUCK-NO-ACTION: agent never attempted code changes")))
               ((> act-count 2) "ACTIVE: agent made multiple edit attempts")
               ((> act-count 0) "PROGRESS: agent made at least one edit")
               (t "UNKNOWN"))))
        (list :categories categories
              :dominant dominant
              :acts act-count
              :explores explore-count
              :confused confused-count
              :plans plan-count
              :n-blocks n-blocks
              :score reasoning-score
              :verdict verdict)))))

(defun gptel-auto-experiment--analyze-agent-output (output)
  "Analyze agent OUTPUT to extract think-block intelligence.
Returns plist suitable for experiment result enrichment."
  (let* ((blocks (gptel-auto-experiment--extract-think-blocks output))
         (analysis (when blocks
                     (gptel-auto-experiment--classify-think-blocks blocks))))
    (if analysis
        (progn
          (message "[think-intel] %s (n=%d acts=%d explores=%d confused=%d score=%.1f)"
                   (plist-get analysis :verdict)
                   (plist-get analysis :n-blocks)
                   (plist-get analysis :acts)
                   (plist-get analysis :explores)
                   (plist-get analysis :confused)
                   (plist-get analysis :score))
          analysis)
      (list :verdict "NO-THINK" :score 0.0))))

(provide 'gptel-tools-agent-benchmark)
;;; gptel-tools-agent-benchmark.el ends here
