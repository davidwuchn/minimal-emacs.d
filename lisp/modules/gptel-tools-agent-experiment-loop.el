;;; gptel-tools-agent-experiment-loop.el --- Experiment loop, status management -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(declare-function gptel-auto-experiment--frontier-saturated-p "gptel-tools-agent-prompt-build" (target &optional min-frontier-size min-axes min-quality))
(declare-function gptel-auto-experiment--compute-frontier "gptel-tools-agent-prompt-build" (target))

(defun gptel-auto-experiment--extract-last-explicit-hypothesis (output pattern)
  "Return the last non-placeholder hypothesis in OUTPUT matching PATTERN."
  (when (stringp output)
    (let ((start 0)
          candidate)
      (while (and (< start (length output))
                  (string-match pattern output start))
        (let ((match (string-trim (match-string 1 output))))
          (unless (gptel-auto-experiment--placeholder-hypothesis-p match)
            (setq candidate match)))
        ;; Advance from the current match start so nested/repeated markers on the
        ;; same logical line still get a chance to replace malformed earlier text.
        (setq start (1+ (match-beginning 0))))
      candidate)))

(defun gptel-auto-experiment--extract-hypothesis (output)
  "Extract HYPOTHESIS from agent OUTPUT.
Tries multiple patterns in order:
1. Check for error message (returns 'Agent error')
2. Explicit HYPOTHESIS: prefix
3. **HYPOTHESIS** markdown
4. Sentence with 'will improve' (predictive statement)
5. Action verb at start of sentence
6. Summary after ✓ checkmark (fallback)"
  (cond
   ;; Guard against non-string input
   ((not (stringp output))
    "No hypothesis stated")
   ;; Check for error message first
   ((gptel-auto-experiment--agent-error-p output)
    "Agent error")
   ((gptel-auto-experiment--extract-last-explicit-hypothesis
     output
     "HYPOTHESIS:\\s-*\\([^\n]+\\)"))
   ((gptel-auto-experiment--extract-last-explicit-hypothesis
     output
     "\\*\\*HYPOTHESIS\\*\\*:?\\s-*\\([^\n]+\\)"))
   ((string-match "[^.]*\\s-+will improve\\s-+[^.]*\\.?" output)
    (let ((match (match-string 0 output)))
      (string-trim match)))
   ((string-match "\\(?:Adding\\|Changing\\|Improving\\|Enhancing\\|Removing\\|Refactoring\\)\\s-+[^.\n]+\\." output)
    (let ((match (match-string 0 output)))
      (string-trim match)))
   ((string-match "✓\\s-+[^:]+:\\s-+\\([^\n|]+\\)" output)
    (let ((match (match-string 1 output)))
      (string-trim match)))
   (t "No hypothesis stated")))

(defun gptel-auto-experiment--agent-error-p (output)
  "Check if OUTPUT is an error message from agent tool."
  (and (stringp output)
       (or (string-match-p "^Error:" output)
           (gptel-auto-experiment--aborted-agent-output-p output))))

(defun gptel-auto-experiment--summarize (hypothesis)
  "Create short summary of HYPOTHESIS."
  (let ((words (split-string hypothesis)))
    (string-join (cl-subseq words 0 (min 6 (length words))) " ")))

(defvar gptel-auto-experiment-max-validation-retries 1
  "Maximum retries when validation fails due to teachable patterns.
Executor will be instructed to load relevant skill and regenerate.")

(defun gptel-auto-experiment--elisp-syntax-error-p (target error)
  "Return non-nil when ERROR indicates an Elisp syntax issue in TARGET."
  (and (stringp error)
       (or (string-match-p
            "cl-return-from.*without.*cl-block\\|Dangerous pattern"
            error)
           (and (stringp target)
                (string-suffix-p ".el" target)
                (string-match-p "\\`Syntax error in " error)))))

(defun gptel-auto-experiment--teachable-validation-error-p (target validation-error)
  "Return non-nil when VALIDATION-ERROR should trigger an immediate retry.
TARGET is the file currently being optimized."
  (and (stringp validation-error)
       (> (length validation-error) 0)
       (not (null (gptel-auto-experiment--elisp-syntax-error-p target validation-error)))))

(defun gptel-auto-experiment--make-retry-prompt (target validation-error original-prompt)
  "Create retry prompt after validation failure.
TARGET is the file being edited.
VALIDATION-ERROR is the error message.
Instructs executor to load relevant skill instead of hardcoding patterns."
  (let ((skill-guidance
         (cond
          ;; Elisp syntax and dangerous patterns - tell executor to load skill
          ((gptel-auto-experiment--elisp-syntax-error-p target validation-error)
           "CALL THIS FIRST: Skill(\"elisp-expert\")
This skill teaches syntax-safe Elisp edits and dangerous patterns including cl-return-from requirements.")
          ;; Add more skill mappings here as needed
          (t "")))
        (original-contract
         (if (and (stringp original-prompt)
                  (> (length original-prompt) 0))
             original-prompt
           (concat
            "FINAL RESPONSE must include:\n"
            "- CHANGED: exact file path(s) and function/variable names touched\n"
            "- EVIDENCE: 1-2 concrete code snippets or diff hunks showing the real edit\n"
            "- VERIFY: exact command(s) run and whether they passed or failed\n"
            "- COMMIT: always \"not committed\"\n"
            "End the final response with: Task completed"))))
    (format "Your previous edit to %s was REJECTED due to validation error:

ERROR: %s

IMPORTANT:
1. This is a focused repair retry, not a fresh experiment.
2. Fix ONLY the reported validation issue in %s with the smallest possible edit.
3. Keep the earlier improvement if it still makes sense after the repair; do not broaden the change.
4. Prefer focused reads near the reported failure instead of rereading large files.
5. Do not run broad repo tests or compile unrelated files until the validation issue is fixed.
6. For Elisp syntax errors, repair the parse error first and confirm the file reads or byte-compiles before broader verification.
7. Reuse the original experiment contract and final response format below.

Before retrying, load the relevant skill for guidance.

%s

ORIGINAL TASK:
%s"
            target
            validation-error
            target
            skill-guidance
            original-contract)))

;;; Experiment Loop

(defun gptel-auto-experiment-loop (target callback)
  "Run experiments for TARGET until stop condition. Call CALLBACK with results.
Uses local state captured in closure for parallel execution safety.
Adapts max-experiments based on API error rate."
  (let* ((workflow-root (gptel-auto-workflow--resolve-run-root))
         (loop-buffer (current-buffer))
         baseline
         baseline-code-quality)
    (gptel-auto-workflow--call-in-run-context
     workflow-root
     (lambda ()
       (setq baseline (gptel-auto-experiment-benchmark t)
             baseline-code-quality (or (gptel-auto-experiment--code-quality-score) 0.5)))
     loop-buffer
     workflow-root)
     (let* ((original-max gptel-auto-experiment-max-per-target)
            (max-exp (gptel-auto-experiment--adaptive-max-experiments original-max))
            ;; Adjust max-exp based on frontier size: underexplored targets get more experiments
            (max-exp (if (fboundp 'gptel-auto-experiment--compute-frontier)
                         (let* ((frontier (gptel-auto-experiment--compute-frontier target))
                                (frontier-size (length frontier)))
                           (cond
                            ;; No frontier yet: extra experiments to bootstrap
                            ((= frontier-size 0)
                             (message "[auto-workflow] %s has no frontier yet; allowing +2 experiments" target)
                             (+ max-exp 2))
                            ;; Small frontier: allow more experiments
                            ((< frontier-size 3)
                             (message "[auto-workflow] %s frontier size %d; allowing +1 experiment" target frontier-size)
                             (+ max-exp 1))
                            ;; Large frontier: reduce experiments
                            ((> frontier-size 6)
                             (message "[auto-workflow] %s frontier size %d; reducing by 1" target frontier-size)
                             (max 2 (1- max-exp)))
                            ;; Medium frontier: keep default
                            (t max-exp)))
                       max-exp))
            (threshold gptel-auto-experiment-no-improvement-threshold)
           (run-id gptel-auto-workflow--run-id)
           (results nil)
           (best-score (let ((score (gptel-auto-workflow--plist-get baseline :eight-keys nil)))
                         (if (numberp score) score 0.0)))
           (no-improvement-count 0))
      (message "[auto-experiment] Baseline for %s: %.2f (max-exp: %d)"
               target best-score max-exp)
      (cl-labels ((run-next (exp-id)
                    (when gptel-auto-experiment--quota-exhausted
                      (message "[auto-workflow] Provider quota exhausted; stopping early for %s"
                               target)
                      (setq max-exp (min max-exp (1- exp-id))))
                     (when (and (>= gptel-auto-experiment--api-error-count
                                    gptel-auto-experiment--api-error-threshold)
                                (< exp-id max-exp))
                       (message "[auto-workflow] API pressure reached threshold (%d), stopping early for %s"
                                gptel-auto-experiment--api-error-count target)
                       (setq max-exp (1- exp-id)))
                     ;; Check frontier saturation: stop if target sufficiently explored
                     (when (and (fboundp 'gptel-auto-experiment--frontier-saturated-p)
                                (gptel-auto-experiment--frontier-saturated-p target)
                                (< exp-id max-exp))
                       (message "[auto-workflow] Target %s frontier saturated; stopping early"
                                target)
                       (setq max-exp (1- exp-id)))
                     (if (or (> exp-id max-exp)
                             (>= no-improvement-count threshold))
                         (progn
                           (message "[auto-experiment] Done with %s: %d experiments, best score %.2f"
                                    target (length results)
                                    best-score)
                           (funcall callback (nreverse results)))
                       (gptel-auto-experiment--run-with-retry
                       target exp-id max-exp
                       best-score
                       baseline-code-quality
                       results
                       (lambda (result)
                         (push result results)
                         (gptel-auto-workflow--update-progress)
                         (let* ((score-after (gptel-auto-workflow--plist-get result :score-after 0))
                                (kept (gptel-auto-workflow--plist-get result :kept nil))
                                (quality-after
                                 (gptel-auto-workflow--plist-get result :code-quality baseline-code-quality))
                                (hard-timeout
                                 (gptel-auto-experiment--result-hard-timeout-p result))
                                (grader-only-failure
                                 (plist-get result :grader-only-failure))
                                (next-exp-id (1+ exp-id)))
                           (when grader-only-failure
                             (message "[auto-experiment] Final grader-only failure for %s in experiment %d; stopping further experiments for this target"
                                      target exp-id)
                             (setq max-exp exp-id))
                           (when kept
                             (setq best-score score-after
                                   baseline-code-quality quality-after
                                   no-improvement-count 0))
                           (when (and (not kept)
                                      score-after
                                      (<= score-after best-score))
                             (cl-incf no-improvement-count))
                           (when hard-timeout
                             (message "[auto-experiment] Hard timeout for %s in experiment %d; skipping retries for this attempt and continuing if budget remains"
                                      target exp-id))
                           (let ((continue
                                  (lambda ()
                                    (if (gptel-auto-workflow--run-callback-live-p run-id)
                                        (gptel-auto-workflow--call-in-run-context
                                         workflow-root
                                         (lambda () (run-next next-exp-id))
                                         loop-buffer
                                         workflow-root)
                                      (progn
                                        (message "[auto-experiment] Run %s no longer active; returning accumulated results for %s"
                                                 run-id target)
                                        (funcall callback (nreverse results)))))))
                             (if (> gptel-auto-experiment-delay-between 0)
                                 (run-with-timer gptel-auto-experiment-delay-between nil
                                                 continue)
                               (funcall continue)))))))))
        (gptel-auto-workflow--call-in-run-context
         workflow-root
         (lambda () (run-next 1))
         loop-buffer
         workflow-root)))))

;;; Main Entry Point

(defvar gptel-auto-workflow--running nil
  "Flag to track if auto-workflow is currently running.")

(defvar gptel-auto-workflow--headless nil
  "Flag to suppress interactive prompts during headless operation.")

(defvar gptel-auto-workflow--auto-revert-was-enabled nil
  "Remember if global-auto-revert-mode was enabled before headless operation.")

(defvar gptel-auto-workflow--uniquify-style nil
  "Remember uniquify-buffer-name-style before headless operation.")

(defvar gptel-auto-workflow--compile-angel-on-load-was-enabled nil
  "Remember whether `compile-angel-on-load-mode' was enabled before headless operation.")

(defvar gptel-auto-workflow--undo-fu-session-was-enabled nil
  "Remember whether `undo-fu-session-global-mode' was enabled before headless operation.")

(defvar gptel-auto-workflow--recentf-was-enabled nil
  "Remember whether `recentf-mode' was enabled before headless operation.")

(defvar gptel-auto-workflow--create-lockfiles-value t
  "Remember `create-lockfiles' before headless operation.")

(defvar gptel-auto-workflow--stats nil
  "Current run statistics: (:kept :total :phase).")

(defvar gptel-auto-workflow--current-target nil
  "Current target file being processed by auto-workflow.")

(defvar gptel-auto-workflow--cron-job-running nil
  "Non-nil while a queued cron job is executing.")

(defvar gptel-auto-workflow--cron-job-timer nil
  "Timer object for a queued cron job that has not started yet.")

(defvar gptel-auto-workflow--watchdog-timer nil
  "Watchdog timer to prevent workflow from getting stuck.")

(defvar gptel-auto-workflow--status-refresh-timer nil
  "Timer that keeps the persisted workflow status snapshot fresh.")

(defvar gptel-auto-workflow--force-idle-status-overwrite nil
  "When non-nil, allow an idle status snapshot to replace an active snapshot.")

(defvar gptel-auto-workflow--last-progress-time nil
  "Timestamp of last progress update.")

(defvar gptel-auto-workflow--messages-start-pos nil
  "Buffer position where the current workflow run's messages begin.")

(defvar gptel-auto-workflow--max-stuck-minutes 30
  "Maximum minutes workflow can be stuck before auto-stopping.")

(defcustom gptel-auto-workflow-status-file "var/tmp/cron/auto-workflow-status.sexp"
  "Path to the persisted auto-workflow status snapshot.
Relative paths are resolved from the project root."
  :type 'file
  :group 'gptel)

(defcustom gptel-auto-workflow-messages-file "var/tmp/cron/auto-workflow-messages-tail.txt"
  "Path to the persisted auto-workflow messages snapshot.
Relative paths are resolved from the project root."
  :type 'file
  :group 'gptel)

(defcustom gptel-auto-workflow-messages-chars 16000
  "Maximum number of trailing *Messages* characters to persist for cron tools."
  :type 'integer
  :group 'gptel)

(defcustom gptel-auto-workflow-status-refresh-interval 10
  "Seconds between persisted status refreshes during active workflow runs."
  :type 'integer
  :group 'gptel)

(defun gptel-auto-workflow--status-file ()
  "Return absolute path to the persisted workflow status snapshot."
  (let* ((configured-file gptel-auto-workflow-status-file)
         (default-file "var/tmp/cron/auto-workflow-status.sexp")
         (env-file (getenv "AUTO_WORKFLOW_STATUS_FILE")))
    (cond
     ((not (equal configured-file default-file))
      (if (file-name-absolute-p configured-file)
          configured-file
        (expand-file-name configured-file
                          (gptel-auto-workflow--default-dir))))
     ((and (stringp env-file)
           (not (string-empty-p env-file)))
      env-file)
     ((file-name-absolute-p configured-file)
      configured-file)
     (t
      (expand-file-name configured-file
                        (gptel-auto-workflow--default-dir))))))

(defun gptel-auto-workflow--messages-file ()
  "Return absolute path to the persisted workflow messages snapshot."
  (let* ((configured-file gptel-auto-workflow-messages-file)
         (default-file "var/tmp/cron/auto-workflow-messages-tail.txt")
         (env-file (getenv "AUTO_WORKFLOW_MESSAGES_FILE")))
    (cond
     ((not (equal configured-file default-file))
      (if (file-name-absolute-p configured-file)
          configured-file
        (expand-file-name configured-file
                          (gptel-auto-workflow--default-dir))))
     ((and (stringp env-file)
           (not (string-empty-p env-file)))
      env-file)
     ((file-name-absolute-p configured-file)
      configured-file)
     (t
      (expand-file-name configured-file
                        (gptel-auto-workflow--default-dir))))))

(defun gptel-auto-workflow--messages-chars ()
  "Return the configured trailing *Messages* snapshot size."
  (let* ((env-value (getenv "AUTO_WORKFLOW_MESSAGES_CHARS"))
         (parsed-env (and (stringp env-value)
                          (not (string-empty-p env-value))
                          (string-to-number env-value))))
    (if (and parsed-env (> parsed-env 0))
        parsed-env
      gptel-auto-workflow-messages-chars)))

(defun gptel-auto-workflow--mark-messages-start ()
  "Mark the current end of *Messages* as the start of a new workflow run."
  (with-current-buffer (get-buffer-create "*Messages*")
    (setq gptel-auto-workflow--messages-start-pos (point-max))))

(defun gptel-auto-workflow--persist-messages-tail ()
  "Persist the trailing *Messages* tail for non-blocking cron inspection."
  (let* ((file (gptel-auto-workflow--messages-file))
         (dir (file-name-directory file))
         (max-chars (gptel-auto-workflow--messages-chars)))
    (when dir
      (make-directory dir t))
    (with-current-buffer (get-buffer-create "*Messages*")
      (let* ((start-pos (cond
                         ((integer-or-marker-p gptel-auto-workflow--messages-start-pos)
                          (max (point-min)
                               (min (point-max)
                                    gptel-auto-workflow--messages-start-pos)))
                         (t (point-min))))
             (tail-start (max (point-min) (- (point-max) max-chars))))
        (write-region (max start-pos tail-start)
                      (point-max)
                      file nil 'silent)))))

(defun gptel-auto-workflow--status-plist ()
  "Return current workflow status as a plist."
  (let* ((running (or gptel-auto-workflow--running
                      (bound-and-true-p gptel-auto-workflow--cron-job-running)))
         (phase (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :phase "idle"))
         (active-run-id (and (stringp gptel-auto-workflow--run-id)
                             (not (string-empty-p gptel-auto-workflow--run-id))
                             gptel-auto-workflow--run-id))
         (status-run-id (and (stringp gptel-auto-workflow--status-run-id)
                             (not (string-empty-p gptel-auto-workflow--status-run-id))
                             gptel-auto-workflow--status-run-id))
         (run-id (or active-run-id
                     (and running status-run-id)
                     (and (member phase '("complete" "quota-exhausted" "error"))
                          status-run-id))))
    (list :running running
          :kept (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :kept 0)
          :total (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :total 0)
          :phase phase
          :run-id run-id
          :results (and run-id
                        (gptel-auto-workflow--results-relative-path run-id)))))

(defun gptel-auto-workflow--status-active-p (status)
  "Return non-nil when STATUS reflects an active workflow snapshot."
  (and (listp status)
       (or (plist-get status :running)
           (let ((phase (plist-get status :phase)))
             (and (stringp phase)
                  (not (member phase '("idle" "complete" "skipped"))))))))

(defun gptel-auto-workflow--status-placeholder-p (status)
  "Return non-nil when STATUS is only an idle placeholder snapshot."
  (and (listp status)
       (not (plist-get status :running))
       (equal (plist-get status :phase) "idle")
       (zerop (or (plist-get status :kept) 0))
       (zerop (or (plist-get status :total) 0))))

(defun gptel-auto-workflow--status-owned-by-current-run-p (status)
  "Return non-nil when STATUS belongs to the current workflow run."
  (and (listp status)
       (stringp gptel-auto-workflow--run-id)
       (not (string-empty-p gptel-auto-workflow--run-id))
       (equal (plist-get status :run-id)
              gptel-auto-workflow--run-id)))

(defun gptel-auto-workflow--persist-status ()
  "Persist current workflow status for non-blocking cron health checks."
  (let* ((file (gptel-auto-workflow--status-file))
         (dir (file-name-directory file))
         (status (gptel-auto-workflow--status-plist))
         (existing-status (gptel-auto-workflow-read-persisted-status)))
    ;; Preserve the last active snapshot when an unrelated process only has an
    ;; idle placeholder view of workflow state. The shell wrapper already owns
    ;; stale-active detection; this guard prevents bogus idle rewrites with
    ;; synthetic run ids while a real run is still active elsewhere.
    (when (and (not gptel-auto-workflow--force-idle-status-overwrite)
               (gptel-auto-workflow--status-placeholder-p status)
               (gptel-auto-workflow--status-active-p existing-status)
               (not (gptel-auto-workflow--status-owned-by-current-run-p
                     existing-status)))
      (setq status existing-status))
    (when dir
      (make-directory dir t))
    (with-temp-file file
      (let ((print-length nil)
            (print-level nil))
        (prin1 status (current-buffer))
        (insert "\n")))
    (gptel-auto-workflow--persist-messages-tail)))

(defun gptel-auto-workflow-read-persisted-status ()
  "Read the persisted workflow status snapshot, or nil if unavailable."
  (let ((file (gptel-auto-workflow--status-file)))
    (when (file-readable-p file)
      (condition-case err
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (read (current-buffer)))
        (error
         (message "[auto-workflow] Failed to read status snapshot: %s" err)
         nil)))))

(defun gptel-auto-workflow--suppress-ask-user-about-supersession-threat (orig-fn &rest args)
  "Suppress supersession threat prompts in headless mode."
  (if gptel-auto-workflow--headless
      'revert
    (apply orig-fn args)))

(defun gptel-auto-workflow--suppress-yes-or-no-p (orig-fn prompt)
  "Suppress yes-or-no prompts in headless mode, auto-answer yes."
  (if gptel-auto-workflow--headless
      t
    (funcall orig-fn prompt)))

(defun gptel-auto-workflow--suppress-y-or-n-p (orig-fn prompt)
  "Suppress y-or-n prompts in headless mode, auto-answer yes."
  (if gptel-auto-workflow--headless
      t
    (funcall orig-fn prompt)))

(defun gptel-auto-workflow--suppress-ask-user-about-lock (orig-fn file opponent)
  "Suppress lock prompts in headless mode by grabbing the lock.
FILE and OPPONENT match `ask-user-about-lock'."
  (if gptel-auto-workflow--headless
      t
    (funcall orig-fn file opponent)))

(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  "Suppress kill-buffer queries in headless mode.
Returns t to allow killing modified buffers without asking.
When not in headless mode, returns t to not interfere with normal behavior."
  (or gptel-auto-workflow--headless t))

(defun gptel-auto-workflow--suppress-kill-buffer-modified (orig-fn &optional buffer-or-name)
  "Suppress 'Buffer modified; kill anyway?' prompt in headless mode.
ORIG-FN is the original `kill-buffer'. BUFFER-OR-NAME is the buffer to kill.
In headless mode, marks buffer as unmodified before killing to bypass prompt."
  (if gptel-auto-workflow--headless
      (let ((buf (if buffer-or-name
                     (get-buffer buffer-or-name)
                   (current-buffer))))
        (when (and buf (buffer-live-p buf))
          (with-current-buffer buf
            (set-buffer-modified-p nil)))
        (funcall orig-fn buffer-or-name))
    (funcall orig-fn buffer-or-name)))

(defun gptel-auto-workflow--enable-headless-suppression ()
  "Enable suppression of interactive prompts for headless operation.
Also disables auto-revert, compile-angel, undo-fu-session, recentf, and
uniquify to prevent buffer churn in ephemeral workflow worktrees."
  (setq gptel-auto-workflow--headless t)
  ;; Remember and disable auto-revert
  (setq gptel-auto-workflow--auto-revert-was-enabled 
        (bound-and-true-p global-auto-revert-mode))
  (when gptel-auto-workflow--auto-revert-was-enabled
    (global-auto-revert-mode -1))
  ;; Disable on-load auto-compilation so clean replay/worktree buffers do not
  ;; spend their first analyzer/executor pass byte-compiling repo files.
  (setq gptel-auto-workflow--compile-angel-on-load-was-enabled
        (bound-and-true-p compile-angel-on-load-mode))
  (when (and gptel-auto-workflow--compile-angel-on-load-was-enabled
             (fboundp 'compile-angel-on-load-mode))
    (compile-angel-on-load-mode -1))
  ;; Disable undo-fu session recovery so worker daemons do not spam *Messages*
  ;; with stale-session mismatch warnings while replaying repo/worktree files.
  (setq gptel-auto-workflow--undo-fu-session-was-enabled
        (bound-and-true-p undo-fu-session-global-mode))
  (when (and gptel-auto-workflow--undo-fu-session-was-enabled
             (fboundp 'undo-fu-session-global-mode))
    (undo-fu-session-global-mode -1))
  ;; Disable recentf cleanup so worker daemons do not pollute *Messages* with
  ;; background recentf maintenance while experiments are running.
  (setq gptel-auto-workflow--recentf-was-enabled
        (bound-and-true-p recentf-mode))
  (when (and gptel-auto-workflow--recentf-was-enabled
             (fboundp 'recentf-mode))
    (recentf-mode -1))
  ;; Disable lockfiles so repeated experiment/worktree reuse does not prompt.
  (setq gptel-auto-workflow--create-lockfiles-value create-lockfiles
        create-lockfiles nil)
  ;; Remember and disable uniquify (prevents ".emacs.d/" prefix in buffer names)
  (setq gptel-auto-workflow--uniquify-style 
        (when (boundp 'uniquify-buffer-name-style)
          uniquify-buffer-name-style))
  (when (boundp 'uniquify-buffer-name-style)
    (setq uniquify-buffer-name-style nil))
  (advice-add 'ask-user-about-lock :around
              #'gptel-auto-workflow--suppress-ask-user-about-lock)
  (advice-add 'ask-user-about-supersession-threat :around 
              #'gptel-auto-workflow--suppress-ask-user-about-supersession-threat)
  (advice-add 'yes-or-no-p :around 
              #'gptel-auto-workflow--suppress-yes-or-no-p)
  (advice-add 'y-or-n-p :around 
              #'gptel-auto-workflow--suppress-y-or-n-p)
  (advice-add 'kill-buffer :around 
              #'gptel-auto-workflow--suppress-kill-buffer-modified)
  ;; Suppress kill-buffer queries for modified buffers
  (add-hook 'kill-buffer-query-functions 
            #'gptel-auto-workflow--suppress-kill-buffer-query))

(defcustom gptel-auto-workflow-persistent-headless nil
  "If non-nil, keep headless suppression enabled between runs.
Set to t when running as daemon/cron to prevent interactive prompts."
  :type 'boolean
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--disable-headless-suppression ()
  "Disable suppression of interactive prompts.
Restores auto-revert, compile-angel, undo-fu-session, recentf, and uniquify if
they were
enabled before headless operation.
Does nothing if `gptel-auto-workflow-persistent-headless' is non-nil."
  (when (and (not gptel-auto-workflow-persistent-headless)
             gptel-auto-workflow--headless)
    (setq gptel-auto-workflow--headless nil)
    ;; Restore auto-revert
    (when (and (boundp 'gptel-auto-workflow--auto-revert-was-enabled)
               gptel-auto-workflow--auto-revert-was-enabled)
      (global-auto-revert-mode 1))
    ;; Restore on-load auto-compilation only when this session disabled it.
    (when (and gptel-auto-workflow--compile-angel-on-load-was-enabled
               (fboundp 'compile-angel-on-load-mode))
      (compile-angel-on-load-mode 1))
    (setq gptel-auto-workflow--compile-angel-on-load-was-enabled nil)
    ;; Restore undo-fu-session only when this session disabled it.
    (when (and gptel-auto-workflow--undo-fu-session-was-enabled
               (fboundp 'undo-fu-session-global-mode))
      (undo-fu-session-global-mode 1))
    (setq gptel-auto-workflow--undo-fu-session-was-enabled nil)
    ;; Restore recentf only when this session disabled it.
    (when (and gptel-auto-workflow--recentf-was-enabled
               (fboundp 'recentf-mode))
      (recentf-mode 1))
    (setq gptel-auto-workflow--recentf-was-enabled nil)
    ;; Restore lockfile behavior
    (setq create-lockfiles gptel-auto-workflow--create-lockfiles-value)
    ;; Restore uniquify
    (when (and (boundp 'gptel-auto-workflow--uniquify-style)
               gptel-auto-workflow--uniquify-style)
      (setq uniquify-buffer-name-style gptel-auto-workflow--uniquify-style))
    (advice-remove 'ask-user-about-lock
                   #'gptel-auto-workflow--suppress-ask-user-about-lock)
    (advice-remove 'ask-user-about-supersession-threat 
                   #'gptel-auto-workflow--suppress-ask-user-about-supersession-threat)
    (advice-remove 'yes-or-no-p 
                   #'gptel-auto-workflow--suppress-yes-or-no-p)
    (advice-remove 'y-or-n-p 
                   #'gptel-auto-workflow--suppress-y-or-n-p)
    (advice-remove 'kill-buffer 
                   #'gptel-auto-workflow--suppress-kill-buffer-modified)
    (remove-hook 'kill-buffer-query-functions 
                 #'gptel-auto-workflow--suppress-kill-buffer-query)))

(defcustom gptel-auto-workflow-git-timeout 120
  "Timeout in seconds for git commands during auto-workflow.
Default 120s (2 minutes) handles slow network connections.
Increase if git operations frequently timeout."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--git-cmd (cmd &optional timeout)
  "Run git command CMD with TIMEOUT (default: gptel-auto-workflow-git-timeout).
Returns command output as string.
Automatically adds --no-pager to prevent blocking on pager output."
  (gptel-auto-workflow--validate-non-empty-string cmd "command")
  (let ((git-cmd (if (string-match-p "^git " cmd)
                     (concat "git --no-pager " (substring cmd 4))
                   cmd)))
    (gptel-auto-workflow--shell-command-string git-cmd (or timeout gptel-auto-workflow-git-timeout))))


(defun gptel-auto-workflow--git-result (cmd &optional timeout)
  "Run git command CMD with TIMEOUT and return (OUTPUT . EXIT-CODE).
Automatically adds --no-pager to prevent blocking on pager output."
  (gptel-auto-workflow--validate-non-empty-string cmd "command")
  (let ((git-cmd (if (string-match-p "^git " cmd)
                     (concat "git --no-pager " (substring cmd 4))
                   cmd)))
    (gptel-auto-workflow--shell-command-with-timeout
     git-cmd
     (or timeout gptel-auto-workflow-git-timeout))))

(defconst gptel-auto-workflow--skip-submodule-sync-env
  "VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1"
  "Environment override used to skip workflow git-hook submodule sync checks.")

(defun gptel-auto-workflow--with-skipped-submodule-sync (fn)
  "Run FN with workflow git hooks skipping submodule sync."
  (let ((process-environment
         (cons gptel-auto-workflow--skip-submodule-sync-env
               process-environment)))
    (funcall fn)))

(defconst gptel-auto-workflow--isolated-state-env-prefixes
  '("AUTO_WORKFLOW_STATUS_FILE="
    "AUTO_WORKFLOW_MESSAGES_FILE="
    "AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE="
    "AUTO_WORKFLOW_EMACS_SERVER=")
  "Environment prefixes that bind a process to workflow state.")

(defvar gptel-auto-workflow--subagent-process-environment nil
  "Full isolated env to persist on routed headless subagent buffers.")

(defun gptel-auto-workflow--isolated-state-env-entry-p (entry)
  "Return non-nil when ENTRY binds shared workflow state."
  (and (stringp entry)
       (cl-some (lambda (prefix)
                  (string-prefix-p prefix entry))
                gptel-auto-workflow--isolated-state-env-prefixes)))

(defun gptel-auto-workflow--isolated-state-environment (&optional server-prefix extra-env include-messages-p)
  "Return `process-environment' isolated from live workflow state.
SERVER-PREFIX customizes the temporary daemon name prefix.
EXTRA-ENV entries are prepended ahead of the isolated workflow vars.
When INCLUDE-MESSAGES-P is non-nil, also isolate messages and snapshot files."
  (let* ((isolated-status-file (make-temp-file "auto-workflow-status-" nil ".sexp"))
         (isolated-messages-file
          (and include-messages-p
               (make-temp-file "auto-workflow-messages-" nil ".txt")))
         (isolated-snapshot-file
          (and include-messages-p
               (make-temp-file "auto-workflow-snapshot-paths-" nil ".txt")))
         (isolated-server-name
          (make-temp-name (or server-prefix "copilot-auto-workflow-test-")))
         (env
          (append
           extra-env
           (list (format "AUTO_WORKFLOW_STATUS_FILE=%s" isolated-status-file))
           (when include-messages-p
             (list (format "AUTO_WORKFLOW_MESSAGES_FILE=%s" isolated-messages-file)
                   (format "AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE=%s" isolated-snapshot-file)))
           (list (format "AUTO_WORKFLOW_EMACS_SERVER=%s" isolated-server-name)))))
    (dolist (path (delq nil (list isolated-status-file
                                  (and include-messages-p isolated-messages-file)
                                  (and include-messages-p isolated-snapshot-file))))
      (when (file-exists-p path)
        (delete-file path)))
    (append (flatten-tree env)
            (cl-remove-if #'gptel-auto-workflow--isolated-state-env-entry-p
                          process-environment))))

(defun gptel-auto-workflow--persist-subagent-process-environment (&optional buffer env)
  "Persist isolated workflow ENV onto BUFFER for later async tool processes."
  (let ((target (or buffer (current-buffer)))
        (effective-env (or env gptel-auto-workflow--subagent-process-environment)))
    (when (and (not gptel-auto-workflow--defer-subagent-env-persistence)
               (buffer-live-p target)
               (listp effective-env))
      (with-current-buffer target
        (unless (and (local-variable-p 'gptel-auto-workflow--subagent-process-environment target)
                     (local-variable-p 'process-environment target)
                     (equal gptel-auto-workflow--subagent-process-environment effective-env)
                     (equal process-environment effective-env))
          (setq-local gptel-auto-workflow--subagent-process-environment
                      (copy-sequence effective-env))
          (setq-local process-environment
                      (copy-sequence effective-env)))))))

(defun gptel-auto-workflow--git-step-success-p (cmd action &optional timeout)
  "Run git CMD and report whether it succeeded.
ACTION is a short description used in the failure message."
  (pcase-let ((`(,output . ,exit-code)
               (gptel-auto-workflow--git-result cmd timeout)))
    (if (= exit-code 0)
        t
      (message "[auto-workflow] %s failed: %s"
               action
               (my/gptel--sanitize-for-logging output 200))
      nil)))

(defun gptel-auto-workflow--empty-commit-output-p (output)
  "Return non-nil when OUTPUT describes a localized clean no-op commit."
  (and (stringp output)
       (string-match-p
        "nothing to commit\\|working tree clean\\|无文件要提交\\|工作区干净"
        output)))

(defun gptel-auto-workflow--commit-step-success-p (cmd action &optional timeout)
  "Run commit CMD and report whether it succeeded or was already captured.
ACTION is a short description used in the failure message."
  (pcase-let ((`(,output . ,exit-code)
               (gptel-auto-workflow--git-result cmd timeout)))
    (cond
     ((= exit-code 0) t)
     ((gptel-auto-workflow--empty-commit-output-p output)
      (message "[auto-workflow] %s already captured (nothing new to commit)" action)
      t)
     (t
      (message "[auto-workflow] %s failed: %s"
               action
               (my/gptel--sanitize-for-logging output 200))
      nil))))

(defun gptel-auto-workflow--current-head-hash ()
  "Return the current HEAD hash in `default-directory', or nil on failure."
  (let ((hash (string-trim (or (ignore-errors
                                 (gptel-auto-workflow--git-cmd "git rev-parse HEAD" 30))
                               ""))))
    (when (string-match-p "^[a-f0-9]\\{7,40\\}$" hash)
      hash)))

(defun gptel-auto-workflow--checked-out-submodule-head (&optional worktree path)
  "Return the checked-out HEAD for top-level submodule PATH in WORKTREE, or nil."
  (let* ((root (or worktree default-directory))
         (target (and (stringp path) (expand-file-name path root)))
         (git-marker (and target (expand-file-name ".git" target)))
         (result (and target
                      (file-directory-p target)
                      (file-exists-p git-marker)
                      (gptel-auto-workflow--git-result
                       (format "git -C %s rev-parse HEAD"
                               (shell-quote-argument target))
                       60)))
         (hash (and result (string-trim (car result)))))
    (when (and result
               (= 0 (cdr result))
               (string-match-p "^[a-f0-9]\\{40\\}$" hash))
      hash)))

(defun gptel-auto-workflow--restage-top-level-submodule-gitlinks (&optional worktree)
  "Restore top-level submodule gitlinks in WORKTREE after `git add -A'.
Hydrated experiment worktrees materialize submodules as checked-out directories.
Reassert gitlink index entries so commits do not record those paths as typechanges."
  (let* ((root (or worktree default-directory))
         (paths (gptel-auto-workflow--staging-submodule-paths root))
         failure)
    (dolist (path paths)
      (unless failure
        (let* ((commit (or (gptel-auto-workflow--checked-out-submodule-head root path)
                           (gptel-auto-workflow--staging-submodule-gitlink-revision root path)))
               (result (and commit
                            (gptel-auto-workflow--git-result
                             (format "git update-index --cacheinfo 160000 %s %s"
                                     (shell-quote-argument commit)
                                     (shell-quote-argument path))
                             60))))
          (cond
           ((not commit)
            (setq failure
                  (format "Missing gitlink revision for submodule %s" path)))
           ((/= 0 (cdr result))
            (setq failure
                  (format "Failed to restage %s as gitlink: %s"
                          path
                          (car result))))))))
    (if failure
        (progn
          (message "[auto-workflow] Failed to preserve submodule gitlinks: %s"
                   (my/gptel--sanitize-for-logging failure 200))
          nil)
      t)))

(defun gptel-auto-workflow--stage-worktree-changes (action &optional timeout)
  "Stage current worktree changes for ACTION while preserving submodule gitlinks."
  (and (gptel-auto-workflow--git-step-success-p
        "git add -A"
        action
        timeout)
       (gptel-auto-workflow--restage-top-level-submodule-gitlinks)))

(defun gptel-auto-workflow--create-provisional-experiment-commit (target hypothesis &optional timeout)
  "Create a provisional WIP commit for TARGET and return its hash.
Returns nil when the commit could not be created."
  (let ((msg (format "WIP: experiment %s\n\nHYPOTHESIS: %s"
                     target
                     (or hypothesis "Improve code quality"))))
    (when (and (gptel-auto-workflow--stage-worktree-changes
                (format "Stage provisional experiment for %s" target)
                60)
               (gptel-auto-workflow--git-step-success-p
                (format "%s git commit -m %s"
                        gptel-auto-workflow--skip-submodule-sync-env
                        (shell-quote-argument msg))
                (format "Create provisional experiment commit for %s" target)
                (or timeout gptel-auto-workflow-git-timeout)))
      (gptel-auto-workflow--current-head-hash))))

(defun gptel-auto-workflow--promote-provisional-commit (message action provisional-hash &optional timeout)
  "Create final commit with MESSAGE, amending PROVISIONAL-HASH when needed.
ACTION is used for failure logging."
  (let* ((head-hash (and provisional-hash
                         (gptel-auto-workflow--current-head-hash)))
         (commit-command
          (format "%s git commit -m %s"
                  gptel-auto-workflow--skip-submodule-sync-env
                  (shell-quote-argument message)))
         (amend-command
          (format "%s git commit --amend -m %s"
                  gptel-auto-workflow--skip-submodule-sync-env
                  (shell-quote-argument message))))
    (if (and provisional-hash head-hash (equal provisional-hash head-hash))
        (gptel-auto-workflow--git-step-success-p
         amend-command
         (format "%s (promote provisional commit)" action)
         timeout)
      (gptel-auto-workflow--commit-step-success-p
       commit-command
       action
       timeout))))

(defun gptel-auto-workflow--drop-provisional-commit (provisional-hash action &optional timeout)
  "Drop PROVISIONAL-HASH when it is still the current HEAD.
ACTION is used for failure logging."
  (when (and provisional-hash
             (equal provisional-hash (gptel-auto-workflow--current-head-hash)))
    (gptel-auto-workflow--git-step-success-p
     "git reset --hard HEAD~1"
     action
     (or timeout 60))))

(defun gptel-auto-experiment--prepare-validation-retry-worktree (target provisional-hash)
  "Reset the current experiment worktree to a clean base before retrying validation.
Drops PROVISIONAL-HASH when it is still the current HEAD so retries do not
start from a syntax-invalid provisional commit."
  (and (magit-git-success "checkout" "--" ".")
       (or (null provisional-hash)
           (not (equal provisional-hash (gptel-auto-workflow--current-head-hash)))
           (gptel-auto-workflow--drop-provisional-commit
            provisional-hash
            (format "Drop provisional commit before validation retry for %s" target)))))

(defun gptel-auto-workflow--with-staging-worktree (fn)
  "Run FN with `default-directory' bound to the staging worktree.
Creates the worktree on demand and returns nil if unavailable."
  (let ((worktree (or gptel-auto-workflow--staging-worktree-dir
                      (gptel-auto-workflow--create-staging-worktree))))
    (when (and worktree (file-exists-p worktree))
      (let ((default-directory worktree))
        (funcall fn)))))


(defun gptel-auto-workflow--watchdog-check ()
  "Check if workflow is stuck and force-stop if necessary.
Prevents workflow from hanging indefinitely due to callback failures."
  (when gptel-auto-workflow--running
    (let ((stuck-minutes (and gptel-auto-workflow--last-progress-time
                              (/ (float-time (time-subtract (current-time) gptel-auto-workflow--last-progress-time))
                                 60))))
      (cond
       ((null stuck-minutes)
        (message "[auto-workflow] WATCHDOG: No progress time recorded, force-stopping")
        (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
        (setq gptel-auto-workflow--running nil
              gptel-auto-workflow--cron-job-running nil
              gptel-auto-workflow--run-project-root nil
              gptel-auto-workflow--current-project nil
              gptel-auto-workflow--current-target nil)
        (setq gptel-auto-workflow--stats
              (plist-put gptel-auto-workflow--stats :phase "idle"))
        (gptel-auto-workflow--persist-status)
        (when gptel-auto-workflow--watchdog-timer
          (cancel-timer gptel-auto-workflow--watchdog-timer)
          (setq gptel-auto-workflow--watchdog-timer nil))
        (gptel-auto-workflow--stop-status-refresh-timer)
        nil)
       ((> stuck-minutes gptel-auto-workflow--max-stuck-minutes)
        (message "[auto-workflow] WATCHDOG: Workflow stuck for %.1f minutes, force-stopping"
                 stuck-minutes)
        (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
        (setq gptel-auto-workflow--running nil
              gptel-auto-workflow--cron-job-running nil
              gptel-auto-workflow--run-project-root nil
              gptel-auto-workflow--current-project nil
              gptel-auto-workflow--current-target nil)
        (setq gptel-auto-workflow--stats
              (plist-put gptel-auto-workflow--stats :phase "idle"))
        (gptel-auto-workflow--persist-status)
        (when gptel-auto-workflow--watchdog-timer
          (cancel-timer gptel-auto-workflow--watchdog-timer)
          (setq gptel-auto-workflow--watchdog-timer nil))
        (gptel-auto-workflow--stop-status-refresh-timer)
        nil)
       (t
        ;; Still running normally, check again in 5 minutes
        t)))))

(defun gptel-auto-workflow--update-progress ()
  "Update progress timestamp for watchdog tracking."
  (setq gptel-auto-workflow--last-progress-time (current-time)))

(defun gptel-auto-workflow--restart-watchdog-timer ()
  "Restart the workflow watchdog timer if a workflow run is active."
  (when (timerp gptel-auto-workflow--watchdog-timer)
    (cancel-timer gptel-auto-workflow--watchdog-timer))
  (setq gptel-auto-workflow--watchdog-timer nil)
  (when (or gptel-auto-workflow--running
            gptel-auto-workflow--cron-job-running)
    (setq gptel-auto-workflow--watchdog-timer
          (run-with-timer 300 300 #'gptel-auto-workflow--watchdog-check))))

(provide 'gptel-tools-agent-experiment-loop)
;;; gptel-tools-agent-experiment-loop.el ends here
