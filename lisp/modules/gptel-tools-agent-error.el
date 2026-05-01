;;; gptel-tools-agent-error.el --- Error analysis, retry logic -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defun gptel-auto-workflow--first-available-provider-candidate (candidates &optional excluded-backends)
  "Return the first available entry from CANDIDATES, skipping EXCLUDED-BACKENDS.

EXCLUDED-BACKENDS may be nil, a backend name string, or a list of backend
name strings."
  (let ((excluded
         (cond
          ((null excluded-backends) nil)
          ((listp excluded-backends) excluded-backends)
          (t (list excluded-backends)))))
    (seq-find
     (lambda (entry)
       (and (not (seq-some (lambda (backend-name)
                             (and (stringp backend-name)
                                  (string= (car entry) backend-name)))
                           excluded))
            (gptel-auto-workflow--backend-available-p (car entry))))
     candidates)))

(defun gptel-auto-workflow--runtime-provider-failover-candidate (agent-type preset)
  "Return the active provider-wide fallback candidate for AGENT-TYPE and PRESET."
  (let* ((current-backend
          (gptel-auto-workflow--preset-backend-name
           (plist-get preset :backend)))
         (candidates
          (gptel-auto-workflow--rate-limit-failover-candidates agent-type)))
    (when (gptel-auto-workflow--backend-rate-limited-p current-backend)
      (gptel-auto-workflow--first-available-provider-candidate
       candidates
       gptel-auto-workflow--rate-limited-backends))))

(defun gptel-auto-workflow--rewrite-subagent-provider (preset candidate)
  "Return PRESET rewritten to use CANDIDATE backend/model."
  (let* ((override (copy-sequence preset))
         (backend-name (car candidate))
         (model-name (cdr candidate))
         (backend-object (gptel-auto-workflow--backend-object backend-name))
         (model-symbol
          (gptel-auto-workflow--backend-model-symbol
           backend-object model-name))
         (max-output
          (gptel-auto-workflow--model-max-output-tokens
           (or model-symbol model-name)))
         (existing-max-tokens
          (let ((value (plist-get override :max-tokens)))
            (cond
             ((integerp value) value)
             ((and (stringp value)
                   (string-match-p "^[0-9]+$" value))
              (string-to-number value))
             (t nil)))))
    (setq override (plist-put override :backend
                              (or backend-object backend-name)))
    (setq override (plist-put override :model
                              (or model-symbol model-name)))
    (when (and (integerp max-output) (> max-output 0))
      (setq override
            (plist-put override :max-tokens
                       (if (and (integerp existing-max-tokens)
                                (> existing-max-tokens 0))
                           (min existing-max-tokens max-output)
                         max-output))))
    override))

(defun gptel-auto-workflow--activate-provider-failover (agent-type preset &optional reason)
  "Mark PRESET's backend unavailable for this run and fail AGENT-TYPE over.

REASON is only used for logging."
  (when (and (gptel-auto-workflow--headless-provider-override-active-p)
             (stringp agent-type)
             (listp preset))
    (let* ((current-backend
            (gptel-auto-workflow--preset-backend-name
             (plist-get preset :backend)))
           (current-model (plist-get preset :model))
           (candidate nil))
      (when (stringp current-backend)
        (cl-pushnew current-backend
                    gptel-auto-workflow--rate-limited-backends
                    :test #'string=)
        (setq candidate
              (gptel-auto-workflow--runtime-provider-failover-candidate
               agent-type preset)))
      (when candidate
        (message "[auto-workflow] Provider failure on %s/%s for %s%s; future retries will use %s/%s"
                 (or current-backend "unknown")
                 (or current-model "unknown")
                 agent-type
                 (if (and (stringp reason) (not (string-empty-p reason)))
                     (format " (%s)"
                             (my/gptel--sanitize-for-logging reason 120))
                   "")
                 (car candidate)
                 (cdr candidate)))
      candidate)))

(defun gptel-auto-workflow--maybe-activate-rate-limit-failover (agent-type preset result)
  "Activate a per-run fallback for AGENT-TYPE when RESULT shows provider pressure."
  (when (and (gptel-auto-workflow--headless-provider-override-active-p)
             (gptel-auto-experiment--provider-pressure-error-p result))
    (gptel-auto-workflow--activate-provider-failover
     agent-type preset "provider pressure")))

(defun gptel-auto-workflow--maybe-override-subagent-provider (agent-type preset)
  "Return PRESET with a fallback provider for headless auto-workflow AGENT-TYPE."
  (let* ((runtime-candidate
          (and (gptel-auto-workflow--headless-provider-override-active-p)
               (or (gptel-auto-workflow--runtime-provider-failover-candidate
                    agent-type preset)
                   (gptel-auto-workflow--runtime-subagent-provider-override
                    agent-type)))))
    (cond
     (runtime-candidate
      (gptel-auto-workflow--rewrite-subagent-provider preset runtime-candidate))
     (t preset))))

(defun gptel-auto-experiment--aborted-agent-output-p (output)
  "Return non-nil when OUTPUT reflects an explicit subagent abort."
  (and (stringp output)
       (let ((case-fold-search t)
             (trimmed (string-trim-left output)))
         (string-match-p
          "\\`\\(?:Aborted:\\|\\(?:gptel:\\s-*\\)?inspection-thrash aborted\\|\\(?:gptel:\\s-*\\)?doom-loop aborted\\|Error: Task .* was aborted by the user\\|Error: Task .* was cancelled or timed out\\)"
          trimmed))))

(defun gptel-auto-experiment--shared-transient-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT matches shared transient retry rules."
  (and (stringp error-output)
       (not (gptel-auto-experiment--aborted-agent-output-p error-output))
       (fboundp 'my/gptel--transient-error-p)
       (my/gptel--transient-error-p error-output nil)))

(defun gptel-auto-experiment--is-retryable-error-p (error-output)
  "Check if ERROR-OUTPUT is a transient/retryable error."
  (and (stringp error-output)
       (not (gptel-auto-experiment--aborted-agent-output-p error-output))
       (or (gptel-auto-experiment--shared-transient-error-p error-output)
           (gptel-auto-experiment--provider-usage-limit-error-p error-output)
           (let ((case-fold-search t))
             (string-match-p
               "throttling\\|rate.limit\\|quota\\|429\\|timeout\\|timed out\\|temporary\\|overloaded\\|server_error\\|WebClientRequestException\\|curl failed with exit code 28\\|curl failed with exit code 56\\|operation timed out\\|authorized_error\\|token is unusable\\|invalid[_ ]api[_ ]key\\|unauthorized\\|http_code \"401\"\\|Malformed JSON"
               error-output)))))

(defun gptel-auto-experiment--provider-usage-limit-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT reflects a provider billing-cycle limit."
  (and (stringp error-output)
       (let ((case-fold-search t))
         (string-match-p
          "access_terminated_error\\|usage limit exceeded\\|usage limit for this billing cycle\\|reached your usage limit for this billing cycle"
          error-output))))

(defun gptel-auto-experiment--rate-limit-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT reflects retryable provider pressure."
  (and (stringp error-output)
       (or (gptel-auto-experiment--provider-usage-limit-error-p error-output)
           (let ((case-fold-search t))
             (string-match-p
              "rate_limit_error\\|allocated quota exceeded\\|insufficient_quota\\|billing_hard_limit_reached\\|throttling\\|rate.limit\\|429\\|overloaded_error\\|cluster overloaded\\|529\\|负载较高"
              error-output)))))

(defun gptel-auto-experiment--provider-auth-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT reflects provider auth failure."
  (and (stringp error-output)
       (let ((case-fold-search t))
         (string-match-p
          "authorized_error\\|token is unusable\\|invalid[_ ]api[_ ]key\\|unauthorized\\|http_code \"401\""
          error-output))))

(defun gptel-auto-experiment--provider-pressure-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT suggests trying a fallback backend."
  (or (gptel-auto-experiment--rate-limit-error-p error-output)
      (gptel-auto-experiment--provider-auth-error-p error-output)
      (gptel-auto-experiment--shared-transient-error-p error-output)
      (and (stringp error-output)
           (let ((case-fold-search t))
             (string-match-p
               "WebClientRequestException\\|server_error\\|curl failed with exit code 28\\|curl failed with exit code 56\\|operation timed out\\|Malformed JSON"
               error-output)))))

(defun gptel-auto-experiment--retry-delay-seconds (error-output retries)
  "Return retry delay for ERROR-OUTPUT after RETRIES previous attempts."
  (let ((base-delay (max 1 gptel-auto-experiment-retry-delay)))
    (if (gptel-auto-experiment--rate-limit-error-p error-output)
        (min gptel-auto-experiment-rate-limit-max-retry-delay
             (* base-delay (ash 1 retries)))
      base-delay)))

(defun gptel-auto-experiment--grade-failure-error-output (grade-details agent-output)
  "Return retryable/error-shaped output for a failed grade.
Prefer GRADE-DETAILS when the grader itself failed transiently; otherwise
fall back to an error-shaped AGENT-OUTPUT."
  (cond
   ((gptel-auto-experiment--normal-grade-details-p grade-details)
    nil)
   ((and (stringp grade-details)
         (or (gptel-auto-experiment--agent-error-p grade-details)
             (gptel-auto-experiment--is-retryable-error-p grade-details)
             (gptel-auto-experiment--quota-exhausted-p grade-details)))
    grade-details)
   ((gptel-auto-experiment--agent-error-p agent-output)
    agent-output)))

(defun gptel-auto-experiment--grader-only-failure-p (agent-output grade-error-output)
  "Return non-nil when GRADE-ERROR-OUTPUT came from the grader, not the executor."
  (and (stringp grade-error-output)
       (not (gptel-auto-experiment--agent-error-p agent-output))))

(defun gptel-auto-experiment--grader-only-error-label (error-category)
  "Return a durable result label for grader-only ERROR-CATEGORY."
  (pcase error-category
    (:timeout "grader-timeout")
    (:api-rate-limit "grader-api-rate-limit")
    (:api-error "grader-api-error")
    (:grader-failed "grader-failed")
    (:tool-error "grader-failed")
    (_ "grader-failed")))

(defun gptel-auto-experiment--should-retry-grader-p (agent-output grade-error-output error-category retries)
  "Return non-nil when a failed grade should retry locally.
Only successful executor output may take the local grader retry path."
  (and (gptel-auto-experiment--grader-only-failure-p agent-output grade-error-output)
       (memq error-category '(:api-rate-limit :api-error :timeout))
       (not (gptel-auto-experiment--hard-quota-stops-run-p "grader"
                                                           grade-error-output))
       (< retries gptel-auto-experiment-max-grader-retries)))

(defun gptel-auto-experiment--remaining-provider-failover-candidate (agent-type)
  "Return the next available provider fallback for AGENT-TYPE in this run, or nil."
  (when (and (stringp agent-type)
             (fboundp 'gptel-auto-workflow--headless-provider-override-active-p)
             (gptel-auto-workflow--headless-provider-override-active-p)
             (fboundp 'gptel-auto-workflow--rate-limit-failover-candidates)
             (fboundp 'gptel-auto-workflow--first-available-provider-candidate))
    (gptel-auto-workflow--first-available-provider-candidate
     (gptel-auto-workflow--rate-limit-failover-candidates agent-type)
     gptel-auto-workflow--rate-limited-backends)))

(defun gptel-auto-experiment--hard-quota-stops-run-p (agent-type error-output)
  "Return non-nil when ERROR-OUTPUT should stop the run for AGENT-TYPE.

Hard quota errors only stop the whole run after the configured provider fallback
chain is exhausted. When another backend is still available, the workflow keeps
retrying on that provider instead."
  (and (gptel-auto-experiment--hard-quota-exhausted-p error-output)
       (not (gptel-auto-experiment--remaining-provider-failover-candidate
             agent-type))))

(cl-defun gptel-auto-experiment--note-api-pressure (target error-category error-source
                                                           &optional agent-type
                                                           (escalate-run-pressure t))
  "Record API pressure state for TARGET after ERROR-CATEGORY from ERROR-SOURCE.

AGENT-TYPE is the subagent that produced ERROR-SOURCE, when known.
When ESCALATE-RUN-PRESSURE is nil, log provider pressure without incrementing
the shared run-wide API counter or stopping the rest of the workflow."
  (when (memq error-category '(:api-rate-limit :api-error))
    (let* ((resolved-agent-type (or agent-type "executor"))
           (hard-quota (gptel-auto-experiment--hard-quota-exhausted-p error-source)))
      (if escalate-run-pressure
          (progn
            (cl-incf gptel-auto-experiment--api-error-count)
            (message "[auto-workflow] API error #%d: %s"
                     gptel-auto-experiment--api-error-count error-category)
            (when hard-quota
              (if-let ((remaining
                        (gptel-auto-experiment--remaining-provider-failover-candidate
                         resolved-agent-type)))
                  (message "[auto-workflow] Provider hard quota on %s; continuing with %s/%s"
                           resolved-agent-type
                           (car remaining)
                           (cdr remaining))
                (setq gptel-auto-experiment--quota-exhausted t)
                (message "[auto-workflow] Provider quota exhausted; stopping remaining work for this run")))
            (when (>= gptel-auto-experiment--api-error-count
                      gptel-auto-experiment--api-error-threshold)
              (message "[auto-workflow] API pressure detected; reducing future experiments for %s"
                       target)))
        (progn
          (message "[auto-workflow] Local API pressure on %s for %s; keeping run-wide pressure unchanged"
                   resolved-agent-type target)
          (when hard-quota
            (if-let ((remaining
                      (gptel-auto-experiment--remaining-provider-failover-candidate
                       resolved-agent-type)))
                (message "[auto-workflow] Provider hard quota on %s; continuing with %s/%s"
                         resolved-agent-type
                         (car remaining)
                         (cdr remaining))
              (message "[auto-workflow] Provider quota exhausted for %s; continuing other workflow work"
                       resolved-agent-type))))))))

(defun gptel-auto-experiment--grade-with-retry (output callback &optional retry-count)
  "Grade OUTPUT and locally retry transient grader failures.
CALLBACK receives the final grade plist. RETRY-COUNT tracks local grader retries."
  (let* ((retries (or retry-count 0))
         (grade-buffer (current-buffer))
         (target gptel-auto-experiment--grading-target)
         (worktree gptel-auto-experiment--grading-worktree))
    (gptel-auto-experiment-grade
     output
     (lambda (grade)
       (let* ((grade-passed (plist-get grade :passed))
              (grade-details (plist-get grade :details))
              (grade-error-output
               (gptel-auto-experiment--grade-failure-error-output
                grade-details output))
              (error-source (or grade-error-output output))
              (error-info (gptel-auto-experiment--categorize-error error-source))
              (error-category (car error-info))
              (grader-only-failure
               (gptel-auto-experiment--grader-only-failure-p output grade-error-output)))
         (if (and (not grade-passed)
                  (gptel-auto-experiment--should-retry-grader-p
                   output grade-error-output error-category retries))
             (progn
               (gptel-auto-experiment--note-api-pressure
                target error-category grade-error-output "grader" nil)
               (let ((retry-delay
                      (gptel-auto-experiment--retry-delay-seconds
                       grade-error-output retries)))
                 (message "[auto-exp] Retrying grader (attempt %d/%d) after %ds delay"
                          (1+ retries) gptel-auto-experiment-max-grader-retries retry-delay)
                 (run-with-timer
                  retry-delay nil
                  (lambda ()
                    (if (buffer-live-p grade-buffer)
                        (with-current-buffer grade-buffer
                          (let ((gptel-auto-experiment--grading-target target)
                                (gptel-auto-experiment--grading-worktree worktree))
                            (gptel-auto-experiment--grade-with-retry
                             output callback (1+ retries))))
                      (let ((final-grade (copy-sequence grade)))
                        (when grade-error-output
                          (setq final-grade
                                (plist-put final-grade :error-source grade-error-output)))
                        (when grader-only-failure
                          (setq final-grade
                                (plist-put final-grade :grader-only-failure t)))
                        (funcall callback final-grade)))))))
           (when (and (not grade-passed)
                      (memq error-category '(:api-rate-limit :api-error)))
             (gptel-auto-experiment--note-api-pressure
              target error-category error-source
              (if grader-only-failure "grader" "executor")
              (not grader-only-failure)))
           (let ((final-grade (copy-sequence grade)))
             (when grade-error-output
               (setq final-grade
                     (plist-put final-grade :error-source grade-error-output)))
             (when grader-only-failure
               (setq final-grade
                     (plist-put final-grade :grader-only-failure t)))
             (funcall callback final-grade))))))))

(defun gptel-auto-experiment--hard-timeout-p (error-output)
  "Return non-nil when ERROR-OUTPUT reports a hard wall-clock timeout."
  (and (stringp error-output)
       (string-match-p
        "timed out after [0-9]+s total runtime\\.?"
        error-output)))

(defun gptel-auto-experiment--result-hard-timeout-p (result)
  "Return non-nil when RESULT failed due to a hard executor timeout."
  (and (not (plist-get result :validation-retry))
       (gptel-auto-experiment--hard-timeout-p
        (or (plist-get result :error)
            (plist-get result :agent-output)
            (plist-get result :grader-reason)))))

(defun gptel-auto-experiment--quota-exhausted-p (agent-output)
  "Return non-nil when AGENT-OUTPUT shows provider quota exhaustion."
  (and (stringp agent-output)
       (or (gptel-auto-experiment--provider-usage-limit-error-p agent-output)
           (let ((case-fold-search t))
             (string-match-p
              "allocated quota exceeded\\|insufficient_quota\\|insufficient balance\\|billing_hard_limit_reached\\|hard limit reached"
              agent-output)))))

(defun gptel-auto-experiment--hard-quota-exhausted-p (agent-output)
  "Return non-nil when AGENT-OUTPUT shows a hard quota stop for executor work."
  (and (stringp agent-output)
       (let ((case-fold-search t))
         (string-match-p
          "allocated quota exceeded\\|insufficient_quota\\|insufficient balance\\|billing_hard_limit_reached\\|hard limit reached"
          agent-output))))

(defun gptel-auto-experiment--run-with-retry (target experiment-id max-experiments baseline baseline-code-quality previous-results callback &optional retry-count)
  "Run experiment with automatic retry on transient errors.
RETRY-COUNT tracks current retry attempt."
  (let ((retries (or retry-count 0))
        (workflow-root (gptel-auto-workflow--resolve-run-root))
        (retry-buffer (current-buffer))
        (run-id gptel-auto-workflow--run-id)
        (attempt-logs nil))
    (gptel-auto-experiment-run
     target experiment-id max-experiments baseline baseline-code-quality previous-results
     (lambda (result)
       (let* ((agent-output (plist-get result :agent-output))
              (raw-error (or (plist-get result :error)
                             (and (gptel-auto-experiment--agent-error-p agent-output)
                                  agent-output)))
              (grader-only-failure (plist-get result :grader-only-failure))
              (quota-source raw-error)
              (retry-delay
               (gptel-auto-experiment--retry-delay-seconds
                (or raw-error agent-output)
                retries))
              (error-type (plist-get result :comparator-reason))
              (hard-timeout
               (gptel-auto-experiment--hard-timeout-p raw-error))
              (quota-exhausted
               (or gptel-auto-experiment--quota-exhausted
                   (gptel-auto-experiment--hard-quota-stops-run-p
                    "executor" quota-source)))
              (api-rate-limit-category
               (memq error-type '(:api-rate-limit)))
              (timeout-category
               (memq error-type '(:timeout)))
              (inspection-thrash-failure
               (gptel-auto-experiment--inspection-thrash-result-p result))
              (retryable-category
               (or api-rate-limit-category
                   (and (not hard-timeout)
                        timeout-category)))
              (retryable-failure
                (and (not grader-only-failure)
                     (or retryable-category
                         inspection-thrash-failure
                         (and raw-error
                              (not hard-timeout)
                              (gptel-auto-experiment--is-retryable-error-p raw-error)))))
              (retry-history
               (gptel-auto-experiment--retry-history previous-results result)))
         (gptel-auto-workflow--restore-live-target-file target workflow-root)
         (when quota-exhausted
           (setq gptel-auto-experiment--quota-exhausted t))
          (if (and (not quota-exhausted)
                   (< retries gptel-auto-experiment-max-retries)
                   retryable-failure)
              (progn
                (when (and raw-error
                           (or (gptel-auto-experiment--provider-pressure-error-p raw-error)
                               (gptel-auto-experiment--is-retryable-error-p raw-error)))
                  (condition-case nil
                      (gptel-auto-workflow--activate-provider-failover
                       "executor"
                       (gptel-auto-workflow--get-active-agent-preset "executor")
                       raw-error)
                    (error nil)))
                (setq attempt-logs nil)
               (message "[auto-exp] Retrying experiment %d (attempt %d/%d) after %ds delay"
                        experiment-id (1+ retries) gptel-auto-experiment-max-retries
                        retry-delay)
               (run-with-timer retry-delay nil
                               (lambda ()
                                 (if (gptel-auto-workflow--run-callback-live-p run-id)
                                     (gptel-auto-workflow--call-in-run-context
                                      workflow-root
                                      (lambda ()
                                        (gptel-auto-experiment--run-with-retry
                                         target experiment-id max-experiments baseline baseline-code-quality
                                         retry-history callback (1+ retries)))
                                      retry-buffer
                                      workflow-root)
                                   (progn
                                     (message "[auto-exp] Skipping stale retry for experiment %d; run %s is no longer active"
                                              experiment-id run-id)
                                     (funcall callback
                                              (list :target target
                                                    :id experiment-id
                                                    :stale-run t)))))))
           (dolist (logged-result (nreverse attempt-logs))
             (gptel-auto-experiment-log-tsv run-id logged-result))
           (setq attempt-logs nil)
           (when hard-timeout
             (message "[auto-exp] Hard executor timeout during experiment %d; skipping retries"
                      experiment-id))
           (when quota-exhausted
             (message "[auto-exp] Quota exhausted during experiment %d; skipping retries"
                      experiment-id))
           (funcall callback result))))
     (lambda (_logged-run-id exp-result)
       (push exp-result attempt-logs)))))
(defun gptel-auto-experiment--categorize-error (agent-output)
  "Categorize error from AGENT-OUTPUT and return (CATEGORY . DETAILS).
Categories: :api-rate-limit :api-error :tool-error :timeout :grader-failed :unknown
Also logs agent-output snippet for debugging when category is :unknown."
  (cond
   ((or (null agent-output) (string= agent-output ""))
    (cons :grader-failed "Grader returned no output"))
   ((gptel-auto-experiment--aborted-agent-output-p agent-output)
    (cons :tool-error "Subagent aborted"))
   ((string-match-p "hour allocated quota exceeded" agent-output)
    (cons :api-rate-limit "Hourly quota exhausted"))
   ((string-match-p "week allocated quota exceeded" agent-output)
    (cons :api-rate-limit "Weekly quota exhausted"))
   ((gptel-auto-experiment--provider-usage-limit-error-p agent-output)
    (cons :api-rate-limit "Provider usage limit reached"))
   ((string-match-p "throttling\\|rate.limit\\|quota exceeded\\|429" agent-output)
    (cons :api-rate-limit "API rate limit exceeded"))
   ((let ((case-fold-search t))
      (string-match-p "overloaded_error\\|cluster overloaded\\|529\\|负载较高"
                      agent-output))
    (cons :api-rate-limit "Provider overloaded"))
   ((gptel-auto-experiment--provider-auth-error-p agent-output)
    (cons :api-error "Provider authorization failed"))
    ((string-match-p "invalid_parameter_error\\|InvalidParameter\\|JSON format\\|Malformed JSON" agent-output)
     (cons :api-error "API parameter error (invalid JSON format)"))
   ((let ((case-fold-search t))
      (string-match-p "timeout\\|timed out\\|curl failed with exit code 28\\|curl failed with exit code 56\\|operation timed out"
                      agent-output))
    (cons :timeout "Experiment timed out"))
   ((let ((case-fold-search t))
      (string-match-p "server_error\\|WebClientRequestException" agent-output))
    (cons :api-error "Provider server error"))
   ((gptel-auto-experiment--shared-transient-error-p agent-output)
    (cons :api-error "Transient provider response error"))
   ((string-match-p "error.*executor\\|failed to finish" agent-output)
    (cons :tool-error "Tool execution failed"))
   ((string-match-p "could not finish" agent-output)
    (cons :api-error "API request failed"))
   ((string-match-p "Error:.*not available\\|Error:.*not found\\|Error:.*empty" agent-output)
    (cons :tool-error (format "Tool unavailable: %s" (gptel-auto-experiment--error-snippet agent-output))))
   ((string-match-p "^Error:" agent-output)
    (let ((snippet (gptel-auto-experiment--error-snippet agent-output)))
      (message "[auto-experiment] Executor error: %s" snippet)
      (cons :tool-error snippet)))
   ((string-match-p "^Executor result\\|^✓\\|^\\*\\*HYPOTHESIS" agent-output)
    (cons :grader-failed "Executor succeeded, grader returned score 0"))
   ((let ((case-fold-search t))
      (string-match-p "\\bBLOCKED:" agent-output))
    (cons :tool-error (gptel-auto-experiment--error-snippet agent-output)))
   ((string-match-p "error\\|failed\\|exception" agent-output)
    (let ((snippet (gptel-auto-experiment--error-snippet agent-output)))
      (message "[auto-experiment] Unknown error snippet: %s" (my/gptel--sanitize-for-logging snippet))
      (cons :unknown (format "Error pattern: %s" snippet))))
   (t
    (let ((snippet (gptel-auto-experiment--error-snippet agent-output)))
      (message "[auto-experiment] No error pattern found, snippet: %s" (my/gptel--sanitize-for-logging snippet))
      (cons :unknown "Unknown error")))))

(defun gptel-auto-experiment--should-reduce-experiments-p ()
  "Check if we should reduce experiment count due to API issues."
  (>= gptel-auto-experiment--api-error-count gptel-auto-experiment--api-error-threshold))

(defun gptel-auto-experiment--adaptive-max-experiments (original-max)
  "Return adjusted experiment count based on API error rate."
  (if (gptel-auto-experiment--should-reduce-experiments-p)
      (let ((halved (max 1 (ash original-max -1))))
        (message "[auto-workflow] Reducing experiments from %d to %d due to API errors"
                 original-max halved)
        halved)
    original-max))

(defun gptel-auto-experiment--log-failure-analysis (target error-category error-details)
  "Log failure analysis for TARGET with ERROR-CATEGORY and ERROR-DETAILS.
This helps understand patterns in discarded experiments."
  (let ((log-file (expand-file-name 
                   "var/tmp/experiments/failure-analysis.log"
                   (gptel-auto-workflow--project-root))))
    (make-directory (file-name-directory log-file) t)
    (with-temp-buffer
      (when (file-exists-p log-file)
        (insert-file-contents log-file))
      (goto-char (point-max))
      (insert (format "%s | %s | %s | %s\n"
                      (format-time-string "%Y-%m-%d %H:%M:%S")
                      target
                      error-category
                      error-details))
      (write-region (point-min) (point-max) log-file))))

;;; Dynamic Stop

(defun gptel-auto-experiment-should-stop-p (threshold)
  "Check if should stop based on no-improvement count >= THRESHOLD."
  (>= gptel-auto-experiment--no-improvement-count threshold))

;;; Retry Logic (Never Ask User, Just Try Again)

(defcustom gptel-auto-experiment-max-retries 3
  "Maximum retries for transient failures.
Auto-workflow never asks user - just retries until success or max retries."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-experiment--with-retry (fn &optional max-retries)
  "Call FN with retry on failure.
Never asks user - retries up to MAX-RETRIES times.
Auto-workflow principle: try harder, again and again, never stop to ask."
  (let ((attempts 0)
        (max (or max-retries gptel-auto-experiment-max-retries))
        result)
    (while (and (< attempts max) (not result))
      (cl-incf attempts)
      (condition-case err
          (progn
            (setq result (funcall fn))
            (when result
              (message "[auto-experiment] Success on attempt %d/%d" attempts max)))
        (error
         (message "[auto-experiment] Attempt %d/%d failed: %s"
                  attempts max
                  (my/gptel--sanitize-for-logging (error-message-string err) 160))
         (when (< attempts max)
           (sit-for 1)))))  ; Brief pause before retry
    result))

;;; Single Experiment

(provide 'gptel-tools-agent-error)
;;; gptel-tools-agent-error.el ends here
