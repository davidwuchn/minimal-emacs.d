;;; gptel-tools-agent-prompt-build.el --- Prompt building - construction & logging -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defun gptel-auto-experiment-build-prompt (target experiment-id max-experiments analysis baseline
                                                  &optional previous-results)
  "Build prompt for experiment EXPERIMENT-ID on TARGET.
Uses loaded skills and Eight Keys breakdown for focused improvements."
  (let* ((worktree-path (or (gptel-auto-workflow--get-worktree-dir target)
                            (gptel-auto-workflow--project-root)))
         (worktree-quoted (shell-quote-argument worktree-path))
         (git-history (shell-command-to-string
                       (format "cd %s && git log --oneline -20 2>/dev/null || echo 'no history'"
                               worktree-quoted)))
         (patterns (when analysis (plist-get analysis :patterns)))
         (suggestions (when analysis (plist-get analysis :recommendations)))
         (skills (cdr (assoc target gptel-auto-workflow--skills)))
         (scores (gptel-auto-experiment--eight-keys-scores))
         (weakest-keys (when scores (gptel-auto-workflow--format-weakest-keys scores)))
         (mutation-templates (when skills (gptel-auto-workflow--extract-mutation-templates skills)))
         (suggested-hypothesis (when skills (gptel-auto-workflow-skill-suggest-hypothesis skills)))
         (target-full-path (expand-file-name target worktree-path))
         (target-bytes (gptel-auto-experiment--target-byte-size target-full-path))
         (recovery-p
          (gptel-auto-experiment--needs-inspection-thrash-recovery-p previous-results))
         (large-target-p
          (and (numberp target-bytes)
               (>= target-bytes gptel-auto-experiment-large-target-byte-threshold)))
         (focus-candidate
          (when large-target-p
            (gptel-auto-experiment--select-large-target-focus target-full-path experiment-id)))
         (large-target-guidance
          (when large-target-p
            (concat "## Large Target Guidance\n"
                    (format "This target is large (%d bytes). Start from one concrete function or variable instead of surveying the whole file.\n"
                            target-bytes)
                    (when focus-candidate
                      (format "- Begin at `%s` or a direct caller/callee.\n"
                              (plist-get focus-candidate :name)))
                    "- Prefer focused Grep or narrow Read before broader Code_Map surveys.\n"
                    "- Make the first edit before exploring a second subsystem.\n\n")))
         (focus-line
          (format "FOCUS: %s"
                  (or (plist-get focus-candidate :name)
                      "<one concrete function or variable>")))
         (controller-focus
          (when focus-candidate
            (format "## Controller-Selected Starting Symbol\n- Symbol: `%s`\n- Kind: %s\n- Approx lines: %d-%d (%d lines)\n- Reason: controller-selected small or medium helper in a very large file; start here or at a direct caller/callee.\n\n"
                    (plist-get focus-candidate :name)
                    (plist-get focus-candidate :kind)
                    (plist-get focus-candidate :start-line)
                    (plist-get focus-candidate :end-line)
                    (plist-get focus-candidate :size-lines))))
         (inspection-thrash-contract
          (when recovery-p
            (concat "## Mandatory Focus Contract\n"
                    "A previous attempt on this target already failed with inspection-thrash.\n"
                    (when large-target-p
                      (format "This target is large (%d bytes). Broad file surveys are likely to fail.\n"
                              target-bytes))
                    "Follow this exact opening sequence:\n"
                    (format "1. The second line after HYPOTHESIS must be exactly `%s`.\n"
                            focus-line)
                    "2. Do NOT use Code_Map on the whole file.\n"
                    "3. Use at most 3 read-only tool calls, all on that same symbol or its direct callers/callees.\n"
                    "4. Your next tool call after those reads must be a write-capable tool on that same symbol.\n"
                    "5. Do not inspect a second subsystem before the first edit exists.\n\n"))))
    (format "You are running experiment %d of %d to optimize %s.

## Working Directory
%s

## Target File (full path)
%s

%s

%s

%s

## Previous Experiment Analysis
%s

## Suggestions
%s

## Self-Evolution Knowledge
%s

## Git History (recent commits)
%s

## Current Baseline
Overall Eight Keys score: %.2f

%s

%s

%s

## Objective
Improve the CODE QUALITY for %s.
Focus on one improvement at a time.
Make minimal, targeted changes to CODE, not documentation.

## Constraints
- Time budget: %d minutes
- Immutable files: early-init.el, pre-early-init.el, lisp/eca-security.el
- Must pass tests: ./scripts/verify-nucleus.sh
- FORBIDDEN: Adding comments, docstrings, or documentation-only changes
- REQUIRED: Actual code changes (bug fixes, performance, refactoring, error handling)

## Code Improvement Types (PICK ONE)
1. **Bug Fix**: Fix an actual bug or error handling gap
2. **Performance**: Reduce complexity, add caching, optimize hot path
3. **Refactoring**: Extract functions, remove duplication, improve naming
4. **Safety**: Add validation, prevent edge cases, improve error messages
5. **Test Coverage**: Add missing tests for existing functionality

## Instructions
1. FIRST LINE must be: HYPOTHESIS: [What CODE change and why]
2. If a Controller-Selected Starting Symbol is present, line 2 must be exactly `%s`
3. If a Mandatory Focus Contract is present, obey it exactly; otherwise start from one concrete function or variable and prefer focused Grep or narrow Read before broader Code_Map surveys
4. Read only focused line ranges from the target file using its full path; avoid reading the entire file unless absolutely necessary
5. IDENTIFY a real code issue (bug, performance, duplication, missing validation)
6. Implement the CODE change minimally using Edit tool
7. BEFORE finishing, verify your changes have balanced parentheses:
   - Run: emacs --batch --eval \"(find-file \\\"%%s\\\") (emacs-lisp-mode) (condition-case err (scan-sexps (point-min) (point-max)) (error (message \\\"ERROR: %%s\\\" err)))\"
   - If you see an error, FIX IT before submitting
8. Run tests to verify: ./scripts/verify-nucleus.sh && ./scripts/run-tests.sh
9. DO NOT run git add, git commit, git push, or stage changes yourself.
   Leave edits uncommitted in the worktree; the auto-workflow controller
   handles grading, commit creation, review, and staging.
10. FINAL RESPONSE must include:
    - CHANGED: exact file path(s) and function/variable names touched
    - EVIDENCE: 1-2 concrete code snippets or diff hunks showing the real edit
    - VERIFY: exact command(s) run and whether they passed or failed
    - COMMIT: always \"not committed\" (workflow controller handles commits)
11. End the final response with: Task completed
12. NEVER reply with only \"Done\", only a commit message, or a vague success claim

CRITICAL: Your response MUST start with HYPOTHESIS: on the first line.
DO NOT add comments, docstrings, or documentation.
DO make actual code changes that improve functionality.
DO include concrete evidence of what changed so the grader can inspect it.

Example HYPOTHESES:
- HYPOTHESIS: Adding validation for nil input in process-item will prevent runtime errors
- HYPOTHESIS: Extracting duplicate retry logic into a helper will reduce code duplication
- HYPOTHESIS: Adding a cache for expensive computation will improve performance
- HYPOTHESIS: Fixing the off-by-one error in the loop will correct the boundary case"
            experiment-id max-experiments target
            worktree-path
            target-full-path
            large-target-guidance
            (or controller-focus "")
            (or inspection-thrash-contract "")
            (or patterns "No previous experiments")
            (or suggestions "None")
            (if (fboundp 'gptel-auto-workflow--evolution-get-knowledge)
                (gptel-auto-workflow--evolution-get-knowledge)
              "")
            git-history
            (or baseline 0.5)
            (if weakest-keys
                (format "## Weakest Keys (Priority Focus)\n%s" weakest-keys)
              "")
            (if suggested-hypothesis
                (format "## Suggested Hypothesis (from skill)\n%s" suggested-hypothesis)
              "")
            (if mutation-templates
                (format "## Hypothesis Templates\n%s"
                        (mapconcat (lambda (tmpl) (format "- %s" tmpl)) mutation-templates "\n"))
              "")
            target
            (/ gptel-auto-experiment-time-budget 60)
            focus-line)))

;;; TSV Logging (Explainable)

(defun gptel-auto-experiment--tsv-escape (str)
  "Escape STR for TSV format (replace newlines/tabs with spaces)."
  (when str
    (let ((s (if (stringp str) str (format "%s" str))))
      (replace-regexp-in-string "[\t\n\r]+" " | " s))))

(defun gptel-auto-experiment--tsv-decision-token (value)
  "Return a normalized TSV decision token extracted from VALUE, or nil."
  (when (stringp value)
    (let ((normalized (string-trim value)))
      (when (string-prefix-p ":" normalized)
        (setq normalized (substring normalized 1)))
      (when (string-match-p "\\`[[:lower:]][[:lower:]-]*\\'" normalized)
        normalized))))

(defun gptel-auto-experiment--tsv-decision-label (experiment)
  "Return the durable TSV decision label for EXPERIMENT."
  (or (and (gptel-auto-workflow--plist-get experiment :kept nil)
           "kept")
      (and (gptel-auto-experiment--inspection-thrash-result-p experiment)
           "inspection-thrash")
      (and (gptel-auto-workflow--plist-get experiment :validation-error nil)
           "validation-failed")
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :decision nil))
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :comparator-reason nil))
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :grader-reason nil))
      "discarded"))

(defun gptel-auto-experiment--staging-pending-result (experiment)
  "Return a copy of EXPERIMENT labeled as pending staging verification."
  (let ((pending-result (copy-sequence experiment)))
    (setq pending-result (plist-put pending-result :kept nil))
    (setq pending-result (plist-put pending-result :decision "staging-pending"))
    (setq pending-result (plist-put pending-result :comparator-reason
                                    "staging-pending"))
    pending-result))

(defun gptel-auto-experiment--maybe-log-staging-pending (run-id experiment _log-fn)
  "Log EXPERIMENT as staging-pending for RUN-ID when staging is active.
Writes directly to TSV so the pending row survives regardless of the
intermediate logging strategy used by the caller."
  (when gptel-auto-workflow-use-staging
    (gptel-auto-experiment-log-tsv
     run-id
     (gptel-auto-experiment--staging-pending-result experiment))))

(defun gptel-auto-experiment--drop-replaceable-tsv-rows (experiment-id target)
  "Drop stale pending rows for EXPERIMENT-ID/TARGET in current TSV buffer.
Return non-nil when an existing terminal row should prevent appending another
row for the same experiment and target."
  (let ((id-key (format "%s" experiment-id))
        (target-key (format "%s" target))
        (skip nil))
    (goto-char (point-min))
    (forward-line 1)
    (while (and (not skip) (not (eobp)))
      (let* ((line-start (line-beginning-position))
             (line-end (line-end-position))
             (fields (split-string
                      (buffer-substring-no-properties line-start line-end)
                      "\t"))
             (row-id (nth 0 fields))
             (row-target (nth 1 fields))
             (row-decision (nth 7 fields)))
        (if (and (equal row-id id-key)
                 (equal row-target target-key))
            (if (equal row-decision "staging-pending")
                (delete-region line-start (min (point-max) (1+ line-end)))
              (setq skip t))
          (forward-line 1))))
    skip))

(defun gptel-auto-workflow--kept-target-count-from-results-file (file)
  "Return the number of distinct kept targets recorded in TSV FILE."
  (if (not (file-exists-p file))
      0
    (with-temp-buffer
      (insert-file-contents file)
      (forward-line 1)
      (let ((seen (make-hash-table :test 'equal))
            (count 0))
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring-no-properties
                           (line-beginning-position)
                           (line-end-position))
                          "\t"))
                 (target (nth 1 fields))
                 (decision (nth 7 fields)))
            (when (and (equal decision "kept")
                       (stringp target)
                       (not (string-empty-p target))
                       (not (gethash target seen)))
              (puthash target t seen)
              (cl-incf count)))
          (forward-line 1))
        count))))

(defun gptel-auto-workflow--sync-live-kept-count (run-id results-file)
  "Refresh live workflow kept count from RESULTS-FILE for active RUN-ID."
  (when (and gptel-auto-workflow--running
             (stringp run-id)
             (equal run-id (gptel-auto-workflow--current-run-id)))
    (setq gptel-auto-workflow--stats
          (plist-put
           gptel-auto-workflow--stats
           :kept
           (gptel-auto-workflow--kept-target-count-from-results-file
            results-file)))
    (gptel-auto-workflow--persist-status)))

(defun gptel-auto-experiment-log-tsv (run-id experiment)
  "Append EXPERIMENT to results.tsv for RUN-ID."
  (let* ((file (gptel-auto-workflow--ensure-results-file run-id))
         (experiment-id (gptel-auto-workflow--plist-get experiment :id "?"))
         (target (gptel-auto-workflow--plist-get experiment :target "?"))
         (decision (gptel-auto-experiment--tsv-decision-label experiment))
         (agent-output (gptel-auto-workflow--plist-get experiment :agent-output ""))
         (truncated-output (gptel-auto-experiment--tsv-escape
                             (truncate-string-to-width agent-output 500 nil nil "..."))))
    (with-temp-buffer
      (insert-file-contents file)
      (unless (gptel-auto-experiment--drop-replaceable-tsv-rows
               experiment-id target)
        (goto-char (point-max))
        (insert (format "%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%+.2f\t%s\t%d\t%s\t%s\t%s\t%s\t%s\n"
                        experiment-id
                        target
                        (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :hypothesis "unknown"))
                        (gptel-auto-workflow--plist-get experiment :score-before 0)
                        (gptel-auto-workflow--plist-get experiment :score-after 0)
                        (gptel-auto-workflow--plist-get experiment :code-quality 0.5)
                        (- (gptel-auto-workflow--plist-get experiment :score-after 0)
                           (gptel-auto-workflow--plist-get experiment :score-before 0))
                        decision
                        (gptel-auto-workflow--plist-get experiment :duration 0)
                        (gptel-auto-workflow--plist-get experiment :grader-quality "?")
                        (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :grader-reason "N/A"))
                        (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :comparator-reason "N/A"))
                        (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :analyzer-patterns "N/A"))
                        truncated-output)))
      (write-region (point-min) (point-max) file))
    ;; Trigger self-evolution after experiment logging
    (when (and (fboundp 'gptel-auto-workflow--experiment-complete-hook)
               (fboundp 'gptel-auto-workflow-evolution-run-cycle))
      (condition-case err
          (progn
            (gptel-auto-workflow--experiment-complete-hook experiment)
            (let ((exp-id (or (gptel-auto-workflow--plist-get experiment :id) 0)))
              (when (and (> exp-id 0) (zerop (% exp-id 5)))
                (run-with-idle-timer 30 nil #'gptel-auto-workflow-evolution-run-cycle))))
        (error
         (message "[auto-workflow] Evolution hook error: %s" err))))
    (gptel-auto-workflow--sync-live-kept-count run-id file)))

(defun gptel-auto-experiment--make-kept-result-callback (run-id exp-result log-fn callback)
  "Return idempotent callback that finalizes EXP-RESULT after optional staging.

When invoked without arguments, or with a non-nil first argument, log
EXP-RESULT as kept. When invoked with nil, downgrade the result so staging-flow
failures do not masquerade as published kept results. When a second argument is
supplied on failure, use it as the downgrade reason."
  (gptel-auto-workflow--make-idempotent-callback
   (lambda (&rest success-args)
     (let* ((staging-reported-p (not (null success-args)))
            (staging-succeeded (car-safe success-args))
            (failure-reason-arg (cadr success-args))
            (failure-reason
             (cond
              ((stringp failure-reason-arg)
               failure-reason-arg)
              ((and failure-reason-arg
                    (symbolp failure-reason-arg))
               (symbol-name failure-reason-arg))
              (t
               "staging-flow-failed")))
            (final-result
             (if (or (not staging-reported-p) staging-succeeded)
                 exp-result
               (let ((failed-result (and (listp exp-result)
                                          (plist-put (copy-sequence exp-result) :kept nil))))
                 (when failed-result
                   (plist-put failed-result :decision nil)
                   (plist-put failed-result :comparator-reason failure-reason))
                 (or failed-result exp-result)))))
       (when (functionp log-fn)
         (funcall log-fn run-id final-result))
       (when (and callback (functionp callback))
         (funcall callback final-result))))))

(defun gptel-auto-workflow--invoke-staging-completion (callback success &optional reason)
  "Invoke staging CALLBACK with SUCCESS and optional REASON.

Older completion callbacks only accept a single success flag. Newer callbacks
may also accept a second argument describing why staging downgraded an
experiment that had previously looked keep-worthy."
  (when (functionp callback)
    (let* ((arity (ignore-errors (func-arity callback)))
           (max-args (cdr-safe arity)))
      (if (or (eq max-args 'many)
              (and (integerp max-args) (>= max-args 2)))
          (funcall callback success reason)
        (funcall callback success)))))

(defun gptel-auto-workflow--make-idempotent-staging-completion (callback)
  "Return idempotent staging completion wrapper preserving CALLBACK arity."
  (let ((called nil)
        (arity (ignore-errors (func-arity callback))))
    (if (or (eq (cdr-safe arity) 'many)
            (and (integerp (cdr-safe arity))
                 (>= (cdr-safe arity) 2)))
        (lambda (success &optional reason)
          (unless called
            (setq called t)
            (funcall callback success reason)))
      (lambda (success)
        (unless called
          (setq called t)
          (funcall callback success))))))

;;; Error Analysis and Adaptive Workflow

(defvar gptel-auto-experiment--api-error-count 0
  "Count of API errors in current run.")

(defvar gptel-auto-experiment--api-error-threshold 3
  "Threshold of API errors before reducing or stopping future experiments.")

(defvar gptel-auto-experiment--quota-exhausted nil
  "Non-nil when provider quota exhaustion should stop the current workflow.")

(defun gptel-auto-experiment--error-snippet (agent-output &optional max-len)
  "Extract safe snippet from AGENT-OUTPUT for logging.
MAX-LEN defaults to 200 characters. Handles nil/empty strings safely."
  (if (and (stringp agent-output) (> (length agent-output) 0))
      (my/gptel--sanitize-for-logging agent-output (or max-len 200))
    ""))

(defvar gptel-auto-experiment-max-retries 2
  "Maximum retries for executor on transient errors.")

(defvar gptel-auto-experiment-max-grader-retries 2
  "Maximum local retries for transient grader failures.
These retries reuse the successful executor output instead of rerunning the
entire experiment. Two retries let the grader advance past one failing
fallback backend before giving up on otherwise-good executor output.")

(defvar gptel-auto-experiment-max-aux-subagent-retries 2
  "Maximum local retries for transient analyzer/comparator failures.
These retries keep the current experiment alive while headless provider
failover advances past transient timeout or provider-pressure failures.")

(defvar gptel-auto-experiment-retry-delay 5
  "Seconds to wait between retries.")

(defvar gptel-auto-experiment-rate-limit-max-retry-delay 60
  "Maximum seconds between retries for rate-limited API failures.")

(defcustom gptel-auto-workflow-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-v4-flash")
    ("CF-Gateway" . "@cf/zai-org/glm-4.7-flash")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Ordered backend/model fallbacks for headless auto-workflow subagents.

Each entry is (BACKEND . MODEL), where BACKEND matches the agent preset backend
string and MODEL is the model string to use with that backend. The workflow
tries backends in order when the primary is unavailable or rate-limited."
  :type '(repeat (cons (string :tag "Backend")
                       (string :tag "Model")))
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-headless-fallback-agents
  '("analyzer" "comparator" "executor" "grader" "reviewer")
  "Headless subagents that should use the fallback provider list.

Headless workflow runs prefer MiniMax as the workhorse, falling back to
DashScope and others when rate-limited or unavailable."
  :type '(repeat string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-executor-rate-limit-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-v4-flash")
    ("CF-Gateway" . "@cf/zai-org/glm-4.7-flash")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Ordered backend/model fallbacks for executor after provider rate limits.

Headless executor prefers MiniMax by default. When the active executor backend
returns a rate-limit error during a headless run, later retries in that same
run can advance through this list instead of repeatedly hammering the same provider."
  :type '(repeat (cons (string :tag "Backend")
                       (string :tag "Model")))
  :group 'gptel-tools-agent)

(defconst gptel-auto-workflow--legacy-headless-fallback-agents
  '("analyzer" "grader" "reviewer")
  "Previous default for `gptel-auto-workflow-headless-fallback-agents'.")

(defconst gptel-auto-workflow--previous-headless-fallback-agents
  '("analyzer" "executor" "grader" "reviewer")
  "Prior runtime default for `gptel-auto-workflow-headless-fallback-agents'.")

(defconst gptel-auto-workflow--legacy-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-chat")
    ("CF-Gateway" . "@cf/zai-org/glm-4.7-flash")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Previous default for `gptel-auto-workflow-headless-subagent-fallbacks'.")

(defconst gptel-auto-workflow--current-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-v4-flash")
    ("CF-Gateway" . "@cf/zai-org/glm-4.7-flash")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Current runtime default for `gptel-auto-workflow-headless-subagent-fallbacks'.")

(defconst gptel-auto-workflow--legacy-executor-rate-limit-fallbacks
  '(("DeepSeek" . "deepseek-chat")
    ("CF-Gateway" . "@cf/zai-org/glm-4.7-flash")
    ("DashScope" . "qwen3.6-plus")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Previous default for `gptel-auto-workflow-executor-rate-limit-fallbacks'.")

(defconst gptel-auto-workflow--current-headless-fallback-agents
  '("analyzer" "comparator" "executor" "grader" "reviewer")
  "Current runtime default for `gptel-auto-workflow-headless-fallback-agents'.")

(defconst gptel-auto-workflow--current-executor-rate-limit-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-v4-flash")
    ("CF-Gateway" . "@cf/zai-org/glm-4.7-flash")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Current runtime default for `gptel-auto-workflow-executor-rate-limit-fallbacks'.")

(defvar gptel-auto-workflow--runtime-subagent-provider-overrides nil
  "Per-run provider overrides activated by live workflow failures.

Each element is (AGENT-TYPE . (BACKEND . MODEL)). These overrides are cleared
at run start and whenever workflow state is force-reset.")

(defvar gptel-auto-workflow--rate-limited-backends nil
  "Per-run backend names that hit rate limits during workflow execution.

All matching headless subagents skip these backends for the rest of the run
and advance through the configured fallback chain instead.")

(defconst gptel-auto-workflow--backend-key-hosts
  '(("MiniMax" . "api.minimaxi.com")
    ("DeepSeek" . "api.deepseek.com")
    ("Gemini" . "generativelanguage.googleapis.com")
    ("CF-Gateway" . "gateway.ai.cloudflare.com")
    ("DashScope" . "coding.dashscope.aliyuncs.com")
    ("moonshot" . "api.kimi.com"))
  "Map gptel backend names to auth-source hosts for workflow failover.")

(defconst gptel-auto-workflow--backend-object-vars
  '(("MiniMax" . gptel--minimax)
    ("DeepSeek" . gptel--deepseek)
    ("Gemini" . gptel--gemini)
    ("CF-Gateway" . gptel--cf-gateway)
    ("DashScope" . gptel--dashscope)
    ("moonshot" . gptel--moonshot))
  "Map gptel backend names to the corresponding backend object variables.")

(defun gptel-auto-workflow--backend-available-p (backend-name)
  "Return non-nil when BACKEND-NAME has credentials configured."
  (let ((host (alist-get backend-name gptel-auto-workflow--backend-key-hosts
                         nil nil #'string=)))
    (and host
         (fboundp 'my/gptel-api-key)
         (gptel-auto-workflow--non-empty-string-p
          (my/gptel-api-key host)))))

(defun gptel-auto-workflow--headless-provider-override-active-p ()
  "Return non-nil when headless auto-workflow provider override should apply."
  (and (bound-and-true-p gptel-auto-workflow--headless)
       (bound-and-true-p gptel-auto-workflow-persistent-headless)
       (bound-and-true-p gptel-auto-workflow--current-project)))

(defun gptel-auto-workflow--backend-object (backend-name)
  "Return the backend object for BACKEND-NAME, or nil when unavailable."
  (when-let* ((var (alist-get backend-name gptel-auto-workflow--backend-object-vars
                              nil nil #'string=))
              ((boundp var)))
    (symbol-value var)))

(defun gptel-auto-workflow--custom-var-user-customized-p (symbol)
  "Return non-nil when SYMBOL has an explicit Customize override."
  (or (get symbol 'saved-value)
      (get symbol 'customized-value)
      (get symbol 'theme-value)))

(defun gptel-auto-workflow--migrate-legacy-provider-defaults ()
  "Refresh known legacy in-memory provider defaults after hot reloads.

Long-lived daemons can keep pre-fix `defcustom' values even after the source
defines newer defaults.  Migrate only the exact legacy defaults, and only when
the user has not explicitly customized the variable."
  (let (migrated)
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-headless-fallback-agents)
      (when (or (equal gptel-auto-workflow-headless-fallback-agents
                       gptel-auto-workflow--legacy-headless-fallback-agents)
                (equal gptel-auto-workflow-headless-fallback-agents
                       gptel-auto-workflow--previous-headless-fallback-agents))
        (setq gptel-auto-workflow-headless-fallback-agents
              (copy-tree gptel-auto-workflow--current-headless-fallback-agents))
        (push 'gptel-auto-workflow-headless-fallback-agents migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-headless-subagent-fallbacks)
      (when (equal gptel-auto-workflow-headless-subagent-fallbacks
                   gptel-auto-workflow--legacy-headless-subagent-fallbacks)
        (setq gptel-auto-workflow-headless-subagent-fallbacks
              (copy-tree gptel-auto-workflow--current-headless-subagent-fallbacks))
        (push 'gptel-auto-workflow-headless-subagent-fallbacks migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-executor-rate-limit-fallbacks)
      (when (equal gptel-auto-workflow-executor-rate-limit-fallbacks
                   gptel-auto-workflow--legacy-executor-rate-limit-fallbacks)
        (setq gptel-auto-workflow-executor-rate-limit-fallbacks
              (copy-tree
               gptel-auto-workflow--current-executor-rate-limit-fallbacks))
        (push 'gptel-auto-workflow-executor-rate-limit-fallbacks migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-experiment-validation-retry-active-grace)
      (when (= gptel-auto-experiment-validation-retry-active-grace
               gptel-auto-workflow--legacy-validation-retry-active-grace)
        (setq gptel-auto-experiment-validation-retry-active-grace
              gptel-auto-workflow--current-validation-retry-active-grace)
        (push 'gptel-auto-experiment-validation-retry-active-grace migrated)))
    (when migrated
      (setq migrated (nreverse migrated))
      (message "[auto-workflow] Refreshed legacy fallback defaults: %s"
               (mapconcat #'symbol-name migrated ", ")))
    migrated))

(defun gptel-auto-workflow--backend-model-symbol (backend model-name)
  "Return MODEL-NAME as a supported symbol for BACKEND.

If MODEL-NAME is not yet listed on BACKEND, append it so hot-reloaded daemons
can use newer models without a restart."
  (let ((model (if (symbolp model-name) model-name (intern model-name))))
    (when (and backend (fboundp 'gptel-backend-models))
      (let ((models (gptel-backend-models backend)))
        (unless (memq model models)
          (setf (gptel-backend-models backend) (append models (list model))))))
    model))

(defun gptel-auto-workflow--clear-runtime-subagent-provider-overrides ()
  "Reset per-run provider failover state."
  (setq gptel-auto-workflow--runtime-subagent-provider-overrides nil
        gptel-auto-workflow--rate-limited-backends nil))

(defun gptel-auto-workflow--rate-limit-failover-candidates (agent-type)
  "Return fallback provider candidates for AGENT-TYPE after rate limiting."
  (cond
   ((not (stringp agent-type)) nil)
   ((string= agent-type "executor")
    gptel-auto-workflow-executor-rate-limit-fallbacks)
   ((member agent-type gptel-auto-workflow-headless-fallback-agents)
    gptel-auto-workflow-headless-subagent-fallbacks)))

(defun gptel-auto-workflow--agent-base-preset (agent-type)
  "Return the current base preset plist for AGENT-TYPE, or nil when unavailable."
  (when-let* ((agent-type (and (stringp agent-type) agent-type))
              (agent-config (and (boundp 'gptel-agent--agents)
                                 (assoc agent-type gptel-agent--agents))))
    (append (list :include-reasoning nil
                  :use-tools t
                  :use-context nil
                  :stream my/gptel-subagent-stream)
            (copy-sequence (cdr agent-config)))))

(defun gptel-auto-workflow--runtime-subagent-provider-override (agent-type)
  "Return the active per-run provider override for AGENT-TYPE, if any."
  (alist-get agent-type
             gptel-auto-workflow--runtime-subagent-provider-overrides
             nil nil #'string=))

(defun gptel-auto-workflow--backend-rate-limited-p (backend-name)
  "Return non-nil when BACKEND-NAME has already rate-limited this run."
  (and (stringp backend-name)
       (seq-contains-p gptel-auto-workflow--rate-limited-backends
                       backend-name
                       #'string=)))

(defun gptel-auto-workflow--preset-backend-name (backend)
  "Return a readable backend name for BACKEND."
  (cond
   ((stringp backend) backend)
   ((and backend (fboundp 'gptel-backend-name))
    (gptel-backend-name backend))
   (t nil)))

(defun gptel-auto-workflow--model-max-output-tokens (model-id)
  "Return the documented max output tokens for MODEL-ID, or nil when unknown."
  (when (require 'gptel-ext-context-cache nil t)
    (when-let* (((fboundp 'my/gptel-get-model-metadata))
                (meta (my/gptel-get-model-metadata model-id))
                (max-output
                 (if (fboundp 'my/gptel--plist-get)
                     (my/gptel--plist-get meta :max-output nil)
                   (plist-get meta :max-output)))
                ((integerp max-output))
                ((> max-output 0)))
      max-output)))

(provide 'gptel-tools-agent-prompt-build)
;;; gptel-tools-agent-prompt-build.el ends here
