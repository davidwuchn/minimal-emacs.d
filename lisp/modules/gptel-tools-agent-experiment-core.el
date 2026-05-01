;;; gptel-tools-agent-experiment-core.el --- Single experiment execution -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defun gptel-auto-experiment-run (target experiment-id max-experiments baseline baseline-code-quality previous-results callback &optional log-fn)
  "Run single experiment. Call CALLBACK with result plist.
BASELINE-CODE-QUALITY is the initial code quality score.
LOG-FN receives deferred results as (RUN-ID EXPERIMENT)."
  ;; Clear per-experiment provider overrides so MiniMax gets first crack
  ;; at each new experiment. Rate-limited backends still stay blacklisted.
  (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
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
         (project-buf (when (and (boundp 'gptel-auto-workflow--current-project)
                                 gptel-auto-workflow--current-project)
                        (gptel-auto-workflow--hash-get-bound
                         'gptel-auto-workflow--project-buffers
                         (expand-file-name gptel-auto-workflow--current-project))))
         ;; Disable preview for headless auto-workflow
         (gptel-tools-preview-enabled nil)
         ;; Disable tool confirmations for headless auto-workflow
         (gptel-confirm-tool-calls nil)
         ;; Capture the experiment timeout lexically because later analyzer
         ;; callbacks run after this outer let frame exits.
         (experiment-timeout gptel-auto-experiment-time-budget)
         (run-id gptel-auto-workflow--run-id)
         (workflow-root (gptel-auto-workflow--resolve-run-root))
         ;; The subagent timeout wrapper owns executor timeout/abort behavior.
         (my/gptel-agent-task-timeout experiment-timeout)
         (start-time (float-time))
         (finished nil)
         (provisional-commit-hash nil)
         (executor-prompt nil)
         (executor-callback nil)
         (validation-retry-active nil))
    (if (not worktree)
        (funcall callback (list :target target :error "Failed to create worktree"))
      (gptel-auto-experiment--call-in-context
       experiment-buffer experiment-worktree
       (lambda ()
         (gptel-auto-experiment-analyze
          previous-results
          (lambda (analysis)
            (gptel-auto-experiment--call-in-context
             experiment-buffer experiment-worktree
             (lambda ()
               (let* ((patterns (when analysis (plist-get analysis :patterns)))
                      (prompt (gptel-auto-experiment-build-prompt
                               target experiment-id max-experiments analysis baseline previous-results)))
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
                             (repeated-focus
                              (gptel-auto-experiment--repeated-focus-match
                               effective-agent-output previous-results)))
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
                                            :agent-output effective-agent-output)))
                                (setq finished t)
                                (let ((default-directory experiment-worktree))
                                  (message "[auto-exp] Repeated focus on %s after %d prior non-kept attempts; discarding without grading"
                                           symbol count)
                                  (magit-git-success "checkout" "--" "."))
                                 (cl-incf gptel-auto-experiment--no-improvement-count)
                                 (funcall log-fn run-id exp-result)
                                 (funcall callback exp-result))
                             ;; Validate syntax BEFORE calling grader to avoid wasting API calls
                             (let ((validation-error
                                    (when target
                                      (gptel-auto-experiment--validate-code
                                       (expand-file-name target experiment-worktree)))))
                               (if validation-error
                                   (progn
                                     (message "[auto-exp] ✗ Pre-grade validation failed: %s"
                                              (my/gptel--sanitize-for-logging validation-error 200))
                                     ;; Trigger retry or fail immediately without grader
                                      (let ((default-directory experiment-worktree)
                                            (gptel-auto-experiment--grading-target target)
                                            (gptel-auto-experiment--grading-worktree experiment-worktree))
                                        (if (and (gptel-auto-experiment--teachable-validation-error-p
                                                  target validation-error)
                                                 (not validation-retry-active))
                                            (progn
                                              (message "[auto-experiment] Validation failed with teachable pattern, retrying...")
                                              (gptel-auto-experiment--prepare-validation-retry-worktree
                                               target provisional-commit-hash)
                                              (setq provisional-commit-hash nil)
                                              (setq validation-retry-active t)
                                              (let ((gptel-auto-experiment-active-grace
                                                     gptel-auto-experiment-validation-retry-active-grace))
                                                (my/gptel--run-agent-tool-with-timeout
                                                 gptel-auto-experiment-validation-retry-time-budget
                                                 (lambda (retry-output)
                                                   ;; Treat retry output as new executor output
                                                   (funcall executor-callback retry-output))
                                                 "executor"
                                                 "Validation retry"
                                                       executor-prompt
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
                                                       :validation-error validation-error)))
                                           (setq finished t)
                                           (cl-incf gptel-auto-experiment--no-improvement-count)
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
                                                                     :agent-output effective-agent-output)))
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
                                         (let* ((bench (gptel-auto-experiment-benchmark t))
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
		                                                          effective-agent-output)))
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
                                                                 (let ((retry-bench (gptel-auto-experiment-benchmark t)))
                                                                   (if (plist-get retry-bench :passed)
                                                                       (let* ((retry-score (plist-get retry-bench :eight-keys))
                                                                              (retry-quality
                                                                               (or (gptel-auto-experiment--code-quality-score) 0.5))
                                                                              (retry-hypothesis
                                                                               (gptel-auto-experiment--extract-hypothesis retry-output)))
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
                                                                                            :retries 1)))
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
                                                                                   :validation-error retry-validation-error)))
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
                                                                             :retries 1)))
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
                                                               :agent-output agent-output)))
                                                   (message "[auto-experiment] ✗ %s for %s" reason target)
                                                   (funcall log-fn
                                                            run-id exp-result)
                                                   (funcall callback exp-result))))))
                                          ))))))))))))))))
                                   workflow-root))
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





(defun gptel-auto-experiment--placeholder-hypothesis-p (hypothesis)
  "Return non-nil when HYPOTHESIS is still an unresolved prompt template."
  (let ((trimmed (and (stringp hypothesis) (string-trim hypothesis))))
    (or (not (gptel-auto-workflow--non-empty-string-p trimmed))
        (member trimmed '("[What CODE change and why]"
                          "What CODE change and why"))
        (string-match-p "\\`\\[What\\b.*\\]\\'" trimmed))))

(provide 'gptel-tools-agent-experiment-core)
;;; gptel-tools-agent-experiment-core.el ends here
