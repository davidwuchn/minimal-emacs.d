; -*- lexical-binding: t; -*-
(declare-function gptel-auto-experiment--promote-correctness-fix-decision "gptel-tools-agent-prompt-analyze")
(declare-function magit-git-success "magit-git")
(declare-function gptel-auto-experiment--extract-axis "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--stale-run-p "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--stale-run-result "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--hash-get-bound "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--resolve-run-root "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--track-commit "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--call-in-context "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--code-quality-score "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--repeated-focus-match "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--timeout-salvage-output "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment-analyze "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment-benchmark "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--categorize-error "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--grade-failure-error-output "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--grade-with-retry "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--grader-only-error-label "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--grader-only-failure-p "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--extract-hypothesis "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--make-retry-prompt "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--prepare-validation-retry-worktree "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--summarize "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--teachable-validation-error-p "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--create-provisional-experiment-commit "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--drop-provisional-commit "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--promote-provisional-commit "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--stage-worktree-changes "gptel-tools-agent-experiment-loop")
(declare-function my/gptel--sanitize-for-logging "gptel-tools-agent-git")
(declare-function gptel-auto-experiment--normal-grade-details-p "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-experiment-decide "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-experiment--make-kept-result-callback "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-experiment--maybe-log-staging-pending "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-experiment-build-prompt "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-experiment-log-tsv "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--push-branch-with-lease "gptel-tools-agent-staging-merge")
(declare-function gptel-auto-workflow--staging-flow "gptel-tools-agent-staging-merge")
(declare-function gptel-auto-workflow--branch-name "gptel-tools-agent-subagent")
(declare-function gptel-auto-workflow--get-current-branch "gptel-tools-agent-subagent")
(declare-function my/gptel--run-agent-tool-with-timeout "gptel-tools-agent-subagent")
(declare-function gptel-auto-experiment--validate-code "gptel-tools-agent-validation")
(declare-function gptel-auto-workflow--assert-main-untouched "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow-create-worktree "gptel-tools-agent-worktree")
;;; gptel-tools-agent-experiment-core.el --- Single experiment execution -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defvar gptel-auto-workflow--current-target)
(defvar gptel-auto-experiment-time-budget)
(defvar gptel-auto-workflow--run-id)
(defvar gptel-auto-experiment--no-improvement-count)
(defvar gptel-auto-experiment--grading-target)
(defvar gptel-auto-experiment--grading-worktree)
(defvar gptel-auto-experiment-validation-retry-active-grace)
(defvar gptel-auto-experiment-validation-retry-time-budget)
(defvar gptel-auto-workflow-git-timeout)
(defvar gptel-auto-experiment--best-score)
(defvar gptel-auto-experiment-auto-push)
(defvar gptel-auto-workflow-use-staging)
(defvar gptel-auto-experiment--in-retry)
(defvar gptel-auto-experiment-active-grace)
(defvar gptel-auto-workflow-executor-rate-limit-fallbacks)
(defvar gptel-auto-workflow--rate-limited-backends)
(defvar gptel-model)
(defvar gptel-backend)

(defun gptel-auto-experiment--validate-all-modified-files (worktree)
  "Validate all modified .el files in WORKTREE.
Returns nil if all pass, or error message string for first failure."
  (let ((default-directory worktree)
        (modified-files (ignore-errors
                          (split-string
                           (shell-command-to-string
                            "git diff --name-only HEAD 2>/dev/null")
                           "\n" t))))
    (catch 'validation-error
      (dolist (file modified-files)
        (when (and (string-suffix-p ".el" file)
                   (not (string-suffix-p "-autoloads.el" file)))
          (let ((full-path (expand-file-name file worktree)))
            (when (file-exists-p full-path)
              (let ((error (gptel-auto-experiment--validate-code full-path)))
                (when error
                  (message "[auto-exp] ✗ Validation failed for %s: %s"
                           file
                           (my/gptel--sanitize-for-logging error 120))
                  (throw 'validation-error
                         (format "%s in %s" error file)))))))))))

(defun gptel-auto-experiment--maybe-failover-main-backend ()
  "Switch `gptel-backend' to a fallback if the current one is rate-limited.
Checks `gptel-auto-workflow--rate-limited-backends' and uses
`gptel-auto-workflow-executor-rate-limit-fallbacks' to find an alternative."
  (when (and (boundp 'gptel-backend) gptel-backend
             (fboundp 'gptel-backend-name)
             (fboundp 'gptel-auto-workflow--backend-rate-limited-p)
             (fboundp 'gptel-auto-workflow--first-available-provider-candidate)
             (fboundp 'gptel-auto-workflow--backend-object))
    (let* ((current-name (gptel-auto-workflow--safe-backend-name gptel-backend))
           (is-limited (gptel-auto-workflow--backend-rate-limited-p current-name)))
      (when is-limited
        (if-let* ((fallback (gptel-auto-workflow--first-available-provider-candidate
                             gptel-auto-workflow-executor-rate-limit-fallbacks
                             gptel-auto-workflow--rate-limited-backends))
                  (new-backend (gptel-auto-workflow--backend-object (car fallback)))
                  (new-model (intern (cdr fallback))))
            (progn
              (setq gptel-backend new-backend
                    gptel-model new-model)
              (message "[auto-experiment] Main backend switched from %s to %s/%s (rate-limited)"
                       current-name (car fallback) (cdr fallback)))
          (message "[auto-experiment] Main backend %s is rate-limited but no fallback available"
                   current-name))))))

(defun gptel-auto-experiment-run (target experiment-id max-experiments baseline baseline-code-quality previous-results callback &optional log-fn)
  "Run single experiment. Call CALLBACK with result plist.
BASELINE-CODE-QUALITY is the initial code quality score.
LOG-FN receives deferred results as (RUN-ID EXPERIMENT)."
  ;; Clear per-experiment provider overrides so MiniMax gets first crack
  ;; at each new experiment. Rate-limited backends still stay blacklisted.
  (when (fboundp 'gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
    (gptel-auto-workflow--clear-runtime-subagent-provider-overrides))
  ;; Switch main backend if it's been rate-limited, or switch BACK if quota
  ;; reset window has elapsed while this daemon was running.
  (gptel-auto-experiment--maybe-failover-main-backend)
  (when (fboundp 'gptel-auto-experiment--check-quota-reset-and-switch-back)
    (gptel-auto-experiment--check-quota-reset-and-switch-back))
  (message "[auto-experiment] Starting %d/%d for %s" experiment-id max-experiments target)
  (setq gptel-auto-workflow--current-target target)
  (let* ((worktree (gptel-auto-workflow-create-worktree target experiment-id))
         (experiment-worktree (or worktree default-directory))
         (experiment-buffer (and worktree
                                 (fboundp 'gptel-auto-workflow--get-worktree-buffer)
                                 (ignore-errors
                                   (gptel-auto-workflow--get-worktree-buffer
                                    experiment-worktree))))
         (experiment-branch (or (gptel-auto-workflow--get-current-branch target)
                                (gptel-auto-workflow--branch-name target experiment-id)))
         ;; CRITICAL: Set default-directory to worktree so all subagents
         ;; operate in the correct context. Each worktree = one session.
         (default-directory experiment-worktree)
         (log-fn (or log-fn #'gptel-auto-experiment-log-tsv))
          ;; Get project buffer for overlay routing (ensure hash table exists)
          (_project-buf (when (and (boundp 'gptel-auto-workflow--current-project)
                                   gptel-auto-workflow--current-project)
                          (gptel-auto-workflow--hash-get-bound
                           'gptel-auto-workflow--project-buffers
                           (expand-file-name gptel-auto-workflow--current-project))))
          ;; Disable preview for headless auto-workflow
          (_gptel-tools-preview-enabled nil)
          ;; Disable tool confirmations for headless auto-workflow
          (_gptel-confirm-tool-calls nil)
         ;; Capture the experiment timeout lexically because later analyzer
         ;; callbacks run after this outer let frame exits.
         (experiment-timeout gptel-auto-experiment-time-budget)
         (run-id gptel-auto-workflow--run-id)
         (workflow-root (gptel-auto-workflow--resolve-run-root))
          ;; The subagent timeout wrapper owns executor timeout/abort behavior.
          (_my/gptel-agent-task-timeout experiment-timeout)
          (start-time (float-time))
          (finished nil)
          (provisional-commit-hash nil)
          (executor-prompt nil)
          (executor-callback nil)
          (validation-retry-active nil)
          (experiment-backend nil)
          (experiment-model nil))
    (if (not worktree)
        (funcall callback (list :target target :error "Failed to create worktree" :backend "none"))
      (gptel-auto-experiment--call-in-context
       experiment-buffer experiment-worktree
       (lambda ()
         (gptel-auto-experiment-analyze
          previous-results
          (lambda (analysis)
            (gptel-auto-experiment--call-in-context
             experiment-buffer experiment-worktree
             (lambda ()
                 (let* ((patterns (when (proper-list-p analysis) (plist-get analysis :patterns)))
                       ;; Select prompt-building strategy based on historical performance
                       (strategy-name (if (and (boundp 'gptel-auto-workflow--strategy-evolution-enabled)
                                               gptel-auto-workflow--strategy-evolution-enabled
                                               (fboundp 'gptel-auto-workflow--select-best-strategy))
                                          (gptel-auto-workflow--select-best-strategy target)
                                        "template-default"))
                       (prompt (if (and (fboundp 'gptel-auto-experiment-build-prompt-with-strategy)
                                        (not (equal strategy-name "template-default")))
                                   (gptel-auto-experiment-build-prompt-with-strategy
                                    strategy-name target experiment-id max-experiments analysis baseline previous-results)
                                 (gptel-auto-experiment-build-prompt
                                  target experiment-id max-experiments analysis baseline previous-results))))
                  (message "[strategy] Using strategy '%s' for %s experiment %d" strategy-name target experiment-id)
                  ;; Trace strategy execution
                  (when (fboundp 'gptel-auto-workflow--trace-strategy-execution)
                    (gptel-auto-workflow--trace-strategy-execution
                     strategy-name
                     target
                     (length prompt)
                     (and (boundp 'gptel-auto-workflow--last-prompt-sections)
                          (split-string gptel-auto-workflow--last-prompt-sections ","))))
                  (setq executor-prompt prompt)
               (setq executor-callback
                     (lambda (agent-output)
                   (gptel-auto-experiment--call-in-context
                    experiment-buffer experiment-worktree
                    (lambda ()
                      (if (gptel-auto-experiment--stale-run-p run-id)
                        (unless finished
                          (setq finished t)
                          (message "[auto-experiment] Ignoring stale executor callback for %s experiment %d; run %s is no longer active"
                                   target experiment-id run-id)
                          (funcall callback
                                   (gptel-auto-experiment--stale-run-result
                                    target experiment-id)))
                      (let* ((salvaged-agent-output
                              (gptel-auto-experiment--timeout-salvage-output
                               agent-output executor-prompt target experiment-worktree))
                              (effective-agent-output
                               (or salvaged-agent-output agent-output))
                              ;; Capture actual backend AFTER executor completes.
                               ;; gptel-backend may have been dynamically rebound by
                               ;; cl-progv inside the subagent task override — after
                               ;; the callback runs, the global default (MiniMax) is
                               ;; restored.  Fall back to the pre-computed
                               ;; experiment-backend when gptel-backend is MiniMax
                               ;; (the interactive default, not the routed one).
                               (actual-backend
                                (let* ((post-backend (and (boundp 'gptel-backend) gptel-backend
                                                         (fboundp 'gptel-backend-name)
                                                         (gptel-auto-workflow--safe-backend-name gptel-backend)))
                                       (pre-backend (and (stringp experiment-backend)
                                                         experiment-backend))
                                       (global-default "MiniMax"))
                                  (if (and (stringp post-backend)
                                           (not (string= post-backend global-default)))
                                      post-backend
                                    (or pre-backend post-backend global-default))))
                              (actual-model
                               (or (and (boundp 'gptel-model) gptel-model)
                                   experiment-model))
                              (candidate-validation
                               (when (fboundp 'gptel-auto-experiment--batch-validate-candidates)
                                 (condition-case err
                                     (gptel-auto-experiment--batch-validate-candidates
                                      effective-agent-output
                                      (expand-file-name target experiment-worktree))
                                   (error
                                    (message "[auto-exp] Candidate validation error: %s" err)
                                    nil))))
                              (repeated-focus
                               (gptel-auto-experiment--repeated-focus-match
                                effective-agent-output previous-results target)))
                          (when candidate-validation
                             (let ((best-score (plist-get (cdar candidate-validation) :score)))
                              (message "[auto-exp] Validated %d candidates for %s, best score: %.2f"
                                       (length candidate-validation) target (or best-score 0.0))))
                         (when salvaged-agent-output
                          (message "[auto-exp] Executor timed out after partial changes for %s; evaluating actual worktree diff"
                                   target))
                        (message "[auto-exp] Agent output (first 150 chars): %s"
                                 (my/gptel--sanitize-for-logging effective-agent-output 150))
                        (unless finished
                          (if repeated-focus
                              (let* ((hypothesis
                                      (gptel-auto-experiment--extract-hypothesis
                                       effective-agent-output))
                                     (symbol (plist-get repeated-focus :symbol))
                                     (count (plist-get repeated-focus :count))
                                     (reason
                                      (format "Repeated focus on `%s` after %d prior non-kept attempts; choose a different function or subsystem."
                                              symbol count))
                                      (exp-result
                                       (list :target target
                                             :id experiment-id
                                             :hypothesis hypothesis
                                             :score-before baseline
                                             :score-after 0
                                             :code-quality baseline-code-quality
                                             :kept nil
                                             :duration (- (float-time) start-time)
                                             :grader-quality 0
                                             :grader-reason reason
                                             :comparator-reason "repeated-focus-symbol"
                                             :analyzer-patterns (format "%s" patterns)
                                             :agent-output effective-agent-output
                                             :backend actual-backend
                          :model actual-model)))
                                (setq finished t)
                                (let ((default-directory experiment-worktree))
                                  (message "[auto-exp] Repeated focus on %s after %d prior non-kept attempts; discarding without grading"
                                           symbol count)
                                  (magit-git-success "checkout" "--" "."))
                                  (cl-incf gptel-auto-experiment--no-improvement-count)
                                  (when (fboundp 'gptel-auto-workflow--apply-category-vigilance)
                                    (gptel-auto-workflow--apply-category-vigilance target 'discarded))
                                  (funcall log-fn run-id exp-result)
                                  (funcall callback exp-result))
                              ;; Validate syntax BEFORE calling grader to avoid wasting API calls
                              ;; Check ALL modified files, not just target — agent may edit dependencies
                              (let ((validation-error
                                     (when target
                                       (or (gptel-auto-experiment--validate-all-modified-files experiment-worktree)
                                           (gptel-auto-experiment--validate-code
                                            (expand-file-name target experiment-worktree))))))
                                (if validation-error
                                   (progn
                                     (message "[auto-exp] ✗ Pre-grade validation failed: %s"
                                              (my/gptel--sanitize-for-logging validation-error 200))
                                     ;; Trigger retry or fail immediately without grader
                                       (let ((default-directory experiment-worktree)
                                             (_gptel-auto-experiment--grading-target target)
                                             (_gptel-auto-experiment--grading-worktree experiment-worktree))
                                        (if (and (gptel-auto-experiment--teachable-validation-error-p
                                                  target validation-error)
                                                 (not validation-retry-active))
                                            (progn
                                              (message "[auto-experiment] Validation failed with teachable pattern, retrying...")
                                              (gptel-auto-experiment--prepare-validation-retry-worktree
                                               target provisional-commit-hash)
                                              (setq provisional-commit-hash nil)
                                              (setq validation-retry-active t)
                                               (let* ((_gptel-auto-experiment-active-grace
                                                       gptel-auto-experiment-validation-retry-active-grace)
                                                      (retry-prompt
                                                       (if candidate-validation
                                                           (concat executor-prompt
                                                                   "\n\n## PREVIOUS ATTEMPT FAILED\n"
                                                                   "Validation error: " validation-error "\n"
                                                                   "Candidate validation results:\n"
                                                                   (mapconcat
                                                                    (lambda (pair)
                                                                      (format "- %s: score=%.1f, valid=%s"
                                                                              (substring (car pair) 0 (min 30 (length (car pair))))
                                                                              (or (plist-get (cdr pair) :score) 0.0)
                                                                              (if (plist-get (cdr pair) :valid) "yes" "no")))
                                                                    candidate-validation
                                                                    "\n")
                                                                     "\n## INSTRUCTIONS FOR RETRY\n"
                                                                     "The previous implementation failed validation. "
                                                                     "If you have remaining valid candidates, implement one of those instead. "
                                                                     "Otherwise, fix the validation error while keeping the same approach.\n\n"
                                                                     "## CRITICAL: AVOID INSPECTION-THRASH\n"
                                                                     "You have LIMITED read-only inspections before the system aborts your turn.\n"
                                                                     "- Use at most 2 read-only tool calls to locate the issue\n"
                                                                     "- Your NEXT call MUST be a write (Edit, ApplyPatch) to fix the error\n"
                                                                     "- Do NOT re-read the entire file or do broad analysis\n"
                                                                     "- Fix the specific validation error immediately\n"
                                                                     "\n## DANGEROUS PATTERNS TO AVOID\n"
                                                                     "- NEVER use `cl-return-from` without a matching `cl-block` wrapper\n"
                                                                     "- NEVER remove `cl-block` while keeping `cl-return-from` inside\n"
                                                                     "- ALWAYS ensure `cl-return-from` targets a valid `cl-block` name\n")
                                                           (concat executor-prompt
                                                                   "\n\n## CRITICAL: AVOID INSPECTION-THRASH\n"
                                                                   "You have LIMITED read-only inspections before the system aborts your turn.\n"
                                                                   "- Use at most 2 read-only tool calls to locate the issue\n"
                                                                   "- Your NEXT call MUST be a write (Edit, ApplyPatch) to fix the error\n"
                                                                   "- Do NOT re-read the entire file or do broad analysis\n"
                                                                   "- Fix the specific validation error immediately\n"
                                                                   "\n## DANGEROUS PATTERNS TO AVOID\n"
                                                                   "- NEVER use `cl-return-from` without a matching `cl-block` wrapper\n"
                                                                   "- NEVER remove `cl-block` while keeping `cl-return-from` inside\n"
                                                                   "- ALWAYS ensure `cl-return-from` targets a valid `cl-block` name\n"))))
                                                (my/gptel--run-agent-tool-with-timeout
                                                 gptel-auto-experiment-validation-retry-time-budget
                                                 (lambda (retry-output)
                                                   (if (and (stringp retry-output)
                                                            (string-match-p "\\`Error:" retry-output))
                                                       ;; Retry failed: fail experiment immediately, skip grading/staging
                                                       (let* ((hypothesis
                                                               (gptel-auto-experiment--extract-hypothesis
                                                                effective-agent-output))
                                                              (retry-exp-result
                                                               (list :target target
                                                                     :id experiment-id
                                                                     :hypothesis hypothesis
                                                                     :score-before baseline
                                                                     :score-after 0
                                                                     :code-quality baseline-code-quality
                                                                     :kept nil
                                                                     :duration (- (float-time) start-time)
                                                                     :grader-quality 0
                                                                     :grader-reason (format "validation-retry-failed: %s"
                                                                                           retry-output)
                                                                     :comparator-reason "validation-retry-failed"
                                                                     :analyzer-patterns (format "%s" patterns)
                                                                     :agent-output effective-agent-output
                                                                     :validation-error validation-error
                                                                     :backend actual-backend
                          :model actual-model)))
                                                          (setq finished t)
                                                          (cl-incf gptel-auto-experiment--no-improvement-count)
                                                          (when (fboundp 'gptel-auto-workflow--apply-category-vigilance)
                                                            (gptel-auto-workflow--apply-category-vigilance target 'validation-failed))
                                                          (funcall log-fn run-id retry-exp-result)
                                                          (funcall callback retry-exp-result))
                                                     ;; Retry succeeded: treat output as new executor output
                                                     (funcall executor-callback retry-output)))
                                                 "executor"
                                                 "Validation retry"
                                                 retry-prompt
                                                 nil nil nil
                                                 gptel-auto-experiment-validation-retry-active-grace)))
                                         ;; Non-teachable or already retrying: fail fast
                                         (let* ((hypothesis (gptel-auto-experiment--extract-hypothesis
                                                             effective-agent-output))
                                                 (exp-result
                                                  (list :target target
                                                        :id experiment-id
                                                        :hypothesis hypothesis
                                                        :score-before baseline
                                                        :score-after 0
                                                        :code-quality baseline-code-quality
                                                        :kept nil
                                                        :duration (- (float-time) start-time)
                                                        :grader-quality 0
                                                        :grader-reason validation-error
                                                        :comparator-reason "validation-failed"
                                                        :analyzer-patterns (format "%s" patterns)
                                                        :agent-output effective-agent-output
                                                        :validation-error validation-error
                                                        :backend actual-backend
                          :model actual-model)))
                                            (setq finished t)
                                            (cl-incf gptel-auto-experiment--no-improvement-count)
                                            (when (fboundp 'gptel-auto-workflow--apply-category-vigilance)
                                              (gptel-auto-workflow--apply-category-vigilance target 'validation-failed))
                                            (funcall log-fn run-id exp-result)
                                            (funcall callback exp-result)))))
                                 (let ((gptel-auto-experiment--grading-target target)
                                       (gptel-auto-experiment--grading-worktree experiment-worktree))
                                   (gptel-auto-experiment--grade-with-retry
                               effective-agent-output
                                (lambda (grade)
                                  (gptel-auto-experiment--call-in-context
                                   experiment-buffer experiment-worktree
                                   (lambda ()
                                     (if (gptel-auto-experiment--stale-run-p run-id)
                                       (unless finished
                                         (setq finished t)
                                         (message "[auto-experiment] Ignoring stale grader callback for %s experiment %d; run %s is no longer active"
                                                  target experiment-id run-id)
                                         (funcall callback
                                                  (gptel-auto-experiment--stale-run-result
                                                   target experiment-id)))
                                     (let* ((grade-score (plist-get grade :score))
                                            (grade-total (plist-get grade :total))
                                            (grade-passed (plist-get grade :passed))
                                            (grade-details (plist-get grade :details))
                                            (hypothesis (gptel-auto-experiment--extract-hypothesis effective-agent-output)))
                                       (message "[auto-exp] Grade result: score=%s/%s passed=%s"
                                                grade-score grade-total grade-passed)
                                       (when (and effective-agent-output (> (length effective-agent-output) 0))
                                         (message "[auto-exp] Agent preview: %s"
                                                  (my/gptel--sanitize-for-logging effective-agent-output 100)))
                                       ;; Check if grader passed
                                       (if (not grade-passed)
                                           ;; Grader failures should classify from grader details when
                                           ;; they carry the real transient/API error instead of the
                                           ;; executor's normal success output.
                                           (let* ((normal-grade-rejection
                                                   (gptel-auto-experiment--normal-grade-details-p
                                                    grade-details))
                                                  (grade-error-output
                                                   (and (not normal-grade-rejection)
                                                        (or (plist-get grade :error-source)
                                                            (gptel-auto-experiment--grade-failure-error-output
                                                             grade-details effective-agent-output))))
                                                  (error-source (and (not normal-grade-rejection)
                                                                     (or grade-error-output effective-agent-output)))
                                                  (error-info (and error-source
                                                                   (gptel-auto-experiment--categorize-error
                                                                    error-source)))
                                                  (error-category (car-safe error-info))
                                                  (grader-only-failure
                                                   (and (not normal-grade-rejection)
                                                        (plist-get grade :grader-only-failure))))
                                             (setq finished t)
                                             ;; Log the failure
                                             (let ((exp-result (list :target target
                                                                     :id experiment-id
                                                                     :hypothesis hypothesis
                                                                     :score-before baseline
                                                                     :score-after 0
                                                                     :kept nil
                                                                     :duration (- (float-time) start-time)
                                                                     :grader-quality grade-score
                                                                     :grader-reason grade-details
                                                                     :comparator-reason
                                                                     (cond
                                                                      (normal-grade-rejection
                                                                       "grader-rejected")
                                                                      (grader-only-failure
                                                                       (gptel-auto-experiment--grader-only-error-label
                                                                        error-category))
                                                                      (t
                                                                       (symbol-name (or error-category :unknown))))
                                                                      :analyzer-patterns (format "%s" patterns)
                                                                      :agent-output effective-agent-output
                                                                      :backend actual-backend
                          :model actual-model)))
                                               (when grade-error-output
                                                 (setq exp-result
                                                       (plist-put exp-result :error grade-error-output)))
                                               (when grader-only-failure
                                                 (setq exp-result
                                                       (plist-put exp-result :grader-only-failure t)))
                                               (funcall log-fn
                                                        run-id exp-result)
                                               (funcall callback exp-result)))
                                         ;; Grader passed - create a provisional commit so the
                                         ;; benchmark/scope logic can diff against HEAD~1.
                                         (let ((default-directory experiment-worktree))
                                           (setq provisional-commit-hash
                                                 (gptel-auto-workflow--create-provisional-experiment-commit
                                                  target hypothesis
                                                  (max 300 gptel-auto-workflow-git-timeout))))
                                          (let* ((bench (gptel-auto-experiment-benchmark t hypothesis))
                                                (passed (plist-get bench :passed))
                                                (validation-error (plist-get bench :validation-error))
                                                (tests-passed (plist-get bench :tests-passed))
                                                (score-after (plist-get bench :eight-keys)))
                                           (if passed
                                               (let
	                                               ((code-quality
	                                                 (or (gptel-auto-experiment--code-quality-score) 0.5)))
                                                 (gptel-auto-experiment-decide
                                                  (list :score baseline :code-quality baseline-code-quality)
                                                  (list :score score-after :code-quality code-quality :output
	                                                    effective-agent-output)
                                                  (lambda (decision)
	                                                (unless finished
	                                                  (setq finished t)
	                                                  (let*
	                                                      ((decision
	                                                        (gptel-auto-experiment--promote-correctness-fix-decision
	                                                         decision
	                                                         tests-passed
	                                                         grade-score
	                                                         grade-total
	                                                         grade-details
	                                                         hypothesis))
	                                                       (keep (plist-get decision :keep))
		                                                   (reasoning (plist-get decision :reasoning))
												   (exp-result
												    (list :target target :id experiment-id :hypothesis
												          hypothesis :score-before baseline :score-after
												          score-after :code-quality code-quality :kept
												          keep :duration (- (float-time) start-time)
												          :grader-quality grade-score :grader-reason
												          (plist-get grade :details) :comparator-reason
												          reasoning :analyzer-patterns
												          (format "%s" patterns) :agent-output
												          effective-agent-output
                          :backend actual-backend
                          :model actual-model
                          :prompt-chars (length executor-prompt)
                          :prompt-structure (gptel-auto-experiment--prompt-structure-score executor-prompt)
                           :kibcm-axis (gptel-auto-experiment--kibcm-axis hypothesis)
                          :sections-included (or (and (boundp 'gptel-auto-workflow--last-prompt-sections)
                                                      gptel-auto-workflow--last-prompt-sections)
                                                "all")
                          :exploration-axis (gptel-auto-experiment--extract-axis effective-agent-output)
                           :candidate-validation (when candidate-validation
                                                   (mapcar (lambda (pair)
                                                             (list (car pair)
                                                                   :score (plist-get (cdr pair) :score)
                                                                   :valid (plist-get (cdr pair) :valid)))
                                                           candidate-validation))
                           :strategy strategy-name
                           :research-strategy (or (and (boundp 'gptel-auto-workflow--current-research-context)
                                                       (plist-get gptel-auto-workflow--current-research-context :strategy))
                                                  "none")
                            :research-hash (or (and (boundp 'gptel-auto-workflow--current-research-context)
                                                    (plist-get gptel-auto-workflow--current-research-context :hash))
                                               "none")
                            :research-quality (or (and (boundp 'gptel-auto-workflow--current-research-context)
                                                      (plist-get gptel-auto-workflow--current-research-context :source))
                                                 "none"))))
	                                                    (if keep
		                                                    (let* ((msg
			                                                        (format
			                                                         "◈ Optimize %s: %s\n\nHYPOTHESIS: %s\n\nEVIDENCE: Nucleus valid, tests in staging\nScore: %.2f → %.2f (+%.0f%%)"
			                                                         target
			                                                         (gptel-auto-experiment--summarize hypothesis)
			                                                         hypothesis baseline score-after
			                                                         (if (> baseline 0)
			                                                             (* 100
				                                                            (/ (- score-after baseline) baseline))
			                                                           0)))
			                                                       (default-directory experiment-worktree)
			                                                       (commit-timeout
			                                                        (max 300 gptel-auto-workflow-git-timeout))
			                                                       (finalize
			                                                        (gptel-auto-experiment--make-kept-result-callback
			                                                         run-id exp-result log-fn callback)))
		                                                      (gptel-auto-workflow--assert-main-untouched)
		                                                      (message "[auto-experiment] ✓ Committing improvement for %s" target)
		                                                      (if (and (gptel-auto-workflow--stage-worktree-changes
			                                                            (format "Stage experiment changes for %s" target)
			                                                            60)
			                                                           (gptel-auto-workflow--promote-provisional-commit
			                                                            msg
			                                                            (format "Commit experiment changes for %s" target)
			                                                            provisional-commit-hash
			                                                            commit-timeout))
                                                          (progn
                                                        (setq provisional-commit-hash nil)
                                                        (gptel-auto-workflow--track-commit experiment-id
								                                           target
								                                           experiment-worktree)
                                                        (gptel-auto-experiment--maybe-log-staging-pending
								                                     run-id exp-result log-fn)
                                                        (when (fboundp 'gptel-auto-workflow--apply-category-vigilance)
                                                          (gptel-auto-workflow--apply-category-vigilance target 'kept))
                                                        ;; π Synthesis: queue similar targets with inherited strategy
                                                        (when (fboundp 'gptel-auto-workflow--queue-cluster-experiments)
                                                          (gptel-auto-workflow--queue-cluster-experiments target))
                                                        (setq gptel-auto-experiment--best-score score-after
                                                              gptel-auto-experiment--no-improvement-count 0)
			                                                        (if gptel-auto-experiment-auto-push
			                                                            (progn
			                                                              (message "[auto-experiment] Pushing to %s" experiment-branch)
			                                                              (if (gptel-auto-workflow--push-branch-with-lease
				                                                               experiment-branch
				                                                               (format "Push optimize branch %s" experiment-branch)
				                                                               180)
				                                                              (if gptel-auto-workflow-use-staging
				                                                                  (gptel-auto-workflow--staging-flow
					                                                               experiment-branch
					                                                               finalize)
				                                                                (funcall finalize))
				                                                            (let ((failed-result
					                                                               (plist-put (copy-sequence exp-result)
						                                                                      :comparator-reason
						                                                                      "optimize-push-failed")))
				                                                              (setq failed-result (plist-put failed-result :kept nil))
				                                                              (funcall log-fn run-id failed-result)
				                                                              (funcall callback failed-result))))
			                                                          (funcall finalize)))
		                                                        (let ((failed-result
			                                                           (plist-put (copy-sequence exp-result)
				                                                                  :comparator-reason
				                                                                  "experiment-commit-failed")))
		                                                          (gptel-auto-workflow--drop-provisional-commit
			                                                       provisional-commit-hash
			                                                       (format "Drop provisional commit for %s" target))
		                                                          (setq provisional-commit-hash nil)
		                                                          (setq failed-result (plist-put failed-result :kept nil))
		                                                          (funcall log-fn run-id failed-result)
		                                                          (funcall callback failed-result))))
	                                                      (let ((default-directory experiment-worktree))
		                                                    (message "[auto-experiment] Discarding changes for %s (no improvement)" target)
		                                                    (magit-git-success "checkout" "--" ".")
		                                                    (gptel-auto-workflow--drop-provisional-commit
		                                                     provisional-commit-hash
		                                                     (format "Discard provisional commit for %s" target))
		                                                    (setq provisional-commit-hash nil)
		                                                    (cl-incf gptel-auto-experiment--no-improvement-count)
		                                                    (funcall log-fn
			                                                         run-id exp-result)
		                                                    (funcall callback exp-result))))))))
                                             (if (and (gptel-auto-experiment--teachable-validation-error-p
                                                       target validation-error)
                                                      (not (bound-and-true-p gptel-auto-experiment--in-retry)))
                                                 (let ((default-directory experiment-worktree)
                                                       (gptel-auto-experiment--in-retry t))
                                                   (message "[auto-experiment] Validation failed with teachable pattern, retrying...")
                                                   (message "[auto-experiment] ✗ %s"
                                                            (my/gptel--sanitize-for-logging validation-error 200))
                                                   (gptel-auto-experiment--prepare-validation-retry-worktree
                                                    target provisional-commit-hash)
                                                   (setq provisional-commit-hash nil)
                                                   (let ((gptel-auto-experiment-active-grace
                                                          gptel-auto-experiment-validation-retry-active-grace))
                                                     (my/gptel--run-agent-tool-with-timeout
                                                      gptel-auto-experiment-validation-retry-time-budget
                                                      (lambda (retry-output)
                                                        (let ((gptel-auto-experiment--grading-target target)
                                                              (gptel-auto-experiment--grading-worktree experiment-worktree))
                                                          (gptel-auto-experiment--grade-with-retry
                                                           retry-output
                                                           (lambda (retry-grade)
                                                              (if (plist-get retry-grade :passed)
                                                                   (let* ((retry-hypothesis
                                                                           (gptel-auto-experiment--extract-hypothesis retry-output))
                                                                          (retry-bench (gptel-auto-experiment-benchmark t retry-hypothesis)))
                                                                    (if (plist-get retry-bench :passed)
                                                                        (let* ((retry-score (plist-get retry-bench :eight-keys))
                                                                               (retry-quality
                                                                                (or (gptel-auto-experiment--code-quality-score) 0.5)))
                                                                         (message "[auto-experiment] ✓ Retry succeeded")
                                                                         (gptel-auto-experiment-decide
                                                                          (list :score baseline
                                                                                :code-quality baseline-code-quality)
                                                                          (list :score retry-score
                                                                                :code-quality retry-quality
                                                                                :output retry-output)
                                                                          (lambda (decision)
                                                                            (unless finished
                                                                              (setq finished t)
		                                                                      (let* ((decision
		                                                                              (gptel-auto-experiment--promote-correctness-fix-decision
		                                                                               decision
		                                                                               (plist-get retry-bench :tests-passed)
		                                                                               (plist-get retry-grade :score)
		                                                                               (plist-get retry-grade :total)
		                                                                               (plist-get retry-grade :details)
		                                                                               retry-hypothesis))
		                                                                             (keep (plist-get decision :keep))
		                                                                             (reasoning (plist-get decision :reasoning))
                                                                                             (exp-result
                                                                                              (list :target target
                                                                                             :id experiment-id
                                                                                             :hypothesis retry-hypothesis
                                                                                             :score-before baseline
                                                                                             :score-after retry-score
                                                                                             :code-quality retry-quality
                                                                                             :validation-retry t
                                                                                             :kept keep
                                                                                             :duration (- (float-time) start-time)
                                                                                             :grader-quality (plist-get retry-grade :score)
                                                                                             :grader-reason (plist-get retry-grade :details)
                                                                                             :comparator-reason reasoning
                                                                                             :analyzer-patterns (format "%s" patterns)
                                                                                             :agent-output retry-output
                                                                                             :retries 1
                          :backend actual-backend
                          :model actual-model
                          :model actual-model
                                                                                             :prompt-chars (length executor-prompt)
                           :output-chars (length (or effective-agent-output ""))
                                                                                             :prompt-structure (gptel-auto-experiment--prompt-structure-score executor-prompt)
                           :kibcm-axis (gptel-auto-experiment--kibcm-axis hypothesis)
                                                                                             :exploration-axis (gptel-auto-experiment--extract-axis retry-output)
                                                                                              :candidate-validation (when candidate-validation
                                                                                                                      (mapcar (lambda (pair)
                                                                                                                                (list (car pair)
                                                                                                                                      :score (plist-get (cdr pair) :score)
                                                                                                                                      :valid (plist-get (cdr pair) :valid)))
                                                                                                                              candidate-validation))
                                                                                               :strategy strategy-name)))
                                                                                  (if keep
                                                                                    (let* ((msg (format "◈ Retry: fix validation in %s"
								                                                                        target))
									                                                       (default-directory experiment-worktree)
									                                                       (commit-timeout
									                                                        (max 300 gptel-auto-workflow-git-timeout))
									                                                       (finalize
									                                                        (gptel-auto-experiment--make-kept-result-callback
									                                                         run-id exp-result log-fn callback)))
								                                                      (gptel-auto-workflow--assert-main-untouched)
								                                                      (if (and (gptel-auto-workflow--stage-worktree-changes
									                                                            (format "Stage retry changes for %s" target)
									                                                            60)
									                                                           (gptel-auto-workflow--promote-provisional-commit
									                                                            msg
									                                                            (format "Commit retry changes for %s" target)
									                                                            provisional-commit-hash
									                                                            commit-timeout))
						                                                      (progn
		                                                        (setq provisional-commit-hash nil)
		                                                        (gptel-auto-workflow--track-commit experiment-id
							                                                                               target
							                                                                               experiment-worktree)
                                                                                            (gptel-auto-experiment--maybe-log-staging-pending
                                                                                             run-id exp-result log-fn)
                                                                                            (setq gptel-auto-experiment--best-score retry-score
                                                                                                  gptel-auto-experiment--no-improvement-count 0)
                                                                                            (if gptel-auto-experiment-auto-push
                                                                                                (progn
                                                                                                  (message "[auto-experiment] Pushing to %s" experiment-branch)
                                                                                                  (if (gptel-auto-workflow--push-branch-with-lease
                                                                                                       experiment-branch
                                                                                                       (format "Push optimize branch %s" experiment-branch)
                                                                                                       180)
                                                                                                      (if gptel-auto-workflow-use-staging
                                                                                                          (gptel-auto-workflow--staging-flow
                                                                                                           experiment-branch
                                                                                                           finalize)
                                                                                                        (funcall finalize))
                                                                                                    (let ((failed-result
                                                                                                           (plist-put (copy-sequence exp-result)
                                                                                                                      :comparator-reason
                                                                                                                      "retry-push-failed")))
                                                                                                      (setq failed-result (plist-put failed-result :kept nil))
                                                                                                      (funcall log-fn run-id failed-result)
                                                                                                      (funcall callback failed-result))))
                                                                                              (funcall finalize)))
								                                                        (let ((failed-result
									                                                           (plist-put (copy-sequence exp-result)
											                                                              :comparator-reason
											                                                              "retry-commit-failed")))
									                                                      (gptel-auto-workflow--drop-provisional-commit
									                                                       provisional-commit-hash
									                                                       (format "Drop provisional commit for %s" target))
									                                                      (setq provisional-commit-hash nil)
									                                                      (setq failed-result (plist-put failed-result :kept nil))
									                                                      (funcall log-fn run-id failed-result)
									                                                      (funcall callback failed-result))))
							                                                      (let ((default-directory experiment-worktree))
								                                                    (message "[auto-experiment] Discarding changes for %s (no improvement)" target)
								                                                    (magit-git-success "checkout" "--" ".")
								                                                    (gptel-auto-workflow--drop-provisional-commit
								                                                     provisional-commit-hash
								                                                     (format "Discard provisional commit for %s" target))
								                                                    (setq provisional-commit-hash nil)
								                                                    (cl-incf gptel-auto-experiment--no-improvement-count)
								                                                    (funcall log-fn
									                                                         run-id exp-result)
                                                                                    (funcall callback exp-result))))))))
                                                                     (setq finished t)
                                                                     (message "[auto-experiment] ✗ Retry still failed validation")
                                                                     (let* ((retry-hypothesis
                                                                             (gptel-auto-experiment--extract-hypothesis retry-output))
                                                                            (retry-validation-error
                                                                             (plist-get retry-bench :validation-error))
                                                                            (retry-tests-passed
                                                                             (plist-get retry-bench :tests-passed))
                                                                            (reason
                                                                             (cond
                                                                              (retry-validation-error retry-validation-error)
                                                                              ((not (plist-get retry-bench :nucleus-passed))
                                                                               "nucleus-validation-failed")
                                                                              ((not retry-tests-passed)
                                                                               "tests-failed")
                                                                              (t "verification-failed")))
                                                                            (exp-result
                                                                             (list :target target
                                                                                   :id experiment-id
                                                                                   :hypothesis retry-hypothesis
                                                                                   :score-before baseline
                                                                                   :score-after 0
                                                                                   :validation-retry t
                                                                                   :kept nil
                                                                                   :duration (- (float-time) start-time)
                                                                                   :grader-quality (plist-get retry-grade :score)
                                                                                   :grader-reason (plist-get retry-grade :details)
                                                                                   :comparator-reason reason
                                                                                   :analyzer-patterns (format "%s" patterns)
                                                                                   :agent-output retry-output
                                                                                    :retries 1
                                                                                    :validation-error retry-validation-error
                                                                                    :backend actual-backend
                          :model actual-model)))
                                                                       (funcall log-fn
                                                                                run-id exp-result)
                                                                       (gptel-auto-workflow--drop-provisional-commit
                                                                        provisional-commit-hash
                                                                        (format "Drop provisional commit for %s" target))
                                                                       (setq provisional-commit-hash nil)
                                                                       (funcall callback exp-result))))
                                                               (setq finished t)
                                                               (let* ((retry-hypothesis
                                                                       (gptel-auto-experiment--extract-hypothesis retry-output))
                                                                      (retry-grade-details
                                                                       (plist-get retry-grade :details))
                                                                      (normal-grade-rejection
                                                                       (gptel-auto-experiment--normal-grade-details-p
                                                                        retry-grade-details))
                                                                      (retry-grade-error-output
                                                                       (and (not normal-grade-rejection)
                                                                            (or (plist-get retry-grade :error-source)
                                                                                (gptel-auto-experiment--grade-failure-error-output
                                                                                 retry-grade-details retry-output))))
                                                                      (grader-only-failure
                                                                       (and (not normal-grade-rejection)
                                                                            (or (plist-get retry-grade :grader-only-failure)
                                                                                (gptel-auto-experiment--grader-only-failure-p
                                                                                 retry-output retry-grade-error-output))))
                                                                      (retry-error-category
                                                                       (and retry-grade-error-output
                                                                            (car (gptel-auto-experiment--categorize-error
                                                                                  retry-grade-error-output))))
                                                                      (reason
                                                                       (if retry-grade-error-output
                                                                           (if grader-only-failure
                                                                               (gptel-auto-experiment--grader-only-error-label
                                                                                retry-error-category)
                                                                             (symbol-name (or retry-error-category :unknown)))
                                                                         "retry-grade-rejected"))
                                                                      (exp-result
                                                                       (list :target target
                                                                             :id experiment-id
                                                                             :hypothesis retry-hypothesis
                                                                             :score-before baseline
                                                                             :score-after 0
                                                                             :validation-retry t
                                                                             :kept nil
                                                                             :duration (- (float-time) start-time)
                                                                             :grader-quality (plist-get retry-grade :score)
                                                                             :grader-reason retry-grade-details
                                                                             :comparator-reason reason
                                                                             :analyzer-patterns (format "%s" patterns)
                                                                              :agent-output retry-output
                                                                              :retries 1
                                                                              :backend actual-backend
                          :model actual-model)))
                                                                 (when retry-grade-error-output
                                                                   (setq exp-result
                                                                         (plist-put exp-result :error retry-grade-error-output)))
                                                                 (when grader-only-failure
                                                                   (setq exp-result
                                                                         (plist-put exp-result :grader-only-failure t)))
                                                                 (funcall log-fn
                                                                          run-id exp-result)
                                                                 (gptel-auto-workflow--drop-provisional-commit
                                                                  provisional-commit-hash
                                                                  (format "Drop provisional commit for %s" target))
                                                                 (setq provisional-commit-hash nil)
                                                                 (funcall callback exp-result)))))))
                                                      "executor"
                                                      (format "Retry: fix validation error in %s" target)
                                                      (gptel-auto-experiment--make-retry-prompt
                                                       target validation-error executor-prompt)
								   nil "false" nil
								   gptel-auto-experiment-validation-retry-active-grace)))
                                               (let ((default-directory experiment-worktree))
                                                 (setq finished t)
                                                 (magit-git-success "checkout" "--" ".")
                                                 (gptel-auto-workflow--drop-provisional-commit
                                                  provisional-commit-hash
                                                  (format "Discard provisional commit for %s" target))
                                                 (setq provisional-commit-hash nil)
                                                 (let* ((reason
                                                         (cond (validation-error validation-error)
                                                               ((not (plist-get bench :nucleus-passed))
                                                                "nucleus-validation-failed")
                                                               ((not tests-passed) "tests-failed")
                                                               (t "verification-failed")))
                                                         (exp-result
                                                          (list :target target
                                                                :id experiment-id
                                                                :hypothesis hypothesis
                                                                :score-before baseline
                                                                :score-after 0
                                                                :kept nil
                                                                :duration (- (float-time) start-time)
                                                                :grader-quality grade-score
                                                                :grader-reason (plist-get grade :details)
                                                                :comparator-reason reason
                                                                :analyzer-patterns (format "%s" patterns)
                                                                :agent-output agent-output
                                                                :backend actual-backend
                          :model actual-model
                                                                :prompt-chars (length executor-prompt)
                           :output-chars (length (or effective-agent-output ""))
                                                                 :prompt-structure (gptel-auto-experiment--prompt-structure-score executor-prompt)
                                                                 :kibcm-axis (gptel-auto-experiment--kibcm-axis hypothesis))))
                                                   (message "[auto-experiment] ✗ %s for %s" reason target)
                                                   (funcall log-fn
                                                            run-id exp-result)
                                                   (funcall callback exp-result))))))
                                          ))))))))))))))))
                                    workflow-root))
                ;; Capture the backend and model that will actually be used by the
                ;; executor, including any subagent provider override.
                ;; Note: gptel-auto-workflow--get-active-agent-preset does not exist.
                ;; Use agent-base-preset + maybe-override-subagent-provider directly.
                ;; Wrap in condition-case: agent-base-preset calls into the ranked
                ;; backend chain which may fail if ontology hash tables are unbound.
                (condition-case err
                    (setq experiment-backend
                          (let* ((base-preset
                                  (when (fboundp 'gptel-auto-workflow--agent-base-preset)
                                    (gptel-auto-workflow--agent-base-preset "executor")))
                                 (override-preset
                                  (when (and base-preset
                                             (fboundp 'gptel-auto-workflow--maybe-override-subagent-provider))
                                    (gptel-auto-workflow--maybe-override-subagent-provider "executor" base-preset)))
                                 (effective-preset (or override-preset base-preset))
                                 (effective-backend
                                  (or (and effective-preset
                                           (fboundp 'gptel-auto-workflow--preset-backend-name)
                                           (gptel-auto-workflow--preset-backend-name
                                            (plist-get effective-preset :backend)))
                                      (and (boundp 'gptel-backend) gptel-backend
                                           (fboundp 'gptel-backend-name)
                                           (gptel-auto-workflow--safe-backend-name gptel-backend))
                                      "unknown")))
                            effective-backend))
                  (error
                   (message "[auto-exp] Backend capture failed: %s" (error-message-string err))
                   (setq experiment-backend
                         (and (boundp 'gptel-backend) gptel-backend
                              (fboundp 'gptel-backend-name)
                              (gptel-auto-workflow--safe-backend-name gptel-backend)))))
                (condition-case err
                    (setq experiment-model
                          (let* ((base-preset
                                  (when (fboundp 'gptel-auto-workflow--agent-base-preset)
                                    (gptel-auto-workflow--agent-base-preset "executor")))
                                 (override-preset
                                  (when (and base-preset
                                             (fboundp 'gptel-auto-workflow--maybe-override-subagent-provider))
                                    (gptel-auto-workflow--maybe-override-subagent-provider "executor" base-preset)))
                                 (effective-preset (or override-preset base-preset))
                                 (effective-model
                                  (or (and effective-preset (plist-get effective-preset :model))
                                      (and (boundp 'gptel-model) gptel-model)
                                      "unknown")))
                            (if (stringp effective-model) effective-model
                              (format "%s" effective-model))))
                  (error
                   (message "[auto-exp] Model capture failed: %s" (error-message-string err))
                   (setq experiment-model
                         (and (boundp 'gptel-model) gptel-model
                              (symbol-name gptel-model)))))
                ;; Routing handled by gptel-auto-workflow--advice-task-override
                (my/gptel--run-agent-tool-with-timeout
                experiment-timeout
                executor-callback
                "executor"
                (format "Experiment %d: optimize %s" experiment-id target)
                executor-prompt
                nil "false" nil))))))
             workflow-root)))
       workflow-root)
  )





(defconst gptel-auto-experiment--placeholder-hypothesis-exact-patterns
  '("[What CODE change and why]"
    "What CODE change and why")
  "Exact hypothesis strings that indicate unresolved placeholder prompts.")

(defun gptel-auto-experiment--placeholder-hypothesis-p (hypothesis)
  "Return non-nil when HYPOTHESIS is still an unresolved prompt template."
  (cond
   ((not (stringp hypothesis)) t)
   (t
    (let ((trimmed (string-trim hypothesis)))
      (or (string-empty-p trimmed)
          (string-match-p "\\`\\[What\\b.*\\]\\'" trimmed)
          (member trimmed gptel-auto-experiment--placeholder-hypothesis-exact-patterns))))))

;; ─── Staging Recovery Sweep ───

(defconst gptel-auto-experiment--staging-recovery-max-age-hours 72
  "Maximum age (hours) for staging-pending recovery. Older experiments have
likely been merged or abandoned — skip to avoid noise.")

(defun gptel-auto-experiment--recover-stale-staging-pending ()
  "Retry staging flow for experiments stuck in `staging-pending`.
Scans all TSV files for rows still in `staging-pending` between 1h
and `gptel-auto-experiment--staging-recovery-max-age-hours` old.
Older entries are skipped (branches likely deleted/merged).
Safe to call multiple times: already-merged branches are skipped."
  (interactive)
  (when (and gptel-auto-workflow-use-staging
             (fboundp 'gptel-auto-workflow--staging-flow)
             (fboundp 'gptel-auto-workflow--parse-all-results))
    (let ((recovered 0)
          (skipped 0)
          (gptel-auto-workflow--recovering-stale-staging t)
          (now (float-time))
          (results-dir (expand-file-name "var/tmp/experiments"
                        (gptel-auto-workflow--worktree-base-root))))
      (dolist (run-dir (directory-files results-dir t "^202[0-9]-"))
        (let* ((tsv-file (expand-file-name "results.tsv" run-dir))
               (run-id (file-name-nondirectory run-dir)))
          (when (file-exists-p tsv-file)
            (let ((gptel-auto-workflow--run-id run-id))
              (with-temp-buffer
                (insert-file-contents tsv-file)
                (forward-line 1)
                (while (not (eobp))
                  (let ((line (buffer-substring-no-properties
                               (line-beginning-position) (line-end-position))))
                    (unless (string-empty-p line)
                      (let* ((fields (split-string line "\t"))
                             (decision (nth 7 fields))
                             (experiment-id (nth 0 fields))
                             (target (nth 1 fields))
                             (exp-ts (and (string-match
                                           "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T[0-9]\\{2\\}[0-9]\\{2\\}[0-9]\\{2\\}\\)Z"
                                           run-id)
                                          (float-time
                                           (date-to-time (match-string 1 run-id)))))
                             (age (if exp-ts (/ (- now exp-ts) 3600.0) 0)))
                        (when (and (string= decision "staging-pending")
                                   (stringp experiment-id)
                                   (> age 1.0))
                          (if (>= age gptel-auto-experiment--staging-recovery-max-age-hours)
                              (cl-incf skipped)
                            (condition-case err
                                (let* ((exp-id (string-to-number experiment-id))
                                       (branch (gptel-auto-workflow--branch-name
                                                target exp-id)))
                                  (message "[staging-recovery] Retrying stale staging-pending: %s (age=%.1fh)"
                                           branch age)
                                  (gptel-auto-workflow--staging-flow branch)
                                  (cl-incf recovered))
                              (error
                               (message "[staging-recovery] Recovery failed for %s/exp%s: %s"
                                        target experiment-id
                                        (error-message-string err)))))))))
                  (forward-line 1)))))))
      (when (> recovered 0)
        (message "[staging-recovery] Recovered %d stale staging-pending experiments (skipped %d too old)"
                 recovered skipped))
      (when (> skipped 0)
        (message "[staging-recovery] %d experiments are > %dh old — skipping (branches likely deleted)"
                 skipped gptel-auto-experiment--staging-recovery-max-age-hours)))))

(provide 'gptel-tools-agent-experiment-core)
;;; gptel-tools-agent-experiment-core.el ends here
