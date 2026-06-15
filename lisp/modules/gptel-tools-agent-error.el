;;; gptel-tools-agent-error.el --- Error analysis, retry logic -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(require 'cl-lib)
(declare-function gptel-auto-workflow--call-in-run-context "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--make-idempotent-callback "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--resolve-run-root "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--restore-live-target-file "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--run-callback-live-p "gptel-tools-agent-base")
(declare-function gptel-auto-experiment-grade "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--normalize-grade-result "gptel-tools-agent-benchmark")
(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment-run "gptel-tools-agent-experiment-core")
(declare-function gptel-auto-experiment--agent-error-p "gptel-tools-agent-experiment-loop")
(declare-function my/gptel--sanitize-for-logging "gptel-tools-agent-git")
(declare-function my/gptel--invoke-callback-safely "gptel-tools-agent-subagent")
(declare-function gptel-auto-experiment--inspection-thrash-result-p "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-experiment--normal-grade-details-p "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-experiment--retry-history "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-experiment--error-snippet "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-experiment-log-tsv "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--agent-base-preset "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--backend-available-p "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--backend-model-symbol "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--backend-object "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--backend-rate-limited-p "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--headless-provider-override-active-p "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--model-max-output-tokens "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--preset-backend-name "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--rate-limit-failover-candidates "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--runtime-subagent-provider-override "gptel-tools-agent-prompt-build")

;; Variables defined in companion modules to silence byte-compiler.
(defvar gptel-auto-workflow--rate-limited-backends nil)
(defvar gptel-auto-workflow-executor-rate-limit-fallbacks nil)
(defvar gptel-auto-experiment-retry-delay nil)
(defvar gptel-auto-experiment-rate-limit-max-retry-delay nil)
(defvar gptel-auto-experiment--api-error-threshold 5)
(defvar gptel-auto-experiment--no-improvement-count nil)
(defvar gptel-auto-experiment--api-error-count 0)
(defvar gptel-auto-experiment-max-grader-retries 2)
(defvar gptel-auto-experiment-max-retries)
(defvar gptel-auto-experiment-max-per-provider-attempts 3)
(defvar gptel-auto-experiment--quota-exhausted nil)
(defvar gptel-auto-workflow--run-id nil)
(defvar gptel-auto-experiment--grading-target nil)
(defun gptel-error--load-patterns-from-skill ()
  "Load error patterns from provider-error-analyzer skill.
Returns alist of (category . pattern) or nil."
  (when (fboundp 'gptel-auto-workflow--load-skill-content)
    (let ((skill (gptel-auto-workflow--load-skill-content "provider-error-analyzer")))
      (when (stringp skill)
        (let ((patterns nil)
              (pos 0))
          (while (string-match "^\\*\\*Pattern\\*\\*: `\\([^`]+\\)`" skill pos)
            (push (match-string 1 skill) patterns)
            (setq pos (match-end 0)))
          patterns)))))

(defun gptel-error--match-ignore-case (pattern string)
  "Return non-nil if PATTERN matches STRING case-insensitively.
This is a convenience wrapper that sets case-fold-search around
string-match-p."
  (when (stringp string)
    (let ((case-fold-search t))
      (string-match-p pattern string))))

(defconst gptel-auto-experiment--hard-quota-error-pattern
  "allocated quota exceeded\\|insufficient_quota\\|insufficient balance\\|billing_hard_limit_reached\\|hard limit reached\\|quota exceeded\\|quota exhausted\\|1302\\|您的账户已达到速率限制"
  "Regex pattern matching hard quota exhaustion errors.
Usage-limit errors are excluded because they are retryable rate limits until
the configured fallback chain is exhausted.")

(defvar gptel-auto-workflow--runtime-subagent-provider-overrides nil)
(defvar gptel-auto-experiment--shared-retryable-error-patterns
  (list :general
        (regexp-opt '("timeout" "timed out" "temporary" "server_error" "WebClientRequestException" "curl failed with exit code 28" "curl failed with exit code 35" "curl failed with exit code 56" "operation timed out" "authorized_error" "token is unusable" "invalid_api_key" "invalid api key" "unauthorized" "http_code \"401\"" "Malformed JSON" "余额不足" "无可用资源包" "insufficient balance" ":code \"1113\"" "credit limit reached") t)
        :transient
        (regexp-opt '("WebClientRequestException" "server_error" "curl failed with exit code 28" "curl failed with exit code 35" "curl failed with exit code 56" "operation timed out" "Malformed JSON" "余额不足" "无可用资源包" "insufficient balance" ":code \"1113\"" "credit limit reached") t))
   "Pre-compiled shared retryable error patterns as a plist.
Keys :general (used in is-retryable-error-p) and :transient
(used in provider-pressure-error-p).")

(defvar gptel-auto-experiment--auto-learned-patterns nil
  "Error patterns auto-learned by monitoring agent in headless mode.
Accumulated across daemon lifetime. Rebuilt into retryable pattern
regex on each append via --auto-append-retryable-pattern.")

(defun gptel-auto-workflow--auto-append-retryable-pattern (snippet)
  "Auto-add SNIPPET to retryable error patterns (headless, no human gate).
Called by --detect-unknown-error-patterns for low-risk pattern additions.
Rebuilds :general and :transient regex from accumulated learned patterns."
  (unless (member snippet gptel-auto-experiment--auto-learned-patterns)
    (push snippet gptel-auto-experiment--auto-learned-patterns)
    ;; Rebuild both regex patterns from base + auto-learned
    (let* ((base-general '("timeout" "timed out" "temporary" "server_error"
                           "WebClientRequestException" "curl failed with exit code 28"
                           "curl failed with exit code 35" "curl failed with exit code 56"
                           "operation timed out" "authorized_error" "token is unusable"
                           "invalid_api_key" "invalid api key" "unauthorized"
                           "http_code \"401\"" "Malformed JSON"
                           "余额不足" "无可用资源包" "insufficient balance"
                           ":code \"1113\"" "credit limit reached"))
           (base-transient '("WebClientRequestException" "server_error"
                             "curl failed with exit code 28" "curl failed with exit code 35"
                             "curl failed with exit code 56" "operation timed out"
                             "Malformed JSON" "余额不足" "无可用资源包"
                             "insufficient balance" ":code \"1113\"" "credit limit reached"))
           (all-general (append base-general gptel-auto-experiment--auto-learned-patterns))
           (all-transient (append base-transient gptel-auto-experiment--auto-learned-patterns)))
      (plist-put gptel-auto-experiment--shared-retryable-error-patterns
                 :general (regexp-opt all-general t))
      (plist-put gptel-auto-experiment--shared-retryable-error-patterns
                 :transient (regexp-opt all-transient t)))
    (message "[auto-learn] Appended retryable pattern: %S (total learned: %d)"
             snippet (length gptel-auto-experiment--auto-learned-patterns))))

(defun gptel-auto-workflow--plist-delete-all (plist prop)
  "Return PLIST without any entries for PROP."
  (let (result tail)
    (while plist
      (let ((key (pop plist))
            (val (pop plist)))
        (unless (eq key prop)
          (let ((cell (list key val)))
            (if tail
                (setcdr (cdr tail) cell)
              (setq result cell))
            (setq tail cell)))))
    result))

(defun gptel-auto-workflow--first-available-provider-candidate (candidates &optional excluded-backends)
  "Return the first available entry from CANDIDATES, skipping EXCLUDED-BACKENDS.

EXCLUDED-BACKENDS may be nil, a backend name string, or a list of backend
name strings."
  ;; ASSUMPTION: excluded-backends is nil, a string, or a proper list
  ;; BEHAVIOR: Normalizes excluded-backends to a proper list for seq-some
  ;; EDGE CASE: Improper lists (dotted pairs) are treated as single items
  (let ((excluded
         (cond
          ((null excluded-backends) nil)
          ((proper-list-p excluded-backends) excluded-backends)
          (t (list excluded-backends)))))
    (seq-find
     (lambda (entry)
       (and (consp entry)
            (stringp (car entry))
            (not (seq-some (lambda (backend-name)
                             (and (stringp backend-name)
                                  (string= (car entry) backend-name)))
                           excluded))
            (gptel-auto-workflow--backend-available-p (car entry))))
     candidates)))

(defun gptel-auto-workflow--runtime-provider-failover-candidate (agent-type preset)
  "Return the active provider-wide fallback candidate for AGENT-TYPE and PRESET.

On fresh daemon start the preset may have no backend.  Pick the first
available from the headless chain so the subagent always has a working
provider rather than falling through to the global default (often
MiniMax)."
  (let* ((current-backend
          (and (plistp preset)
               (gptel-auto-workflow--preset-backend-name
                (plist-get preset :backend))))
         (candidates
          (gptel-auto-workflow--rate-limit-failover-candidates agent-type)))
    (when (and candidates
               (or (null current-backend)
                   (gptel-auto-workflow--backend-rate-limited-p current-backend)
                   (not (gptel-auto-workflow--backend-available-p current-backend))))
      (gptel-auto-workflow--first-available-provider-candidate
       candidates
       gptel-auto-workflow--rate-limited-backends))))

(defun gptel-auto-workflow--rewrite-subagent-provider (preset candidate)
  "Return PRESET rewritten to use CANDIDATE backend/model.
Returns PRESET unchanged if CANDIDATE is nil or malformed."
  (if (or (null candidate) (not (consp candidate)))
      preset
    (let ((effective-preset preset))
      (unless (or (null effective-preset) (plistp effective-preset))
        (error "gptel-auto-workflow--rewrite-subagent-provider: preset must be a plist or nil, got: %S" effective-preset))
      (let* ((override (copy-sequence effective-preset))
             (backend-name (car candidate))
             (model-name (cdr candidate))
             (backend-object (when (stringp backend-name)
                               (gptel-auto-workflow--backend-object backend-name)))
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
        (setq override (gptel-auto-workflow--plist-delete-all override :backend))
        (setq override (gptel-auto-workflow--plist-delete-all override :model))
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
        override))))

(defun gptel-auto-workflow--demote-backend-in-fallback-chain (backend-name)
  "Move BACKEND-NAME to the end of
`gptel-auto-workflow-executor-rate-limit-fallbacks'.
Does nothing when BACKEND-NAME is not in the chain."
  (when (and (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
             gptel-auto-workflow-executor-rate-limit-fallbacks
             (stringp backend-name))
    (let* ((entry (assoc backend-name
                         gptel-auto-workflow-executor-rate-limit-fallbacks
                         #'string=))
           (rest (if entry
                      (cl-remove (car entry)
                                 gptel-auto-workflow-executor-rate-limit-fallbacks
                                 :key #'car :test #'string=)
                    nil)))
      (when entry
        (setq gptel-auto-workflow-executor-rate-limit-fallbacks
              (append rest (list entry)))))))

(defun gptel-auto-workflow--activate-provider-failover (agent-type preset &optional reason skip-blacklist)
  "Mark PRESET's backend unavailable for this run and fail AGENT-TYPE over.

REASON is only used for logging.
When SKIP-BLACKLIST is nil (the default), add the current backend to
`gptel-auto-workflow--rate-limited-backends'.  When non-nil, only
switch to a fallback without blacklisting (used for transient errors)."
  (when (and (gptel-auto-workflow--headless-provider-override-active-p)
             (stringp agent-type)
             (plistp preset))
    (let* ((current-backend
            (gptel-auto-workflow--preset-backend-name
             (plist-get preset :backend)))
           (current-model (plist-get preset :model))
           (candidate nil))
      (when (stringp current-backend)
        (unless skip-blacklist
          (cl-pushnew current-backend
                      gptel-auto-workflow--rate-limited-backends
                      :test #'string=))
        ;; Feed subagent failure into persistent health tracking so
        ;; the Ouroboros smart routing deprioritizes this backend
        ;; across runs, not just within this run.
        (when (fboundp 'gptel-auto-workflow--record-lambda-strike)
          (gptel-auto-workflow--record-lambda-strike current-backend :degraded))
        ;; Move failed backend to end of fallback chain so subsequent
        ;; subagent calls try working providers first.
        (when (and (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
                   (fboundp 'gptel-auto-workflow--demote-backend-in-fallback-chain))
          (gptel-auto-workflow--demote-backend-in-fallback-chain current-backend))
        (setq candidate
              (if skip-blacklist
                  (gptel-auto-workflow--first-available-provider-candidate
                   (gptel-auto-workflow--rate-limit-failover-candidates agent-type)
                   current-backend)
                (gptel-auto-workflow--runtime-provider-failover-candidate
                 agent-type preset))))
      (when candidate
        (when skip-blacklist
          (setf (alist-get agent-type
                           gptel-auto-workflow--runtime-subagent-provider-overrides
                           nil nil #'string=)
                candidate))
        (message "[auto-workflow] Provider failure on %s/%s for %s%s; future retries will use
%s/%s"
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
  "Activate a per-run fallback for AGENT-TYPE when RESULT shows provider issues.
Triggers on rate limits, hard quotas, AND persistent timeouts.
Only permanently blacklists for real rate limits and hard quotas."
  (when (gptel-auto-workflow--headless-provider-override-active-p)
    (cond
     ;; Real rate limits or hard quotas: blacklist permanently
     ((gptel-auto-experiment--should-blacklist-provider-p result)
      (gptel-auto-experiment--parse-quota-reset-time result)
      (gptel-auto-workflow--activate-provider-failover
       agent-type preset "rate limit or hard quota"))
     ;; Timeouts or transient errors: advance provider but don't blacklist
     ((gptel-auto-experiment--provider-pressure-error-p result)
      (gptel-auto-workflow--activate-provider-failover
       agent-type preset "timeout or transient error" t)))))

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

(defun gptel-auto-experiment--error-message (error-output)
  "Extract error message string from ERROR-OUTPUT.
ERROR-OUTPUT may be a string, a plist with :error or :message key, or nil.
Returns the message string or nil."
  (cond ((stringp error-output) error-output)
        ((proper-list-p error-output) (or (plist-get error-output :error)
                                          (plist-get error-output :message)))
        (t nil)))

(defun gptel-auto-experiment--shared-transient-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT matches shared transient retry rules."
  (let ((msg (gptel-auto-experiment--error-message error-output)))
    (and (stringp msg)
         (not (string-empty-p msg))
         (not (gptel-auto-experiment--aborted-agent-output-p msg))
         (fboundp 'my/gptel--transient-error-p)
         (my/gptel--transient-error-p msg nil))))

(defun gptel-auto-experiment--is-retryable-error-p (error-output)
  "Check if ERROR-OUTPUT is a transient/retryable error."
  (let ((msg (gptel-auto-experiment--error-message error-output)))
    (and (stringp msg)
         (not (gptel-auto-experiment--aborted-agent-output-p msg))
         (or (gptel-auto-experiment--shared-transient-error-p msg)
             (gptel-auto-experiment--rate-limit-error-p msg)
             (gptel-auto-experiment--provider-usage-limit-error-p msg)
             (let ((case-fold-search t)
                   (pattern (plist-get gptel-auto-experiment--shared-retryable-error-patterns :general)))
               (and pattern (string-match-p pattern msg)))))))

(defvar gptel-auto-experiment--quota-reset-timestamp nil
  "Parsed timestamp (seconds since epoch) when quota resets.
Set automatically from rate-limit error messages.
Checked at startup to auto-switch back to the primary backend.")

(defun gptel-auto-experiment--provider-usage-limit-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT reflects a provider billing-cycle limit."
  (let ((msg (gptel-auto-experiment--error-message error-output)))
    (and (stringp msg)
         (let ((case-fold-search t))
           (string-match-p
            "access_terminated_error\\|usage limit exceeded\\|usage limit for this billing cycle\\|reached your usage limit for this billing cycle"
            msg)))))

(defun gptel-auto-experiment--parse-quota-reset-time (error-output)
  "Extract quota-reset timestamp from ERROR-OUTPUT and store it.
Returns the parsed timestamp (seconds since epoch) or nil if not found."
  (let ((msg (gptel-auto-experiment--error-message error-output)))
    (when (and (stringp msg)
               (string-match "resets at \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T[0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}[^ ]*\\)" msg))
      (let* ((iso (match-string 1 msg))
             (ts (ignore-errors (date-to-time iso))))
        (when ts
          (setq gptel-auto-experiment--quota-reset-timestamp (float-time ts))
          (message "[auto-workflow] Quota resets at %s (%.0fs from now)"
                   iso (- gptel-auto-experiment--quota-reset-timestamp (float-time)))
          gptel-auto-experiment--quota-reset-timestamp)))))

(defun gptel-auto-experiment--rate-limit-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT reflects retryable provider pressure."
  (let ((msg (gptel-auto-experiment--error-message error-output)))
    (and (stringp msg)
         (or (gptel-auto-experiment--provider-usage-limit-error-p msg)
             (let ((case-fold-search t))
               (string-match-p
                 "rate_limit_error\\|allocated quota exceeded\\|insufficient_quota\\|billing_hard_limit_reached\\|throttling\\|rate.limit\\|429\\|overloaded_error\\|cluster overloaded\\|529\\|负载较高\\|请求量较高\\|Token Plan\\|1302\\|您的账户已达到速率限制"
                msg))))))

(defun gptel-auto-experiment--provider-auth-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT reflects provider auth failure."
  (let ((msg (gptel-auto-experiment--error-message error-output)))
    (and (stringp msg)
         (let ((case-fold-search t))
           (string-match-p
            "authorized_error\\|token is unusable\\|invalid[_ ]api[_ ]key\\|unauthorized\\|http_code \"401\""
            msg)))))

(defun gptel-auto-experiment--provider-pressure-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT suggests trying a fallback backend.
This is used for retry logic and includes transient errors."
  (or (gptel-auto-experiment--rate-limit-error-p error-output)
      (gptel-auto-experiment--provider-auth-error-p error-output)
      (gptel-auto-experiment--shared-transient-error-p error-output)
      (let ((msg (gptel-auto-experiment--error-message error-output)))
        (and (stringp msg)
             (let ((case-fold-search t)
                   (pattern (plist-get gptel-auto-experiment--shared-retryable-error-patterns :transient)))
               (and pattern (string-match-p pattern msg)))))))

(defun gptel-auto-experiment--should-blacklist-provider-p (error-output)
  "Return non-nil only when ERROR-OUTPUT shows a real rate limit or hard quota.
Unlike `provider-pressure-error-p', this does NOT blacklist for timeouts,
connection errors, or other transient failures."
  (or (gptel-auto-experiment--rate-limit-error-p error-output)
      (gptel-auto-experiment--hard-quota-exhausted-p error-output)))

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
  (let ((grade-msg (when (stringp grade-details) grade-details)))
    (cond
     ((gptel-auto-experiment--normal-grade-details-p grade-details)
      nil)
     ((and grade-msg
           (or (gptel-auto-experiment--agent-error-p grade-msg)
               (gptel-auto-experiment--is-retryable-error-p grade-msg)
               (gptel-auto-experiment--quota-exhausted-p grade-msg)))
      grade-msg)
     ((and (stringp agent-output)
           (gptel-auto-experiment--agent-error-p agent-output))
      agent-output)
     (t nil))))

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
  "Return the next available provider fallback for AGENT-TYPE in this run, or
nil."
  (when (and (stringp agent-type)
             (fboundp 'gptel-auto-workflow--headless-provider-override-active-p)
             (gptel-auto-workflow--headless-provider-override-active-p)
             (fboundp 'gptel-auto-workflow--rate-limit-failover-candidates)
             (fboundp 'gptel-auto-workflow--first-available-provider-candidate))
    (gptel-auto-workflow--first-available-provider-candidate
     (gptel-auto-workflow--rate-limit-failover-candidates agent-type)
     gptel-auto-workflow--rate-limited-backends)))

(defun gptel-auto-experiment--check-quota-reset-and-switch-back ()
  "If quota reset time has passed, switch to first available fallback.
Uses `gptel-auto-experiment--quota-reset-timestamp' and clears rate-limited
backends so the next experiment can try MiniMax first."
  (when (and gptel-auto-experiment--quota-reset-timestamp
             (> (float-time) gptel-auto-experiment--quota-reset-timestamp)
             (boundp 'gptel-auto-workflow--rate-limited-backends))
    ;; Clear rate-limited backends so MiniMax gets first crack again
    (setq gptel-auto-workflow--rate-limited-backends nil)
    (setq gptel-auto-experiment--quota-reset-timestamp nil)
    (message "[auto-workflow] Quota window elapsed. Cleared rate-limited backends. MiniMax
will be tried first on next experiment.")))

(defun gptel-auto-experiment--hard-quota-stops-run-p (agent-type error-output)
  "Return non-nil when ERROR-OUTPUT should stop the run for AGENT-TYPE.

Hard quota errors only stop the whole run after the configured provider
fallback
chain is exhausted. When another backend is still available, the workflow
keeps
retrying on that provider instead."
  (and (gptel-auto-experiment--hard-quota-exhausted-p error-output)
       (not (gptel-auto-experiment--remaining-provider-failover-candidate
             agent-type))))


(defun gptel-auto-experiment--handle-hard-quota (agent-type &optional set-quota-exhausted)
  "Handle hard quota exhaustion for AGENT-TYPE.
When SET-QUOTA-EXHAUSTED is non-nil, set the global quota-exhausted flag."
  (if-let ((remaining
            (gptel-auto-experiment--remaining-provider-failover-candidate
             agent-type)))
      (message "[auto-workflow] Provider hard quota on %s; continuing with %s/%s"
               agent-type
               (car remaining)
               (cdr remaining))
    (when set-quota-exhausted
      (setq gptel-auto-experiment--quota-exhausted t))
    (if set-quota-exhausted
        (message "[auto-workflow] Provider quota exhausted; stopping remaining work for this run")
      (message "[auto-workflow] Provider quota exhausted for %s; continuing other workflow work"
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
            (setq gptel-auto-experiment--api-error-count (1+ (or gptel-auto-experiment--api-error-count 0)))
            (message "[auto-workflow] API error #%d: %s"
                     gptel-auto-experiment--api-error-count error-category)
            (when hard-quota
              (gptel-auto-experiment--handle-hard-quota resolved-agent-type t))
            (when (>= gptel-auto-experiment--api-error-count
                      gptel-auto-experiment--api-error-threshold)
              (message "[auto-workflow] API pressure detected; reducing future experiments for %s"
                       target)))
        (progn
          (message "[auto-workflow] Local API pressure on %s for %s; keeping run-wide pressure unchanged"
                   resolved-agent-type target)
          (when hard-quota
            (gptel-auto-experiment--handle-hard-quota resolved-agent-type nil)))))))

(defun gptel-auto-experiment--grade-with-retry (output callback &optional retry-count)
  "Grade OUTPUT and locally retry transient grader failures.
CALLBACK receives the final grade plist.
RETRY-COUNT tracks local grader retries."
  (let* ((retries (or retry-count 0))
         (grade-buffer (current-buffer))
         (target (or gptel-auto-experiment--grading-target "unknown")))
    (gptel-auto-experiment-grade
     output
     (lambda (grade)
       (let* ((grade (if (fboundp 'gptel-auto-experiment--normalize-grade-result)
                         (gptel-auto-experiment--normalize-grade-result grade)
                       (if (proper-list-p grade)
                           grade
                         (list :score 0 :total 1 :percentage 0.0 :passed nil
                               :details (format "Error: malformed grader result: %S" grade)
                               :grader-only-failure t))))
              (grade-passed (eq (plist-get grade :passed) t))
               (grade-details (plist-get grade :details))
               (grade-error-output
                (or (plist-get grade :error-source)
                    (gptel-auto-experiment--grade-failure-error-output
                     grade-details output)))
              (error-source (or grade-error-output output))
              (error-info (gptel-auto-experiment--categorize-error error-source))
              (error-category (car error-info))
               (grader-only-failure
                (or (plist-get grade :grader-only-failure)
                    (gptel-auto-experiment--grader-only-failure-p output grade-error-output))))
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
                          (gptel-auto-experiment--grade-with-retry
                           output callback (1+ retries)))
                      (let ((final-grade (copy-sequence grade)))
                        (when grade-error-output
                          (setq final-grade
                                (plist-put final-grade :error-source grade-error-output)))
                         (when grader-only-failure
                           (setq final-grade
                                 (plist-put final-grade :grader-only-failure t)))
                        (if (fboundp 'my/gptel--invoke-callback-safely)
                            (my/gptel--invoke-callback-safely callback final-grade "grader")
                          (funcall callback final-grade))))))))
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
              (if (fboundp 'my/gptel--invoke-callback-safely)
                  (my/gptel--invoke-callback-safely callback final-grade "grader")
                (funcall callback final-grade)))))))))

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

(defun gptel-auto-experiment--hard-quota-match-p (msg)
  "Return non-nil if MSG matches hard quota exhaustion pattern.
MSG must be a string. Returns t if pattern matches, nil otherwise."
  (and (stringp msg)
       (let ((case-fold-search t))
         (string-match-p
          gptel-auto-experiment--hard-quota-error-pattern
          msg))))

(defun gptel-auto-experiment--quota-exhausted-p (agent-output)
  "Return non-nil when AGENT-OUTPUT shows provider quota exhaustion."
  (let ((msg (gptel-auto-experiment--error-message agent-output)))
    (or (gptel-auto-experiment--provider-usage-limit-error-p msg)
        (gptel-auto-experiment--hard-quota-match-p msg))))

(defun gptel-auto-experiment--hard-quota-exhausted-p (agent-output)
  "Return non-nil when AGENT-OUTPUT shows a hard quota stop for executor work."
  (let ((msg (gptel-auto-experiment--error-message agent-output)))
    (gptel-auto-experiment--hard-quota-match-p msg)))

(defun gptel-auto-experiment--run-with-retry (target experiment-id max-experiments baseline baseline-code-quality previous-results callback &optional retry-count provider-attempts)
  "Run experiment with automatic retry on transient errors.
RETRY-COUNT tracks current retry attempt."
  (let ((retries (or retry-count 0))
        (prov-attempts (or provider-attempts 0))
        (workflow-root (gptel-auto-workflow--resolve-run-root))
        (retry-buffer (current-buffer))
        (run-id gptel-auto-workflow--run-id)
        (attempt-logs nil))
    (gptel-auto-experiment-run
     target experiment-id max-experiments baseline baseline-code-quality previous-results
     (gptel-auto-workflow--make-idempotent-callback
      (lambda (result)
        (let* ((result (if (proper-list-p result) result
                         (progn
                           (message "[auto-experiment] Invalid result structure received, treating as empty plist")
                           (list :error "Invalid result structure"))))
               (agent-output (plist-get result :agent-output))
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
                    timeout-category))
               (retryable-failure
                (and (not grader-only-failure)
                     (or retryable-category
                         inspection-thrash-failure
                         hard-timeout
                         (and raw-error
                              (not hard-timeout)
                              (gptel-auto-experiment--is-retryable-error-p raw-error)))))
               (retry-history
                (gptel-auto-experiment--retry-history previous-results result))
               (is-pressure (when raw-error
                              (gptel-auto-experiment--provider-pressure-error-p raw-error)))
               (hard-quota (and raw-error
                                (gptel-auto-experiment--hard-quota-exhausted-p raw-error)))
               (should-advance (or hard-quota
                                   timeout-category
                                   (and is-pressure
                                        (>= (1+ prov-attempts)
                                            gptel-auto-experiment-max-per-provider-attempts)))))
          (gptel-auto-workflow--restore-live-target-file target workflow-root)
          (when quota-exhausted
            (setq gptel-auto-experiment--quota-exhausted t))
          (if (and (not quota-exhausted)
                   (< retries gptel-auto-experiment-max-retries)
                   retryable-failure)
              (progn
                (when should-advance
                  (condition-case nil
                      (gptel-auto-workflow--maybe-activate-rate-limit-failover
                       "executor"
                       (gptel-auto-workflow--agent-base-preset "executor")
                       raw-error)
                    (error nil)))
                (setq attempt-logs nil)
                (message "[auto-exp] Retrying experiment %d (attempt %d/%d) after %ds delay%s"
                         experiment-id (1+ retries) gptel-auto-experiment-max-retries
                         retry-delay (if should-advance " [advanced provider]" ""))
                (run-with-timer retry-delay nil
                                (lambda ()
                                  (if (gptel-auto-workflow--run-callback-live-p run-id)
                                      (gptel-auto-workflow--call-in-run-context
                                       workflow-root
                                       (lambda ()
                                         (gptel-auto-experiment--run-with-retry
                                          target experiment-id max-experiments baseline baseline-code-quality
                                          retry-history callback (1+ retries)
                                          (if should-advance 0 (1+ prov-attempts))))
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
              (condition-case nil
                  (gptel-auto-workflow--maybe-activate-rate-limit-failover
                   "executor"
                   (gptel-auto-workflow--agent-base-preset "executor")
                   raw-error)
                (error nil))
              (setq prov-attempts 0)
              (message "[auto-exp] Executor hard timeout during experiment %d; advancing provider for retry"
                       experiment-id))
            (when quota-exhausted
              (message "[auto-exp] Quota exhausted during experiment %d; skipping retries"
                       experiment-id))
            ;; Cross-backend exhaustion: when we've exhausted all retries
            ;; (tried every backend) and the last attempt was a timeout,
            ;; mark global quota-exhausted so subsequent experiments skip
            ;; the retry loop and fail fast.
            (when (and (>= retries gptel-auto-experiment-max-retries)
                       (or hard-timeout (string-match-p "timed out" (or raw-error ""))))
              (setq gptel-auto-experiment--quota-exhausted t)
              (message "[auto-exp] All backends exhausted after %d retries; marking quota exhausted"
                       (1+ retries)))
            (funcall callback result)))))
     (lambda (_logged-run-id exp-result)
       (push exp-result attempt-logs)))))

(defconst gptel-auto-experiment--error-categories
  `(
    ;; Rate limit sub-categories (checked after rate-limit-error-p)
    ("hour allocated quota exceeded" :api-rate-limit "Hourly quota exhausted")
    ("week allocated quota exceeded" :api-rate-limit "Weekly quota exhausted")
    ("overloaded_error\\|cluster overloaded\\|529\\|负载较高" :api-rate-limit "Provider overloaded")
    ("access_terminated_error\\|usage limit for this billing cycle" :api-rate-limit "Provider usage limit reached")
    ;; Auth errors
    ("authorized_error\\|token is unusable\\|invalid[_ ]api[_ ]key\\|unauthorized\\|http_code \"401\""
     :api-error "Provider authorization failed")
    ;; Parameter errors
    ("invalid_parameter_error\\|InvalidParameter\\|JSON format\\|Malformed JSON"
     :api-error "API parameter error (invalid JSON format)")
    ;; Timeouts
    ("timeout\\|timed out\\|curl failed with exit code 28\\|curl failed with exit code 56\\|operation timed out"
     :timeout "Experiment timed out")
    ;; Server errors
    ("server_error\\|WebClientRequestException" :api-error "Provider server error")
    ;; Tool execution errors
    ("error.*executor\\|failed to finish" :tool-error "Tool execution failed")
    ("could not finish" :api-error "API request failed")
    ("Error:.*not available\\|Error:.*not found\\|Error:.*empty"
     :tool-error ,(lambda (s)
                    (format "Tool unavailable: %s"
                            (gptel-auto-experiment--error-snippet s))))
    ("^Error:" :tool-error ,(lambda (s)
                              (let ((snip (gptel-auto-experiment--error-snippet s)))
                                (message "[auto-experiment] Executor error: %s" snip)
                                snip)))
    ("^Executor result\\|^✓\\|^\\*\\*HYPOTHESIS"
     :grader-failed "Executor succeeded, grader returned score 0")
    ("\\bBLOCKED:" :tool-error ,(lambda (s)
                                  (gptel-auto-experiment--error-snippet s)))
    ;; Reviewer/executor result text — NOT an error, just a review rejection.
    ;; Must appear BEFORE the catch-all "error|failed|exception" pattern
    ;; because reviewer output often contains these words in its analysis.
    ("^Reviewer result for task:\\|^Executor result for task:"
     :grader-failed "Review blocked — reviewer did not approve")
    ("error\\|failed\\|exception" :unknown ,(lambda (s)
                                              (let ((snip (gptel-auto-experiment--error-snippet s)))
                                                (message "[auto-experiment] Unknown error snippet: %s"
                                                         (my/gptel--sanitize-for-logging snip))
                                                (format "Error pattern: %s" snip)))))
  "Data-driven error category patterns
for `gptel-auto-experiment--categorize-error'.
Each entry is (PATTERN CATEGORY DETAIL) where PATTERN is a
case-insensitive regexp, CATEGORY is the error keyword, and
DETAIL is a string or function.")

(defun gptel-auto-experiment--categorize-error (agent-output)
  "Categorize error from AGENT-OUTPUT and return (CATEGORY . DETAILS).
Categories: :api-rate-limit :api-error :tool-error :timeout
  :grader-failed :unknown
Also logs agent-output snippet for debugging when category is :unknown."
  (cond
   ((or (null agent-output) (not (stringp agent-output)) (string= agent-output ""))
    (cons :grader-failed "Grader returned no output"))
   ((gptel-auto-experiment--aborted-agent-output-p agent-output)
    (cons :tool-error "Subagent aborted"))
(t
     (catch 'categorize-done
       (let ((case-fold-search t))
         (dolist (entry gptel-auto-experiment--error-categories)
           (when (string-match-p (car entry) agent-output)
             (throw 'categorize-done
                    (cons (nth 1 entry)
                          (let ((detail (nth 2 entry)))
                            (if (functionp detail)
                                (funcall detail agent-output)
                              detail))))))
         (cons :ok nil))))))

(defun gptel-auto-experiment--should-reduce-experiments-p ()
  "Check if we should reduce experiment count due to API issues."
  (>= (or gptel-auto-experiment--api-error-count 0)
      gptel-auto-experiment--api-error-threshold))

(defun gptel-auto-experiment--adaptive-max-experiments (original-max)
  "Return adjusted experiment count based on API error rate."
  (let ((omax (or original-max 1)))    ; guard nil
    (if (gptel-auto-experiment--should-reduce-experiments-p)
        (let ((halved (max 1 (ash omax -1))))
          (message "[auto-workflow] Reducing experiments from %d to %d due to API errors"
                   omax halved)
          halved)
      omax)))


;;; Dynamic Stop

(defun gptel-auto-experiment-should-stop-p (threshold)
  "Check if should stop based on no-improvement count >= THRESHOLD."
  (>= gptel-auto-experiment--no-improvement-count threshold))

;;; Retry Logic (Never Ask User, Just Try Again)

(defcustom gptel-auto-experiment-max-retries 1
  "Maximum retries for transient failures.
Reduced from 3 to 1 because moonshot/kimi-k2.6 always times out (Curl 28).
Fewer retries on failing providers → faster fallback to working provider."
  :type 'integer
  :group 'gptel-tools-agent)


;;; Single Experiment

(provide 'gptel-tools-agent-error)
;;; gptel-tools-agent-error.el ends here
