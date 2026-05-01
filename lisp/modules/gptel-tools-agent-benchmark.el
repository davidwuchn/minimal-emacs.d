;;; gptel-tools-agent-benchmark.el --- Benchmark, evaluation, scoring -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

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
           "copilot-auto-workflow-test-"
           (list "VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1")))
         (isolated-status-file (getenv "AUTO_WORKFLOW_STATUS_FILE"))
         (test-script (expand-file-name "scripts/run-tests.sh" worktree))
         (output-buffer (generate-new-buffer "*test-output*"))
         result)
    (unwind-protect
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
                result))))
      (when (buffer-live-p output-buffer)
        (kill-buffer output-buffer))
      (when (file-exists-p isolated-status-file)
        (delete-file isolated-status-file)))))

(defcustom gptel-auto-experiment-require-tests t
  "When non-nil, require tests to pass before merging experiment to staging.
This catches bugs that the grader might miss (e.g., CL idioms that don't work in ELisp).
Set to nil to disable (only for emergency situations)."
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

(defcustom gptel-auto-experiment-max-changed-files 3
  "Maximum number of files an experiment can change.
Prevents scope creep where executor touches many unrelated files.
Set to 0 to disable the check."
  :type 'integer
  :group 'gptel-auto-workflow)
(defcustom gptel-auto-workflow-protected-configs
  '(("assistant/agents/code_agent.md" . "minimax-m2.7-highspeed")
    ("assistant/agents/plan_agent.md" . "minimax-m2.7-highspeed")
    ("assistant/agents/comparator.md" . "minimax-m2.7-highspeed")
    ("assistant/agents/explorer_agent.md" . "minimax-m2.7-highspeed")
    ("assistant/agents/introspector.md" . "minimax-m2.7-highspeed"))
  "Protected configuration files and their expected values.
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
        (when (and (= 0 (cdr staging-content))
                   (= 0 (cdr experiment-content)))
          (let ((staging-has-it (string-match-p (regexp-quote expected)
                                                (car staging-content)))
                (experiment-has-it (string-match-p (regexp-quote expected)
                                                   (car experiment-content))))
            (when (and staging-has-it (not experiment-has-it))
              (push (format "%s: lost %s" file expected) regressions))))))
    (if regressions
        (progn
          (message "[auto-workflow] ⚠ Protected config regression detected: %s"
                   (mapconcat #'identity regressions "; "))
          (cons nil (mapconcat #'identity regressions "; ")))
      (cons t nil))))


(defun gptel-auto-experiment--check-scope ()
  "Return (ok-p . changed-files) for current experiment.
Checks that the number of changed files is within limits."
  (let* ((worktree (gptel-auto-workflow--worktree-or-project-dir))
         (changed-files (shell-command-to-string
                         (format "cd %s && git diff --name-only HEAD~1 2>/dev/null"
                                 (shell-quote-argument worktree))))
         (files (split-string changed-files "\n" t))
         (count (length files)))
    (if (and (> gptel-auto-experiment-max-changed-files 0)
             (> count gptel-auto-experiment-max-changed-files))
        (progn
          (message "[auto-exp] ⚠ Scope creep detected: %d files changed (max: %d)"
                   count gptel-auto-experiment-max-changed-files)
          (cons nil files))
      (cons t files))))

(defun gptel-auto-experiment-benchmark (&optional skip-tests)
  "Run syntax validation + Eight Keys scoring.
  If SKIP-TESTS is non-nil, skip test execution (tests run in staging flow).
  Returns plist with :passed, :tests-passed, :eight-keys, etc.

NOTE: Nucleus script validation is skipped for experiments because:
1. verify-nucleus.sh uses script location ($DIR), not worktree context
2. Executor already runs verification in worktree context
3. Full validation happens in staging flow

IMPORTANT: When `gptel-auto-experiment-require-tests' is non-nil (default),
tests still run before the experiment is considered passed, even if SKIP-TESTS
is t. The exception is the normal headless staging workflow, where benchmark
tests are deferred to the staging gate to keep the worker daemon alive."
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
             (final-tests-output (or (and baseline-check (cdr baseline-check))
                                     tests-output))
             (scores (gptel-auto-experiment--eight-keys-scores)))
        (when defer-tests-to-staging
          (message "[auto-exp] Deferring tests to staging flow for %s"
                   (or gptel-auto-workflow--current-target default-directory)))
        (when (and skip-tests gptel-auto-experiment-require-tests)
          (message "[auto-exp] Tests required before staging merge: %s"
                   (if tests-passed "PASS" "FAIL")))
        (list :passed tests-passed
              :nucleus-passed t
              :nucleus-skipped t
              :tests-passed tests-passed
              :tests-output final-tests-output
              :tests-skipped (not should-run-tests)
              :time (- (float-time) start)
              :eight-keys (when scores (alist-get 'overall scores))
              :eight-keys-scores scores)))))

(defun gptel-auto-experiment--eight-keys-scores ()
  "Get full Eight Keys scores alist from current codebase.
Scores based on commit message + code diff (not just stat)."
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
      (gptel-benchmark-eight-keys-score output))))

(defun gptel-auto-experiment--eight-keys-score ()
  "Get Eight Keys overall score from current codebase."
  (let ((scores (gptel-auto-experiment--eight-keys-scores)))
    (when scores (alist-get 'overall scores))))

(defun gptel-auto-experiment--code-quality-score ()
  "Get code quality score from current changes."
  (when (fboundp 'gptel-benchmark--code-quality-score)
    (let* ((worktree (gptel-auto-workflow--worktree-or-project-dir))
           ;; SECURITY: Use shell-quote-argument to prevent shell injection
           (worktree-quoted (shell-quote-argument worktree))
           (changed-files (shell-command-to-string
                           (format "cd %s && git diff --name-only HEAD~1 2>/dev/null | grep '\\.el$'"
                                   worktree-quoted))))
      (when (string-match-p "\\.el$" (string-trim-right changed-files))
        (let ((total-score 0.0)
              (file-count 0))
          (dolist (file (split-string changed-files "\n" t))
            (let* ((filepath (expand-file-name file worktree))
                   (content (gptel-auto-workflow--read-file-contents filepath)))
              (when content
                (cl-incf total-score (gptel-benchmark--code-quality-score content))
                (cl-incf file-count))))
          (if (> file-count 0)
              (/ total-score file-count)
            0.5))))))

;;; Subagent Integrations

(defun gptel-auto-experiment--call-in-context (buffer directory fn &optional run-root)
  "Call FN in BUFFER with DIRECTORY bound as `default-directory'.
When RUN-ROOT is non-nil, preserve that workflow root for async callbacks that
resume from buffers outside the original project context."
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
   ((listp value) (not (null value)))
   (t t)))

(defun gptel-auto-experiment--analysis-list (value)
  "Return VALUE as a list for analyzer prompt composition."
  (cond
   ((null value) nil)
   ((vectorp value) (append value nil))
   ((listp value) value)
   (t (list value))))

(defun gptel-auto-experiment--summarize-previous-results (previous-results)
  "Return a prompt-friendly summary string for PREVIOUS-RESULTS."
  (when previous-results
    (mapconcat
     (lambda (result)
       (let* ((experiment-id (gptel-auto-workflow--plist-get result :id "?"))
              (decision (gptel-auto-experiment--tsv-decision-label result))
              (hypothesis
               (truncate-string-to-width
                (gptel-auto-experiment--tsv-escape
                 (gptel-auto-workflow--plist-get result :hypothesis "unknown"))
                220 nil nil "...")))
         (format "- Experiment %s: %s - %s"
                 experiment-id decision hypothesis)))
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
               (string= (gptel-auto-experiment--tsv-decision-label result)
                        "discarded"))
             previous-results)
        (push "At least one prior attempt was discarded as no improvement; pivot to a different function, defect, or improvement type."
              recommendations))
      (when (cl-some
             (lambda (result)
               (member (gptel-auto-experiment--tsv-decision-label result)
                       '("tests-failed"
                         "validation-failed"
                         "inspection-thrash"
                         "repeated-focus-symbol"
                         "retry-grade-failed")))
             previous-results)
        (push "At least one prior attempt failed validation/tests; avoid editing the same code path again unless the new change directly fixes that failure."
              recommendations))
      (list :patterns (gptel-auto-experiment--summarize-previous-results
                       previous-results)
            :issues nil
            :recommendations (nreverse (delete-dups recommendations))))))

(defun gptel-auto-experiment--merge-analysis (analysis previous-results)
  "Merge ANALYSIS with deterministic history from PREVIOUS-RESULTS."
  (let* ((fallback (gptel-auto-experiment--fallback-analysis previous-results))
         (patterns (if (gptel-auto-experiment--analysis-value-present-p
                        (plist-get analysis :patterns))
                       (plist-get analysis :patterns)
                     (plist-get fallback :patterns)))
         (issues (if (gptel-auto-experiment--analysis-value-present-p
                      (plist-get analysis :issues))
                     (plist-get analysis :issues)
                   (plist-get fallback :issues)))
         (recommendations
          (delete-dups
           (append (gptel-auto-experiment--analysis-list
                    (plist-get analysis :recommendations))
                   (gptel-auto-experiment--analysis-list
                    (plist-get fallback :recommendations))))))
    (when (or (gptel-auto-experiment--analysis-value-present-p patterns)
              (gptel-auto-experiment--analysis-value-present-p issues)
              recommendations)
      (list :patterns patterns
            :issues issues
            :recommendations recommendations))))

(defcustom gptel-auto-experiment-repeat-focus-threshold 2
  "Prior non-kept attempts on the same changed symbol before short-circuiting repeats."
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
            (when (and (stringp candidate)
                       (string-match-p "--\\|::" candidate)
                       (not (string-match-p "\\.el\\'" candidate)))
              (push candidate symbols))))))
    (nreverse (cl-remove-duplicates symbols :test #'string=))))

(defun gptel-auto-experiment--repeated-focus-match (output previous-results)
  "Return plist when OUTPUT repeats a changed symbol in PREVIOUS-RESULTS.
Only counts prior non-kept results and triggers once a symbol appears in at
least `gptel-auto-experiment-repeat-focus-threshold' previous attempts."
  (let ((current-symbols (gptel-auto-experiment--extract-focus-symbols output)))
    (when current-symbols
      (let ((counts (make-hash-table :test 'equal))
            matches)
        (dolist (result previous-results)
          (unless (gptel-auto-workflow--plist-get result :kept nil)
            (dolist (symbol
                     (gptel-auto-experiment--extract-focus-symbols
                      (gptel-auto-workflow--plist-get result :agent-output "")))
              (puthash symbol (1+ (gethash symbol counts 0)) counts))))
        (dolist (symbol current-symbols)
          (let ((count (gethash symbol counts 0)))
            (when (>= count gptel-auto-experiment-repeat-focus-threshold)
              (push (cons symbol count) matches))))
        (when matches
          (let* ((sorted (sort matches (lambda (a b) (> (cdr a) (cdr b)))))
                 (best (car sorted)))
            (list :symbol (car best)
                  :count (cdr best)
                  :matches (nreverse sorted))))))))

(defun gptel-auto-experiment--subagent-raw-result (result)
  "Return raw transient error text from RESULT, or nil when unavailable."
  (cond
   ((stringp result) result)
   ((and (listp result)
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
    (agent-type invoke callback &optional retries)
  "Invoke AGENT-TYPE via INVOKE, retrying transient failures before CALLBACK.

INVOKE is called with a single callback argument and must start the actual
subagent request."
  (funcall
   invoke
   (lambda (result)
     (let* ((attempt (or retries 0))
            (category
             (gptel-auto-experiment--retryable-aux-subagent-category result))
            (raw (gptel-auto-experiment--subagent-raw-result result)))
       (if (and category
                (< attempt gptel-auto-experiment-max-aux-subagent-retries))
           (progn
             (when-let ((preset
                         (gptel-auto-experiment--current-subagent-preset
                          agent-type)))
               (gptel-auto-workflow--activate-provider-failover
                agent-type preset raw))
             (message "[auto-exp] %s failed transiently (%s), retrying (%d/%d)"
                      agent-type category
                      (1+ attempt) gptel-auto-experiment-max-aux-subagent-retries)
             (gptel-auto-experiment--call-aux-subagent-with-retry
              agent-type invoke callback (1+ attempt)))
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

(defvar gptel-auto-experiment-grade-timeout 120
  "Timeout in seconds for grading subagent.
Default 120s (2 min) allows grader to process complex outputs.")

(defun gptel-auto-experiment--reset-grade-state ()
  "Cancel and clear all pending grade callbacks."
  (maphash
   (lambda (_grade-id state)
     (when (timerp (plist-get state :timer))
       (cancel-timer (plist-get state :timer))))
   gptel-auto-experiment--grade-state)
  (clrhash gptel-auto-experiment--grade-state))

(defun gptel-auto-experiment--invalid-cl-return-target-in-forms (forms &optional blocks)
  "Return the first invalid `cl-return-from' target in FORMS.
BLOCKS is the list of block names currently in scope."
  (cond
   ((null forms) nil)
   ((listp forms)
    (cl-some (lambda (form)
               (gptel-auto-experiment--invalid-cl-return-target form blocks))
             forms))
   (t
    (gptel-auto-experiment--invalid-cl-return-target forms blocks))))

(defun gptel-auto-experiment--invalid-cl-return-target (form &optional blocks)
  "Return the first invalid `cl-return-from' target in FORM.
BLOCKS is the list of block names currently in scope."
  (cond
   ((atom form) nil)
   ((not (listp form)) nil)
   (t
    (pcase (car form)
      ((or 'quote 'quasiquote 'backquote) nil)
      ('cl-return-from
          (let ((target (nth 1 form)))
            (or (and (symbolp target)
                     (not (memq target blocks))
                     target)
                (gptel-auto-experiment--invalid-cl-return-target-in-forms
                 (nthcdr 2 form) blocks))))
      ('cl-block
          (let ((name (nth 1 form)))
            (gptel-auto-experiment--invalid-cl-return-target-in-forms
             (nthcdr 2 form)
             (if (symbolp name) (cons name blocks) blocks))))
      ((or 'cl-defun 'cl-defmacro 'cl-defsubst)
       (let ((name (nth 1 form))
             (body (nthcdr 3 form)))
         (gptel-auto-experiment--invalid-cl-return-target-in-forms
          body
          (if (symbolp name) (cons name blocks) blocks))))
      ((or 'cl-labels 'cl-flet)
       (let ((bindings (nth 1 form))
             (body (nthcdr 2 form)))
         (or (cl-some
              (lambda (binding)
                (when (and (consp binding) (symbolp (car binding)))
                  (let ((name (car binding))
                        (fbody (cddr binding)))
                    (gptel-auto-experiment--invalid-cl-return-target-in-forms
                     fbody
                     (cons name blocks)))))
              bindings)
             (gptel-auto-experiment--invalid-cl-return-target-in-forms
              body blocks))))
      (_
       (or (gptel-auto-experiment--invalid-cl-return-target (car form) blocks)
           (gptel-auto-experiment--invalid-cl-return-target-in-forms
            (cdr form) blocks)))))))

(defun gptel-auto-experiment--removed-diff-lines (file)
  "Return removed diff lines for FILE relative to HEAD, or nil.
Only real removed lines are returned; diff headers such as --- a/file are
excluded.  If FILE is not in a Git worktree, return nil."
  (when-let* ((absolute-file (expand-file-name file))
              (root (locate-dominating-file absolute-file ".git")))
    (let* ((default-directory root)
           (relative-file (file-relative-name absolute-file root))
           (diff (shell-command-to-string
                  (format "git --no-pager diff --no-ext-diff --unified=0 HEAD -- %s 2>/dev/null"
                          (shell-quote-argument relative-file)))))
      (cl-loop for line in (split-string diff "\n")
               when (and (string-prefix-p "-" line)
                         (not (string-prefix-p "---" line)))
               collect (substring line 1)))))

(defun gptel-auto-experiment--defensive-code-removal-p (removed-lines)
  "Return non-nil if REMOVED-LINES delete defensive JSON fallbacks.
REMOVED-LINES must be lines removed by an actual diff, not final file content."
  (let ((patterns
         '("cdr\\s-*(assoc\\s-+\""
           "assoc\\s-+\"[^\"]+\"")))
    (cl-some (lambda (line)
               (cl-some (lambda (pattern)
                          (string-match-p pattern line))
                        patterns))
             removed-lines)))

(defun gptel-auto-experiment--validate-code (file)
  "Validate code in FILE for syntax and dangerous patterns.
Returns nil if valid, or error message string if invalid."
  (when (and (stringp file) (string-suffix-p ".el" file))
    (if (not (file-exists-p file))
        (format "Missing target file: %s" file)
      (let ((content (gptel-auto-workflow--read-file-contents file))
            forms)
        (or (cond
             ((null content)
              (format "Empty or unreadable file: %s" file))
             ((condition-case err
                  (with-temp-buffer
                    (insert content)
                    (set-syntax-table emacs-lisp-mode-syntax-table)
                    (goto-char (point-min))
                    (while (progn
                             (forward-comment (point-max))
                             (< (point) (point-max)))
                      (push (read (current-buffer)) forms))
                    nil)
                (error (format "Syntax error in %s: %s" file err)))))
            (when (gptel-auto-experiment--invalid-cl-return-target-in-forms
                   (nreverse forms))
              (format "Dangerous pattern in %s: cl-return-from without cl-block" file))
            ;; Check removed diff lines, not final content, for deleted fallbacks.
            (when (gptel-auto-experiment--defensive-code-removal-p
                   (gptel-auto-experiment--removed-diff-lines file))
              (format "Defensive code removal detected in %s: removing or/assoc fallbacks without proof" file)))))))

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
      (unwind-protect
          (my/gptel--invoke-callback-safely callback result)
        (remhash grade-id gptel-auto-experiment--grade-state))
      t)))

(defun gptel-auto-experiment--build-grading-output (output &optional target worktree)
  "Augment OUTPUT with concrete worktree evidence for grading.
When TARGET and WORKTREE are available, include git status and a diff excerpt
so the grader can inspect the actual edit instead of relying only on the
executor's prose summary."
  (let* ((base-output (if (stringp output) output (format "%s" output)))
         (resolved-target (or target gptel-auto-experiment--grading-target))
         (resolved-worktree (or worktree gptel-auto-experiment--grading-worktree)))
    (if (or (not (gptel-auto-workflow--non-empty-string-p resolved-target))
            (not (gptel-auto-workflow--non-empty-string-p resolved-worktree))
            (not (file-directory-p resolved-worktree)))
        base-output
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
        (format "%s\n\nWORKTREE EVIDENCE:\n- Target: %s\n- Git status:\n%s\n- Diff excerpt:\n%s"
                base-output
                resolved-target
                status-text
                diff-text)))))

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
  "Return synthetic executor output when timed-out error OUTPUT left real target edits.
PROMPT is the original executor prompt so the salvage path can preserve the
intended hypothesis. TARGET and WORKTREE identify the actual edited file."
  (when (and (gptel-auto-experiment--agent-error-p output)
             (gptel-auto-experiment--executor-timeout-p output)
             (gptel-auto-experiment--target-pending-changes-p target worktree))
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
       (my/gptel--sanitize-for-logging output 200)))))

(defun gptel-auto-experiment-grade (output callback &optional target worktree)
  "Grade experiment OUTPUT. LLM decides quality threshold.
Timeout fails the grade (conservative).
If OUTPUT is an error message, fails immediately with error details.
Uses hash table keyed by grade-id to support parallel execution.
The grader subagent overlay will appear in the current buffer at time of call.
TARGET and WORKTREE let the grader inspect concrete git evidence."
  (let ((grade-id (cl-incf gptel-auto-experiment--grade-counter))
        (grade-buffer (current-buffer)))
    (cl-block gptel-auto-experiment-grade
      (when (gptel-auto-experiment--agent-error-p output)
        (let* ((error-snippet (if (stringp output)
                                  (my/gptel--sanitize-for-logging output 200)
                                "Unknown error"))
               (error-category (car (gptel-auto-experiment--categorize-error output))))
          (message "[auto-exp] Executor error detected: %s" error-snippet)
          (my/gptel--invoke-callback-safely
           callback (list :score 0 :passed nil
                          :details (format "Agent error: %s" error-snippet)
                          :error-category error-category))
          (cl-return-from gptel-auto-experiment-grade)))
      (puthash grade-id (list :done nil :timer nil)
               gptel-auto-experiment--grade-state)
      (let ((timeout-timer
             (run-with-timer
              gptel-auto-experiment-grade-timeout nil
              (lambda ()
                (let ((state (gethash grade-id
                                      gptel-auto-experiment--grade-state)))
                  (when (gptel-auto-workflow--state-active-p state)
                    (message "[auto-exp] Grading timeout after %ds, failing"
                             gptel-auto-experiment-grade-timeout)
                    (gptel-auto-experiment--finish-grade
                     grade-id callback
                     (list :score 0 :passed nil :details "timeout"))))))))
        (puthash grade-id (list :done nil :timer timeout-timer)
                 gptel-auto-experiment--grade-state))
      (if (and gptel-auto-experiment-use-subagents
               (fboundp 'gptel-benchmark-grade))
          ;; Ensure grader runs in the captured buffer context so overlay appears in right place
          (with-current-buffer grade-buffer
            (gptel-benchmark-grade
             (gptel-auto-experiment--build-grading-output output target worktree)
             '("change clearly described"
               "change is minimal and focused"
               "improves code: fixes bug, improves performance, addresses TODO/FIXME, or enhances clarity/testability"
               "verification attempted (byte-compile, nucleus, tests, or manual)")
             '("large refactor unrelated to stated improvement"
               "changed security files without review"
               "no description or unclear purpose"
               "style-only change without functional impact"
               "replaces working code without clear improvement")
             (lambda (result)
               (gptel-auto-experiment--finish-grade
                grade-id callback result t))
             gptel-auto-experiment-grade-timeout))
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
  (let* ((decision-threshold (or threshold 0.005))
         (combined-delta (- combined-after combined-before)))
    (cond
     ((>= combined-delta decision-threshold) "B")
     ((<= combined-delta (- decision-threshold)) "A")
     (t "tie"))))

(defun gptel-auto-experiment--decision-gate
    (winner score-before score-after quality-before quality-after combined-before combined-after
            &optional threshold)
  "Return gated comparator decision metadata for WINNER.

The gate rejects any score regression, and also rejects score ties unless code
quality improves by at least
`gptel-auto-experiment-min-quality-gain-on-score-tie' while the combined score
still improves."
  (let* ((decision-threshold (or threshold 0.005))
         (score-delta (- score-after score-before))
         (quality-delta (- quality-after quality-before))
         (combined-delta (- combined-after combined-before)))
    (cond
     ((<= score-delta (- decision-threshold))
      (list :winner "A"
            :note "Rejected: score regressed"))
     ((< (abs score-delta) decision-threshold)
      (if (and (> combined-delta 0)
               (>= quality-delta gptel-auto-experiment-min-quality-gain-on-score-tie))
          (list :winner "B"
                :note (format "Kept: score tie with >= %.2f quality gain"
                              gptel-auto-experiment-min-quality-gain-on-score-tie))
        (list :winner "A"
              :note (if (<= combined-delta 0)
                        "Rejected: score tie without positive combined improvement"
                      (format "Rejected: score tie without >= %.2f quality gain"
                              gptel-auto-experiment-min-quality-gain-on-score-tie)))))
     (t
      (list :winner (if (string= winner "tie") "B" winner)
            :note (and (string= winner "tie")
                       "Kept: score improved despite combined tie"))))))

(provide 'gptel-tools-agent-benchmark)
;;; gptel-tools-agent-benchmark.el ends here
